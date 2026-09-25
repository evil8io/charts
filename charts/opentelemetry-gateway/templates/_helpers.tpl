{{/*
Expand the name of the chart.
*/}}
{{- define "opentelemetry-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "opentelemetry-gateway.fullname" -}}
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
{{- define "opentelemetry-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opentelemetry-gateway.labels" -}}
helm.sh/chart: {{ include "opentelemetry-gateway.chart" . }}
{{ include "opentelemetry-gateway.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opentelemetry-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opentelemetry-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels of the OpenTelemetryCollector objects. The operator copies them to the pod
template, so they exclude the chart version: a chart change alone does not restart
the collectors.
*/}}
{{- define "opentelemetry-gateway.collectorLabels" -}}
{{ include "opentelemetry-gateway.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Labels that the OpenTelemetry Operator sets on the pods of every collector.
The network policies select on them.
*/}}
{{- define "opentelemetry-gateway.otelOperatorLabels" -}}
app.kubernetes.io/component: opentelemetry-collector
app.kubernetes.io/managed-by: opentelemetry-operator
{{- end }}

{{/*
The signals. Each signal gets its own collector.
*/}}
{{- define "opentelemetry-gateway.signals" -}}
logs traces metrics profiles
{{- end }}

{{/*
Merges the base config and configOverrides.
*/}}
{{- define "opentelemetry-gateway.otelConfig" -}}
{{- $base := include "opentelemetry-gateway.baseConfig" . | fromYaml -}}
{{- if hasKey $base "Error" -}}
{{-   fail (printf "the collector config is not valid YAML: %s" $base.Error) -}}
{{- end -}}
{{- $merged := mustMergeOverwrite $base (.Values.configOverrides | default dict) -}}
{{- toYaml $merged -}}
{{- end -}}
