# drover

Tenancy extensions for Rancher ([evil8io/drover](https://github.com/evil8io/drover)).
One image has three components. Every component authenticates as one Rancher service
user, through one token Secret.

1. `apiFilter`: a reverse proxy in front of Rancher. It limits the namespace
   list of a tenant to the namespaces of its projects. With `apiFilter.fanout.enabled`,
   it also answers a cluster-wide list of a namespaced kind, for example
   `kubectl get pods -A`, with one request per allowed namespace.
2. `tokenRotation`: a CronJob that logs in as the service user and writes
   the API token into the token Secret. A run renews the token only when it expires
   inside `tokenRotation.renewBefore`. The CronJob is the only writer of the token Secret.
3. `projectSync`: copies `projectSync.labelKeys` and
   `projectSync.annotationKeys` from a Rancher project to the namespaces of the project.
   `projectSync.nameAnnotation` gets the display name of the project, and
   `projectSync.nameLabel` gets a label-safe copy: a character outside `[A-Za-z0-9._-]`
   becomes `-`, and the value is cut to 63 characters. The sync records the keys that it
   wrote in the namespace annotations `drover-managed-labels` and
   `drover-managed-annotations`. It removes a key of that record once the project drops
   it, and a key outside the record belongs to the tenant.

The chart needs `rancher.url` and `httpRoute.parentRefs`. The filter reads the token
file on every use, so a new token needs no restart.

## Service user

The chart adds the Rancher `User` object `u-drover`, the password Secret that Rancher
reads, and two hook Jobs. The external-secrets `Password` generator writes the password
into the credentials Secret of the release, so the chart needs the external-secrets
CRDs. The rotation run derives the PBKDF2-SHA3-512 hash from that Secret, and it writes
the hash into the password Secret before the login. The generator makes a new password
every `serviceUser.password.refreshInterval`. The token in use stays valid, so the
rotation costs no outage.

The `post-install` Job applies the `RoleTemplate`, the `GlobalRole` that inherits it on
every downstream cluster, and three bindings: the `GlobalRoleBinding`, the `user-base`
`GlobalRoleBinding`, and a `ClusterRoleTemplateBinding` in the `local` cluster, because
an inherited cluster role never applies to the local cluster. The `pre-delete` Job
deletes them in the reverse order.

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

## Values

See [values.yaml](values.yaml). A comment describes each key whose name does not explain
it. A template fails the render on a dependent value that is missing.
