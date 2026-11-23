{{- define "gvisor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gvisor.fullname" -}}
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

{{- define "gvisor.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "gvisor.labels" -}}
helm.sh/chart: {{ include "gvisor.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{ include "gvisor.selectorLabels" . }}
{{- end }}

{{/*
Selector labels. The DaemonSet selector is immutable: keep this label only.
*/}}
{{- define "gvisor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gvisor.name" . }}
{{- end }}

{{- define "gvisor.image" -}}
{{- printf "%s:%s" .Values.image.repository (toString .Values.image.tag) | quote }}
{{- end }}
