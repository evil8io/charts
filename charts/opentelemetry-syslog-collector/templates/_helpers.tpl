{{/*
Expand the name of the chart.
*/}}
{{- define "opentelemetry-syslog-collector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "opentelemetry-syslog-collector.fullname" -}}
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
{{- define "opentelemetry-syslog-collector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "opentelemetry-syslog-collector.labels" -}}
helm.sh/chart: {{ include "opentelemetry-syslog-collector.chart" . }}
{{ include "opentelemetry-syslog-collector.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "opentelemetry-syslog-collector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opentelemetry-syslog-collector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels that the OpenTelemetry Operator sets on pods it manages.
Used as selectors for Services, CNPs, etc. that target operator-managed pods.
*/}}
{{- define "opentelemetry-syslog-collector.otelOperatorLabels" -}}
app.kubernetes.io/component: opentelemetry-collector
app.kubernetes.io/instance: {{ .Release.Namespace }}.{{ include "opentelemetry-syslog-collector.fullname" . }}
app.kubernetes.io/managed-by: opentelemetry-operator
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "opentelemetry-syslog-collector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opentelemetry-syslog-collector.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Merge config + configOverrides (plain dicts).
When collector.debug is true, append the debug exporter to all pipelines.
*/}}
{{- define "opentelemetry-syslog-collector.otelConfig" -}}
{{- $merged := mustMergeOverwrite (mustDeepCopy .Values.config) (.Values.configOverrides | default dict) -}}
{{- if .Values.collector.debug -}}
{{-   range $name, $pipeline := $merged.service.pipelines -}}
{{-     if not (has "debug" $pipeline.exporters) -}}
{{-       $_ := set $pipeline "exporters" (append $pipeline.exporters "debug") -}}
{{-     end -}}
{{-   end -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end -}}

{{/*
Build OTEL_RESOURCE_ATTRIBUTES env var value from .Values.resourceAttributes.
Each value is rendered through tpl to support Go template expressions.
*/}}
{{- define "opentelemetry-syslog-collector.resourceAttributesEnv" -}}
{{- $parts := list -}}
{{- range $k := keys .Values.resourceAttributes | sortAlpha -}}
{{-   $v := index $.Values.resourceAttributes $k | toString -}}
{{-   $parts = append $parts (printf "%s=%s" $k (tpl $v $)) -}}
{{- end -}}
{{- join "," $parts -}}
{{- end -}}
