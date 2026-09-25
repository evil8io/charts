# opentelemetry-gateway

A Helm chart that deploys four [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) gateways, one per signal, managed by the [opentelemetry-operator](https://github.com/open-telemetry/opentelemetry-operator). The gateways receive OTLP and OTel Arrow, and send the signals to Loki, Tempo, Mimir, and Pyroscope.

## Usage

```bash
helm install otel-gateway oci://ghcr.io/evil8io/charts/opentelemetry-gateway
```

The release name sets the object names. With the release name `otel-gateway`, the collectors are `otel-gateway-<signal>`, and the operator creates the Deployment and the Service `otel-gateway-<signal>-collector`.

## Collectors

The chart creates one `OpenTelemetryCollector` in deployment mode for each of the signals `logs`, `traces`, `metrics`, and `profiles`. All four collectors have the same config, so each collector accepts every signal. The routes send each signal to its own collector, so each signal has its own replicas and its own scaling.

| Port | Receiver | Protocol |
|---|---|---|
| 4317 | `otelarrow` | OTLP gRPC and OTel Arrow, without profiles |
| 4318 | `otlp` | OTLP/HTTP |
| 4319 | `otlp` | OTLP gRPC, for profiles |
| 3500 | `loki` | Loki push API |

The exporters send OTLP/HTTP to the endpoints in `endpoints`. Loki, Mimir, and Pyroscope get the tenant of the request in the `x-scope-orgid` header, or `defaultTenant` when the request has no tenant. Tempo always gets `defaultTenant`.

The traces pipeline drops GET spans whose URL attributes match `noisyUrlPatterns`, for example health checks and static files. The span metrics connector (`spanMetrics.enabled`) derives RED metrics from the spans and sends them to Mimir.

To change the config, set `configOverrides`. The chart deep-merges it on top of the config. A list in `configOverrides` replaces the list in the config.

```yaml
configOverrides:
  exporters:
    otlp_http/tempo:
      endpoint: http://tempo-distributor.tempo:4318
```

## Routes

`httpRoute` and `grpcRoute` create a Gateway API `HTTPRoute` and `GRPCRoute`. The rules send each signal to the Service of its collector:

| Signal | HTTPRoute path prefixes (port 4318) | GRPCRoute services | GRPCRoute port |
|---|---|---|---|
| logs | `/v1/logs` | `LogsService`, `ArrowLogsService` | 4317 |
| traces | `/v1/traces` | `TraceService`, `ArrowTracesService` | 4317 |
| metrics | `/v1/metrics` | `MetricsService`, `ArrowMetricsService` | 4317 |
| profiles | `/v1/profiles`, `/v1development/profiles` | `ProfilesService` (`v1` and `v1development`) | 4319 |

The gRPC ports have `appProtocol: kubernetes.io/h2c`, so the gateway uses h2c to the backend. A gRPC service that is not in the table gets no route.

## Prerequisites

- The opentelemetry-operator, for the `OpenTelemetryCollector` CRD.
- [KEDA](https://keda.sh/), when `autoscaling.keda.enabled` is true (the default).
- The Gateway API CRDs and a Gateway, when `httpRoute.enabled` or `grpcRoute.enabled` is true.
- [Cilium](https://cilium.io/), when `ciliumNetworkPolicy.enabled` is true.

## Readiness Hook

The operator creates the collector Deployments after Helm applies the `OpenTelemetryCollector` objects, so the Helm wait does not include them. A `post-install` and `post-upgrade` Job waits for each Deployment: first until the Deployment exists, then until `kubectl rollout status` reports the rollout as complete. Each step has the timeout `readinessHook.timeout`. The four rollouts run at the same time, so the Job takes about as long as the slowest rollout. Set the Helm timeout above that time.

On an upgrade, the operator can update a Deployment after the Job checks it. The Job then reports the previous rollout.

## Network Policies

`ciliumNetworkPolicy.enabled` creates a CiliumNetworkPolicy with these rules:

- Every pod in the namespace can connect to the kube-apiserver.
- The collectors accept connections from the pods in `networkPolicyPeers.ingressNamespaces`.
- The collectors can connect to the pods with the label `app.kubernetes.io/component: distributor` in `networkPolicyPeers.distributorNamespaces`.
- The collectors can connect to port 4317 of the pods in `networkPolicyPeers.selfTelemetry`.

`networkPolicy.enabled` creates NetworkPolicy objects with the same rules, for a cluster without Cilium. A NetworkPolicy cannot select the kube-apiserver, so the rule allows TCP ports 443 and 6443 to every destination. A second rule allows DNS, because a cluster without Cilium has no cluster-wide DNS rule.

An empty peer value omits its rule.

## Values

See [values.yaml](values.yaml) for all values and their defaults.

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `gateway` | Name part of the object names. |
| `image.repository` | `otel/opentelemetry-collector-contrib` | Collector image. |
| `image.tag` | `""` | Collector image tag. An empty tag selects the chart `appVersion`. |
| `featureGates` | `connector.spanmetrics.includeCollectorInstanceID,service.profilesSupport` | Feature gates, comma-separated. The profiles pipeline needs `service.profilesSupport`. |
| `replicaCount` | `3` | Replicas of each collector when KEDA is off. |
| `resources` | 1 CPU, 2Gi | Resources of each collector pod. |
| `podSecurityContext`, `securityContext` | restricted | Security contexts of the collector pods. |
| `podDisruptionBudget` | `maxUnavailable: 40%` | PodDisruptionBudget of each collector. |
| `deploymentUpdateStrategy` | RollingUpdate 40% | Update strategy of each collector Deployment. |
| `nodeSelector`, `tolerations` | empty | Scheduling of the collector pods. |
| `autoscaling.keda.enabled` | `true` | One KEDA ScaledObject per collector. |
| `autoscaling.keda.minReplicas`, `maxReplicas` | `3`, `90` | Replica bounds of each collector. |
| `autoscaling.keda.targetCPUUtilizationPercentage` | `50` | CPU target, in percent of the request. |
| `autoscaling.keda.targetMemoryUtilizationPercentage` | `50` | Memory target, in percent of the request. |
| `defaultTenant` | `anonymous` | Tenant for a request without an `x-scope-orgid` header. |
| `endpoints.logs`, `traces`, `metrics`, `profiles` | in-cluster distributors | OTLP/HTTP endpoints of the backends. |
| `selfTelemetry.endpoint` | `""` | OTLP gRPC endpoint (`host:port`) for the spans and metrics of the collectors. An empty value disables the export. |
| `selfTelemetry.tracesSampleRatio` | `0.01` | Sample ratio for the root spans of the collectors. |
| `lokiIndexedLabels` | see values.yaml | Attribute keys that the `groupbyattrs/loki` processor moves to the resource. |
| `droppedResourceAttributes` | see values.yaml | Resource attributes that the collectors delete from every signal. |
| `noisyUrlAttributes` | see values.yaml | Span attributes that the noisy URL filter reads. |
| `noisyUrlPatterns` | see values.yaml | Regular expressions (RE2) of the noisy URL filter. |
| `spanMetrics.enabled` | `true` | Derives RED metrics from the spans. |
| `grafanaCloudMetrics.enabled` | `false` | Derives Grafana Cloud host metrics from the spans. |
| `configOverrides` | `{}` | Deep-merged on top of the collector config. |
| `httpRoute.enabled`, `hostnames`, `parentRefs` | off | HTTPRoute for OTLP/HTTP. |
| `grpcRoute.enabled`, `hostnames`, `parentRefs` | off | GRPCRoute for OTLP gRPC and OTel Arrow. |
| `ciliumNetworkPolicy.enabled` | `false` | CiliumNetworkPolicy. |
| `networkPolicy.enabled` | `false` | NetworkPolicy objects. |
| `networkPolicyPeers.ingressNamespaces` | `[]` | Namespaces that send to the collectors. |
| `networkPolicyPeers.distributorNamespaces` | `[]` | Namespaces of the backend distributors. |
| `networkPolicyPeers.selfTelemetry.namespace`, `podLabels` | empty | Pods behind `selfTelemetry.endpoint`. |
| `readinessHook.image.repository`, `tag` | `dtzar/helm-kubectl`, `4.3.0` | Image of the readiness Job. It needs `kubectl` 1.31 or later. |
| `readinessHook.timeout` | `4m` | Timeout of each wait step of the readiness Job. |
| `readinessHook.resources` | 10m, 128Mi | Resources of the readiness Job. |
