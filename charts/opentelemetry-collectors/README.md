# opentelemetry-collectors

A Helm chart that deploys [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) objects for a Kubernetes cluster, managed by the [opentelemetry-operator](https://github.com/open-telemetry/opentelemetry-operator). It has five collectors: node, cluster, events, profiler, and cloudwatch. Each collector sends its signals as OTLP/HTTP to `exporter.endpoint`.

## Usage

```bash
helm install opentelemetry-collectors oci://ghcr.io/evil8io/charts/opentelemetry-collectors
```

The objects are named `<fullname>-<collector>`. With `fullnameOverride: opentelemetry`, the collectors are `opentelemetry-node`, `opentelemetry-cluster`, and `opentelemetry-events`. The operator creates the workload and the Service `<name>-collector` for each collector.

## Collectors

| Collector | Workload | Collects | Sends to |
|---|---|---|---|
| node | DaemonSet | OTLP, OTel Arrow, container logs, kubelet and cAdvisor metrics of its node | `exporter.endpoint` |
| cluster | StatefulSet | Targets with the target allocator labels, the kube-apiserver, the Fargate kubelets | `exporter.endpoint` |
| events | StatefulSet, 1 replica | Kubernetes events | `exporter.endpoint` |
| profiler | DaemonSet | eBPF profiles | `exporter.endpoint` |
| cloudwatch | StatefulSet, 1 replica | CloudWatch log groups | `exporter.endpoint` |

The node collector receives OTLP on port 4317 (gRPC and OTel Arrow) and port 4318 (HTTP). It reads the container logs of its node, and scrapes the kubelet and the cAdvisor of its node. Its per-node target allocator scrapes every ServiceMonitor, PodMonitor, Probe, and ScrapeConfig object without the labels of `collectors.cluster.targetAllocator.matchLabels`.

The cluster collector scrapes the ServiceMonitor, PodMonitor, Probe, and ScrapeConfig objects with the labels of `collectors.cluster.targetAllocator.matchLabels`, through a target allocator with the consistent-hashing strategy. It also runs a static scrape job for the kube-apiserver, and scrapes the kubelet and the cAdvisor of the Fargate nodes when `aws.fargate.enabled` is true.

The events collector watches the Kubernetes events, and sends them as logs with the service name `kubernetes-events`. A PersistentVolumeClaim holds its checkpoint of the watch stream.

The profiler collector runs the eBPF profiler distribution of the OpenTelemetry Collector.

The cloudwatch collector reads CloudWatch log groups on AWS. Enable it with `aws.enabled` and `aws.cloudwatch.enabled`.

Each collector has a `configOverrides` value. The chart deep-merges it on top of the collector config. A list in `configOverrides` replaces the list in the config.

```yaml
collectors:
  cluster:
    configOverrides:
      exporters:
        otlp_http:
          timeout: 30s
```

## Platforms

Set `aws.enabled` to add the eks resource detector to the node, cluster, and events collectors. The detector reads the cloud account ID, the cloud region, and the cluster name.

Set `aws.roleArn` to an IAM role ARN for the ServiceAccounts of the node, cluster, and events collectors (IRSA). The eks detector needs the role for its AWS calls.

Set `aws.fargate.enabled` to keep the collectors off the Fargate nodes. The Fargate kubelet and cAdvisor scrapes then move to the cluster collector.

Set `aws.cloudwatch.enabled`, with `aws.enabled`, to add the cloudwatch collector.

Set `resourceAttributes` to add static resource attributes to every signal, on a platform without a resource detector.

`azure` holds platform settings for Azure. It is reserved and currently empty.

## Subcharts

The chart bundles kube-state-metrics and prometheus-node-exporter as subcharts. Both are off by default.

Set `kubeStateMetrics.enabled` to install kube-state-metrics, with its values under the `kube-state-metrics` key. Its ServiceMonitor has the label `target: opentelemetry-cluster-collector`, which matches `collectors.cluster.targetAllocator.matchLabels`, so the cluster collector scrapes it.

Set `nodeExporter.enabled` to install prometheus-node-exporter, with its values under the `prometheus-node-exporter` key.

## Prerequisites

- The opentelemetry-operator, for the `OpenTelemetryCollector` CRD.
- The Prometheus Operator CRDs (`ServiceMonitor`, `PodMonitor`, `Probe`, `ScrapeConfig`), for the target allocators of the node and cluster collectors.
- [Cilium](https://cilium.io/), when `ciliumNetworkPolicy.enabled` is true.

## Network Policies

`ciliumNetworkPolicy.enabled` creates a CiliumNetworkPolicy. It lets the node, cluster, events, and profiler collectors connect out to any destination. It also lets the node collector accept connections from any source, because the node collector receives OTLP from the pods of its node. The cloudwatch collector may connect to the kube-apiserver, to TCP port 443, and to the node collector on port 4317 only. `networkPolicy.enabled` creates the same rules as NetworkPolicy objects, for a cluster without Cilium. A NetworkPolicy cannot select the kube-apiserver, so the cloudwatch rule allows TCP ports 443 and 6443 to every destination, and a second rule allows DNS.

## Values

See [values.yaml](values.yaml) for all values and their defaults.

| Key | Default | Description |
|---|---|---|
| `nameOverride`, `fullnameOverride` | `""` | Name part of the object names. The collectors are named `<fullname>-<collector>`. |
| `clusterName` | `""` (required) | Name of the cluster. It sets the `k8s.cluster.name` resource attribute of every signal. |
| `image.repository`, `image.tag` | `otel/opentelemetry-collector-k8s`, `""` | Collector image of the node, cluster, and events collectors. An empty tag selects the chart `appVersion`. |
| `featureGates` | `""` | Feature gates of every collector, comma-separated. |
| `exporter.endpoint` | `""` (required) | OTLP/HTTP endpoint of the backend, for example an OpenTelemetry gateway. |
| `exporter.tenant` | `""` | Value of the `X-Scope-OrgID` header. An empty value sends no header. |
| `exporter.insecureSkipVerify` | `false` | Skips the TLS certificate check of the endpoint. |
| `exporter.basicAuth.username`, `password` | `""` | Basic auth of the endpoint. An empty username sends no auth. |
| `selfTelemetry.endpoint` | `""` | OTLP gRPC endpoint (`host:port`) for the spans and metrics of the collectors. The node collector reports to itself. |
| `selfTelemetry.tracesSampleRatio` | `0.01` | Sample ratio for the root spans of the collectors. |
| `resourceAttributes` | `{}` | Static resource attributes, added to every signal. Use them on a platform without a resource detector. |
| `targetAllocator.image.repository`, `tag` | `ghcr.io/open-telemetry/opentelemetry-operator/target-allocator`, `v0.159.0` | Image of the target allocator of the node and cluster collectors. |
| `targetAllocator.scrapeInterval` | `30s` | Scrape interval of the target allocators. |
| `aws.enabled` | `false` | Adds the eks resource detector to the node, cluster, and events collectors. |
| `aws.roleArn` | `""` | IAM role for the ServiceAccounts of the node, cluster, and events collectors (IRSA). The eks detector calls `ec2:DescribeInstances`. |
| `aws.fargate.enabled` | `false` | Keeps the collectors off the Fargate nodes. The Fargate kubelet scrapes then move to the cluster collector. |
| `aws.fargate.nodeSelector` | `eks.amazonaws.com/compute-type: fargate` | Node label of the Fargate nodes. |
| `aws.cloudwatch.enabled` | `false` | The cloudwatch collector, a StatefulSet with one replica. It reads CloudWatch log groups. |
| `aws.cloudwatch.image.repository`, `tag` | `otel/opentelemetry-collector-contrib`, `""` | Image of the cloudwatch collector. |
| `aws.cloudwatch.roleArn` | `""` | IAM role for the ServiceAccount of the cloudwatch collector (IRSA). The receiver calls `logs:FilterLogEvents` and `logs:DescribeLogGroups`. |
| `aws.cloudwatch.region`, `pollInterval` | `""`, `10s` | AWS region and poll interval of the CloudWatch log groups. |
| `aws.cloudwatch.annotations`, `resources`, `podSecurityContext`, `securityContext`, `priorityClassName`, `nodeSelector`, `tolerations` | see values.yaml | Pod settings of the cloudwatch collector. |
| `aws.cloudwatch.podDisruptionBudget` | `maxUnavailable: 1` | PodDisruptionBudget of the cloudwatch collector. |
| `aws.cloudwatch.storage` | `1Gi` | PersistentVolumeClaim for the receiver checkpoints and the exporter queue. |
| `aws.cloudwatch.fileStorage.maxSize` | `268435456` | Cap of each bbolt file, in bytes. Keep it at a quarter of the storage size, because compaction writes a second copy. |
| `aws.cloudwatch.sources.controlPlane` | `enabled: true` | The control plane log group of an EKS cluster, `/aws/eks/<cluster>/cluster`. |
| `aws.cloudwatch.sources.fargate` | `enabled: true` | The Fargate pod log group, `/aws/eks/<cluster>/fargate`. |
| `aws.cloudwatch.sources.cloudfront` | `enabled: false` | A CloudFront standard log group. CloudFront logs go to `us-east-1`. |
| `aws.cloudwatch.sources.cloudfront.geoip` | `enabled: false` | Adds the client geolocation from a GeoLite2-City database. An init container downloads the database. |
| `aws.cloudwatch.logGroups` | `{}` | Other log groups, one receiver and one pipeline per key. See values.yaml for the entry shape. |
| `aws.cloudwatch.configOverrides` | `{}` | Deep-merged on top of the cloudwatch collector config. |
| `azure` | `{}` | Platform settings for Azure. Reserved. |
| `collectors.node.enabled` | `true` | Enables the node collector, a DaemonSet. |
| `collectors.node.annotations`, `resources`, `podSecurityContext`, `securityContext`, `priorityClassName`, `nodeSelector`, `tolerations` | see values.yaml | Pod settings of the node collector. |
| `collectors.node.logs.enabled` | `true` | Reads the container logs of the node. |
| `collectors.node.kubelet.enabled` | `true` | Scrapes the kubelet metrics of the node. |
| `collectors.node.cadvisor.enabled` | `true` | Scrapes the cAdvisor metrics of the node. |
| `collectors.node.fileStorage.maxSize` | `1073741824` | Cap of each bbolt file, in bytes, on the node root volume. |
| `collectors.node.targetAllocator.enabled` | `true` | The per-node target allocator. It scrapes every ServiceMonitor, PodMonitor, Probe, and ScrapeConfig object without the labels of `collectors.cluster.targetAllocator.matchLabels`. |
| `collectors.node.configOverrides` | `{}` | Deep-merged on top of the node collector config. |
| `collectors.cluster.enabled` | `true` | Enables the cluster collector, a StatefulSet. |
| `collectors.cluster.replicas` | `3` | Replicas of the cluster collector. |
| `collectors.cluster.annotations`, `resources`, `podSecurityContext`, `securityContext`, `priorityClassName`, `nodeSelector`, `tolerations` | see values.yaml | Pod settings of the cluster collector. |
| `collectors.cluster.podDisruptionBudget` | `minAvailable: 1` | PodDisruptionBudget of the cluster collector. |
| `collectors.cluster.scrapes.apiserver.enabled` | `true` | A static scrape job of the kube-apiserver, through the kubernetes Service in the default namespace. |
| `collectors.cluster.targetAllocator.enabled` | `true` | The target allocator with the consistent-hashing strategy over the replicas. |
| `collectors.cluster.targetAllocator.allowNamespaces` | `[]` | Extra namespaces of the ServiceMonitor, PodMonitor, Probe, and ScrapeConfig objects, next to the release namespace. |
| `collectors.cluster.targetAllocator.matchLabels` | `target: opentelemetry-cluster-collector` | Labels of the objects that the cluster collector scrapes. |
| `collectors.cluster.configOverrides` | `{}` | Deep-merged on top of the cluster collector config. |
| `collectors.events.enabled` | `true` | Enables the events collector, a StatefulSet with one replica. |
| `collectors.events.annotations`, `resources`, `podDisruptionBudget`, `podSecurityContext`, `securityContext`, `priorityClassName`, `nodeSelector`, `tolerations` | see values.yaml | Pod settings of the events collector. |
| `collectors.events.storage` | `1Gi` | PersistentVolumeClaim for the watch checkpoint and the exporter queue. |
| `collectors.events.configOverrides` | `{}` | Deep-merged on top of the events collector config. |
| `collectors.profiler.enabled` | `false` | Enables the profiler collector, a DaemonSet with the eBPF profiler distribution. |
| `collectors.profiler.image.repository`, `tag` | `otel/opentelemetry-collector-ebpf-profiler`, `""` | Image of the profiler collector. |
| `collectors.profiler.resources`, `podSecurityContext`, `priorityClassName`, `nodeSelector`, `tolerations` | see values.yaml | Pod settings of the profiler collector. |
| `collectors.profiler.securityContext` | see values.yaml | Capabilities and unconfined profiles that the profiler needs to attach its eBPF programs. |
| `collectors.profiler.configOverrides` | `{}` | Deep-merged on top of the profiler collector config. |
| `kubeStateMetrics.enabled` | `false` | The kube-state-metrics subchart. Its values are under the `kube-state-metrics` key. |
| `nodeExporter.enabled` | `false` | The prometheus-node-exporter subchart. Its values are under the `prometheus-node-exporter` key. |
| `ciliumNetworkPolicy.enabled` | `false` | CiliumNetworkPolicy for the collectors. |
| `networkPolicy.enabled` | `false` | NetworkPolicy objects for a cluster without Cilium. |
