# drover-policies

Multi-tenancy policies for [drover](https://github.com/evil8io/drover), as Kyverno
policies. Install the chart in the Rancher management
cluster and in each downstream cluster. The chart needs Kyverno 1.19+ and Kubernetes
1.30+.

## Policies

| Policy | Kind | Rule |
|---|---|---|
| `drover.namespace-project` | MutatingPolicy, ValidatingPolicy | Kyverno adds a new namespace of a tenant to the Rancher project of the tenant. When the tenant has more than one project, Kyverno denies the request. The deny message contains the projects to choose from. |
| `drover.namespace-quotas.<revision>` | GeneratingPolicy | Kyverno generates a ResourceQuota and a LimitRange in every namespace of a tenant. |
| `drover.namespace-metadata` | ValidatingPolicy | A tenant cannot change the labels and the annotations that the drover project sync copies from a project to its namespaces. |
| `drover.namespace-platform-metadata` | MutatingPolicy | Kyverno sets the platform labels and annotations on every platform namespace. |
| `drover.namespace-platform-name` | ValidatingPolicy | A Rancher user cannot create a namespace with a name in `policies.namespace-platform-metadata.namespaces` or with a prefix in `policies.namespace-platform-name.deniedPrefixes`. |
| `drover.namespace-orphan` | ValidatingPolicy | A tenant cannot remove a namespace from its project. |
| `drover.route-hostname` | ValidatingPolicy | A route of a tenant needs a hostname when the route has a Gateway parent. A tenant cannot use a wildcard hostname or a hostname of another project on such a route. |
| `drover.listenerset-hostname` | ValidatingPolicy | Every listener of a ListenerSet of a tenant must have a hostname. A tenant cannot use a hostname of a ListenerSet of another project. |
| `drover.prometheus-monitors`, `drover.prometheus-monitors-existing` | MutatingPolicy | Kyverno sets the namespace selector of a PodMonitor or a ServiceMonitor of a tenant to its own namespace. |
| `drover.generated-integrity` | ValidatingAdmissionPolicy | A tenant cannot change or delete an object that Kyverno generated. |
| `drover.managed-metadata` | ValidatingAdmissionPolicy | A tenant cannot set, change, or remove a label or an annotation under `managedPrefix`. |
| `drover.managed-rolebindings` | ValidatingAdmissionPolicy | A tenant cannot change or delete a RoleBinding that the drover project sync created. |

## Tenant roles

Tenants get access to the namespaced platform kinds, for example routes, monitors, and
autoscalers, through `tenantRoles`. Each key of `tenantRoles` is a map from API group to
resource plurals. A tenant gets the access of a key through its Rancher project role, in
every namespace of the project:

| Key | Rancher project role | Verbs |
|---|---|---|
| `view` | Read-only | get, list, watch |
| `edit` | Project Member | create, update, patch, delete, deletecollection |
| `admin` | Project Owner | create, update, patch, delete, deletecollection |

### Rancher users

When `rancherUsers.enabled` is `true`, every Rancher user can get, list, and watch
`principals` and `roletemplates`. The Rancher UI reads both when a project owner adds
members to a project. Set the value to `true` in the Rancher management cluster only.

### Public reads

Rancher binds the tenant roles only in the namespaces of a project. A kind in
`tenantRoles` is thus readable only in those namespaces. Set `publicRead` for a kind that
every Rancher user must read outside its project, for example the platform Gateways.
`publicRead` contains two maps:

```yaml
publicRead:
  cluster:
    gateway.networking.k8s.io:
      - gatewayclasses
      - gateways
  namespaces:
    kube-public:
      "":
        - configmaps
```

`cluster` is a map from API group to resource plurals. Every Rancher user can get, list,
and watch every object of a listed kind, cluster-wide. Do not list a kind whose objects
contain names or settings of one tenant, for example PolicyExceptions.

`namespaces` is a map from namespace name to a kind map. A kind map is a map from API
group to resource plurals. Every Rancher user can get, list, and watch the listed kinds in
that namespace only. In the example, every Rancher user can read the ConfigMaps of
`kube-public`.

## Values

| Key | Default | Description |
|---|---|---|
| `managedPrefix` | `managed.drover.evil8.io/` | The prefix of the labels and the annotations that drover manages. The value must equal the prefix that drover uses. |
| `kyverno.namespace` | `kyverno` | The namespace of the Kyverno controllers. |
| `rancher.namespace` | `cattle-system` | The namespace of the Rancher Deployment. |
| `externalDns.annotationPrefix` | `external-dns.alpha.kubernetes.io/` | The prefix of the external-dns annotations that Kyverno reads on a Service for `drover.route-hostname`. |
| `tenantRoles.view`, `tenantRoles.edit`, `tenantRoles.admin` | `{}` | See Tenant roles. |
| `publicRead.cluster`, `publicRead.namespaces` | `{}` | See Public reads. |
| `rancherUsers.enabled` | `false` | See Rancher users. |
| `policies.<name>.enabled` | `true` | Set the value to `false` to turn off the policy `drover.<name>`. |
| `policies.namespace-project.nameAnnotation` | `project.display_name` | The key of the namespace annotation with the display name of its project. Kyverno shows the name next to the project id in the deny message. Set the value to `""` to leave the name out. |
| `policies.namespace-quotas.hard` | object counts | The `spec.hard` of the generated ResourceQuota. |
| `policies.namespace-platform-metadata.namespaces` | `[]` | The names of the platform namespaces that have a project, for example the names that Rancher puts in its System project. A namespace without the project annotation is a platform namespace too. |
| `policies.namespace-platform-metadata.labels`, `policies.namespace-platform-metadata.annotations` | `{}` | The labels and the annotations that Kyverno sets on every platform namespace. |
| `policies.namespace-platform-name.deniedPrefixes` | `[]` | The name prefixes that a Rancher user cannot use for a namespace, for example `kube-` and `cattle-`. |
| `globalContextEntries.<name>.enabled` | not set | By default, a Kyverno GlobalContextEntry is installed only when an enabled policy needs it. Set the value to `true` or `false` to override this default. |
