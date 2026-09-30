# drover

drover ([evil8io/drover](https://github.com/evil8io/drover)) is a set of tenancy
extensions for Rancher. Install the chart in the Rancher management cluster.

| Feature | Result | Values |
|---|---|---|
| [Namespace list](#namespace-list) | Through Rancher, a tenant sees only the namespaces of its own projects. | `apiFilter` |
| [Cluster-wide reads](#cluster-wide-reads) | A tenant can read a namespaced kind in all its namespaces with one request, for example `kubectl get pods -A`. | `apiFilter.fanout` |
| [Project metadata](#project-metadata) | Each namespace of a project gets the labels, the annotations, and the display name of the project. | `projectSync` |
| [Required project metadata](#required-project-metadata) | Kyverno denies a project without the required keys. | `projectPolicy` |
| [Project ServiceAccounts](#project-serviceaccounts) | Each project gets three ServiceAccounts, one for each project role. | `projectSync.serviceAccounts` |
| [Short-lived credentials](#short-lived-credentials) | A client of a tenant outside the cluster, for example a CI job, gets a short-lived token of a project ServiceAccount without a stored secret. | `global.broker`, `openbao` |

## Requirements

The chart needs these items in the cluster:

- Kubernetes 1.30 or later, with Rancher in the same cluster.
- Kyverno with its cleanup controller. Install the chart after Kyverno.
- external-secrets with the `Password` generator.
- A Gateway API gateway for the hostname of Rancher.
- Cilium, for the network policies. Without Cilium, set `ciliumNetworkPolicy.enabled` to
  false.
- The `PodMonitor` kind of the Prometheus operator, when
  `projectSync.serviceAccounts.enabled` is true.

## Install

```sh
helm install drover oci://ghcr.io/evil8io/charts/drover \
  --namespace drover-system --create-namespace --values values.yaml
```

Two values are required: `rancher.url` and `httpRoute.parentRefs`.

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

- `rancher.url` is the URL of the Rancher Service in the cluster, and it must be an
  `https` URL. The certificate of Rancher contains the name `rancher.<namespace>`. It
  does not contain the name `rancher.<namespace>.svc`. When drover cannot verify the
  certificate, set `rancher.insecureSkipVerify` to true.
- `httpRoute.parentRefs` is the gateway of Rancher. Set `httpRoute.hostnames` to the
  hostname of Rancher, so that the routes of drover apply to that hostname only.

## Service users

drover logs in to Rancher as two service users. The API filter uses `u-drover`, and
project-sync uses `u-drover-project-sync`. Helm creates both users and their Rancher
roles.

external-secrets makes a new password for each user at every
`serviceUser.password.refreshInterval`. A CronJob renews the API token of each user when
the token expires within `tokenRotation.renewBefore`. The token in use stays valid after
a password change and after a renewal, so these changes cause no outage.

## Namespace list

In Rancher, a tenant cannot list the namespaces of a cluster. With drover, the tenant gets
the namespaces of its own projects as the answer.

For each Rancher cluster, Kyverno creates one `HTTPRoute` on the gateway of Rancher.
Through this route, the gateway sends these two requests to the API filter, and all
other requests to Rancher:

- `GET /k8s/clusters/<cluster id>/api/v1/namespaces`
- `POST /k8s/clusters/<cluster id>/apis/authorization.k8s.io/v1/selfsubjectaccessreviews`

After a change of `httpRoute`, of `apiFilter.fanout.enabled`, or of the release
namespace, Kyverno replaces the routes. During the replacement, the requests of a cluster
can go to Rancher without the API filter, until Kyverno creates the new route.

## Cluster-wide reads

When `apiFilter.fanout.enabled` is true, the gateway also sends every `GET` under
`/api/v1` and `/apis` of a cluster to the API filter. For a cluster-wide read of a
namespaced kind, the API filter sends one request for each namespace of the tenant. The
gateway sends `exec`, `attach`, `portforward`, and log streams to Rancher. It also sends
every write to Rancher, except the `selfsubjectaccessreviews` request.

- The API filter is then in the path of most tenant reads. When the API filter is not
  available, these reads fail. The default of the value is thus false.
- Set `httpRoute.rancherBackendRef` to the Rancher Service. A Service in another
  namespace needs a `ReferenceGrant` in that namespace, and Helm does not create it.
  Without the grant, the gateway answers `500`.
- The keys under `apiFilter.fanout` and the rate keys under `apiFilter` are limits for
  the load on the API filter and on Rancher. See [values.yaml](values.yaml).

## ServiceAccount tokens

With drover, Rancher accepts a ServiceAccount token of a downstream cluster on its
cluster proxy. In the Rancher UI, the name of this setting is JWT Authentication, and
Kyverno enables it for each downstream cluster. To turn this off, set
`clusterProxyConfig.enabled` to false. Rancher then refuses these tokens, as it does
after an uninstall.

## Project metadata

project-sync copies metadata from a Rancher project to each namespace of the project:

- The labels in `projectSync.labelKeys` and the annotations in
  `projectSync.annotationKeys`.
- The display name of the project, into the annotation in `projectSync.nameAnnotation`.
- A label-safe copy of the display name, into the label in `projectSync.nameLabel`. In
  this copy, each character outside `[A-Za-z0-9._-]` is `-`, and the value has 63
  characters at most.

project-sync lists the keys that it wrote in the namespace annotations
`drover-managed-labels` and `drover-managed-annotations`. When the project no longer has
a key from these lists, project-sync removes the key from the namespace. A key outside
these lists belongs to the tenant, and project-sync does not change it.

## Required project metadata

List the keys that each project must have in `projectPolicy.requiredLabels` and
`projectPolicy.requiredAnnotations`. Each key must also be in `projectSync.labelKeys` or
`projectSync.annotationKeys`.

Kyverno denies a new project without one of these keys. Kyverno also denies an update
that removes a required key or sets it to an empty value. A project that never had the
key stays editable, for example the System project and the Default project.

With `projectPolicy.failurePolicy: Fail`, the default, a project write is denied when
Kyverno does not answer. With `Ignore`, the write is allowed.

## Project ServiceAccounts

When `projectSync.serviceAccounts.enabled` is true, project-sync keeps three
ServiceAccounts for each tenant project: `project-owner`, `project-member`, and
`read-only`. The ServiceAccounts are in the namespace `drover-<project id>`, in a hidden
project of the cluster.

A token of such a ServiceAccount has the Kubernetes rights of its project role in every
namespace of the project: `admin`, `edit`, or `view`. It also has the namespace rights of
that role in the project. It does not have the extra rules of the Rancher role templates,
for example the monitoring resources or the read of nodes.

With this value on, the service user of project-sync gets wide rights in every cluster.
It gets every verb on namespaces. It can also create ServiceAccounts, roles, and
bindings, and it can create tokens of the project ServiceAccounts.

## Short-lived credentials

A tenant can have automation outside the cluster that works in the namespaces of its
project. Examples are a GitHub Actions workflow, a GitLab CI job, and an AWS Lambda
function. Such a client needs a Kubernetes credential. Without drover, the tenant must
store a long-lived secret in the client, for example a ServiceAccount token that does not
expire.

With drover, the client needs no stored secret. The client proves its own identity to
[OpenBao](https://openbao.org), and OpenBao gives it a token of a project ServiceAccount.
By default, the token is valid for 15 minutes.

When `projectSync.serviceAccounts.enabled` is true, Helm installs OpenBao in the release
namespace. A client then gets a token in three steps:

1. The client logs in to OpenBao with the identity that it already has: the JWT of its
   CI system, or its AWS IAM role. The login role of the client has the policy
   `kubernetes-<cluster id>-<project id>-<role>`.
2. The client requests the credential
   `kubernetes/<cluster id>/creds/<project id>-<role>`, with
   `kubernetes_namespace=drover-<project id>`.
3. The client uses the token from the answer at
   `<Rancher URL>/k8s/clusters/<cluster id>`, for example with `kubectl`.

The role is `project-owner`, `project-member`, or `read-only`. project-sync writes the
credential roles and the policies for each project, and it removes them for a deleted
project. A credential is valid for `global.broker.credentials.ttl`. A client can request
a longer time, up to `global.broker.credentials.maxTTL`.

OpenBao reaches each cluster through the Rancher URL in `global.broker.rancherUrl`. When
the value is empty, Helm uses the first entry of `httpRoute.hostnames`. OpenBao verifies
the certificate of that URL, so a Rancher with a private CA needs the Rancher setting
`cacerts`.

Helm does not create login roles yet. An OpenBao admin writes each login role. See
[OpenBao administration](#openbao-administration) for the admin login.

### Login with a JWT

A client in a CI system, for example a GitHub Actions workflow, gets a JWT from that
system and logs in with it. For each entry of `global.broker.jwtIssuers`, OpenBao has a
JWT auth mount at `auth/jwt/<name>`. The default entries are GitHub Actions and
GitLab.com. When an entry is removed from the value, OpenBao removes the mount and its
login roles at the next upgrade.

OpenBao reads the discovery URL of each issuer at an install and at an upgrade. When
OpenBao cannot reach an issuer, the mount keeps its previous config, and a new mount has
no config until the next upgrade.

### Login with an AWS identity

When `global.broker.aws.enabled` is true, a client with an AWS IAM role can log in at
the auth mount `auth/aws`. The default is false. When the value goes back to false,
OpenBao removes the mount and its login roles.

- OpenBao needs egress to `ghcr.io` and to `sts.<region>.amazonaws.com`. Without egress
  to `ghcr.io`, OpenBao does not start. Keep the value false in such a cluster.
- `openbao.server.gateway.httpRoute.hosts` must contain the host name of OpenBao.

For a login, a client signs an `sts:GetCallerIdentity` request with its AWS credentials
and sends the signed request to `auth/aws/login`. The signed request must contain the
header `X-Vault-AWS-IAM-Server-ID`, with the first host of
`openbao.server.gateway.httpRoute.hosts` as its value. The client can sign the request
for the AWS region of its choice.

Write a login role with `resolve_aws_unique_ids=false` and the exact ARN of the IAM
role. The ARN must have no path and no wildcard.

```sh
bao write auth/aws/role/<name> auth_type=iam resolve_aws_unique_ids=false \
  bound_iam_principal_arn=arn:aws:iam::<account id>:role/<role name> \
  token_policies=kubernetes-<cluster id>-<project id>-<role>
```

OpenBao identifies an IAM role by its account ID and its name. When a tenant deletes an
IAM role and creates it again with the same name, the new IAM role can log in.

### OpenBao administration

OpenBao runs three replicas with a PersistentVolume each. Helm installs it from the
[openbao chart](https://github.com/openbao/openbao-helm), with the values under the
`openbao` key.

- **Route.** Set the route of OpenBao in `openbao.server.gateway.httpRoute`. Clients and
  admins reach OpenBao through this route.
- **Admin login.** OpenBao has no root token and no recovery key. An admin logs in with
  a token of the ServiceAccount `<openbao fullname>-admin`:

  ```sh
  bao write auth/kubernetes/login role=admin \
    jwt="$(kubectl -n <namespace> create token <openbao fullname>-admin)"
  ```

- **Seal key.** OpenBao unseals its data with the key in the Secret `openbao-seal`. Helm
  creates the Secret when it does not exist. Without the key, OpenBao cannot read its
  data.
- **Lost seal key.** When the Secret does not exist but a `data-*` PersistentVolumeClaim
  of OpenBao exists, the install or the upgrade stops. Delete the `data-*`
  PersistentVolumeClaims of OpenBao. OpenBao then starts with empty data.
- **Lost volume of pod 0.** When pod 0 lost its volume but a `data-*` claim of another
  pod exists, pod 0 stays not ready. Restore the volume, or delete all `data-*`
  PersistentVolumeClaims.
- **Metrics.** Helm creates a `PodMonitor` for OpenBao. The metrics are on port 8210,
  and the route does not reach that port.

## Network policies

Helm creates a `CiliumNetworkPolicy` for each component. DNS traffic and the metric
scrapes need a separate policy. For a cluster without Cilium, set
`ciliumNetworkPolicy.enabled` to false.

- Every component can reach the API server. The API filter, project-sync, and the token
  rotation can also reach `rancher.namespace`.
- The API filter and OpenBao accept traffic from the namespaces in
  `ciliumNetworkPolicy.gatewayNamespaces`. Set this value to the namespaces of the
  gateway pods.
- OpenBao reaches the Rancher host and the hosts of `global.broker.jwtIssuers` on port
  443. When `global.broker.aws.enabled` is true, OpenBao also reaches `ghcr.io`,
  `pkg-containers.githubusercontent.com`, and the hosts `sts.*.amazonaws.com`. These
  rules are rules by host name, so the cluster needs the Cilium DNS proxy.

## Uninstall

Helm does not delete these objects at an uninstall:

- The seal key Secret and the `data-*` PersistentVolumeClaims of OpenBao. After a
  reinstall, OpenBao thus unseals the old data.
- The objects of `projectSync.serviceAccounts`: the hidden projects, the
  `drover-<project id>` namespaces, the ServiceAccounts, and their bindings. A token of
  such a ServiceAccount stays valid. To remove the objects, delete the projects with the
  label `drover-service-accounts` and the namespaces with the label `drover-project`.

## Values

See [values.yaml](values.yaml) for all keys. Helm stops with an error when a dependent
value is not set. The keys with the value zero select the default of the drover service.

| Key | Default | Description |
|---|---|---|
| `rancher.url` | none | Required. The `https` URL of the Rancher Service in the cluster. |
| `rancher.insecureSkipVerify` | `false` | When true, drover does not verify the certificate of `rancher.url`. |
| `rancher.namespace` | `cattle-system` | The namespace of the Rancher Deployment. |
| `httpRoute.parentRefs` | `[]` | Required. The gateway of Rancher. |
| `httpRoute.hostnames` | `[]` | The hostname of Rancher. |
| `httpRoute.rancherBackendRef` | none | The Rancher Service. Required when `apiFilter.fanout.enabled` is true. |
| `apiFilter.replicaCount` | `3` | The number of API filter pods. |
| `apiFilter.fanout.enabled` | `false` | See [Cluster-wide reads](#cluster-wide-reads). |
| `serviceUser.password.refreshInterval` | `2160h` | The time between two passwords of a service user. |
| `tokenRotation.schedule` | `*/10 * * * *` | The schedule of the token rotation CronJob. |
| `tokenRotation.ttl` | `48h` | The lifetime of an API token of a service user. |
| `tokenRotation.renewBefore` | `24h` | A rotation run renews a token that expires within this time. It must be shorter than `tokenRotation.ttl`. |
| `projectSync.interval` | `60s` | The time between two full runs of project-sync. |
| `projectSync.labelKeys` | `[]` | The label keys that project-sync copies to the namespaces. |
| `projectSync.annotationKeys` | `[]` | The annotation keys that project-sync copies to the namespaces. |
| `projectSync.nameLabel` | `""` | The label key for the label-safe display name. An empty value turns it off. |
| `projectSync.nameAnnotation` | `""` | The annotation key for the display name. An empty value turns it off. |
| `projectSync.serviceAccounts.enabled` | `false` | See [Project ServiceAccounts](#project-serviceaccounts). When true, Helm also installs OpenBao. |
| `projectPolicy.requiredLabels` | `[]` | See [Required project metadata](#required-project-metadata). |
| `projectPolicy.requiredAnnotations` | `[]` | See [Required project metadata](#required-project-metadata). |
| `projectPolicy.failurePolicy` | `Fail` | `Fail` or `Ignore`. |
| `clusterProxyConfig.enabled` | `true` | See [ServiceAccount tokens](#serviceaccount-tokens). |
| `ciliumNetworkPolicy.enabled` | `true` | See [Network policies](#network-policies). |
| `ciliumNetworkPolicy.gatewayNamespaces` | `[]` | The namespaces of the gateway pods. |
| `global.broker.jwtIssuers` | GitHub Actions, GitLab.com | A map from a name to the `discoveryUrl` of a JWT issuer. |
| `global.broker.aws.enabled` | `false` | See [Login with an AWS identity](#login-with-an-aws-identity). |
| `global.broker.credentials.ttl` | `15m` | The lifetime of a credential. |
| `global.broker.credentials.maxTTL` | `2h` | The longest lifetime that a client can request. |
| `global.broker.rancherUrl` | `""` | The Rancher URL through which OpenBao reaches the clusters. |
| `openbao` | | The values of the openbao chart. |
| `otlp.endpoint` | `""` | The OTLP endpoint for the telemetry of drover. An empty value turns telemetry off. |
| `logLevel` | `info` | The log level of the drover components. |
