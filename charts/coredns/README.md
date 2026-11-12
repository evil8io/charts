# coredns

Installs CoreDNS as the cluster DNS server, behind the Service `kube-dns`.

Set `service.clusterIP` to the `clusterDNS` address of the kubelet. The kubelet writes
this address into the `resolv.conf` file of each pod.

## Values

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `3` | The replica count at the first install. |
| `autoscaling.enabled` | `true` | An upgrade keeps the replica count that your autoscaler set, for example a KEDA ScaledObject. Put the annotations that the autoscaler reads in `deploymentAnnotations`. Set the key to `false` to reset the count to `replicaCount` at each upgrade. |
| `corefile` | CoreDNS for `cluster.local`, forward to `/etc/resolv.conf` of the node, 30 s cache | The Corefile. CoreDNS loads a change without a pod restart. |
| `terminationGracePeriodSeconds` | `35` | Keep it above the `lameduck` time in `corefile` (30 s), so that CoreDNS answers until the Service stops sending queries to the pod. |
| `service.clusterIP` | `""` | The address of the DNS Service. When it is empty, Kubernetes selects an address. |
| `podDisruptionBudget` | `maxUnavailable: 1`, `unhealthyPodEvictionPolicy: AlwaysAllow` | The spec of the PodDisruptionBudget, without the selector. Set `{}` to turn it off. |
| `podMonitor.enabled` | `false` | Adds a PodMonitor for the metrics port 9153. It needs the PodMonitor CRD of the Prometheus operator. |
