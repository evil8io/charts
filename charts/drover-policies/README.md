# drover-policies

Multi-tenancy policies for [drover](https://github.com/evil8io/drover). Install this in
both the Rancher management cluster, and any downstream cluster. Requires Kyverno 1.19+
and Kubernetes 1.30+.

## Policies

| Policy | Kind | Rule |
|---|---|---|
| `drover.namespace-project` | MutatingPolicy, ValidatingPolicy | A namespace that a tenant creates without the `field.cattle.io/projectId` annotation is assigned to the Rancher project of the tenant. A requester with more than one project gets a deny that lists the values to choose from. |
| `drover.namespace-quotas.<revision>` | GeneratingPolicy | Generates a ResourceQuota `counts.<revision>` and a LimitRange `default.<revision>` in every namespace of a Rancher project, except the System and the Default project. |
| `drover.route-hostname` | ValidatingPolicy | A Gateway-parented HTTPRoute, GRPCRoute, or TLSRoute in a project namespace requires at least one hostname. The policy denies a wildcard hostname, and a hostname that a route or an external-dns Service outside the project already uses. |
| `drover.listenerset-hostname` | ValidatingPolicy | A ListenerSet in a project namespace requires that a hostname is configured on every listener, and no hostname of a ListenerSet outside the project. |
| `drover.prometheus-monitors`, `drover.prometheus-monitors-existing` | MutatingPolicy | Restricts a PodMonitor or a ServiceMonitor in a namespace of a user project to its own namespace. The second policy applies the restriction again when the project of a namespace changes. |
| `drover.generated-integrity` | ValidatingAdmissionPolicy | Denies a create, an update, or a delete of an object that a GeneratingPolicy generated. Exempt are the ServiceAccounts of the Kyverno and the kube-system namespace, a principal that may delete GeneratingPolicies, and a finalizer-only update. |

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
| `externalDns.annotationPrefix` | `external-dns.alpha.kubernetes.io/` | The annotation prefix that the route-hostname policy reads on Services. |
| `policies.<name>.enabled` | `true` | Renders the policy. |
| `policies.namespace-quotas.revision` | `1` | See Quota revision. |
| `policies.namespace-quotas.hard` | object counts | The `spec.hard` of the generated ResourceQuota. |
| `globalContextEntries.<name>.enabled` | derived | Renders the entry. |
