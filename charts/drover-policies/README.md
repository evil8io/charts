# drover-policies

Multi-tenancy policies for [drover](https://github.com/evil8io/drover). Install this in
both the Rancher management cluster, and any downstream cluster. Requires Kyverno 1.19+
and Kubernetes 1.30+.

## Policies

| Policy | Kind | Rule |
|---|---|---|
| `drover.namespace-project` | MutatingPolicy, ValidatingPolicy | A namespace that a tenant creates without the `field.cattle.io/projectId` annotation is assigned to the Rancher project of the tenant. A requester with more than one project gets a deny that lists the values to choose from, with the display name of each project that has a namespace. |
| `drover.namespace-quotas.<revision>` | GeneratingPolicy | Generates a ResourceQuota `counts.<revision>` and a LimitRange `default.<revision>` in every namespace of a Rancher project, except the System and the Default project. |
| `drover.namespace-metadata` | ValidatingPolicy | Denies an update of a namespace that sets, changes, or removes a key that the drover project sync recorded on that namespace, or one of the two records `drover-managed-labels` and `drover-managed-annotations`. Exempt is a requester that may patch every namespace, for example the Rancher user of the sync, a cluster owner, or an admin. |
| `drover.namespace-orphan` | ValidatingPolicy | Denies an update of a namespace that removes or empties the annotation `field.cattle.io/projectId`. Exempt is a requester that may manage the namespaces of every Rancher project, and every ServiceAccount of the Rancher namespace. |
| `drover.route-hostname` | ValidatingPolicy | A Gateway-parented HTTPRoute, GRPCRoute, or TLSRoute in a project namespace requires at least one hostname. The policy denies a wildcard hostname, and a hostname that a route or an external-dns Service outside the project already uses. |
| `drover.listenerset-hostname` | ValidatingPolicy | A ListenerSet in a project namespace requires that a hostname is configured on every listener, and no hostname of a ListenerSet outside the project. |
| `drover.prometheus-monitors`, `drover.prometheus-monitors-existing` | MutatingPolicy | Restricts a PodMonitor or a ServiceMonitor in a namespace of a user project to its own namespace. The second policy applies the restriction again when the project of a namespace changes. |
| `drover.generated-integrity` | ValidatingAdmissionPolicy | Denies a create, an update, or a delete of an object that a GeneratingPolicy generated. Exempt are the ServiceAccounts of the Kyverno and the kube-system namespace, a principal that may delete GeneratingPolicies, and a finalizer-only update. |

## Tenant roles

Tenants get access to the namespaced platform kinds, for example routes, monitors, and
autoscalers, through three ClusterRoles: `drover:aggregate-to-view`,
`drover:aggregate-to-edit`, and `drover:aggregate-to-admin`. Kubernetes aggregates the
rules of these ClusterRoles into the built-in `view`, `edit`, and `admin` roles. Rancher
binds those built-in roles for the Read-only, Project Member, and Project Owner roles of a
project. A tenant thus gets the rules through its project role, in every namespace of
the project.

List the kinds of each role in `tenantRoles`, as a map from API group to resource
plurals. Helm renders a ClusterRole only for a map that is not empty. The verbs of each
role are fixed in the templates:

| Role | Verbs |
|---|---|
| `view` | get, list, watch |
| `edit` | create, update, patch, delete, deletecollection |
| `admin` | create, update, patch, delete, deletecollection |

### Rancher users

When `rancherUsers.enabled` is `true`, Helm also installs the ClusterRole `drover:users`
and binds it to the group `system:cattle:authenticated`. Every Rancher user can then get,
list, and watch `principals` and `roletemplates`. The Rancher UI reads both when a
project owner adds members to a project. The built-in Rancher role `user-base` does not
include these reads.

Enable the value in the Rancher management cluster only. Principals are not a CRD: the
Rancher server answers a principal search, and it checks the RBAC of the management
cluster. In a downstream cluster, Rancher never checks the binding.

## Context entries

The policies read cached GlobalContextEntries named `drover-<resource>`. An entry without
`enabled` renders when a policy that reads it is enabled, and an explicit `enabled` wins.

## Quota revision

`policies.namespace-quotas.revision` is part of the policy name and of the generated
names. A change of a generated field that is immutable needs a new revision: the old
policy goes with its objects, and the new policy generates them again.

## Values

| Key | Default | Description |
|---|---|---|
| `platform` | `generic` | The platform that the cluster runs on: `generic`, `aws`, or `azure`. It selects the cloud-specific policies. This policy set has none yet. |
| `kyverno.namespace` | `kyverno` | The namespace of the Kyverno controllers. Their ServiceAccounts may write generated objects. |
| `rancher.namespace` | `cattle-system` | The namespace of the Rancher Deployment. The namespace-orphan policy skips the writes of its ServiceAccounts. |
| `externalDns.annotationPrefix` | `external-dns.alpha.kubernetes.io/` | The annotation prefix that the route-hostname policy reads on Services. |
| `tenantRoles.view` | `{}` | The kinds of the `view` role, as a map from API group to resource plurals. See Tenant roles. |
| `tenantRoles.edit` | `{}` | The kinds of the `edit` role, as a map from API group to resource plurals. See Tenant roles. |
| `tenantRoles.admin` | `{}` | The kinds of the `admin` role, as a map from API group to resource plurals. See Tenant roles. |
| `rancherUsers.enabled` | `false` | When `true`, Helm installs `drover:users` and binds it to `system:cattle:authenticated`. Enable it in the Rancher management cluster only. See Rancher users. |
| `policies.<name>.enabled` | `true` | Renders the policy. |
| `policies.namespace-project.nameAnnotation` | `project.display_name` | The annotation key on a namespace that has the display name of its project. The deny message shows the name next to the project id. Empty turns the hint off. |
| `policies.namespace-quotas.revision` | `1` | See Quota revision. |
| `policies.namespace-quotas.hard` | object counts | The `spec.hard` of the generated ResourceQuota. |
| `globalContextEntries.<name>.enabled` | derived | Renders the entry. |
