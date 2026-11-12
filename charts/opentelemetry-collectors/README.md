# opentelemetry-collectors

Five [OpenTelemetry Collectors](https://opentelemetry.io/docs/collector/) for a Kubernetes cluster: node, cluster, events, profiler, and cloudwatch. Each collector sends its signals as OTLP/HTTP to `exporter.endpoint`.

## Collectors

| Collector | Workload | Collects |
|---|---|---|
| node | DaemonSet | OTLP, OTel Arrow, container logs, kubelet and cAdvisor metrics of its node |
| cluster | StatefulSet | Targets with the target allocator labels, the kube-apiserver, the Fargate kubelets |
| events | StatefulSet, 1 replica | Kubernetes events |
| profiler | DaemonSet | eBPF profiles |
| cloudwatch | StatefulSet, 1 replica | CloudWatch log groups |

The node, cluster, and events collectors are on by default. To turn off one of these collectors, set `collectors.<collector>.enabled` to false. To turn on the profiler collector, set `collectors.profiler.enabled` to true. To turn on the cloudwatch collector, set `aws.enabled` and `aws.cloudwatch.enabled` to true.

The node collector receives OTLP on port 4317 (gRPC and OTel Arrow) and port 4318 (HTTP) of the Service `<fullname>-node-collector`. It also scrapes the targets of each ServiceMonitor, PodMonitor, Probe, and ScrapeConfig object that does not have the labels of `collectors.cluster.targetAllocator.matchLabels`. A target allocator, a component of the opentelemetry-operator, finds these targets. To turn off one source of the node collector, set its key to false:

- `collectors.node.logs.enabled`: the container logs.
- `collectors.node.kubelet.enabled`: the kubelet metrics.
- `collectors.node.cadvisor.enabled`: the cAdvisor metrics.
- `collectors.node.targetAllocator.enabled`: the targets of the ServiceMonitor, PodMonitor, Probe, and ScrapeConfig objects.

The cluster collector scrapes the targets of each ServiceMonitor, PodMonitor, Probe, and ScrapeConfig object that has the labels of `collectors.cluster.targetAllocator.matchLabels`. The default label is `target: opentelemetry-cluster-collector`. A target allocator divides these targets over the replicas of the cluster collector. To turn off these scrapes, set `collectors.cluster.targetAllocator.enabled` to false.

The cluster collector also scrapes the kube-apiserver. To turn off this scrape, set `collectors.cluster.scrapes.apiserver.enabled` to false.

The events collector watches the Kubernetes events and sends them as logs with the service name `kubernetes-events`.

To change the config of a collector, set `collectors.<collector>.configOverrides`, or `aws.cloudwatch.configOverrides` for the cloudwatch collector. Helm deep-merges this value on top of the collector config. A list in the value replaces the list in the config.

```yaml
collectors:
  cluster:
    configOverrides:
      exporters:
        otlp_http:
          timeout: 30s
```

## Platforms

Set `aws.enabled` to true to add the `eks` resource detector to the node, cluster, and events collectors. The detector reads the cloud account ID, the cloud region, and the cluster name.

Set `aws.roleArn` to the ARN of an IAM role for the node, cluster, and events collectors. The collectors use the role through IAM roles for service accounts (IRSA). The `eks` detector calls `ec2:DescribeInstances` with this role.

Set `aws.fargate.enabled` to true to keep the collectors off the Fargate nodes. The cluster collector then scrapes the kubelet and the cAdvisor of the Fargate nodes.

On a platform without a resource detector, set `resourceAttributes` to static resource attributes. The node, cluster, and events collectors add these attributes to every signal.

## Subcharts

kube-state-metrics and prometheus-node-exporter are subcharts of this chart. Both are off by default.

Set `kubeStateMetrics.enabled` to true to install kube-state-metrics. Put its values under the `kube-state-metrics` key. The cluster collector scrapes kube-state-metrics.

Set `nodeExporter.enabled` to true to install prometheus-node-exporter. Put its values under the `prometheus-node-exporter` key.

## Prerequisites

- The [opentelemetry-operator](https://github.com/open-telemetry/opentelemetry-operator), for the `OpenTelemetryCollector` CRD.
- The Prometheus Operator CRDs (`ServiceMonitor`, `PodMonitor`, `Probe`, `ScrapeConfig`), for the target allocators of the node and cluster collectors.
- [Cilium](https://cilium.io/), when `ciliumNetworkPolicy.enabled` is true.

## Network Policies

When `ciliumNetworkPolicy.enabled` is true, Helm creates a CiliumNetworkPolicy with these rules:

- The node, cluster, events, and profiler collectors can connect to any destination.
- The node collector accepts connections from any source.
- The cloudwatch collector can connect only to the kube-apiserver, to TCP port 443, and to the node collector on port 4317.

For a cluster without Cilium, set `networkPolicy.enabled` to true. Helm then creates NetworkPolicy objects with the same rules, except the rules of the cloudwatch collector. In place of the kube-apiserver, the cloudwatch collector can connect to TCP port 6443 on any destination. It can also connect to port 53 (DNS) on any destination.

## Values

| Key | Default | Description |
|---|---|---|
| `clusterName` | `""` (required) | Name of the cluster, in the `k8s.cluster.name` resource attribute of every signal except the profiles. |
| `image.repository`, `image.tag` | `otel/opentelemetry-collector-k8s`, `""` | Image of the node, cluster, and events collectors. With an empty tag, Helm uses the chart `appVersion`. |
| `featureGates` | `""` | Comma-separated feature gates for every collector. |
| `exporter.endpoint` | `""` (required) | OTLP/HTTP endpoint of the backend, for example an OpenTelemetry gateway. |
| `exporter.tenant` | `""` | Value of the `X-Scope-OrgID` header. With an empty value, the collectors do not send the header. |
| `exporter.basicAuth.username`, `password` | `""` | Basic auth for the endpoint. With an empty username, the collectors do not use basic auth. |
| `selfTelemetry.endpoint` | `""` | OTLP gRPC endpoint (`host:port`) for the spans and metrics of the collectors. When it is set, the node collector sends them to itself instead. With an empty value, the collectors do not export them. |
| `selfTelemetry.tracesSampleRatio` | `0.01` | Sample ratio for the root spans of the collectors. |
| `targetAllocator.scrapeInterval` | `30s` | Scrape interval of the target allocators and of the kubelet, cAdvisor, and kube-apiserver jobs. |
| `aws.fargate.nodeSelector` | `eks.amazonaws.com/compute-type: fargate` | The node label that identifies a Fargate node. |
| `aws.cloudwatch.roleArn` | `""` | IAM role for the cloudwatch collector (IRSA). The collector calls `logs:FilterLogEvents` and `logs:DescribeLogGroups` with this role. |
| `aws.cloudwatch.region`, `pollInterval` | `""`, `1m` | AWS region of the log groups, except the CloudFront log group. Poll interval of every log group. |
| `aws.cloudwatch.storage.size`, `className` | `1Gi`, `""` | PersistentVolumeClaim for the receiver checkpoints and the exporter queue. |
| `aws.cloudwatch.fileStorage.maxSize` | `268435456` | Maximum size of each storage file in the PersistentVolumeClaim, in bytes. Keep it at a quarter of `storage.size`, because the collector writes a second copy of a file during compaction. |
| `aws.cloudwatch.sources.controlPlane` | `enabled: true` | The control plane log group of an EKS cluster. Set `logGroup` to its name, `/aws/eks/<cluster>/cluster`. |
| `aws.cloudwatch.sources.fargate` | `enabled: true` | The Fargate pod log group. Set `logGroup` to its name, `/aws/eks/<cluster>/fargate`. |
| `aws.cloudwatch.sources.cloudfront` | `enabled: false`, `region: us-east-1` | A CloudFront standard log group. Set `logGroup` to its name. CloudFront writes these logs in `us-east-1`. |
| `aws.cloudwatch.sources.cloudfront.geoip` | `enabled: false` | Client geolocation attributes from the GeoLite2-City database. An init container downloads the database from the URL prefix in `mirror`. `mirror` is required. |
| `aws.cloudwatch.logGroups` | `{}` | Other log groups, one entry per key. See `values.yaml` for the entry shape. |
| `collectors.node.fileStorage.maxSize` | `1073741824` | Maximum size of each storage file on the root volume of the node, in bytes. |
| `collectors.cluster.scrapes.apiserver.metricAllowlist` | `""` | A regex of the kube-apiserver metric names that the cluster collector keeps. With an empty value, the collector keeps every metric. |
| `collectors.cluster.targetAllocator.allowNamespaces` | `[]` | Other namespaces with ServiceMonitor, PodMonitor, Probe, and ScrapeConfig objects for the cluster collector. The release namespace is always included. |
| `collectors.events.storage.size`, `className` | `1Gi`, `""` | PersistentVolumeClaim for the checkpoint of the event watch and the exporter queue. |
