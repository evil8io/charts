# drover-policies

drover-policies is a Helm chart with multi-tenancy policies for
[drover](https://github.com/evil8io/drover). Install the chart in the Rancher management
cluster and in each downstream cluster. The chart needs Kyverno 1.19+ and Kubernetes
1.30+.

## Policies

| Policy | Kind | Rule |
|---|---|---|
| `drover.namespace-project` | MutatingPolicy, ValidatingPolicy | When a tenant creates a namespace without the `field.cattle.io/projectId` annotation, Kyverno assigns the namespace to the Rancher project of the tenant. When the requester has more than one project, Kyverno denies the request. The deny message contains the values to choose from. For each project that has a namespace, the message also contains the display name of the project. |
| `drover.namespace-quotas.<revision>` | GeneratingPolicy | Kyverno generates a ResourceQuota `counts.<revision>` and a LimitRange `default.<revision>` in every namespace with a project annotation, except the namespaces of the System and the Default project, and except a namespace that is terminating. |
| `drover.namespace-metadata` | ValidatingPolicy | Kyverno denies an update of a namespace that sets, changes, or removes a key that the drover project sync recorded on that namespace. Kyverno also denies an update that sets, changes, or removes one of the two records of the sync, the annotations `drover-managed-labels` and `drover-managed-annotations`. A requester with permission to patch every namespace is exempt, for example the Rancher user of the sync, a cluster owner, or an admin. |
| `drover.namespace-orphan` | ValidatingPolicy | Kyverno denies an update of a namespace that removes or empties the annotation `field.cattle.io/projectId`. A requester with permission to manage the namespaces of every Rancher project is exempt. Every ServiceAccount of the Rancher namespace is exempt too. |
| `drover.route-hostname` | ValidatingPolicy | In a namespace with a project annotation, an HTTPRoute, a GRPCRoute, or a TLSRoute with a Gateway parent must have at least one hostname. Kyverno denies a wildcard hostname. Kyverno also denies a hostname that a route or an external-dns Service outside the project already uses. |
| `drover.listenerset-hostname` | ValidatingPolicy | In a namespace with a project annotation, every listener of a ListenerSet must have a hostname. A ListenerSet in such a namespace must not use a hostname of a ListenerSet outside the project. |
| `drover.prometheus-monitors`, `drover.prometheus-monitors-existing` | MutatingPolicy | Kyverno restricts a PodMonitor or a ServiceMonitor in a namespace of a user project to its own namespace. A user project is a Rancher project other than the System and the Default project. Through the second policy, Kyverno applies the restriction again when the project annotation of a namespace changes. |
| `drover.generated-integrity` | ValidatingAdmissionPolicy | The API server denies a create, an update, or a delete of an object that Kyverno generated for a GeneratingPolicy. The ServiceAccounts of the Kyverno and the kube-system namespace are exempt. A principal with permission to delete GeneratingPolicies is exempt too. A finalizer-only update is also exempt. |

## Project of a namespace

Kyverno reads the project of a namespace from the annotation `field.cattle.io/projectId`,
with the form `<cluster>:<project>`. Kyverno never reads the label
`field.cattle.io/projectId`, because a project member can remove the label from its
namespace. The cluster id is the prefix of the annotation on `kube-system`. The System
project and the Default project are the projects of `kube-system` and `default`.

| Annotation | Outcome |
|---|---|
| Absent or empty | The namespace is in no project. Kyverno skips the namespace. |
| The prefix is the cluster id | The namespace is in the project after the prefix. |
| Another prefix, or no colon | The namespace has no trusted project. Kyverno denies every route with a Gateway parent and every ListenerSet, restricts every monitor to its own namespace, and generates the quota objects. |

When the cluster id is unknown, Kyverno skips every namespace. For example, the cluster id
is unknown when `kube-system` has no annotation, or when the namespaces context entry is
off. For the monitors and the quota objects, Kyverno also skips every namespace when the
project of `default` is unknown.

## Tenant roles

Tenants get access to the namespaced platform kinds, for example routes, monitors, and
autoscalers, through three ClusterRoles: `drover:aggregate-to-view`,
`drover:aggregate-to-edit`, and `drover:aggregate-to-admin`. Kubernetes aggregates the
rules of these ClusterRoles into the built-in `view`, `edit`, and `admin` roles. Rancher
binds those built-in roles for the Read-only, Project Member, and Project Owner roles of a
project. A tenant thus gets the rules through its project role, in every namespace of the
project.

List the kinds of each role in `tenantRoles`, as a map from API group to resource plurals.
Helm renders a ClusterRole only for a map that is not empty. The verbs of each role are
fixed in the templates:

| Role | Verbs |
|---|---|
| `view` | get, list, watch |
| `edit` | create, update, patch, delete, deletecollection |
| `admin` | create, update, patch, delete, deletecollection |

### Rancher users

When `rancherUsers.enabled` is `true`, Helm also installs the ClusterRole `drover:users`
and binds it to the group `system:cattle:authenticated`. Every Rancher user can then get,
list, and watch `principals` and `roletemplates`. The Rancher UI reads both when a project
owner adds members to a project. The built-in Rancher role `user-base` does not include
these reads.

Enable the value in the Rancher management cluster only. Principals are not a CRD. The
Rancher server answers a principal search, and it checks the RBAC of the management
cluster. In a downstream cluster, Rancher never checks the binding.

## Context entries

The policies read GlobalContextEntries with the names `drover-<resource>`. A
GlobalContextEntry is a Kyverno cache of one resource kind. When an entry has no `enabled`
value, Helm renders the entry if a policy that reads it is enabled. When an entry has an
explicit `enabled` value, Helm uses that value.

## Quota revision

`policies.namespace-quotas.revision` is part of the policy name and of the generated
names. A change of a generated field that is immutable needs a new revision. The old
policy is deleted together with its objects, and Kyverno generates the objects again for
the new policy.

## Values

| Key | Default | Description |
|---|---|---|
| `platform` | `generic` | The platform that the cluster runs on: `generic`, `aws`, or `azure`. Helm uses the value to select the cloud-specific policies. At this time, no cloud-specific policy exists in this policy set. |
| `kyverno.namespace` | `kyverno` | The namespace of the Kyverno controllers. Their ServiceAccounts can write generated objects. |
| `rancher.namespace` | `cattle-system` | The namespace of the Rancher Deployment. The namespace-orphan policy skips the writes of its ServiceAccounts. |
| `externalDns.annotationPrefix` | `external-dns.alpha.kubernetes.io/` | The annotation prefix that the route-hostname policy reads on Services. |
| `tenantRoles.view` | `{}` | The kinds of the `view` role, as a map from API group to resource plurals. See Tenant roles. |
| `tenantRoles.edit` | `{}` | The kinds of the `edit` role, as a map from API group to resource plurals. See Tenant roles. |
| `tenantRoles.admin` | `{}` | The kinds of the `admin` role, as a map from API group to resource plurals. See Tenant roles. |
| `rancherUsers.enabled` | `false` | When the value is `true`, Helm installs `drover:users` and binds it to `system:cattle:authenticated`. Enable the value in the Rancher management cluster only. See Rancher users. |
| `policies.<name>.enabled` | `true` | When the value is `true`, Helm renders the policy. |
| `policies.namespace-project.nameAnnotation` | `project.display_name` | The annotation key on a namespace that has the display name of its project. Kyverno shows the name next to the project id in the deny message. When the value is empty, Kyverno shows no name. |
| `policies.namespace-quotas.revision` | `1` | See Quota revision. |
| `policies.namespace-quotas.hard` | object counts | The `spec.hard` of the generated ResourceQuota. |
| `globalContextEntries.<name>.enabled` | derived | When the value is `true`, Helm renders the entry. |
