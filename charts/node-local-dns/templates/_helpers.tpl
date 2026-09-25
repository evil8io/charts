{{/*
Expand the name of the chart.
*/}}
{{- define "node-local-dns.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "node-local-dns.fullname" -}}
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
{{- define "node-local-dns.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Release labels, without app.kubernetes.io/name.
*/}}
{{- define "node-local-dns.releaseLabels" -}}
helm.sh/chart: {{ include "node-local-dns.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "node-local-dns.labels" -}}
{{ include "node-local-dns.releaseLabels" . }}
{{ include "node-local-dns.selectorLabels" . }}
{{- end }}

{{/*
Selector labels. The DaemonSet selector is immutable: keep this label only.
*/}}
{{- define "node-local-dns.selectorLabels" -}}
app.kubernetes.io/name: {{ include "node-local-dns.name" . }}
{{- end }}

{{- define "node-local-dns.kubectlImage" -}}
{{- printf "%s:%s" .Values.kubectl.image.repository (toString .Values.kubectl.image.tag) | quote }}
{{- end }}
