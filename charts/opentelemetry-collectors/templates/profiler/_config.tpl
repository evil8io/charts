{{/*
The config of the profiler collector. The eBPF profiler distribution has only the profiling
receiver, and batch and memory_limiter have no profiles support, so the exporter queue batches.
*/}}
{{- define "opentelemetry-collectors.profiler.config" -}}
receivers:
  profiling: {}

exporters:
  otlphttp:
    {{- include "opentelemetry-collectors.exporterConfig" . | nindent 4 }}
    sending_queue:
      batch:
        flush_timeout: 2s
        min_size: 8192

{{- with include "opentelemetry-collectors.basicAuthExtension" . }}

extensions:
  {{- . | nindent 2 }}
{{- end }}

processors:
  k8s_attributes:
    {{- include "opentelemetry-collectors.k8sAttributes" (dict "daemonset" true "profiles" true) | nindent 4 }}

service:
  {{- if .Values.exporter.basicAuth.username }}
  extensions:
    - basicauth
  {{- end }}
  telemetry:
    {{- include "opentelemetry-collectors.serviceTelemetry" (dict "root" . "endpoint" .Values.selfTelemetry.endpoint) | nindent 4 }}
  pipelines:
    profiles:
      receivers:
        - profiling
      processors:
        - k8s_attributes
      exporters:
        - otlphttp
{{- end }}
