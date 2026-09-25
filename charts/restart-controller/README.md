# restart-controller

The restart-controller restarts subscribed Deployments, DaemonSets, and StatefulSets
after one of two cluster events:

- An API server address leaves the `default/kubernetes` EndpointSlice.
- A new CustomResourceDefinition (CRD) appears.

Some clients keep a watch on one API server, or read the API discovery data only once
at start. Such a client misses events after the removal of its API server, or does not
see the resources of a new CRD. A restart of the client fixes both.

The controller is a Bash loop with `kubectl` and `jq`. It runs one pass every
`intervalSeconds`. The chart runs one replica with the `Recreate` strategy, so two
controllers never run at the same time.

## Usage

```bash
helm install restart-controller oci://ghcr.io/evil8io/charts/restart-controller \
  --namespace restart-controller --create-namespace
```

## Subscribe a workload

Add a trigger label with the value `"true"` to the Deployment, DaemonSet, or
StatefulSet:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-controller
  labels:
    restart.autopilot.kubernetes.io/on-apiserver-removal: "true"
    restart.autopilot.kubernetes.io/on-crd-change: "true"
```

Put the label on the workload object, not on the pod template, because the controller
finds the subscribers with a label selector on the workload objects.

| Label | Trigger | Settle time |
|---|---|---|
| `restart.autopilot.kubernetes.io/on-apiserver-removal` | A pass sees that an address left the `default/kubernetes` EndpointSlice. An added API server does not count, because it does not close client connections. | 0 s. Do not add a settle time, because a watch on the removed API server stays stale until the restart. |
| `restart.autopilot.kubernetes.io/on-crd-change` | The newest CRD `creationTimestamp` changes. Only a new CRD counts. | 120 s after the newest `creationTimestamp`. Each new CRD in this time moves the trigger, so an install of many CRDs causes one restart. |

## Restarts

The controller restarts a workload with a patch of the trigger annotation on the pod
template, as `kubectl rollout restart` does. The annotation value is the trigger time.
The controller skips a workload whose annotation already has that time or a later time.

The controller skips a StatefulSet with the `OnDelete` update strategy, because a pod
template change does not restart its pods.

At each start, the controller handles the newest CRD again. A subscriber without the
annotation restarts once at that pass. After a new install, this applies to each
subscriber.

The controller writes the time of the last API server removal to the ConfigMap
`<fullname>-state`. After a restart of the controller, it reads that time and restarts
the subscribers that it did not restart yet. The CRD trigger needs no state, because
the controller reads the CRDs from the cluster at each pass.

The controller writes a heartbeat file at the start of each pass. The liveness probe
restarts the pod when the heartbeat is 120 s old.

## RBAC

| Kind | Rules |
|---|---|
| ClusterRole | `get` and `list` on `endpointslices`. `list` on `customresourcedefinitions`. `get`, `list`, and `patch` on `deployments`, `daemonsets`, and `statefulsets`. |
| Role | `get` and `update` on the state ConfigMap only. |

The `patch` rule applies to all Deployments, DaemonSets, and StatefulSets in the
cluster. With it, the ServiceAccount can change any pod template, which is almost
equal to cluster-admin. Treat the ServiceAccount token as a cluster-admin credential.

## Network policies

The controller needs no DNS, because `kubectl` in a pod connects to the IP address in
the `KUBERNETES_SERVICE_HOST` variable.

- `ciliumNetworkPolicy.enabled` renders a CiliumNetworkPolicy that allows egress to
  the `kube-apiserver` entity only.
- `networkPolicy.enabled` renders a NetworkPolicy. A NetworkPolicy cannot select the
  API server, so it allows egress on TCP ports 443 and 6443 to all addresses.

## Values

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Replaces the chart name in the object names and in the `app.kubernetes.io/name` label. |
| `fullnameOverride` | `""` | Replaces the full object name. |
| `image.repository` | `dtzar/helm-kubectl` | The image needs `bash`, `kubectl`, and `jq`. |
| `image.tag` | `4.3.0` | The image tag. |
| `intervalSeconds` | `15` | The time between the start of two passes. Keep it below 120 s, the heartbeat limit of the liveness probe. |
| `triggers.apiserverRemoval.label` | `restart.autopilot.kubernetes.io/on-apiserver-removal` | The workload label that subscribes to the API server trigger. |
| `triggers.apiserverRemoval.annotation` | `restart.autopilot.kubernetes.io/apiserver-removal-at` | The pod template annotation that the restart sets to the trigger time. |
| `triggers.apiserverRemoval.settleSeconds` | `0` | The minimum time between the trigger and the restart. |
| `triggers.crdChange.label` | `restart.autopilot.kubernetes.io/on-crd-change` | The workload label that subscribes to the CRD trigger. |
| `triggers.crdChange.annotation` | `restart.autopilot.kubernetes.io/crd-change-at` | The pod template annotation that the restart sets to the trigger time. |
| `triggers.crdChange.settleSeconds` | `120` | The minimum time between the newest CRD `creationTimestamp` and the restart. |
| `deploymentAnnotations` | `{}` | Annotations on the Deployment. |
| `podAnnotations` | `{}` | Annotations on the pod template. |
| `nodeSelector` | `{}` | The node selector of the pod. |
| `tolerations` | `[]` | The tolerations of the pod. |
| `resources` | 100m CPU and 200Mi memory requests, 200Mi memory limit | The container resources. |
| `podSecurityContext` | user and group 1001, non-root, `RuntimeDefault` seccomp profile | The pod security context. |
| `containerSecurityContext` | no privilege escalation, no capabilities, read-only root file system | The container security context. An emptyDir on `/tmp` is the home directory and has the heartbeat file. |
| `ciliumNetworkPolicy.enabled` | `false` | Renders the CiliumNetworkPolicy. |
| `networkPolicy.enabled` | `false` | Renders the NetworkPolicy. |
