# gvisor

With this chart, a pod on each selected node installs [gVisor](https://gvisor.dev). Use the
chart for nodes whose image or boot script does not contain gVisor. At its start, the pod
does these steps on the node:

1. It downloads the gVisor release `gvisor.version` and checks the SHA-512 checksum.
2. It extracts `runsc`, `containerd-shim-runsc-v1`, and the directory `gvisor-bin` into
   `/usr/local/bin`.
3. It adds the runtime `runsc` to the containerd configuration `containerd.configPath`.
4. It restarts containerd.

The pod does these steps one time for each node. After a restart of the node, the pod
does not install gVisor again.

Select the nodes with `nodeSelector` and `affinity`. With the default `nodeSelector`,
Kubernetes runs a pod on each Linux node.

## Requirements

- The nodes run Linux 5.6 or later on x86_64 or arm64.
- systemd runs containerd as the unit `containerd`.
- The file `containerd.configPath` contains the table of the runtime `runc`, for example
  `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]`. Without this table,
  the pod fails with `<path> does not contain a table for the runtime runc`.
- The nodes have `bash`, `curl`, `tar`, `zstd`, and `sha512sum`.
- The nodes have egress to `storage.googleapis.com` on port 443.
- A privileged pod with `hostPID` and `hostNetwork` must be permitted in the namespace of
  the Helm release.

## RuntimeClass

The chart does not contain a RuntimeClass. Create a RuntimeClass with the handler `runsc`.
A pod that has the name of this RuntimeClass in `runtimeClassName` then runs in gVisor.
When only some nodes have gVisor, give the RuntimeClass the node selector of those nodes:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
scheduling:
  nodeSelector:
    example.com/runtime: gvisor
```

## Startup taint

The scheduler can place a pod on a new node before the install is complete. A pod with
the RuntimeClass on such a node does not start, because containerd does not have the
runtime `runsc` yet. To prevent this, give each selected node the taint
`taintRemover.taint` as a startup taint. Then set `taintRemover.enabled` to `true`. The
scheduler does not place a pod without a toleration for the taint on the node. After the
install, the pod removes the taint from its node.

## gVisor upgrade

After an upgrade of the Helm release, the new pod on a node with gVisor does not install
gVisor again. The old gVisor version stays on the node. To get a new `gvisor.version` on a
node, replace the node.

## Values

| Key | Default | Description |
|---|---|---|
| `gvisor.version` | none, required | The gVisor release, for example `"20261116.0"`. Write the value in quotes. Without quotes, the YAML parser reads the value as a number. Helm then rejects the value. |
| `containerd.configPath` | `/etc/containerd/config.toml` | The containerd configuration file on the node. |
| `image.repository` | `dtzar/helm-kubectl` | The image of all containers. The image needs `nsenter` and `sleep`. For the taint remover, the image also needs `sh`, `seq`, and `kubectl`. |
| `nodeSelector` | `kubernetes.io/os: linux` | The node selector of the pods. |
| `affinity` | `{}` | The affinity of the pods. |
| `tolerations` | a toleration for each taint | The tolerations of the pods. Helm replaces the list as a whole. When you set the list, keep a toleration for `taintRemover.taint`. Without it, Kubernetes does not schedule the pod on a new node. The startup taint then stays on the node. |
| `resources` | 100m CPU, 256Mi memory | The resources of the install container. Keep the memory limit above 128Mi. With a limit of 128Mi, the kernel kills `tar` at the extraction of the gVisor archive. |
| `labels` | `{}` | Extra labels on the DaemonSet and the ServiceAccount. |
| `taintRemover.enabled` | `false` | Removes the startup taint from the node after the install. |
| `taintRemover.taint` | `startup-taint.cluster-autoscaler.kubernetes.io/gvisor-not-ready` | The key of the startup taint. |
