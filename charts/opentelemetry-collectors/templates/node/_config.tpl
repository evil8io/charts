{{/*
The config of the node collector.
*/}}
{{- define "opentelemetry-collectors.node.config" -}}
{{- $v := .Values.collectors.node }}
{{- $detection := include "opentelemetry-collectors.resourceDetection" (dict "root" . "scope" "node") }}
{{- $global := include "opentelemetry-collectors.resourceGlobal" . }}
receivers:
  otelarrow:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
        keepalive:
          server_parameters:
            max_connection_age: 1m
            max_connection_age_grace: 10m
  otlp:
    protocols:
      http:
        endpoint: "0.0.0.0:4318"
        include_metadata: true
        cors:
          allowed_origins:
            - "*"
          allowed_headers:
            - "*"
          max_age: 7200
  {{- if $v.logs.enabled }}
  file_log:
    include:
      - /var/log/pods/*/*/*.log
    exclude: []
    start_at: end
    retry_on_failure:
      enabled: true
    storage: file_storage
    include_file_path: true
    include_file_name: false
    skip_unmodified_files: true
    operators:
      - type: container
        id: container-parser
        max_log_size: 102400
  {{- end }}
  prometheus:
    config:
      global:
        {{- include "opentelemetry-collectors.prometheusGlobal" . | nindent 8 }}
      scrape_configs:
        {{- $jobs := include "opentelemetry-collectors.kubeletJobs" (dict "root" . "prefix" "" "fargate" (.Values.aws.fargate.enabled | ternary "drop" "") "kubelet" $v.kubelet.enabled "cadvisor" $v.cadvisor.enabled) }}
        {{- if $jobs }}
        {{- $jobs | nindent 8 }}
        {{- else }} []
        {{- end }}

exporters:
  # Local troubleshooting only. Do not add it to a pipeline.
  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200
  otlp_http:
    {{- include "opentelemetry-collectors.exporterConfig" . | nindent 4 }}
    sending_queue:
      storage: file_storage

extensions:
  file_storage:
    directory: /var/lib/otelcol
    max_size: {{ $v.fileStorage.maxSize }}
  {{- include "opentelemetry-collectors.basicAuthExtension" . | nindent 2 }}

processors:
  batch:
    send_batch_size: 8192
    timeout: 2s
  k8s_attributes:
    wait_for_metadata: true
    wait_for_metadata_timeout: 10s
    {{- include "opentelemetry-collectors.k8sAttributes" (dict "daemonset" true "profiles" false) | nindent 4 }}
  {{- with $detection }}
  resource_detection/env:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with $global }}
  resource/global:
    {{- . | nindent 4 }}
  {{- end }}
  transform/delete_attributes:
    error_mode: ignore
    log_statements:
      - context: log
        statements:
          - delete_key(log.attributes, "log.file.path")

service:
  extensions:
    - file_storage
    {{- if .Values.exporter.basicAuth.username }}
    - basicauth
    {{- end }}
  telemetry:
    {{- include "opentelemetry-collectors.serviceTelemetry" (dict "root" . "endpoint" (ternary "localhost:4317" "" (ne .Values.selfTelemetry.endpoint ""))) | nindent 4 }}
  pipelines:
    logs:
      receivers:
        - otlp
        - otelarrow
        {{- if $v.logs.enabled }}
        - file_log
        {{- end }}
      processors:
        - k8s_attributes
        {{- if $detection }}
        - resource_detection/env
        {{- end }}
        {{- if $global }}
        - resource/global
        {{- end }}
        - transform/delete_attributes
        - batch
      exporters:
        - otlp_http
    metrics:
      receivers:
        - otlp
        - otelarrow
        - prometheus
      processors:
        - k8s_attributes
        {{- if $detection }}
        - resource_detection/env
        {{- end }}
        {{- if $global }}
        - resource/global
        {{- end }}
        - batch
      exporters:
        - otlp_http
    traces:
      receivers:
        - otlp
        - otelarrow
      processors:
        - k8s_attributes
        {{- if $detection }}
        - resource_detection/env
        {{- end }}
        {{- if $global }}
        - resource/global
        {{- end }}
        - batch
      exporters:
        - otlp_http
{{- end }}
