# opentelemetry-gateway

With this chart, the [opentelemetry-operator](https://github.com/open-telemetry/opentelemetry-operator) manages four [OpenTelemetry Collectors](https://opentelemetry.io/docs/collector/), one for each signal. The collectors receive OTLP and OTel Arrow and send the signals to Loki, Tempo, Mimir, and Pyroscope.

## Collectors

The chart contains one collector for each of the signals `logs`, `traces`, `metrics`, and `profiles`. For the release name `otel-gateway`, the Service of a collector is `otel-gateway-<signal>-collector`. The four collectors have the same config, so each collector accepts every signal.

Each collector has these receivers:

| Port | Receiver | Protocol |
|---|---|---|
| 4317 | `otelarrow` | OTLP gRPC and OTel Arrow, without profiles |
| 4318 | `otlp` | OTLP/HTTP |
| 4319 | `otlp` | OTLP gRPC, for profiles |
| 3500 | `loki` | Loki push API |

The collectors send the tenant of each request, from its `x-scope-orgid` header, to Loki, Mimir, and Pyroscope. The collectors send the `defaultTenant` value to Tempo as the tenant of every request.

The collectors drop a GET span when one of its URL attributes matches a pattern in `noisyUrlPatterns`. Examples are the spans of health checks and static files. The collectors also derive RED metrics (rate, errors, and duration) from the spans and send them to Mimir. To turn off these span metrics, set `spanMetrics.enabled` to false.

To change the collector config, set `configOverrides`. Helm deep-merges `configOverrides` into the collector config. Helm replaces a list in the config as a whole with the list in `configOverrides`.

```yaml
configOverrides:
  exporters:
    otlp_http/tempo:
      endpoint: http://tempo-distributor.tempo:4318
```

## Routes

The `HTTPRoute` and the `GRPCRoute` contain one rule for each signal. The backend of each rule is the Service of the collector of that signal:

| Signal | HTTPRoute path prefixes (port 4318) | GRPCRoute services | GRPCRoute port |
|---|---|---|---|
| logs | `/v1/logs` | `LogsService`, `ArrowLogsService` | 4317 |
| traces | `/v1/traces` | `TraceService`, `ArrowTracesService` | 4317 |
| metrics | `/v1/metrics` | `MetricsService`, `ArrowMetricsService` | 4317 |
| profiles | `/v1/profiles`, `/v1development/profiles` | `ProfilesService` (`v1` and `v1development`) | 4319 |

## Prerequisites

- The opentelemetry-operator, for the `OpenTelemetryCollector` CRD.
- [KEDA](https://keda.sh/), which scales each collector. To run without KEDA, set `autoscaling.keda.enabled` to false.
- The Gateway API CRDs and a Gateway, when `httpRoute.enabled` or `grpcRoute.enabled` is true.
- [Cilium](https://cilium.io/) and a cluster-wide Cilium policy that allows DNS, when `ciliumNetworkPolicy.enabled` is true.

## Helm timeout

After each install and upgrade, Helm waits until the rollout of each collector is complete. Set the Helm timeout above the time of the slowest rollout.

## Network Policies

When `ciliumNetworkPolicy.enabled` is true, Helm creates a CiliumNetworkPolicy with these rules:

- Every pod in the namespace can connect to the kube-apiserver.
- The collectors accept connections from the pods in the namespaces in `networkPolicyPeers.ingressNamespaces`.
- The collectors can connect to the pods with the label `app.kubernetes.io/component: distributor` in the namespaces in `networkPolicyPeers.distributorNamespaces`.
- The collectors can connect to port 4317 of the pods behind `selfTelemetry.endpoint`. Set the namespace and the labels of these pods in `networkPolicyPeers.selfTelemetry.namespace` and `networkPolicyPeers.selfTelemetry.podLabels`.

When `networkPolicy.enabled` is true, Helm creates NetworkPolicy objects with the same rules, for a cluster without Cilium. In place of the kube-apiserver rule, every pod in the namespace can connect to TCP ports 443 and 6443 of every destination. The NetworkPolicy objects also allow DNS for every pod in the namespace.

A rule with an empty peer value is left out.

## Values

| Key | Default | Description |
|---|---|---|
| `featureGates` | `service.profilesSupport` | Collector feature gates, comma-separated. The profiles pipeline needs `service.profilesSupport`. |
| `replicaCount` | `3` | Replicas of each collector when `autoscaling.keda.enabled` is false. |
| `autoscaling.keda.minReplicas`, `maxReplicas` | `3`, `90` | Replica bounds of each collector. |
| `autoscaling.keda.targetCPUUtilizationPercentage` | `50` | CPU target, in percent of the CPU request. |
| `autoscaling.keda.targetMemoryUtilizationPercentage` | `50` | Memory target, in percent of the memory request. |
| `defaultTenant` | `anonymous` | Tenant for a request without an `x-scope-orgid` header. |
| `endpoints.logs`, `traces`, `metrics`, `profiles` | distributor Services in the release namespace | OTLP/HTTP endpoints of the backends. |
| `selfTelemetry.endpoint` | `""` | OTLP gRPC endpoint (`host:port`) for the spans and metrics of the collectors. When the value is empty, the collectors do not export them. |
| `selfTelemetry.tracesSampleRatio` | `0.01` | Sample ratio for the root spans of the collectors. |
| `lokiIndexedLabels` | see values.yaml | Attribute keys that the collectors move from the log records to the resource. |
| `droppedResourceAttributes` | see values.yaml | Resource attributes that the collectors delete from the traces, metrics, and logs. |
| `noisyUrlAttributes` | see values.yaml | Span attributes that the collectors compare with `noisyUrlPatterns`. |
| `noisyUrlPatterns` | see values.yaml | RE2 regular expressions. |
| `spanMetrics.extraDimensions` | `[]` | Attribute keys that the collectors add as span metric dimensions, next to the built-in list. |
| `grafanaCloudMetrics.enabled` | `false` | When true, the collectors derive Grafana Cloud host metrics from the spans. |
| `httpRoute.enabled`, `hostnames`, `parentRefs` | off | HTTPRoute for OTLP/HTTP. |
| `grpcRoute.enabled`, `hostnames`, `parentRefs` | off | GRPCRoute for OTLP gRPC and OTel Arrow. |
| `readinessHook.image.repository`, `tag` | `dtzar/helm-kubectl`, `4.3.0` | The image needs `kubectl` 1.31 or later. |
| `readinessHook.timeout` | `4m` | Timeout of each `kubectl` call of the readiness hook. |
