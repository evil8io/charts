# drover

Tenancy extensions for Rancher ([evil8io/drover](https://github.com/evil8io/drover)).
One image has three components. The API filter authenticates as the Rancher service
user `u-drover`. project-sync authenticates as its own service user,
`u-drover-project-sync`, because it needs rights that the filter must not hold.

1. `apiFilter`: a reverse proxy in front of Rancher. It limits the namespace
   list of a tenant to the namespaces of its projects. With `apiFilter.fanout.enabled`,
   it also answers a cluster-wide list of a namespaced kind, for example
   `kubectl get pods -A`, with one request per allowed namespace.
2. `tokenRotation`: a CronJob with one container per service user. Each container logs
   in as its own user and writes the API token into its own token Secret. A run renews
   a token only when it expires inside `tokenRotation.renewBefore`. The CronJob is the
   only writer of each token Secret.
3. `projectSync`: copies `projectSync.labelKeys` and
   `projectSync.annotationKeys` from a Rancher project to the namespaces of the project.
   `projectSync.nameAnnotation` gets the display name of the project, and
   `projectSync.nameLabel` gets a label-safe copy: a character outside `[A-Za-z0-9._-]`
   becomes `-`, and the value is cut to 63 characters. The sync records the keys that it
   wrote in the namespace annotations `drover-managed-labels` and
   `drover-managed-annotations`. It removes a key of that record once the project drops
   it, and a key outside the record belongs to the tenant. With
   `projectSync.serviceAccounts.enabled`, it also keeps a set of project
   ServiceAccounts; see [Project ServiceAccounts](#project-serviceaccounts) below.

The chart needs `rancher.url` and `httpRoute.parentRefs`. The filter reads the token
file on every use, so a new token needs no restart.

## Service users

The chart adds two Rancher `User` objects: `u-drover` for the API filter, and
`u-drover-project-sync` for project-sync. Each user gets a password Secret that Rancher
reads, and a credentials Secret from the same external-secrets `Password` generator, so
the chart needs the external-secrets CRDs. Each rotation run derives the
PBKDF2-SHA3-512 hash from its own credentials Secret, and it writes the hash into its
own password Secret before the login. The generator makes a new password every
`serviceUser.password.refreshInterval`. The token in use stays valid, so the rotation
costs no outage.

The `post-install` Job applies a `RoleTemplate` and a `GlobalRole` per user, and three
bindings per user: the `GlobalRoleBinding`, the `user-base` `GlobalRoleBinding`, and a
`ClusterRoleTemplateBinding` in the `local` cluster, because an inherited cluster role
never applies to the local cluster. The `pre-delete` Job deletes them in the reverse
order.

## Rancher URL

Rancher answers `400 Use HTTPS` to a login over plain HTTP, so `rancher.url` is an
`https` URL. In the Rancher cluster, the name `rancher.<namespace>` is in the
certificate, and the name `rancher.<namespace>.svc` is not.
`rancher.insecureSkipVerify` skips the certificate verification.

## Route

The chart ships a Kyverno `GeneratingPolicy` that writes one `HTTPRoute` per
`clusters.management.cattle.io` object, so install the chart after Kyverno. Each route
sends two paths to the filter, and every other path goes to Rancher:

- `GET /k8s/clusters/<id>/api/v1/namespaces`
- `POST /k8s/clusters/<id>/apis/authorization.k8s.io/v1/selfsubjectaccessreviews`

With `apiFilter.fanout.enabled`, the route also sends every `GET` under `/api/v1` and
`/apis` of the cluster to the filter, and a second rule sends
`GET /k8s/clusters/<id>/api/v1/namespaces/...` to `httpRoute.rancherBackendRef`. A
gateway picks the rule by the specificity of the match, not by the order: an `Exact`
match wins over a `PathPrefix` match, and a longer prefix wins over a shorter one. The
second rule therefore keeps `exec`, `attach`, `portforward`, and a log stream on
Rancher. Every match except the review is a `GET`, so a write never reaches the filter.
The filter is then the data path of most tenant reads, and its availability is the
availability of the tenant.

A `rancherBackendRef` in another namespace needs a `ReferenceGrant` in that namespace.
The chart does not create it, because it owns its own namespace only. Without the
grant, the gateway answers `500`.

## ServiceAccount tokens

The Rancher proxy passes a ServiceAccount token to a downstream cluster only when the
namespace of that cluster in the Rancher cluster has an enabled `ClusterProxyConfig`.
The Rancher UI calls this setting JWT Authentication. With `clusterProxyConfig.enabled`,
a second `GeneratingPolicy` writes the `ClusterProxyConfig` `clusterproxyconfig` into
the namespace of every `clusters.management.cattle.io` object except `local`. The local
cluster accepts a ServiceAccount token without the object. Kyverno deletes the objects of
the policy when the policy is removed, so `clusterProxyConfig.enabled: false` and an
uninstall stop the ServiceAccount tokens of every downstream cluster at the proxy.

## Project policy

A Kyverno `ValidatingPolicy` denies a new project without a key of
`projectPolicy.requiredLabels` or `projectPolicy.requiredAnnotations`, and it skips the
writes of the ServiceAccounts in `rancher.namespace`. It denies an update only when the
update removes or empties a key, so the System and the Default project stay editable.
`projectPolicy.failurePolicy` is `Fail`, so a project write is denied when Kyverno does not
answer; `Ignore` lets it through.

## Project ServiceAccounts

With `projectSync.serviceAccounts.enabled`, project-sync also keeps three ServiceAccounts
per Rancher project: `project-owner`, `project-member`, and `read-only`. It keeps them in
a hidden project per cluster, labeled `drover-service-accounts: "true"`, and in a
namespace `drover-<project id>` per tenant project. A `RoleBinding` in every namespace of
the project binds each ServiceAccount to the matching `admin`, `edit`, or `view`
`ClusterRole`. A `ClusterRoleBinding` also binds each ServiceAccount to the matching
Rancher `ClusterRole` of the project: `<project>-namespaces-edit` or
`<project>-namespaces-readonly`, and `create-ns`. A token of the ServiceAccount then has
the Kubernetes rights of that project role in the project. It does not have the extra
rules of the Rancher role templates, for example the monitoring resources or the read of
nodes.

The flag also widens `u-drover-project-sync`:

- Every verb on `namespaces`.
- `create` and `manage-namespaces` on `projects`.
- `get`, `list`, `watch`, `create`, and `delete` on `serviceaccounts`.
- `create` on `serviceaccounts/token` for the names `openbao`, `project-owner`,
  `project-member`, and `read-only`.
- `get`, `list`, `watch`, `create`, `update`, and `delete` on `roles`, `rolebindings`, and
  `clusterrolebindings`.
- `bind` on the `admin`, `edit`, `view`, and `create-ns` `ClusterRoles`.

## OpenBao

With `projectSync.serviceAccounts.enabled`, [OpenBao](https://openbao.org) runs in the
release namespace from the [openbao chart](https://github.com/openbao/openbao-helm) under
the `openbao` key, with three Raft replicas on PersistentVolumes and a static seal. A
pre-install hook Job creates the seal key Secret, the first entry of
`openbao.server.extraVolumes`, when the Secret does not exist. An uninstall keeps that
Secret and the data volumes, so a reinstall unseals the old data. Without the key the
data cannot be read, so delete the `data-*` PersistentVolumeClaims of OpenBao after a loss
of the Secret. On the first start, pod 0 initializes the cluster, configures Kubernetes
auth for the local cluster, and adds the `admin` policy with an `admin` role for the
ServiceAccount `<openbao fullname>-admin` in the release namespace. OpenBao then revokes
the root token, and it makes no recovery key. An admin logs in with
`bao write auth/kubernetes/login role=admin jwt="$(kubectl -n <namespace> create token <openbao fullname>-admin)"`.
The `PodMonitor` scrapes `/v1/sys/metrics` on a second listener at port 8210, and
`openbao.server.gateway.httpRoute` sends traffic to port 8200 only.

## Credential broker

With `projectSync.serviceAccounts.enabled`, OpenBao issues short-lived tokens of the
project ServiceAccounts.

- A post-install and post-upgrade hook Job logs in with the `admin` role. It writes the
  role `project-sync` of the Kubernetes auth method and its policy. It enables a JWT auth
  mount at `auth/jwt/<name>` for every entry of `broker.jwtIssuers`, by default for GitHub
  Actions and GitLab.com, and writes its discovery URL. It disables every other `jwt/`
  mount. The chart has no login roles for these mounts yet.
- project-sync keeps the ServiceAccount `openbao` in the namespace `drover-openbao` of every
  cluster, and a Role in every `drover-<project id>` namespace that lets it request tokens
  of the three project ServiceAccounts.
- For every cluster, project-sync enables a Kubernetes secrets engine at
  `kubernetes/<cluster id>`. It writes the mount config with a token of the `openbao`
  ServiceAccount, the Rancher proxy URL `<broker.rancherUrl>/k8s/clusters/<cluster id>`,
  and the Rancher setting `cacerts` as the CA. It writes a new token at half of
  `broker.clusterTokenTTL`. OpenBao cannot skip the TLS verification, so a Rancher with a
  private CA needs that setting.
- For every project role of every tenant project, project-sync writes the role
  `kubernetes/<cluster id>/roles/<project id>-<role>` for the ServiceAccount of that role,
  and the policy `kubernetes-<cluster id>-<project id>-<role>`. The policy allows only the
  credential request `kubernetes/<cluster id>/creds/<project id>-<role>`. A new project gets
  them from the project watch, in the same pass as its ServiceAccounts. A credential is
  valid for `broker.credentials.ttl`, and a request can ask for at most
  `broker.credentials.maxTTL`. The periodic run corrects a changed role or policy and
  deletes those of a deleted project.

## Network policies

With `ciliumNetworkPolicy.enabled`, each component has a `CiliumNetworkPolicy`. Every
component can reach the API server. The API filter, project-sync, and the token rotation
can also reach `rancher.namespace`. The API filter on port 8080 and OpenBao on port 8200
accept traffic from `ciliumNetworkPolicy.gatewayNamespaces`, and the OpenBao pods reach
each other on 8200 and 8201. OpenBao also accepts traffic on 8200 from project-sync and from
the hook Job of the broker roles. It reaches the
Rancher host and the hosts of `broker.jwtIssuers` on 443 by name, so the cluster needs the
Cilium DNS proxy. DNS and the metric scrapes need a separate policy.

## Values

See [values.yaml](values.yaml). A comment describes each key whose name does not explain
it. A template fails the render on a dependent value that is missing.
