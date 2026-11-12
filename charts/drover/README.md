# drover

[drover](https://github.com/evil8io/drover) is a set of tenancy extensions for Rancher.
Install the chart in the Rancher management cluster.

| Feature | Result | Values |
|---|---|---|
| [Namespace list](#namespace-list) | Through Rancher, a tenant sees only the namespaces of its own projects. | `apiFilter` |
| [Cluster-wide reads](#cluster-wide-reads) | A tenant can read a namespaced kind in all its namespaces with one request, for example `kubectl get pods -A`. | `apiFilter.fanout` |
| [Project metadata](#project-metadata) | The labels, the annotations, and the display name of a project are copied to each namespace of the project. | `projectSync` |
| [Required project metadata](#required-project-metadata) | A project without the required keys is denied. | `projectPolicy` |
| [Unique display names](#unique-display-names) | A project with the display name of another project in the same cluster is denied. | `projectPolicy.uniqueDisplayName` |
| [Project delete](#project-delete) | The delete of a project that contains namespaces is denied. | `projectDeletePolicy` |
| [Project ServiceAccounts](#project-serviceaccounts) | Each project has three ServiceAccounts, one for each project role. | `projectSync.serviceAccounts` |
| [Short-lived credentials](#short-lived-credentials) | A tenant client outside the cluster, for example a CI job, gets a short-lived token of a project ServiceAccount without a stored secret. | `global.broker`, `openbao` |

## Requirements

- Kubernetes 1.30 or later, with Rancher in the same cluster.
- Kyverno with its cleanup controller. Install the chart after Kyverno.
- external-secrets with the `Password` generator.
- A Gateway API gateway for the hostname of Rancher.
- Cilium, for the network policies. Without Cilium, set `ciliumNetworkPolicy.enabled` to
  false.
- The `PodMonitor` kind of the Prometheus operator, when
  `projectSync.serviceAccounts.enabled` is true.
- The drover-policies chart, for its policy `drover.managed-metadata`. Install it with
  `managedPrefix` at its default and with `kyverno.namespace` set to the namespace of
  Kyverno.

## Required values

```yaml
rancher:
  url: https://rancher.cattle-system
httpRoute:
  parentRefs:
    - name: rancher
      namespace: gateway
  hostnames:
    - rancher.example.com
```

In `rancher.url`, use the host name `rancher.<namespace>`, without `.svc`. drover
verifies the certificate of Rancher, and the certificate does not contain the name
`rancher.<namespace>.svc`.

## Namespace list

In Rancher, a tenant cannot list the namespaces of a cluster. With drover, the answer to
this request contains the namespaces of the projects of the tenant.

For each Rancher cluster, the chart adds one `HTTPRoute` to the gateway in
`httpRoute.parentRefs`.

## Cluster-wide reads

When `apiFilter.fanout.enabled` is true, a tenant can read a namespaced kind in all its
namespaces with one request. The answer contains the objects of each namespace in which
the tenant can read that kind.

- When the API filter is not available, these reads fail.
- Set `httpRoute.rancherBackendRef` to the Rancher Service. A Service in another
  namespace needs a `ReferenceGrant` in that namespace, which is not part of the chart.
- The keys under `apiFilter.fanout` and the rate keys under `apiFilter` limit the load on
  the API filter and on Rancher. See [values.yaml](values.yaml).

## ServiceAccount tokens

With drover, Rancher accepts a ServiceAccount token of a downstream cluster on its
cluster proxy. In the Rancher UI, the name of this setting is JWT Authentication. To keep
the setting off for new clusters, set `clusterProxyConfig.enabled` to false.

## Project metadata

These items are copied from a Rancher project to each namespace of the project:

- The labels in `projectSync.labelKeys` and the annotations in
  `projectSync.annotationKeys`.
- The display name of the project, into the annotation in `projectSync.nameAnnotation`.
- A copy of the display name as a valid label value, into the label in
  `projectSync.nameLabel`.

When a key is removed from the project, drover removes the key from the namespaces.

## Required project metadata

List the required keys of a project in `projectPolicy.requiredLabels` and
`projectPolicy.requiredAnnotations`. Each key must also be in `projectSync.labelKeys` or
`projectSync.annotationKeys`.

Kyverno denies a new project without one of these keys. Kyverno also denies an update in
which a user removes a required key or sets it to an empty value.

## Unique display names

When `projectPolicy.uniqueDisplayName` is true, Kyverno denies a new project with the
display name of another project in the same cluster. Kyverno also denies a rename of a
project to such a name.

- Kyverno ignores the case of the ASCII letters and the white space around the name.
- When `projectSync.serviceAccounts.enabled` is true, each cluster has a hidden project
  with the display name `drover`. Kyverno then denies a tenant project with that name.

## Project delete

When you delete a Rancher project, Rancher keeps its namespaces. They stay in the cluster
without a project. Set `projectDeletePolicy.enabled` to true to block the delete of a
project that still has namespaces.

The block applies to every user, also to an admin. Delete the namespaces first, then the
project.

## Project ServiceAccounts

When `projectSync.serviceAccounts.enabled` is true, each tenant project has three
ServiceAccounts: `project-owner`, `project-member`, and `read-only`. The ServiceAccounts
are in the namespace `drover-<cluster id>-<project id>`, for example
`drover-c-m-4x2kq7bd-p-abc12`. Each ServiceAccount has the Kubernetes role `admin`,
`edit`, or `view` in every namespace of the project.

The service user of drover then has wide rights in every cluster. It can use every verb
on namespaces. It can create ServiceAccounts, roles, and bindings. It can also create
tokens of the project ServiceAccounts.

To bind extra roles to every project ServiceAccount, set
`projectSync.serviceAccounts.bindings`. An entry is `{clusterRole: <name>}` or
`{role: <name>, namespace: <namespace>}`. For a `role` entry, the namespace must exist
in every cluster.

## Short-lived credentials

A tenant client outside the cluster, for example a GitHub Actions workflow, a GitLab CI
job, or an AWS Lambda function, can get a token of a project ServiceAccount. The client
does not need a stored secret. The client logs in to [OpenBao](https://openbao.org)
with the identity that it already has: the JWT of its CI system, or its AWS IAM role.
OpenBao then returns the token.

When `projectSync.serviceAccounts.enabled` is true, the chart also installs OpenBao in
the release namespace. A project owner lists the trusted identities in the annotation
`drover.evil8.io/trust-policy` on the Rancher project. The format of the annotation and
the token request are in the drover docs, sections
[Login roles](https://github.com/evil8io/drover/blob/main/docs/project-sync.md#login-roles)
and
[Short-lived tokens](https://github.com/evil8io/drover/blob/main/docs/project-sync.md#short-lived-tokens).

OpenBao verifies the certificate of the Rancher URL in `global.broker.rancherUrl`. For a
Rancher with a private CA, set the Rancher setting `cacerts`.

### Login with a JWT

Each entry of `global.broker.jwtIssuers` is a JWT issuer that a project owner can use.
A client logs in at `auth/jwt/<name>/login`, with a JWT that has the audience in
`global.broker.audience`.

When OpenBao cannot reach the discovery URL of an issuer at an install or an upgrade,
Helm does not fail. Each login with a new issuer then fails until the next upgrade.

### Login with an AWS identity

When `global.broker.aws.enabled` is true, a client with an AWS IAM role can log in at
`auth/aws/login`.

- OpenBao needs egress on port 443 to `ghcr.io`, `pkg-containers.githubusercontent.com`,
  and `sts.<region>.amazonaws.com`. Without egress to `ghcr.io`, OpenBao does not start.
- `openbao.server.gateway.httpRoute.hosts` must contain the host name of OpenBao. The
  signed request of a client must contain the header `X-Vault-AWS-IAM-Server-ID`, with
  the first host of this list as its value.

### OpenBao administration

OpenBao runs three replicas, with one PersistentVolume for each replica.

- **Route.** Set the route of OpenBao in `openbao.server.gateway.httpRoute`. Clients and
  admins reach OpenBao through this route.
- **Admin login.** OpenBao does not have a root token or a recovery key. An admin logs in
  with a token of the ServiceAccount `<openbao fullname>-admin`:

  ```sh
  bao write auth/kubernetes/login role=admin \
    jwt="$(kubectl -n <namespace> create token <openbao fullname>-admin)"
  ```

- **Seal key.** OpenBao unseals its data with the key in the Secret `openbao-seal`.
  Without the key, OpenBao cannot read its data.

## Network policies

The chart contains a `CiliumNetworkPolicy` for each component. DNS traffic and metric
scrapes need a separate policy.

- The API filter and OpenBao accept traffic from the namespaces in
  `ciliumNetworkPolicy.gatewayNamespaces`.
- OpenBao can reach the host of `global.broker.rancherUrl` and the hosts of
  `global.broker.jwtIssuers` on port 443. Cilium matches these hosts by name, so the
  cluster needs the Cilium DNS proxy.

## Uninstall

Helm does not delete these objects at an uninstall:

- The seal key Secret and the `data-*` PersistentVolumeClaims of OpenBao. After a
  reinstall, OpenBao thus unseals the old data.
- The objects of `projectSync.serviceAccounts`: the hidden projects, the
  `drover-<cluster id>-<project id>` namespaces, the ServiceAccounts, and their
  bindings. A token of such a ServiceAccount stays valid. To remove the objects, delete
  the projects with the label `managed.drover.evil8.io/account-project`. Then delete the
  namespaces with the label `managed.drover.evil8.io/tenant-project` or the label
  `managed.drover.evil8.io/role`.
- The `ClusterProxyConfig` objects. Rancher accepts the ServiceAccount tokens of the
  downstream clusters until you delete these objects.

## Values

| Key | Default | Description |
|---|---|---|
| `rancher.url` | none | Required. The `https` URL of the Rancher Service in the cluster. |
| `rancher.insecureSkipVerify` | `false` | Set the value to true when drover cannot verify the certificate of Rancher. |
| `httpRoute.parentRefs` | `[]` | Required. The gateway of Rancher. |
| `httpRoute.hostnames` | `[]` | The hostname of Rancher. The gateway uses the drover routes for this hostname only. |
| `serviceUser.password.refreshInterval` | `2160h` | The time between two passwords of a drover service user in Rancher. |
| `tokenRotation.ttl` | `48h` | The lifetime of an API token of a service user. |
| `tokenRotation.renewBefore` | `24h` | drover renews a token that expires within this time. It must be shorter than `tokenRotation.ttl`. |
| `projectSync.interval` | `60s` | The time between two full runs of the project sync. |
| `projectPolicy.failurePolicy` | `Fail` | `Fail` or `Ignore`. With `Fail`, the API server denies a project write when Kyverno does not answer. |
| `projectDeletePolicy.failurePolicy` | `Fail` | `Fail` or `Ignore`. With `Fail`, the API server denies a project delete when Kyverno does not answer. |
| `ciliumNetworkPolicy.gatewayNamespaces` | `[]` | The namespaces of the gateway pods. |
| `global.broker.jwtIssuers` | GitHub Actions, GitLab.com | A map from a name to a JWT issuer, with `discoveryUrl`, `requiredClaims`, and the optional `allowedClaims`. |
| `global.broker.aws.allowedAccounts` | `[]` | The AWS accounts that are valid in the trust annotation. With an empty list, every account is valid. |
| `global.broker.audience` | `""` | The audience of a JWT login. With an empty value, the audience is `https://<first host of openbao.server.gateway.httpRoute.hosts>`. |
| `global.broker.loginTokenTTL` | `5m` | The lifetime of the OpenBao token of a login, from 1m to 24h. |
| `global.broker.trust.maxStatements` | `20` | The largest number of statements in a trust annotation, from 1 to 100. |
| `global.broker.trust.statementsInfo.enabled` | `false` | When this key is true, project-sync exports the metric `drover.sync.trust.statements.info`. The metric has the issuer, the bound claims or the IAM role, and the project role of each valid statement. The claim values that a tenant writes are then in the metrics backend. |
| `global.broker.credentials.ttl` | `15m` | The lifetime of a credential. |
| `global.broker.credentials.maxTTL` | `2h` | The longest lifetime that a client can request. |
| `global.broker.rancherUrl` | `""` | The Rancher URL through which OpenBao reaches the clusters. With an empty value, the URL is `https://<first entry of httpRoute.hostnames>`. |
| `openbao` | | The values of the [openbao chart](https://github.com/openbao/openbao-helm). |
| `otlp.endpoint` | `""` | The OTLP endpoint for the telemetry of drover. With an empty value, drover does not send telemetry. |
