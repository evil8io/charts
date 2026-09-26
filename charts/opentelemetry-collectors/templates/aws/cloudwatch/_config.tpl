{{/*
The CloudFront standard log fields and their attribute keys.
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logs-reference.html
*/}}
{{- define "opentelemetry-collectors.cloudfrontAttributes" -}}
time-taken: http.request.duration
cs(User-Agent): user_agent.original
c-ip: client.address
c-port: client.port
cs-protocol-version: network.protocol.name
cs-protocol: url.scheme
cs-uri-stem: url.path
cs-uri-query: url.query
cs(Host): server.address
ssl-cipher: tls.cipher
ssl-protocol: tls.protocol.name
cs-method: http.request.method
sc-status: http.response.status_code
x-host-header: http.request.header.host
x-edge-location: http.response.header.x-edge-location
x-edge-request-id: http.response.header.x-edge-request-id
x-edge-result-type: http.response.header.x-edge-result-type
x-edge-response-result-type: http.response.header.x-edge-response-result-type
x-edge-detailed-result-type: http.response.header.x-edge-detailed-result-type
{{- end }}

{{/*
The streams filter of a logGroups entry, without empty lists. Takes the entry.
*/}}
{{- define "opentelemetry-collectors.cloudwatchStreams" -}}
{{- $streams := dict }}
{{- with .streams }}
{{- with .names }}{{ $_ := set $streams "names" . }}{{ end }}
{{- with .prefixes }}{{ $_ := set $streams "prefixes" . }}{{ end }}
{{- end }}
{{- with $streams }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
The config of the cloudwatch collector.
*/}}
{{- define "opentelemetry-collectors.cloudwatch.config" -}}
{{- $v := .Values.aws.cloudwatch }}
{{- $geoip := and $v.sources.cloudfront.enabled $v.sources.cloudfront.geoip.enabled }}
receivers:
  {{- if $v.sources.controlPlane.enabled }}
  awscloudwatch/cluster:
    region: {{ $v.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.controlPlane.logGroup is required" $v.sources.controlPlane.logGroup }}: {}
  {{- end }}
  {{- if $v.sources.fargate.enabled }}
  awscloudwatch/fargate:
    region: {{ $v.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.fargate.logGroup is required" $v.sources.fargate.logGroup }}: {}
  {{- end }}
  {{- if $v.sources.cloudfront.enabled }}
  awscloudwatch/cloudfront:
    region: {{ $v.sources.cloudfront.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.cloudfront.logGroup is required" $v.sources.cloudfront.logGroup }}: {}
  {{- end }}
  {{- range $id, $group := $v.logGroups }}
  awscloudwatch/{{ $id }}:
    region: {{ $v.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        {{- if $group.name }}
        named:
          {{ $group.name }}:
            {{- $streams := include "opentelemetry-collectors.cloudwatchStreams" $group }}
            {{- if $streams }}
            streams:
              {{- $streams | nindent 14 }}
            {{- else }} {}
            {{- end }}
        {{- else }}
        autodiscover:
          {{- with $group.prefix }}
          prefix: {{ . | quote }}
          {{- end }}
          {{- with $group.pattern }}
          pattern: {{ . | quote }}
          {{- end }}
          limit: {{ $group.limit | default 50 }}
          {{- with include "opentelemetry-collectors.cloudwatchStreams" $group }}
          streams:
            {{- . | nindent 12 }}
          {{- end }}
        {{- end }}
  {{- end }}

exporters:
  otlp_http:
    {{- include "opentelemetry-collectors.exporterConfig" . | nindent 4 }}
    sending_queue:
      storage: file_storage

extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  file_storage:
    directory: /var/lib/otelcol/file_storage
    max_size: {{ $v.fileStorage.maxSize }}
    compaction:
      directory: /var/lib/otelcol/file_storage
      on_rebound: true
  {{- include "opentelemetry-collectors.basicAuthExtension" . | nindent 2 }}

processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 25
  batch:
    send_batch_size: 8192
    timeout: 2s
  {{- if $geoip }}
  geoip:
    context: record
    attributes:
      - client.address
    providers:
      maxmind:
        database_path: /var/lib/otelcol/geoip/GeoLite2-City.mmdb
  {{- end }}
  groupbyattrs:
    keys:
      - stream
      - log.iostream
      - container.image.name
      - container.image.tag
      - k8s.container.name
      - k8s.pod.name
      - k8s.job.name
      - k8s.namespace.name
      - k8s.node.name
      - service.name
      - service.namespace
      - service.instance.id
      - service.version
  transform/common_attributes:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["cloud.provider"], "aws")
          - set(resource.attributes["cloud.region"], resource.attributes["aws.region"])
          - delete_key(resource.attributes, "aws.region")
          - set(resource.attributes["k8s.cluster.name"], {{ .Values.clusterName | quote }})
  {{- if $v.sources.controlPlane.enabled }}
  transform/controlplane_attributes:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["cloud.platform"], "aws_eks")
          - set(resource.attributes["service.name"], resource.attributes["cloudwatch.log.stream"])
          - >-
            replace_pattern(
              resource.attributes["service.name"],
              "(.+)-[^-]+$",
              "$1"
            )
      - context: log
        statements:
          # klog header: E0811 09:47:32.123456 1 file.go:332] msg
          - set(log.cache, ExtractPatterns(log.body, "^(?P<klogsev>[IWEF])[0-9]{4} "))
          - set(log.severity_text, "info") where log.cache["klogsev"] == "I"
          - set(log.severity_text, "warn") where log.cache["klogsev"] == "W"
          - set(log.severity_text, "error") where log.cache["klogsev"] == "E"
          - set(log.severity_text, "fatal") where log.cache["klogsev"] == "F"
          - set(log.severity_number, SEVERITY_NUMBER_INFO) where log.cache["klogsev"] == "I"
          - set(log.severity_number, SEVERITY_NUMBER_WARN) where log.cache["klogsev"] == "W"
          - set(log.severity_number, SEVERITY_NUMBER_ERROR) where log.cache["klogsev"] == "E"
          - set(log.severity_number, SEVERITY_NUMBER_FATAL) where log.cache["klogsev"] == "F"
  {{- end }}
  {{- if $v.sources.cloudfront.enabled }}
  transform/cloudfront_attributes:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["service.name"], "cloudfront-access-logs")
          - set(resource.attributes["service.instance.id"], resource.attributes["cloudwatch.log.stream"])
      - context: log
        statements:
          - set(log.cache, ParseJSON(log.body))
          {{- range $field, $attribute := include "opentelemetry-collectors.cloudfrontAttributes" . | fromYaml }}
          - set(log.attributes["{{ $attribute }}"], log.cache["{{ $field }}"])
          {{- end }}
  {{- end }}
  {{- if $v.sources.fargate.enabled }}
  k8s_attributes:
    wait_for_metadata: true
    wait_for_metadata_timeout: 10s
    pod_association:
      - sources:
          - from: resource_attribute
            name: k8s.pod.name
          - from: resource_attribute
            name: k8s.namespace.name
    extract:
      otel_annotations: true
      metadata:
        {{- include "opentelemetry-collectors.k8sMetadata" . | nindent 8 }}
  transform/fargate_attributes:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["cloud.platform"], "aws_eks")
      - context: log
        statements:
          - set(log.cache, ParseJSON(log.body))
          - flatten(log.cache)

          - set(log.body, log.cache["log"])
          - set(log.attributes["stream"], log.cache["stream"])
          - set(log.attributes["log.iostream"], log.cache["stream"])

          - set(log.attributes["k8s.pod.name"], log.cache["kubernetes.pod_name"])
          - set(log.attributes["k8s.namespace.name"], log.cache["kubernetes.namespace_name"])
          - set(log.attributes["k8s.container.name"], log.cache["kubernetes.container_name"])
  {{- end }}

service:
  extensions:
    - health_check
    - file_storage
    {{- if .Values.exporter.basicAuth.username }}
    - basicauth
    {{- end }}
  telemetry:
    {{- include "opentelemetry-collectors.serviceTelemetry" (dict "root" . "endpoint" .Values.selfTelemetry.endpoint) | nindent 4 }}
  pipelines:
    {{- if $v.sources.controlPlane.enabled }}
    logs/cluster:
      receivers:
        - awscloudwatch/cluster
      processors:
        - memory_limiter
        - transform/common_attributes
        - transform/controlplane_attributes
        - batch
        - groupbyattrs
      exporters:
        - otlp_http
    {{- end }}
    {{- if $v.sources.fargate.enabled }}
    logs/fargate:
      receivers:
        - awscloudwatch/fargate
      processors:
        - memory_limiter
        - transform/common_attributes
        - transform/fargate_attributes
        - batch
        - groupbyattrs
        - k8s_attributes
      exporters:
        - otlp_http
    {{- end }}
    {{- if $v.sources.cloudfront.enabled }}
    logs/cloudfront:
      receivers:
        - awscloudwatch/cloudfront
      processors:
        - memory_limiter
        - transform/common_attributes
        - transform/cloudfront_attributes
        {{- if $geoip }}
        - geoip
        {{- end }}
        - batch
        - groupbyattrs
      exporters:
        - otlp_http
    {{- end }}
    {{- range $id, $group := $v.logGroups }}
    logs/{{ $id }}:
      receivers:
        - awscloudwatch/{{ $id }}
      processors:
        - memory_limiter
        - transform/common_attributes
        - batch
        - groupbyattrs
      exporters:
        - otlp_http
    {{- end }}
{{- end }}
