{{/*
These maps contain the CloudFront standard log fields and their attribute keys, by value type.
A field without a semantic convention has a key under aws.cloudfront.
https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logs-reference.html
*/}}
{{- define "opentelemetry-collectors.cloudfrontStringAttributes" -}}
c-ip: client.address
cs(Host): aws.cloudfront.distribution.domain_name
cs(Referer): http.request.header.referer
cs(User-Agent): user_agent.original
cs-method: http.request.method
cs-protocol: url.scheme
cs-uri-query: url.query
cs-uri-stem: url.path
ssl-cipher: tls.cipher
x-edge-detailed-result-type: aws.cloudfront.edge.detailed_result_type
x-edge-location: aws.cloudfront.edge.location
x-edge-request-id: aws.cloudfront.edge.request_id
x-edge-response-result-type: aws.cloudfront.edge.response_result_type
x-edge-result-type: aws.cloudfront.edge.result_type
x-forwarded-for: http.request.header.x-forwarded-for
x-host-header: server.address
{{- end }}

{{- define "opentelemetry-collectors.cloudfrontIntAttributes" -}}
c-port: client.port
cs-bytes: http.request.size
sc-bytes: http.response.size
sc-status: http.response.status_code
{{- end }}

{{/*
The CloudFront durations are in seconds.
*/}}
{{- define "opentelemetry-collectors.cloudfrontDoubleAttributes" -}}
time-taken: aws.cloudfront.time_taken
time-to-first-byte: aws.cloudfront.time_to_first_byte
{{- end }}

{{/*
This list contains the escapes that CloudFront writes in the field values, with their characters.
CloudFront also escapes the % of an escape in the request path and query.
%25 is last, so that a decoded % does not start a new escape.
*/}}
{{- define "opentelemetry-collectors.cloudfrontEscapes" -}}
- ["%09", "\t"]
- ["%20", " "]
- ["%22", "\""]
- ["%23", "#"]
- ["%27", "'"]
- ["%3C", "<"]
- ["%3E", ">"]
- ["%5B", "["]
- ["%5C", "\\"]
- ["%5D", "]"]
- ["%5E", "^"]
- ["%60", "`"]
- ["%7B", "{"]
- ["%7C", "|"]
- ["%7D", "}"]
- ["%7E", "~"]
- ["%25", "%"]
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
  aws_cloudwatch/cluster:
    region: {{ $v.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.controlPlane.logGroup is required" $v.sources.controlPlane.logGroup }}: {}
  {{- end }}
  {{- if $v.sources.fargate.enabled }}
  aws_cloudwatch/fargate:
    region: {{ $v.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.fargate.logGroup is required" $v.sources.fargate.logGroup }}: {}
  {{- end }}
  {{- if $v.sources.cloudfront.enabled }}
  aws_cloudwatch/cloudfront:
    region: {{ $v.sources.cloudfront.region | quote }}
    storage: file_storage
    logs:
      poll_interval: {{ $v.pollInterval }}
      groups:
        named:
          {{ required "aws.cloudwatch.sources.cloudfront.logGroup is required" $v.sources.cloudfront.logGroup }}: {}
  {{- end }}
  {{- range $id, $group := $v.logGroups }}
  aws_cloudwatch/{{ $id }}:
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
      - container.image.tags
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
          - set(resource.attributes["cloud.region"], resource.attributes["aws.region"]) where resource.attributes["aws.region"] != nil
          - delete_key(resource.attributes, "aws.region")
          - set(resource.attributes["k8s.cluster.name"], {{ .Values.clusterName | quote }})
  {{- if $v.sources.controlPlane.enabled }}
  transform/controlplane_attributes:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["cloud.platform"], "aws_eks")
          - set(resource.attributes["service.name"], resource.attributes["cloudwatch.log.stream"]) where resource.attributes["cloudwatch.log.stream"] != nil
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
          - set(resource.attributes["service.instance.id"], resource.attributes["cloudwatch.log.stream"]) where resource.attributes["cloudwatch.log.stream"] != nil
      - context: log
        statements:
          - set(log.cache, ParseJSON(log.body))
          {{- range $escape := include "opentelemetry-collectors.cloudfrontEscapes" . | fromYamlArray }}
          - replace_all_patterns(log.cache, "value", {{ index $escape 0 | quote }}, {{ index $escape 1 | quote }})
          {{- end }}
          {{- range $field, $attribute := include "opentelemetry-collectors.cloudfrontStringAttributes" . | fromYaml }}
          - set(log.attributes["{{ $attribute }}"], log.cache["{{ $field }}"]) where log.cache["{{ $field }}"] != nil and log.cache["{{ $field }}"] != "-"
          {{- end }}
          {{- range $field, $attribute := include "opentelemetry-collectors.cloudfrontIntAttributes" . | fromYaml }}
          - set(log.attributes["{{ $attribute }}"], Int(log.cache["{{ $field }}"])) where log.cache["{{ $field }}"] != nil and log.cache["{{ $field }}"] != "-"
          {{- end }}
          {{- range $field, $attribute := include "opentelemetry-collectors.cloudfrontDoubleAttributes" . | fromYaml }}
          - set(log.attributes["{{ $attribute }}"], Double(log.cache["{{ $field }}"])) where log.cache["{{ $field }}"] != nil and log.cache["{{ $field }}"] != "-"
          {{- end }}
          # Status 000: the viewer closed the connection before the response.
          - delete_key(log.attributes, "http.response.status_code") where log.cache["sc-status"] == "000"
          # HTTP/2.0 -> http and 2
          - set(log.cache["protocol"], ExtractPatterns(log.cache["cs-protocol-version"], "^(?P<name>[A-Z]+)/(?P<version>[0-9.]+)$")) where log.cache["cs-protocol-version"] != nil
          - set(log.attributes["network.protocol.name"], ToLowerCase(log.cache["protocol"]["name"])) where log.cache["protocol"]["name"] != nil
          - set(log.attributes["network.protocol.version"], log.cache["protocol"]["version"]) where log.cache["protocol"]["version"] != nil
          - replace_pattern(log.attributes["network.protocol.version"], "^([23])[.]0$", "$1")
          # TLSv1.3 -> tls and 1.3
          - set(log.cache["tls"], ExtractPatterns(log.cache["ssl-protocol"], "^(?P<name>[A-Z]+)v(?P<version>[0-9.]+)$")) where log.cache["ssl-protocol"] != nil and log.cache["ssl-protocol"] != "-"
          - set(log.attributes["tls.protocol.name"], ToLowerCase(log.cache["tls"]["name"])) where log.cache["tls"]["name"] != nil
          - set(log.attributes["tls.protocol.version"], log.cache["tls"]["version"]) where log.cache["tls"]["version"] != nil
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

          - set(log.body, log.cache["log"]) where log.cache["log"] != nil
          - set(log.attributes["stream"], log.cache["stream"]) where log.cache["stream"] != nil
          - set(log.attributes["log.iostream"], log.cache["stream"]) where log.cache["stream"] != nil

          - set(log.attributes["k8s.pod.name"], log.cache["kubernetes.pod_name"]) where log.cache["kubernetes.pod_name"] != nil
          - set(log.attributes["k8s.namespace.name"], log.cache["kubernetes.namespace_name"]) where log.cache["kubernetes.namespace_name"] != nil
          - set(log.attributes["k8s.container.name"], log.cache["kubernetes.container_name"]) where log.cache["kubernetes.container_name"] != nil
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
        - aws_cloudwatch/cluster
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
        - aws_cloudwatch/fargate
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
        - aws_cloudwatch/cloudfront
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
        - aws_cloudwatch/{{ $id }}
      processors:
        - memory_limiter
        - transform/common_attributes
        - batch
        - groupbyattrs
      exporters:
        - otlp_http
    {{- end }}
{{- end }}
