{{- define "drover-policies.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "drover-policies.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "drover-policies.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "drover-policies.selectorLabels" -}}
app.kubernetes.io/name: {{ include "drover-policies.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "drover-policies.labels" -}}
helm.sh/chart: {{ include "drover-policies.chart" . }}
{{ include "drover-policies.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "drover-policies.gceResources" -}}
namespaces:
  version: v1
  resource: namespaces
clusterrolebindings:
  group: rbac.authorization.k8s.io
  version: v1
  resource: clusterrolebindings
httproutes:
  group: gateway.networking.k8s.io
  version: v1
  resource: httproutes
grpcroutes:
  group: gateway.networking.k8s.io
  version: v1
  resource: grpcroutes
tlsroutes:
  group: gateway.networking.k8s.io
  version: v1
  resource: tlsroutes
listenersets:
  group: gateway.networking.k8s.io
  version: v1
  resource: listenersets
services:
  version: v1
  resource: services
{{- end }}

{{- define "drover-policies.gceReaders" -}}
namespaces:
  - namespace-project
  - namespace-quotas
  - route-hostname
  - listenerset-hostname
  - prometheus-monitors
clusterrolebindings:
  - namespace-project
httproutes:
  - route-hostname
grpcroutes:
  - route-hostname
tlsroutes:
  - route-hostname
listenersets:
  - listenerset-hostname
services:
  - route-hostname
{{- end }}

{{- /* Renders a non-empty string when the entry is on. An explicit enabled wins, else a reader that is on. */ -}}
{{- define "drover-policies.gceEnabled" -}}
{{- $entry := index .root.Values.globalContextEntries .name | default dict -}}
{{- if hasKey $entry "enabled" -}}
{{- if $entry.enabled }}true{{ end -}}
{{- else -}}
{{- range index (include "drover-policies.gceReaders" . | fromYaml) .name -}}
{{- if (index $.root.Values.policies .).enabled }}true{{ end -}}
{{- end -}}
{{- end -}}
{{- end }}
