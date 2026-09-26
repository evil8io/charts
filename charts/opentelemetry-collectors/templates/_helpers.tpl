{{/*
Expand the name of the chart.
*/}}
{{- define "opentelemetry-collectors.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "opentelemetry-collectors.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "opentelemetry-collectors.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opentelemetry-collectors.labels" -}}
helm.sh/chart: {{ include "opentelemetry-collectors.chart" . }}
{{ include "opentelemetry-collectors.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opentelemetry-collectors.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opentelemetry-collectors.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels of the OpenTelemetryCollector objects. The operator copies them to the workload
and the pods, so they exclude the chart version: a chart change alone does not restart
the collectors. They exclude app.kubernetes.io/name too: the operator keeps a name
label that the object has, and the network policies select on the operator's value
<name>-collector.
*/}}
{{- define "opentelemetry-collectors.collectorLabels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Name of a collector: <fullname>-<key>. Takes a dict with root and key.
*/}}
{{- define "opentelemetry-collectors.collectorName" -}}
{{- printf "%s-%s" (include "opentelemetry-collectors.fullname" .root) .key }}
{{- end }}

{{/*
Name of the shared ClusterRole.
*/}}
{{- define "opentelemetry-collectors.clusterRoleName" -}}
{{- printf "%s-collectors" (include "opentelemetry-collectors.fullname" .) }}
{{- end }}

{{/*
Image of a collector. Takes a dict with root and image; an empty tag selects the chart appVersion.
*/}}
{{- define "opentelemetry-collectors.image" -}}
{{- printf "%s:%s" .image.repository (.image.tag | default .root.Chart.AppVersion) }}
{{- end }}

{{/*
The env of every collector. The k8s_attributes filter, the eks detector, and the env detector read them.
*/}}
{{- define "opentelemetry-collectors.env" -}}
- name: K8S_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: OTEL_K8S_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: OTEL_K8S_NODE_IP
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP
- name: OTEL_K8S_NAMESPACE
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.namespace
- name: OTEL_K8S_POD_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.name
- name: OTEL_K8S_POD_IP
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: status.podIP
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.pod.name=$(OTEL_K8S_POD_NAME),k8s.namespace.name=$(OTEL_K8S_NAMESPACE),k8s.node.name=$(OTEL_K8S_NODE_NAME),host.name=$(OTEL_K8S_NODE_NAME),k8s.node.ip=$(OTEL_K8S_NODE_IP),k8s.pod.ip=$(OTEL_K8S_POD_IP),k8s.cluster.name={{ required "clusterName is required" .Values.clusterName }}"
{{- end }}

{{/*
Node affinity that keeps a collector off the Fargate nodes.
*/}}
{{- define "opentelemetry-collectors.affinity" -}}
{{- if .Values.aws.fargate.enabled }}
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            {{- range $key, $value := .Values.aws.fargate.nodeSelector }}
            - key: {{ $key }}
              operator: NotIn
              values:
                - {{ $value }}
            {{- end }}
{{- end }}
{{- end }}

{{/*
The common pod fields of a collector. Takes a dict with root and collector (the values of the collector).
*/}}
{{- define "opentelemetry-collectors.podFields" -}}
{{- with .collector.resources }}
resources:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .collector.podSecurityContext }}
podSecurityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .collector.securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .collector.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
{{- with .collector.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .collector.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- include "opentelemetry-collectors.affinity" .root }}
env:
  {{- include "opentelemetry-collectors.env" .root | nindent 2 }}
{{- end }}

{{/*
The image of the target allocator.
*/}}
{{- define "opentelemetry-collectors.targetAllocatorImage" -}}
{{- printf "%s:%s" .Values.targetAllocator.image.repository .Values.targetAllocator.image.tag }}
{{- end }}

{{/*
The otlp_http exporter settings that every collector shares.
*/}}
{{- define "opentelemetry-collectors.exporterConfig" -}}
endpoint: {{ required "exporter.endpoint is required" .Values.exporter.endpoint | quote }}
{{- with .Values.exporter.tenant }}
headers:
  X-Scope-OrgID: {{ . | quote }}
{{- end }}
{{- if .Values.exporter.insecureSkipVerify }}
tls:
  insecure_skip_verify: true
{{- end }}
{{- if .Values.exporter.basicAuth.username }}
auth:
  authenticator: basicauth
{{- end }}
{{- end }}

{{/*
The basicauth extension, when exporter.basicAuth has a username.
*/}}
{{- define "opentelemetry-collectors.basicAuthExtension" -}}
{{- if .Values.exporter.basicAuth.username }}
basicauth:
  client_auth:
    username: {{ .Values.exporter.basicAuth.username | quote }}
    password: {{ .Values.exporter.basicAuth.password | quote }}
{{- end }}
{{- end }}

{{/*
The service.telemetry block. Takes a dict with root and endpoint (host:port, or empty for no export).
*/}}
{{- define "opentelemetry-collectors.serviceTelemetry" -}}
logs:
  encoding: json
resource:
  service.name: ""
  service.version: ""
metrics:
  level: detailed
  {{- with .endpoint }}
  readers:
    - periodic:
        interval: 30000
        exporter:
          otlp:
            protocol: grpc
            endpoint: http://{{ . }}
            default_histogram_aggregation: base2_exponential_bucket_histogram
  {{- end }}
traces:
  sampler:
    parent_based:
      root:
        trace_id_ratio_based:
          ratio: {{ .root.Values.selfTelemetry.tracesSampleRatio }}
  {{- with .endpoint }}
  processors:
    - batch:
        exporter:
          otlp:
            protocol: grpc
            endpoint: http://{{ . }}
  {{- end }}
{{- end }}

{{/*
The k8s_attributes processor. Takes a dict with daemonset (bool) and profiles (bool).
*/}}
{{- define "opentelemetry-collectors.k8sAttributes" -}}
{{- if .daemonset }}
filter:
  node_from_env_var: OTEL_K8S_NODE_NAME
{{- end }}
passthrough: false
pod_association:
  {{- if .profiles }}
  - sources:
      - from: resource_attribute
        name: container.id
  {{- end }}
  - sources:
      - from: resource_attribute
        name: k8s.pod.uid
  - sources:
      - from: resource_attribute
        name: k8s.pod.name
      - from: resource_attribute
        name: k8s.namespace.name
      - from: resource_attribute
        name: k8s.node.name
  - sources:
      - from: resource_attribute
        name: k8s.pod.ip
  - sources:
      - from: resource_attribute
        name: k8s.pod.name
      - from: resource_attribute
        name: k8s.namespace.name
  - sources:
      - from: connection
extract:
  otel_annotations: true
  metadata:
    {{- include "opentelemetry-collectors.k8sMetadata" . | nindent 4 }}
  labels:
    - tag_name: k8s.app.instance
      key: app.kubernetes.io/instance
      from: pod
    - tag_name: k8s.app.component
      key: app.kubernetes.io/component
      from: pod
{{- end }}

{{/*
The metadata keys of the k8s_attributes processor and of the groupbyattrs processor.
*/}}
{{- define "opentelemetry-collectors.k8sMetadata" -}}
- k8s.namespace.name
- k8s.pod.name
- k8s.pod.uid
- k8s.node.name
- k8s.pod.start_time
- k8s.deployment.name
- k8s.replicaset.name
- k8s.replicaset.uid
- k8s.daemonset.name
- k8s.daemonset.uid
- k8s.job.name
- k8s.job.uid
- k8s.container.name
- k8s.cronjob.name
- k8s.statefulset.name
- k8s.statefulset.uid
- container.image.tag
- container.image.name
- k8s.cluster.uid
- service.namespace
- service.name
- service.version
- service.instance.id
{{- end }}

{{/*
The detectors of the resource_detection/env processor. Takes a dict with root and scope
(node or cluster). The node collector receives the telemetry of its own node only, so
node-scoped attributes are safe there. The cluster scope opts in cluster-scoped
attributes only. An empty result omits the processor.
*/}}
{{- define "opentelemetry-collectors.resourceDetectors" -}}
{{- $detectors := list }}
{{- if eq .scope "node" }}
{{- $detectors = append $detectors "env" }}
{{- end }}
{{- if .root.Values.aws.enabled }}
{{- $detectors = append $detectors "eks" }}
{{- end }}
{{- if eq .scope "node" }}
{{- $detectors = append $detectors "k8s_api" }}
{{- end }}
{{- join " " $detectors }}
{{- end }}

{{- define "opentelemetry-collectors.resourceDetection" -}}
{{- $detectors := include "opentelemetry-collectors.resourceDetectors" . }}
{{- if $detectors }}
detectors:
  {{- range splitList " " $detectors }}
  - {{ . }}
  {{- end }}
timeout: 15s
override: false
fail_on_missing_metadata: true
{{- if .root.Values.aws.enabled }}
eks:
  node_from_env_var: K8S_NODE_NAME
  resource_attributes:
    cloud.account.id:
      enabled: true
    {{- if eq .scope "node" }}
    cloud.availability_zone:
      enabled: true
    {{- end }}
    cloud.region:
      enabled: true
    {{- if eq .scope "node" }}
    host.id:
      enabled: true
    host.image.id:
      enabled: true
    host.type:
      enabled: true
    {{- end }}
    k8s.cluster.name:
      enabled: true
{{- end }}
{{- end }}
{{- end }}

{{/*
The resource/global processor, from resourceAttributes.
*/}}
{{- define "opentelemetry-collectors.resourceGlobal" -}}
{{- with .Values.resourceAttributes }}
attributes:
  {{- range $key, $value := . }}
  - action: insert
    key: {{ $key }}
    value: {{ $value | quote }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
The global settings of the prometheus receiver.
*/}}
{{- define "opentelemetry-collectors.prometheusGlobal" -}}
scrape_native_histograms: true
always_scrape_classic_histograms: false
scrape_protocols:
  - PrometheusProto
  - PrometheusText0.0.4
  - OpenMetricsText0.0.1
  - OpenMetricsText1.0.0
{{- end }}

{{/*
The kubelet and cAdvisor scrape jobs. Takes a dict with root, prefix (job name prefix),
fargate (drop, keep, or empty), kubelet (bool), and cadvisor (bool).
*/}}
{{- define "opentelemetry-collectors.kubeletJobs" -}}
{{- $root := .root }}
{{- $fargate := .fargate }}
{{- $prefix := .prefix }}
{{- range $job := list "kubelet" "kubelet-cadvisor" }}
{{- if or (and (eq $job "kubelet") $.kubelet) (and (eq $job "kubelet-cadvisor") $.cadvisor) }}
- job_name: {{ $prefix }}{{ $job }}
  scrape_interval: {{ $root.Values.targetAllocator.scrapeInterval }}
  scheme: https
  metrics_path: {{ eq $job "kubelet" | ternary "/metrics" "/metrics/cadvisor" }}
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  tls_config:
    insecure_skip_verify: true
  kubernetes_sd_configs:
    - role: node
  relabel_configs:
    {{- if $fargate }}
    {{- range $key, $value := $root.Values.aws.fargate.nodeSelector }}
    - source_labels: [__meta_kubernetes_node_label_{{ regexReplaceAll "[^a-zA-Z0-9_]" $key "_" }}]
      action: {{ $fargate }}
      regex: {{ $value }}
    {{- end }}
    {{- end }}
    - source_labels: [__address__]
      action: replace
      regex: (.+):(.+)
      replacement: ${1}:10250
      target_label: __address__
    - source_labels: [__meta_kubernetes_node_name]
      target_label: node
  honor_labels: true
  honor_timestamps: true
  metric_relabel_configs:
    - target_label: job
      replacement: {{ $root.Release.Namespace }}/kubelet
    {{- if eq $job "kubelet" }}
    - source_labels: [__name__, le]
      action: drop
      regex: (csi_operations|storage_operation_duration)_seconds_bucket;(0.25|2.5|15|25|120|600)
    {{- else }}
    - source_labels: [__name__]
      action: drop
      regex: container_cpu_(load_average_10s|system_seconds_total|user_seconds_total)
    - source_labels: [__name__]
      action: drop
      regex: container_fs_(io_current|reads_merged_total|sector_reads_total|sector_writes_total|writes_merged_total)
    - source_labels: [__name__]
      action: drop
      regex: container_memory_(failures_total|mapped_file|swap)
    - source_labels: [__name__]
      action: drop
      regex: container_(file_descriptors|tasks_state|threads_max)
    - source_labels: [__name__]
      action: drop
      regex: container_spec.*
    # A cgroup id without a pod is system.slice or another non-pod cgroup.
    - source_labels: [id, pod]
      action: drop
      regex: .+;
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Merges configOverrides on top of a base config. Takes a dict with name, base (YAML string), and overrides (map).
*/}}
{{- define "opentelemetry-collectors.mergeConfig" -}}
{{- $base := fromYaml .base -}}
{{- if hasKey $base "Error" -}}
{{-   fail (printf "the %s collector config is not valid YAML: %s" .name $base.Error) -}}
{{- end -}}
{{- $merged := mustMergeOverwrite $base (.overrides | default dict) -}}
{{- toYaml $merged -}}
{{- end -}}
