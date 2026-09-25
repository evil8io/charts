# node-local-dns

The chart runs NodeLocal DNSCache (node-cache) as a DaemonSet. Each node gets one cache
pod. The cache answers the DNS queries of the pods on its node, and it forwards a cache
miss to the upstream DNS Service `kube-dns-upstream`.

## Usage

```bash
helm install node-local-dns oci://ghcr.io/evil8io/charts/node-local-dns \
  --namespace kube-system
```

Install the chart in the namespace of the cluster DNS Service. The pods mount the
optional ConfigMap `kube-dns` of that namespace for the stub domains of the cluster.

## Cilium local redirect mode

The chart supports one mode: a CiliumLocalRedirectPolicy sends the traffic for the
cluster DNS Service to the cache pod on the same node. The pods do not use the host
network, and node-cache makes no change to the network of the node. The default
`extraArgs` set this mode:

| Flag | Effect |
|---|---|
| `-setupinterface=false` | node-cache creates no network interface for `localIp`. |
| `-setupiptables=false` | node-cache adds no iptables rules. |
| `-skipteardown=true` | node-cache removes no interface and no rules when it stops. |

Helm replaces a list value as a whole. Keep the three flags when you add a flag to
`extraArgs`.

The chart has no CiliumLocalRedirectPolicy and no CiliumNetworkPolicy. An object of a
Cilium CRD in the release makes the release depend on Cilium.

Apply the two policies after Cilium, after the CoreDNS release, and after this release.
The redirect policy sends all queries for `kube-dns` to the cache pods, so it must not
exist before the cache pods and CoreDNS exist. These examples are for the CoreDNS of the
coredns chart in `kube-system`:

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
          # all admits Fargate nodes and hostNetwork pods
          - all
        toPorts:
          - ports:
              - port: "53"
    egress:
      - toEntities:
          - kube-apiserver
      # Forwarding to the upstream DNS
      - toPorts:
          - ports:
              - port: "53"
```

The pods have the annotation `io.cilium.no-track-port: "53"`, so Cilium does not track
the connections of the DNS port.

## Taint remover and role label

`taintRemover.enabled` adds the `node-taint-remover` container. The container sends DNS
queries for `kubernetes.default.svc.cluster.local.` until the cache pod answers, with
120 attempts at most. Then it removes the taint `taintRemover.taint` from its node, and
sleeps. Give each new node this taint as a startup taint. A pod without a toleration
for the taint then starts only on a node with a working DNS cache. The default
`dnsConfig` sets the name server 127.0.0.1, so the container queries the cache in its
own pod.

`nodeRoleLabel.enabled` adds the `node-role-label` init container. It reads the value of
the node label `nodeRoleLabel.key`, and sets the label `node-role.kubernetes.io/<value>`
on the node. `kubectl get nodes` shows that label in the `ROLES` column. The kubelet
cannot set a label with the `node-role.kubernetes.io` prefix on its own node.

Both containers use `kubectl.image`, which needs `kubectl`, `jq`, `getent`, and
`timeout`. The chart renders a ClusterRole with `get` and `patch` on nodes when one of
the two containers is enabled.

## Updates

The default update strategy is `OnDelete`. A chart upgrade changes no running pod. A
pod gets the new spec when you delete it, or when its node is replaced. The wait of
Helm 3 treats a DaemonSet with the `OnDelete` strategy as ready at once.

## Values

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Replaces the chart name in the object names and in the `app.kubernetes.io/name` label. The label is the DaemonSet selector. |
| `fullnameOverride` | `""` | Replaces the name of the DaemonSet, ConfigMap, ServiceAccount, ClusterRole, ClusterRoleBinding, and PodMonitor. |
| `platform` | `generic` | `generic` or `aws`. Every platform gets a node affinity for Linux nodes with amd64 or arm64. `aws` also excludes the nodes with the label `eks.amazonaws.com/compute-type: fargate`, because EKS Fargate does not run DaemonSet pods. |
| `image.repository` | `registry.k8s.io/dns/k8s-dns-node-cache` | The node-cache image. |
| `image.tag` | `1.26.8` | The image tag. |
| `localIp` | `172.20.0.1` | The value of the `-localip` flag of node-cache. |
| `extraArgs` | the three flags of the Cilium local redirect mode | The node-cache flags after `-localip`, `-conf`, and `-upstreamsvc`. |
| `upstreamService.name` | `kube-dns-upstream` | The name of the Service in front of the upstream DNS server, and the value of the `-upstreamsvc` flag. |
| `upstreamService.selector` | `app.kubernetes.io/name: coredns` | The pod labels of the upstream DNS server. The Service also gets these labels. |
| `corefile` | cache for `cluster.local`, `in-addr.arpa`, `ip6.arpa`, and `.`, forward to the upstream Service | The Corefile. node-cache replaces `__PILLAR__CLUSTER__DNS__` with the address of the upstream Service. |
| `resources` | 25m CPU and 50Mi memory requests | The resources of the node-cache container. |
| `podAnnotations` | `io.cilium.no-track-port: "53"` | Annotations on the pod template. |
| `dnsConfig` | name server 127.0.0.1, `timeout` 2, `attempts` 5 | The DNS configuration of the pod. A non-empty value sets `dnsPolicy: None`. |
| `tolerations` | `- operator: Exists` | The tolerations of the pod. The default tolerates every taint. |
| `priorityClassName` | `system-node-critical` | The priority class of the pod. |
| `terminationGracePeriodSeconds` | `125` | Keep it above the `lameduck` time of the `health` plugin in the Corefile (120 s). |
| `updateStrategy` | `type: OnDelete` | The update strategy of the DaemonSet. |
| `kubectl.image.repository` | `dtzar/helm-kubectl` | The image of the init container and of the taint remover. |
| `kubectl.image.tag` | `4.3.0` | The image tag. |
| `nodeRoleLabel.enabled` | `false` | Adds the `node-role-label` init container. |
| `nodeRoleLabel.key` | `node.evil8.io/role` | The node label that has the role name. |
| `taintRemover.enabled` | `false` | Adds the `node-taint-remover` container. |
| `taintRemover.taint` | `startup-taint.cluster-autoscaler.kubernetes.io/dns-not-ready` | The taint key that the container removes. |
| `taintRemover.resources` | 25m CPU and 50Mi memory requests | The resources of the taint remover container. |
| `podMonitor.enabled` | `false` | Renders a PodMonitor for the metrics ports 9253 and 9353. It needs the PodMonitor CRD of the Prometheus operator. |
