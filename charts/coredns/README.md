# coredns

The chart installs CoreDNS as the cluster DNS server. The Service `kube-dns` sends the
DNS queries of the pods to the CoreDNS pods.

## Usage

```bash
helm install coredns oci://ghcr.io/evil8io/charts/coredns \
  --namespace kube-system \
  --set service.clusterIP=10.100.0.10
```

Set `service.clusterIP` to the `clusterDNS` address of the kubelet. The kubelet writes
this address into the `resolv.conf` file of each pod.

## Replicas

With `autoscaling.enabled` true (the default), an autoscaler sets the replica count,
for example a KEDA ScaledObject. Put the annotations that the autoscaler reads in
`deploymentAnnotations`.

The chart reads the live Deployment with the Helm `lookup` function, and renders its
`spec.replicas`. Thus the replica count behaves as follows:

- A first install sets the count to `replicaCount`.
- An upgrade renders the live count, so Helm does not change the count that the
  autoscaler set.
- `helm template` and `--dry-run=client` have no cluster connection. They render
  `replicaCount`.
- `helm rollback` applies the count of the stored revision.

With `autoscaling.enabled` false, the chart renders `replicaCount`, and each upgrade
resets the count to that value.

## Values

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Replaces the chart name in the object names and in the `app.kubernetes.io/name` label. The label is part of the Deployment selector. |
| `fullnameOverride` | `""` | Replaces the name of the Deployment, ConfigMap, ServiceAccount, PodDisruptionBudget, and PodMonitor. |
| `image.repository` | `registry.k8s.io/coredns/coredns` | The CoreDNS image. |
| `image.tag` | `v1.14.3` | The image tag. |
| `replicaCount` | `3` | The replica count at the first install, and at each upgrade when `autoscaling.enabled` is false. |
| `autoscaling.enabled` | `true` | Renders the replica count of the live Deployment, so that an upgrade keeps the count of an autoscaler. See Replicas. |
| `corefile` | CoreDNS for `cluster.local`, forward to `/etc/resolv.conf` of the node, 30 s cache | The Corefile. The `reload` plugin loads a change without a pod restart. |
| `resources` | 100m CPU and 70Mi memory requests | The container resources. |
| `deploymentAnnotations` | `{}` | Annotations on the Deployment. |
| `podAnnotations` | `{}` | Annotations on the pod template. |
| `tolerations` | `[]` | The tolerations of the pod. |
| `affinity` | Linux nodes with amd64 or arm64, preferred one pod per node | The affinity of the pod. |
| `priorityClassName` | `system-cluster-critical` | The priority class of the pod. |
| `terminationGracePeriodSeconds` | `35` | Keep it above the `lameduck` time of the `health` plugin (30 s), so that CoreDNS answers until the Service stops sending queries to the pod. |
| `service.name` | `kube-dns` | The name of the DNS Service. |
| `service.clusterIP` | `""` | The address of the DNS Service. Empty lets the API server select an address. |
| `rbac.clusterRoleName` | `system:coredns` | The name of the ClusterRole and the ClusterRoleBinding. |
| `podDisruptionBudget` | `maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow` | The spec of the PodDisruptionBudget without the selector. An empty map renders no PodDisruptionBudget. |
| `podMonitor.enabled` | `false` | Renders a PodMonitor for the metrics port 9153. It needs the PodMonitor CRD of the Prometheus operator. |
