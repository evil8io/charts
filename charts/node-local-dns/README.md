# node-local-dns

NodeLocal DNSCache (node-cache) for a cluster with Cilium. One cache pod runs on each
Linux node with amd64 or arm64. The cache answers the DNS queries of the pods on its node. The cache forwards a cache miss
to the upstream DNS Service `kube-dns-upstream`.

Install the chart in the namespace of the cluster DNS Service. The cache reads the stub
domains of the cluster from the optional ConfigMap `kube-dns` in that namespace.

## Cilium local redirect mode

The chart is for Cilium local redirect mode only. In this mode, Cilium sends the traffic
for the cluster DNS Service to the cache pod on the same node. The redirect is configured
in a [CiliumLocalRedirectPolicy](https://docs.cilium.io/en/stable/network/kubernetes/local-redirect-policy/).

The default `extraArgs` contain the node-cache flags for this mode. When you set
`extraArgs`, Helm replaces the whole default list. Keep the three default flags in your
list.

The chart does not contain a CiliumLocalRedirectPolicy or a CiliumNetworkPolicy. Apply
the two policies after Cilium, after the CoreDNS release, and after this release. The
reason is that Cilium sends all queries for `kube-dns` to the cache pods as soon as the
redirect policy exists. These examples are for CoreDNS from the coredns chart in the
namespace `kube-system`:

```yaml
apiVersion: cilium.io/v2
kind: CiliumLocalRedirectPolicy
metadata:
  name: node-local-dns
  namespace: kube-system
spec:
  redirectFrontend:
    serviceMatcher:
      serviceName: kube-dns
      namespace: kube-system
  redirectBackend:
    localEndpointSelector:
      matchLabels:
        app.kubernetes.io/name: node-local-dns
    toPorts:
      - port: "53"
        name: dns
        protocol: UDP
      - port: "53"
        name: dns-tcp
        protocol: TCP
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: dns
  namespace: kube-system
specs:
  - description: Allow traffic to node-local-dns from the cluster
    endpointSelector:
      matchLabels:
        app.kubernetes.io/name: node-local-dns
    ingress:
      - fromEntities:
          - cluster
        toPorts:
          - ports:
              - port: "53"
    egress:
      - toEntities:
          - kube-apiserver
  - description: Allow traffic to coredns and kube-apiserver access
    endpointSelector:
      matchLabels:
        app.kubernetes.io/name: coredns
    ingress:
      - fromEntities:
          # The entity all includes Fargate nodes and hostNetwork pods.
          - all
        toPorts:
          - ports:
              - port: "53"
    egress:
      - toEntities:
          - kube-apiserver
      # Egress to the upstream DNS servers
      - toPorts:
          - ports:
              - port: "53"
```

## Taint remover and role label

With `taintRemover.enabled`, the cache pod removes the taint `taintRemover.taint` from
its node when the cache answers, or after 120 failed queries. Give each new node this
taint as a startup taint. The scheduler then does not place a pod without a toleration
for the taint on the node until the taint is removed.

With `nodeRoleLabel.enabled`, the cache pod reads the value of the node label
`nodeRoleLabel.key` and sets the label `node-role.kubernetes.io/<value>` on its node.

Both options need a ClusterRole with `get` and `patch` on nodes, which is part of the
chart.

## Values

| Key | Default | Description |
|---|---|---|
| `platform` | `generic` | `generic` or `aws`. With `aws`, the DaemonSet controller does not create a pod for an EKS Fargate node. EKS Fargate does not run DaemonSet pods. |
| `extraArgs` | `-skipteardown=true`, `-setupiptables=false`, `-setupinterface=false` | Extra node-cache flags. The container arguments already contain `-localip`, `-conf`, and `-upstreamsvc`. |
| `upstreamService.name` | `kube-dns-upstream` | The name of the Service in front of the upstream DNS server. |
| `upstreamService.selector` | `app.kubernetes.io/name: coredns` | The pod labels of the upstream DNS server. |
| `corefile` | a cache for `cluster.local`, `in-addr.arpa`, `ip6.arpa`, and `.`, with a forward to the upstream Service | node-cache replaces `__PILLAR__CLUSTER__DNS__` with the address of the upstream Service. |
| `terminationGracePeriodSeconds` | `125` | Keep the value above the `lameduck` time of the `health` plugin in `corefile` (120 s). |
| `updateStrategy` | `type: OnDelete` | With the default, the DaemonSet controller does not replace a running pod at an upgrade. The controller creates a pod with the new spec only after the old pod is deleted, or on a new node. |
| `kubectl.image.repository` | `dtzar/helm-kubectl` | The image for the taint remover and the role label. The image needs `kubectl`, `jq`, `getent`, and `timeout`. |
| `nodeRoleLabel.key` | `node.evil8.io/role` | The node label that contains the role name. |
| `taintRemover.taint` | `startup-taint.cluster-autoscaler.kubernetes.io/dns-not-ready` | The key of the startup taint. |
| `podMonitor.enabled` | `false` | Adds a PodMonitor for the metrics ports 9253 and 9353. The PodMonitor needs the PodMonitor CRD of the Prometheus Operator. |
