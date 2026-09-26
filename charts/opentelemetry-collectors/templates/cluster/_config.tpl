{{/*
The config of the cluster collector.
*/}}
{{- define "opentelemetry-collectors.cluster.config" -}}
{{- $v := .Values.collectors.cluster }}
{{- $detection := include "opentelemetry-collectors.resourceDetection" (dict "root" . "scope" "cluster") }}
{{- $global := include "opentelemetry-collectors.resourceGlobal" . }}
{{- $fargateJobs := "" }}
{{- if .Values.aws.fargate.enabled }}
{{- $fargateJobs = include "opentelemetry-collectors.kubeletJobs" (dict "root" . "prefix" "fargate-" "fargate" "keep" "kubelet" true "cadvisor" true) }}
{{- end }}
receivers:
  prometheus:
    config:
      global:
        {{- include "opentelemetry-collectors.prometheusGlobal" . | nindent 8 }}
      scrape_configs:
        {{- if not (or $fargateJobs $v.scrapes.apiserver.enabled) }} []
        {{- end }}
        {{- with $fargateJobs }}
        {{- . | nindent 8 }}
        {{- end }}
        {{- if $v.scrapes.apiserver.enabled }}
        - job_name: kube-apiserver
          scrape_interval: {{ .Values.targetAllocator.scrapeInterval }}
          scheme: https
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          tls_config:
            ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
            server_name: kubernetes
          kubernetes_sd_configs:
            - role: endpoints
              namespaces:
                names:
                  - default
          relabel_configs:
            - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
              action: keep
              regex: kubernetes;https
          honor_labels: true
          honor_timestamps: true
          metric_relabel_configs:
            - target_label: job
              replacement: kube-apiserver
            - source_labels: [__name__]
              action: drop
              regex: etcd_request_duration_seconds_bucket
            - source_labels: [__name__, le]
              action: drop
              regex: apiserver_request_duration_seconds_bucket;(0.15|0.2|0.3|0.35|0.4|0.45|0.6|0.7|0.8|0.9|1.25|1.5|1.75|2|3|3.5|4|4.5|6|7|8|9|15|25|40|50)
        {{- end }}

exporters:
  # Local troubleshooting only. Do not add it to a pipeline.
  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200
  otlp_http:
    {{- include "opentelemetry-collectors.exporterConfig" . | nindent 4 }}

{{- with include "opentelemetry-collectors.basicAuthExtension" . }}

extensions:
  {{- . | nindent 2 }}
{{- end }}

processors:
  batch:
    send_batch_size: 8192
    timeout: 2s
  resource/k8s_cluster_name:
    attributes:
      - action: insert
        key: k8s.cluster.name
        value: {{ .Values.clusterName | quote }}
  {{- with $detection }}
  resource_detection/env:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with $global }}
  resource/global:
    {{- . | nindent 4 }}
  {{- end }}

service:
  {{- if .Values.exporter.basicAuth.username }}
  extensions:
    - basicauth
  {{- end }}
  telemetry:
    {{- include "opentelemetry-collectors.serviceTelemetry" (dict "root" . "endpoint" .Values.selfTelemetry.endpoint) | nindent 4 }}
  pipelines:
    metrics:
      receivers:
        - prometheus
      processors:
        - resource/k8s_cluster_name
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
