# drover

drover ([evil8io/drover](https://github.com/evil8io/drover)) is a set of tenancy
extensions for Rancher. One image has three components. The API filter authenticates as
the Rancher service user `u-drover`. project-sync authenticates as its own service user,
`u-drover-project-sync`, because it needs rights that the API filter must not have.

1. The API filter (`apiFilter`) is a reverse proxy in front of Rancher. It limits the
   namespace list of a tenant to the namespaces of the projects of that tenant. When
   `apiFilter.fanout.enabled` is true, the API filter also answers a cluster-wide list
   of a namespaced kind, for example `kubectl get pods -A`. For such a list, the API
   filter sends one request for each allowed namespace.
2. The token rotation (`tokenRotation`) is a CronJob with one container for each service
   user. Each container logs in as its own user and writes the API token into its own
   token Secret. A run renews a token only when the token expires within
   `tokenRotation.renewBefore`. After an install and after an upgrade, a hook Job does
   one run with the same containers, so both token Secrets have a token when the
   install is complete. Only these runs write to a token Secret.
3. project-sync (`projectSync`) copies the labels in `projectSync.labelKeys` and the
   annotations in `projectSync.annotationKeys` from a Rancher project to the namespaces
   of the project. project-sync writes the display name of the project into the
   annotation that is named in `projectSync.nameAnnotation`. It writes a label-safe copy
   of the name into the label that is named in `projectSync.nameLabel`. In this copy,
   project-sync replaces each character outside `[A-Za-z0-9._-]` with `-`, and it cuts
   the value to 63 characters.

   In the namespace annotations `drover-managed-labels` and `drover-managed-annotations`,
   project-sync lists the keys that it wrote. When the project no longer has a key from
   that list, project-sync removes the key from the namespace. A key outside that list
   belongs to the tenant. When `projectSync.serviceAccounts.enabled` is true,
   project-sync also keeps a set of project ServiceAccounts. See
   [Project ServiceAccounts](#project-serviceaccounts) below.

The values `rancher.url` and `httpRoute.parentRefs` are required. The API filter reads
the token file each time it uses the token. Thus the API filter does not need a restart
for a new token. The chart needs Kubernetes 1.30 or later.

## Service users

Helm creates two Rancher `User` objects: `u-drover` for the API filter, and
`u-drover-project-sync` for project-sync. For each user, Helm creates a password Secret
that Rancher reads. For each user, external-secrets also creates a credentials Secret.
external-secrets uses the same `Password` generator for both credentials Secrets, so the
external-secrets CRDs must be in the cluster.

Each rotation run computes the PBKDF2-SHA3-512 hash from its own credentials Secret.
Before the login, the run writes the hash into its own password Secret. external-secrets
creates a new password every `serviceUser.password.refreshInterval`. The token in use
stays valid, so there is no outage when the password changes.

For each user, the `post-install` Job applies a `RoleTemplate`, a `GlobalRole`, and three
bindings. The bindings are the `GlobalRoleBinding`, the `user-base` `GlobalRoleBinding`,
and a `ClusterRoleTemplateBinding` in the `local` cluster. The Job applies the
`ClusterRoleTemplateBinding`, because Rancher never applies an inherited cluster role to
the local cluster. The `pre-delete` Job deletes these objects in the reverse order.

## Rancher URL

Rancher answers `400 Use HTTPS` to a login over plain HTTP, so `rancher.url` must be an
`https` URL. In the Rancher cluster, the name `rancher.<namespace>` is in the certificate
of Rancher, and the name `rancher.<namespace>.svc` is not. When
`rancher.insecureSkipVerify` is true, the components skip the certificate verification.

## Route

Helm installs a Kyverno `GeneratingPolicy` from the chart. With this policy, Kyverno
writes one `HTTPRoute` for each `clusters.management.cattle.io` object. Thus, install the
chart after Kyverno. For each route, the gateway sends every request to Rancher, except
the requests of two matches. The gateway sends the requests of these two matches to the
API filter:

- `GET /k8s/clusters/<id>/api/v1/namespaces`
- `POST /k8s/clusters/<id>/apis/authorization.k8s.io/v1/selfsubjectaccessreviews`

When `apiFilter.fanout.enabled` is true, the gateway also sends every `GET` under
`/api/v1` and `/apis` of the cluster to the API filter. Through a second rule of the
route, the gateway sends `GET /k8s/clusters/<id>/api/v1/namespaces/...` to the backend in
`httpRoute.rancherBackendRef`.

A gateway selects the rule with the most specific match. It does not use the order of
the rules. An `Exact` match has priority over a `PathPrefix` match, and a longer prefix
has priority over a shorter prefix. Thus the gateway sends `exec`, `attach`,
`portforward`, and a log stream to Rancher through the second rule. Every match except
the `selfsubjectaccessreviews` match is a `GET`, so the gateway never sends a write to
the API filter. The API filter is then the data path of most tenant reads. When the API
filter is not available, most tenant reads fail.

A `rancherBackendRef` in another namespace needs a `ReferenceGrant` in that namespace.
Helm does not create this `ReferenceGrant`, because Helm creates the namespaced objects
of the chart in the release namespace only. Without the grant, the gateway answers
`500`.

The name of each route is `<fullname>-<cluster id>-<revision>`, and the route has the
label `drover-route-revision: <revision>`. The revision is the first 8 hex characters of
the SHA-256 of the route definition in the policy. Thus a change of `httpRoute`, of
`apiFilter.fanout.enabled`, or of the release namespace gives a new revision. Kyverno
then creates the routes of the new revision. Every minute, a Kyverno `NamespacedDeletingPolicy`
deletes the routes of the other revisions in the release namespace, so the Kyverno
cleanup controller must run in the cluster. Until the cleanup, both routes of a cluster
exist, and for a match in both routes, the gateway uses the older route. When the
cleanup runs before Kyverno creates the new route, the gateway sends the paths of the
route to the other routes of the hostname until Kyverno creates it.

## ServiceAccount tokens

The Rancher proxy passes a ServiceAccount token to a downstream cluster only when its
namespace in the Rancher cluster has an enabled `ClusterProxyConfig`. In the Rancher UI,
the name of this setting is JWT Authentication. When `clusterProxyConfig.enabled` is
true, Kyverno uses a second `GeneratingPolicy` to write the `ClusterProxyConfig`
`clusterproxyconfig` into the namespace of every `clusters.management.cattle.io` object
except `local`. The local cluster accepts a ServiceAccount token without the object.
When the policy is removed, Kyverno deletes the objects that it generated from the
policy. Thus, after a change to `clusterProxyConfig.enabled: false` or after an
uninstall, the Rancher proxy passes no ServiceAccount token to a downstream cluster.

## Project policy

Through a `ValidatingPolicy`, Kyverno denies a new project without a key of
`projectPolicy.requiredLabels` or `projectPolicy.requiredAnnotations`. A write of a
ServiceAccount in `rancher.namespace` is not checked. Kyverno denies an update only when
a key is removed or set to an empty value in the update. Thus the System project and the
Default project stay editable. `projectPolicy.failurePolicy` is `Fail` by default, so a
project write is denied when Kyverno does not answer. With `Ignore`, the write is
allowed.

## Project ServiceAccounts

When `projectSync.serviceAccounts.enabled` is true, project-sync also keeps three
ServiceAccounts for each Rancher project: `project-owner`, `project-member`, and
`read-only`. project-sync keeps them in a hidden project for each cluster, with the label
`drover-service-accounts: "true"`, and in a namespace `drover-<project id>` for each
tenant project. In every namespace of the project, project-sync binds each ServiceAccount
to the related `admin`, `edit`, or `view` `ClusterRole` with a `RoleBinding`. With a
`ClusterRoleBinding`, project-sync also binds each ServiceAccount to the related Rancher
`ClusterRole` of the project: `<project>-namespaces-edit` or
`<project>-namespaces-readonly`, and `create-ns`. A token of the ServiceAccount then has
the Kubernetes rights of that project role in the project. It does not have the extra
rules of the Rancher role templates, for example the monitoring resources or the read of
nodes.

When `projectSync.serviceAccounts.enabled` is true, `u-drover-project-sync` also gets
these rights:

- Every verb on `namespaces`.
- `create` and `manage-namespaces` on `projects`.
- `get` on `clusters` of `management.cattle.io`.
- `get`, `list`, `watch`, `create`, and `delete` on `serviceaccounts`.
- `create` on `serviceaccounts/token` for the names `openbao`, `project-owner`,
  `project-member`, and `read-only`.
- `get`, `list`, `watch`, `create`, `update`, and `delete` on `roles`, `rolebindings`, and
  `clusterrolebindings`.
- `bind` on the `admin`, `edit`, `view`, and `create-ns` `ClusterRoles`.

## OpenBao

When `projectSync.serviceAccounts.enabled` is true, [OpenBao](https://openbao.org) runs
in the release namespace. Helm installs OpenBao from the
[openbao chart](https://github.com/openbao/openbao-helm) with the values under the
`openbao` key. OpenBao runs three Raft replicas on PersistentVolumes with a static seal.
With a static seal, OpenBao unseals its data with a fixed key. A pre-install hook Job
creates the seal key Secret when the Secret does not exist. The name of this Secret is in
the first entry of `openbao.server.extraVolumes`.

After an uninstall, the seal key Secret and the data volumes stay in the cluster. Thus
OpenBao unseals the old data after a reinstall. Without the key, the data cannot be read.
When the Secret does not exist but a `data-*` PersistentVolumeClaim of OpenBao exists,
the hook Job fails, and the install or the upgrade stops. Thus, when the Secret is lost,
delete the `data-*` PersistentVolumeClaims of OpenBao.

Pod 0 initializes the cluster only when no other OpenBao pod is initialized and no
`data-*` PersistentVolumeClaim of another pod exists. For this check, a Role gives the
OpenBao ServiceAccount `get` on these PersistentVolumeClaims. When pod 0 lost its volume
but another claim exists, pod 0 stays not ready, and OpenBao does not start until the
volume is restored or all `data-*` PersistentVolumeClaims are deleted.

On the first start, pod 0 does these steps:

1. It initializes the cluster.
2. It configures the Kubernetes auth method for the local cluster.
3. It adds the `admin` policy with an `admin` role for the ServiceAccount
   `<openbao fullname>-admin` in the release namespace.

OpenBao then revokes the root token. It does not make a recovery key. An admin logs in
with
`bao write auth/kubernetes/login role=admin jwt="$(kubectl -n <namespace> create token <openbao fullname>-admin)"`.
With the `PodMonitor`, `/v1/sys/metrics` is scraped on a second listener at port 8210.
The gateway sends the traffic of the route in `openbao.server.gateway.httpRoute` to port
8200 only.

## Credential broker

When `projectSync.serviceAccounts.enabled` is true, OpenBao issues short-lived tokens of
the project ServiceAccounts.

- The hook Job of the broker roles runs after each install and after each upgrade, and
  it logs in with the `admin` role. It writes the role `project-sync` of the Kubernetes
  auth method, and the policy of that role. For every entry of `broker.jwtIssuers`, it
  enables a JWT auth mount at `auth/jwt/<name>` and writes the discovery URL of the
  issuer. OpenBao reads the discovery document of the issuer at this write. When the
  read fails, the Job logs the error and continues, and the mount keeps its previous
  config. A new mount then has no config. The default entries of `broker.jwtIssuers`
  are for GitHub Actions and GitLab.com. The Job disables every other `jwt/` mount.
  Login roles for these mounts are not in the chart yet.
- project-sync keeps the ServiceAccount `openbao` in the namespace `drover-openbao` of
  every cluster. project-sync also keeps a Role in every `drover-<project id>` namespace.
  With this Role, the `openbao` ServiceAccount can request tokens of the three project
  ServiceAccounts.
- For every cluster, project-sync enables a Kubernetes secrets engine at
  `kubernetes/<cluster id>`. It writes the mount config with a token of the `openbao`
  ServiceAccount, the Rancher proxy URL `<broker.rancherUrl>/k8s/clusters/<cluster id>`,
  and the Rancher setting `cacerts` as the CA. It writes a new token after half of
  `broker.clusterTokenTTL`. OpenBao cannot skip the TLS verification, so a Rancher with
  a private CA needs the `cacerts` setting.
- For every project role of every tenant project, project-sync writes the role
  `kubernetes/<cluster id>/roles/<project id>-<role>` for the ServiceAccount of that role,
  and the policy `kubernetes-<cluster id>-<project id>-<role>`. With this policy, OpenBao
  allows only the credential request `kubernetes/<cluster id>/creds/<project id>-<role>`.
  For a new project, project-sync writes the role and the policy through its project
  watch, in the same pass as the ServiceAccounts of the project. A credential is valid
  for `broker.credentials.ttl`, and at most `broker.credentials.maxTTL` can be
  requested. The periodic run of project-sync corrects a changed role or policy, and it
  deletes the role and the policy of a deleted project.

## Network policies

When `ciliumNetworkPolicy.enabled` is true, Helm creates a `CiliumNetworkPolicy` for each
component. Every component can reach the API server. The API filter, project-sync, and
the token rotation can also reach `rancher.namespace`.

The API filter on port 8080 and OpenBao on port 8200 accept traffic from the namespaces
in `ciliumNetworkPolicy.gatewayNamespaces`. The OpenBao pods reach each other on the
ports 8200 and 8201. OpenBao also accepts traffic on port 8200 from project-sync and from
the hook Job of the broker roles. OpenBao reaches the Rancher host and the hosts of
`broker.jwtIssuers` on port 443 by name, so the cluster needs the Cilium DNS proxy. DNS
traffic and the metric scrapes need a separate policy.

## Values

See [values.yaml](values.yaml). There is a comment on each key whose name is not clear by
itself. Helm stops the render with an error when a dependent value is not set, or when
`tokenRotation.renewBefore` is not shorter than `tokenRotation.ttl`.
