{{/*
The base collector config. The otelConfig helper merges configOverrides on top.
*/}}
{{- define "opentelemetry-gateway.baseConfig" -}}
receivers:
  otelarrow:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
        include_metadata: true
        keepalive:
          server_parameters:
            max_connection_age: 1m
            max_connection_age_grace: 10m
  otlp:
    protocols:
      # The otelarrow receiver has no profiles signal, so OTLP gRPC gets its own port.
      grpc:
        endpoint: "0.0.0.0:4319"
        include_metadata: true
        keepalive:
          server_parameters:
            max_connection_age: 1m
            max_connection_age_grace: 10m
      http:
        endpoint: "0.0.0.0:4318"
        include_metadata: true
        cors:
          allowed_origins:
            - "http://*"
            - "https://*"
          allowed_headers:
            - "*"
          max_age: 7200
  loki:
    protocols:
      http:
        endpoint: "0.0.0.0:3500"
        include_metadata: true
    use_incoming_timestamp: true

exporters:
  # Local troubleshooting only. Do not add it to a pipeline.
  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200
  otlp_http/tempo:
    endpoint: {{ .Values.endpoints.traces | quote }}
    headers:
      x-scope-orgid: {{ .Values.defaultTenant | quote }}
    tls:
      insecure: true
  otlp_http/mimir:
    endpoint: {{ .Values.endpoints.metrics | quote }}
    auth:
      authenticator: headers_setter
    tls:
      insecure: true
    retry_on_failure:
      max_elapsed_time: 20s
      max_interval: 5s
  otlp_http/loki:
    endpoint: {{ .Values.endpoints.logs | quote }}
    auth:
      authenticator: headers_setter
    tls:
      insecure: true
    retry_on_failure:
      max_elapsed_time: 20s
      max_interval: 5s
  otlp_http/pyroscope:
    endpoint: {{ .Values.endpoints.profiles | quote }}
    auth:
      authenticator: headers_setter
    tls:
      insecure: true
    retry_on_failure:
      max_elapsed_time: 20s
      max_interval: 5s
    sending_queue:
      batch:
        flush_timeout: 2s
        min_size: 8192

extensions:
  health_check:
    endpoint: "0.0.0.0:13133"

  # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/extension/headerssetterextension/README.md
  headers_setter:
    headers:
      # The tenant from the request, when present.
      - action: insert
        key: x-scope-orgid
        from_context: x-scope-orgid
      # The default tenant otherwise.
      - action: insert
        key: x-scope-orgid
        value: {{ .Values.defaultTenant | quote }}

connectors:
  {{- if .Values.spanMetrics.enabled }}
  # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/connector/spanmetricsconnector/README.md
  span_metrics:
    histogram:
      unit: s
      exponential:
        max_size: 160
    namespace: span.metrics
    aggregation_temporality: AGGREGATION_TEMPORALITY_CUMULATIVE
    metrics_flush_interval: 15s
    metrics_expiration: 5m
    resource_metrics_cache_size: 5000
    events:
      enabled: false
    exemplars:
      enabled: true
    dimensions:
      - name: db.system.name
      - name: deployment.environment.name
      - name: http.request.method
      - name: http.response.status_code
      - name: http.route
      - name: k8s.cluster.name
      - name: k8s.container.name
      - name: k8s.cronjob.name
      - name: k8s.daemonset.name
      - name: k8s.deployment.name
      - name: k8s.namespace.name
      - name: k8s.statefulset.name
      - name: rpc.grpc.status_code
      - name: rpc.system
      - name: server.address
      - name: service.namespace
      - name: service.version
      - name: telemetry.sdk.language
    resource_metrics_key_attributes:
      - deployment.environment.name
      - k8s.cluster.name
      - service.name
      - service.namespace
      - telemetry.sdk.language
      - telemetry.sdk.name
  {{- end }}
  {{- if .Values.grafanaCloudMetrics.enabled }}
  # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/connector/grafanacloudconnector/README.md
  grafanacloud:
    host_identifiers:
      - k8s.node.name
      - k8s.node.uid
      - host.name
      - host.id
    metrics_flush_interval: 60s
  {{- end }}

processors:
  batch:
    send_batch_size: 8192
    timeout: 2s
    metadata_keys:
      - x-scope-orgid
  groupbyattrs/loki:
    keys: {{ toJson .Values.lokiIndexedLabels }}

  # https://github.com/open-telemetry/opentelemetry-collector/blob/main/processor/memorylimiterprocessor/README.md
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25

  # Source:
  # https://nais.io/blog/posts/otel-from-0-to-100/
  # The template escapes the backslashes and the double quotes of each pattern,
  # because the pattern goes into an OTTL string literal.
  filter/drop_noisy_trace_urls:
    error_mode: ignore
    traces:
      span:
        - IsMatch(span.name, "graphql.resolve .+\\.\\d.+")
        - |
          (span.attributes["http.method"] == "GET" or span.attributes["http.request.method"] == "GET") and (
            false
            {{ range $pattern := .Values.noisyUrlPatterns }}
            {{ range $attr := $.Values.noisyUrlAttributes }}
            or IsMatch(span.attributes["{{ $attr }}"], "{{ $pattern | replace "\\" "\\\\" | replace "\"" "\\\"" }}")
            {{ end }}
            {{ end }}
          )
  transform:
    error_mode: ignore
    trace_statements:
      - context: resource
        statements:
          # https://grafana.com/docs/opentelemetry/collector/opentelemetry-collector/
          {{- range .Values.droppedResourceAttributes }}
          - delete_key(resource.attributes, {{ . | quote }})
          {{- end }}
          - set(resource.attributes["deployment.environment.name"], resource.attributes["deployment.environment"]) where resource.attributes["deployment.environment.name"] == nil and resource.attributes["deployment.environment"] != nil
      - context: span
        statements:
          # Copies from the span attribute keys before semconv 1.21 (HTTP), 1.24
          # (messaging), and 1.30 (database) to the current keys. The old key stays.
          - set(span.attributes["http.request.method"], span.attributes["http.method"]) where span.attributes["http.request.method"] == nil and span.attributes["http.method"] != nil
          - set(span.attributes["http.response.status_code"], Int(span.attributes["http.status_code"])) where span.attributes["http.response.status_code"] == nil and span.attributes["http.status_code"] != nil
          - set(span.attributes["rpc.grpc.status_code"], Int(span.attributes["grpc.status_code"])) where span.attributes["rpc.grpc.status_code"] == nil and span.attributes["grpc.status_code"] != nil
          - set(span.attributes["url.full"], span.attributes["http.url"]) where span.attributes["url.full"] == nil and span.attributes["http.url"] != nil and span.kind == SPAN_KIND_CLIENT
          - set(span.attributes["url.scheme"], span.attributes["http.scheme"]) where span.attributes["url.scheme"] == nil and span.attributes["http.scheme"] != nil
          - set(span.attributes["url.path"], ExtractPatterns(span.attributes["http.target"], "^(?P<path>[^?]*)")["path"]) where span.attributes["url.path"] == nil and span.attributes["http.target"] != nil
          - set(span.attributes["url.query"], ExtractPatterns(span.attributes["http.target"], "\\?(?P<query>.*)$")["query"]) where span.attributes["url.query"] == nil and span.attributes["http.target"] != nil and IsMatch(span.attributes["http.target"], "\\?")
          # Envoy reports http.url on a server span.
          - set(span.cache["url"], URL(span.attributes["http.url"])) where span.attributes["http.url"] != nil and span.attributes["url.path"] == nil and span.kind == SPAN_KIND_SERVER
          - set(span.attributes["url.path"], span.cache["url"]["url.path"]) where span.cache["url"]["url.path"] != nil
          - set(span.attributes["url.query"], span.cache["url"]["url.query"]) where span.attributes["url.query"] == nil and span.cache["url"]["url.query"] != nil
          - set(span.attributes["url.scheme"], span.cache["url"]["url.scheme"]) where span.attributes["url.scheme"] == nil and span.cache["url"]["url.scheme"] != nil
          - set(span.attributes["server.address"], span.attributes["net.host.name"]) where span.attributes["server.address"] == nil and span.attributes["net.host.name"] != nil and span.kind == SPAN_KIND_SERVER
          - set(span.attributes["server.port"], Int(span.attributes["net.host.port"])) where span.attributes["server.port"] == nil and span.attributes["net.host.port"] != nil and span.kind == SPAN_KIND_SERVER
          - set(span.attributes["server.address"], span.attributes["net.peer.name"]) where span.attributes["server.address"] == nil and span.attributes["net.peer.name"] != nil and span.kind == SPAN_KIND_CLIENT
          - set(span.attributes["server.port"], Int(span.attributes["net.peer.port"])) where span.attributes["server.port"] == nil and span.attributes["net.peer.port"] != nil and span.kind == SPAN_KIND_CLIENT
          - set(span.attributes["client.address"], span.attributes["http.client_ip"]) where span.attributes["client.address"] == nil and span.attributes["http.client_ip"] != nil
          - set(span.attributes["network.peer.address"], span.attributes["net.sock.peer.addr"]) where span.attributes["network.peer.address"] == nil and span.attributes["net.sock.peer.addr"] != nil
          - set(span.attributes["network.peer.port"], Int(span.attributes["net.sock.peer.port"])) where span.attributes["network.peer.port"] == nil and span.attributes["net.sock.peer.port"] != nil
          - set(span.attributes["user_agent.original"], span.attributes["http.user_agent"]) where span.attributes["user_agent.original"] == nil and span.attributes["http.user_agent"] != nil
          - set(span.attributes["http.request.body.size"], Int(span.attributes["http.request_content_length"])) where span.attributes["http.request.body.size"] == nil and span.attributes["http.request_content_length"] != nil
          - set(span.attributes["http.response.body.size"], Int(span.attributes["http.response_content_length"])) where span.attributes["http.response.body.size"] == nil and span.attributes["http.response_content_length"] != nil
          - set(span.attributes["db.system.name"], span.attributes["db.system"]) where span.attributes["db.system.name"] == nil and span.attributes["db.system"] != nil
          - set(span.attributes["db.namespace"], span.attributes["db.name"]) where span.attributes["db.namespace"] == nil and span.attributes["db.name"] != nil
          - set(span.attributes["db.query.text"], span.attributes["db.statement"]) where span.attributes["db.query.text"] == nil and span.attributes["db.statement"] != nil
          - set(span.attributes["db.operation.name"], span.attributes["db.operation"]) where span.attributes["db.operation.name"] == nil and span.attributes["db.operation"] != nil
          - set(span.attributes["db.collection.name"], span.attributes["db.sql.table"]) where span.attributes["db.collection.name"] == nil and span.attributes["db.sql.table"] != nil
          - set(span.attributes["messaging.destination.name"], span.attributes["messaging.destination"]) where span.attributes["messaging.destination.name"] == nil and span.attributes["messaging.destination"] != nil
          # Replaces a high-cardinality span.name.
          # https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/transformprocessor/README.md#set_semconv_span_name
          - set_semconv_span_name("1.43.0")
          # The semconv spec advises to drop these attributes.
          # https://opentelemetry.io/docs/specs/otel/trace/semantic_conventions/span-general/#general-identity-attributes
          - delete_key(span.attributes, "enduser.id")
          - delete_key(span.attributes, "enduser.role")
          - delete_key(span.attributes, "enduser.scope")
    metric_statements:
      - context: resource
        statements:
          # https://grafana.com/docs/opentelemetry/collector/opentelemetry-collector/
          {{- range .Values.droppedResourceAttributes }}
          - delete_key(resource.attributes, {{ . | quote }})
          {{- end }}
          - set(resource.attributes["deployment.environment.name"], resource.attributes["deployment.environment"]) where resource.attributes["deployment.environment.name"] == nil and resource.attributes["deployment.environment"] != nil
          # The kubernetes-mixin dashboards, rules, and alerts need the cluster label.
          - set(resource.attributes["cluster"], resource.attributes["k8s.cluster.name"]) where (resource.attributes["cluster"] == nil and resource.attributes["k8s.cluster.name"] != nil)
          # Bounds the cardinality.
          - limit(resource.attributes, 50, [])
          - truncate_all(resource.attributes, 2048)
      - context: datapoint
        statements:
          # Copies to datapoint attributes, so a query can select on them.
          # https://grafana.com/docs/opentelemetry/collector/opentelemetry-collector/
          - set(attributes["deployment.environment.name"], resource.attributes["deployment.environment.name"]) where resource.attributes["deployment.environment.name"] != nil
          - set(attributes["service.version"], resource.attributes["service.version"]) where resource.attributes["service.version"] != nil
          # Bounds the cardinality.
          - limit(datapoint.attributes, 50, [])
          - truncate_all(datapoint.attributes, 2048)
    log_statements:
      - context: resource
        statements:
          # https://grafana.com/docs/opentelemetry/collector/opentelemetry-collector/
          {{- range .Values.droppedResourceAttributes }}
          - delete_key(resource.attributes, {{ . | quote }})
          {{- end }}
          - set(resource.attributes["deployment.environment.name"], resource.attributes["deployment.environment"]) where resource.attributes["deployment.environment.name"] == nil and resource.attributes["deployment.environment"] != nil
          - delete_key(resource.attributes, "host.name") where (resource.attributes["k8s.pod.name"] != nil)
          - truncate_all(resource.attributes, 2048)

  # Derives service.name from the promtail labels.
  transform/loki:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          # https://opentelemetry.io/docs/specs/semconv/non-normative/k8s-attributes/#how-servicename-should-be-calculated
          {{- range list "service_name" "instance" "app" "k8s.deployment.name" "k8s.replicaset.name" "k8s.statefulset.name" "k8s.daemonset.name" "k8s.cronjob.name" "k8s.job.name" "k8s.container.name" "component" "container" "job" }}
          - set(resource.attributes["service.name"], resource.attributes["{{ . }}"]) where (resource.attributes["service.name"] == nil and resource.attributes["{{ . }}"] != nil)
          {{- end }}

service:
  telemetry:
    logs:
      encoding: json
    resource:
      service.name: ""
      service.version: ""
    {{- with .Values.selfTelemetry.endpoint }}
    traces:
      sampler:
        parent_based:
          root:
            trace_id_ratio_based:
              ratio: {{ $.Values.selfTelemetry.tracesSampleRatio }}
      processors:
        - batch:
            exporter:
              otlp:
                protocol: grpc
                endpoint: http://{{ . }}
    {{- end }}
    metrics:
      level: detailed
      {{- with .Values.selfTelemetry.endpoint }}
      readers:
        - periodic:
            interval: 30000
            exporter:
              otlp:
                protocol: grpc
                endpoint: http://{{ . }}
                default_histogram_aggregation: base2_exponential_bucket_histogram
      {{- end }}
  extensions:
    - health_check
    - headers_setter
  pipelines:
    #--------------------------------------------------------------------
    # OTLP metrics
    #--------------------------------------------------------------------
    metrics:
      receivers:
        - otlp
        - otelarrow
      processors:
        - memory_limiter
        - transform
        - batch
      exporters:
        - otlp_http/mimir

    #--------------------------------------------------------------------
    # OTLP traces
    #--------------------------------------------------------------------
    traces:
      receivers:
        - otlp
        - otelarrow
      processors:
        - memory_limiter
        - filter/drop_noisy_trace_urls
        - transform
        - batch
      exporters:
        - otlp_http/tempo
        {{- if .Values.spanMetrics.enabled }}
        - span_metrics
        {{- end }}
        {{- if .Values.grafanaCloudMetrics.enabled }}
        - grafanacloud
        {{- end }}
    {{- if .Values.spanMetrics.enabled }}

    #--------------------------------------------------------------------
    # Span-derived metrics (RED: rate, errors, duration)
    #--------------------------------------------------------------------
    metrics/span_metrics:
      receivers:
        - span_metrics
      processors:
        - memory_limiter
        - transform
        - batch
      exporters:
        - otlp_http/mimir
    {{- end }}
    {{- if .Values.grafanaCloudMetrics.enabled }}

    #--------------------------------------------------------------------
    # Grafana Cloud host metrics, derived from traces
    #--------------------------------------------------------------------
    metrics/grafanacloud:
      receivers:
        - grafanacloud
      processors:
        - memory_limiter
        - transform
        - batch
      exporters:
        - otlp_http/mimir
    {{- end }}

    #--------------------------------------------------------------------
    # OTLP logs
    #--------------------------------------------------------------------
    logs/otlp:
      receivers:
        - otlp
        - otelarrow
      processors:
        - memory_limiter
        - transform
        - batch
        - groupbyattrs/loki
      exporters:
        - otlp_http/loki

    #--------------------------------------------------------------------
    # Loki push logs (promtail format)
    #--------------------------------------------------------------------
    logs/loki:
      receivers:
        - loki
      processors:
        - memory_limiter
        - transform
        - batch
        - groupbyattrs/loki
        - transform/loki
      exporters:
        - otlp_http/loki

    #--------------------------------------------------------------------
    # OTLP profiles
    #
    # No processors: batch and memory_limiter have no profiles support. The
    # exporter queue batches instead.
    #--------------------------------------------------------------------
    profiles:
      receivers:
        - otlp
      exporters:
        - otlp_http/pyroscope
{{- end -}}
