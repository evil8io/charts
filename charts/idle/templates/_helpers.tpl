{{/*
Expand the name of the chart.
*/}}
{{- define "idle.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "idle.fullname" -}}
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
Chart name and version label.
*/}}
{{- define "idle.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (chart-wide resources).
*/}}
{{- define "idle.labels" -}}
helm.sh/chart: {{ include "idle.chart" . }}
{{ include "idle.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (chart-wide).
*/}}
{{- define "idle.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idle.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Per-deployment name: "<fullname>-<deployment>", truncated to 63.
Call with (dict "root" $ "name" $deploymentName).
*/}}
{{- define "idle.deploymentName" -}}
{{- $full := include "idle.fullname" .root -}}
{{- printf "%s-%s" $full .name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Per-deployment labels. Call with (dict "root" $ "name" $name).
*/}}
{{- define "idle.deploymentLabels" -}}
{{ include "idle.labels" .root }}
idle.evil8.io/deployment: {{ .name }}
{{- end }}

{{/*
Per-deployment selector labels. Call with (dict "root" $ "name" $name).
*/}}
{{- define "idle.deploymentSelectorLabels" -}}
{{ include "idle.selectorLabels" .root }}
idle.evil8.io/deployment: {{ .name }}
{{- end }}

{{/*
Merge .Values.defaults with a per-deployment override map.
Call with (dict "root" $ "overrides" $overrides). Returns a dict.
*/}}
{{- define "idle.mergedConfig" -}}
{{- $defaults := deepCopy .root.Values.defaults -}}
{{- $overrides := default (dict) .overrides -}}
{{- mergeOverwrite $defaults $overrides | toYaml -}}
{{- end }}

{{/*
Effective priorityClassName for a deployment. Call with (dict "root" $ "cfg" $cfg).
- per-deployment priorityClassName wins if non-empty
- else priorityClass.name if priorityClass.create=true
- else empty (field is omitted from pod spec)
*/}}
{{- define "idle.priorityClassName" -}}
{{- if .cfg.priorityClassName -}}
{{ .cfg.priorityClassName }}
{{- else if .root.Values.priorityClass.create -}}
{{ .root.Values.priorityClass.name }}
{{- end -}}
{{- end }}

{{/*
ServiceAccount name for a deployment. Call with (dict "root" $ "name" $name "cfg" $cfg).
*/}}
{{- define "idle.serviceAccountName" -}}
{{- if .cfg.serviceAccount.create -}}
{{- default (include "idle.deploymentName" (dict "root" .root "name" .name)) .cfg.serviceAccount.name -}}
{{- else -}}
{{- default "default" .cfg.serviceAccount.name -}}
{{- end -}}
{{- end }}

{{/*
Effective affinity YAML for a deployment. Call with (dict "root" $ "name" $name "cfg" $cfg).
Takes cfg.affinity as-is and splices in a podAntiAffinity stanza when cfg.podAntiAffinity.enabled.
Returns a YAML fragment or empty string.
*/}}
{{- define "idle.affinity" -}}
{{- $cfg := .cfg -}}
{{- $aff := deepCopy (default (dict) $cfg.affinity) -}}
{{- if $cfg.podAntiAffinity.enabled -}}
  {{- $pa := $cfg.podAntiAffinity -}}
  {{- $term := dict
      "labelSelector" (dict "matchLabels" (dict "idle.evil8.io/deployment" .name))
      "topologyKey" $pa.topologyKey
  -}}
  {{- $existing := dict -}}
  {{- if hasKey $aff "podAntiAffinity" -}}
    {{- $existing = index $aff "podAntiAffinity" -}}
  {{- end -}}
  {{- if eq $pa.mode "hard" -}}
    {{- $list := list -}}
    {{- if hasKey $existing "requiredDuringSchedulingIgnoredDuringExecution" -}}
      {{- $list = index $existing "requiredDuringSchedulingIgnoredDuringExecution" -}}
    {{- end -}}
    {{- $list = append $list $term -}}
    {{- $_ := set $existing "requiredDuringSchedulingIgnoredDuringExecution" $list -}}
  {{- else -}}
    {{- $weighted := dict "weight" (int $pa.weight) "podAffinityTerm" $term -}}
    {{- $list := list -}}
    {{- if hasKey $existing "preferredDuringSchedulingIgnoredDuringExecution" -}}
      {{- $list = index $existing "preferredDuringSchedulingIgnoredDuringExecution" -}}
    {{- end -}}
    {{- $list = append $list $weighted -}}
    {{- $_ := set $existing "preferredDuringSchedulingIgnoredDuringExecution" $list -}}
  {{- end -}}
  {{- $_ := set $aff "podAntiAffinity" $existing -}}
{{- end -}}
{{- if $aff -}}
{{ toYaml $aff }}
{{- end -}}
{{- end }}
