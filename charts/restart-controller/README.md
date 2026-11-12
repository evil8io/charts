# restart-controller

The restart-controller restarts the subscribed Deployments, DaemonSets, and
StatefulSets when an API server is removed or when a CustomResourceDefinition (CRD)
is created.

Some clients keep a watch on one API server, or read the API discovery data only once
at start. Such a client does not get events after its API server is removed, or does
not see the resources of a new CRD. After a restart, the client opens a new watch and
reads the discovery data again.

## Subscribe a workload

Add a trigger label with the value `"true"` to the Deployment, DaemonSet, or
StatefulSet. Put the label on the workload object, not on the pod template.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-controller
  labels:
    restart.autopilot.kubernetes.io/on-apiserver-removal: "true"
    restart.autopilot.kubernetes.io/on-crd-change: "true"
```

| Label | Trigger |
|---|---|
| `restart.autopilot.kubernetes.io/on-apiserver-removal` | An address is removed from the `default/kubernetes` EndpointSlice. The controller ignores an added address. |
| `restart.autopilot.kubernetes.io/on-crd-change` | A CRD is created. The controller ignores a change to an existing CRD. |

The controller does not restart a StatefulSet with the `OnDelete` update strategy.

## RBAC

The controller can patch every Deployment, DaemonSet, and StatefulSet in the cluster.
A holder of its ServiceAccount token can thus change any pod template. Treat the
ServiceAccount token as a cluster-admin credential.

## Network policies

The controller does not need DNS.

- When `ciliumNetworkPolicy.enabled` is true, Helm creates a CiliumNetworkPolicy. The
  policy allows egress to the `kube-apiserver` entity only.
- When `networkPolicy.enabled` is true, Helm creates a NetworkPolicy. The policy allows
  egress on TCP ports 443 and 6443 to all addresses.

## Values

| Key | Default | Description |
|---|---|---|
| `image.repository` | `dtzar/helm-kubectl` | The image needs `bash`, `kubectl`, `jq`, and `awk`. |
| `intervalSeconds` | `15` | The time in seconds between the start of two checks of the cluster. Keep it below 120. The liveness probe fails when a check does not start within 120 s. |
| `triggers.apiserverRemoval.label` | `restart.autopilot.kubernetes.io/on-apiserver-removal` | The workload label for the API server trigger. |
| `triggers.apiserverRemoval.annotation` | `restart.autopilot.kubernetes.io/apiserver-removal-at` | The pod template annotation that the controller sets to the trigger time. |
| `triggers.apiserverRemoval.settleSeconds` | `0` | The minimum time in seconds between the trigger and the restart. Keep it at 0. A client with a watch on the removed API server does not get events until the restart. |
| `triggers.crdChange.label` | `restart.autopilot.kubernetes.io/on-crd-change` | The workload label for the CRD trigger. |
| `triggers.crdChange.annotation` | `restart.autopilot.kubernetes.io/crd-change-at` | The pod template annotation that the controller sets to the trigger time. |
| `triggers.crdChange.settleSeconds` | `120` | The controller restarts the subscribed workloads when the newest CRD is at least this many seconds old. When the CRDs of an install are created less than this time apart, the controller restarts each subscribed workload once. |
