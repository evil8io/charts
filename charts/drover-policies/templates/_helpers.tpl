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

{{- /* CEL: the project annotation of the namespace object that the CEL expression in . names, or "". */ -}}
{{- define "drover-policies.projectAnnotation" -}}
(has({{ . }}.metadata.annotations) && "field.cattle.io/projectId" in {{ . }}.metadata.annotations ? {{ . }}.metadata.annotations["field.cattle.io/projectId"] : "")
{{- end }}

{{- /* CEL: the project in the annotation value in ., when its prefix is variables.clusterId, else "". */ -}}
{{- define "drover-policies.projectOf" -}}
(variables.clusterId != "" && {{ . }}.startsWith(variables.clusterId + ":") ? {{ . }}.substring(variables.clusterId.size() + 1) : "")
{{- end }}

{{- /* CEL variables for the namespace object in .ns. Put them after variables.nsAll. A namespace with hasProject and an empty projectId has no trusted project. */ -}}
{{- define "drover-policies.projectVariables" -}}
- name: clusterIds
  expression: >-
    variables.nsAll.filter(ns, ns.metadata.name == "kube-system")
      .map(ns, {{ include "drover-policies.projectAnnotation" "ns" }})
      .filter(a, a.contains(":"))
      .map(a, a.split(":")[0])
- name: clusterId
  expression: 'variables.clusterIds.size() > 0 ? variables.clusterIds[0] : ""'
- name: projectAnnotation
  expression: >-
    {{ include "drover-policies.projectAnnotation" .ns }}
- name: hasProject
  expression: >-
    variables.clusterId != "" && variables.projectAnnotation != ""
- name: projectId
  expression: >-
    {{ include "drover-policies.projectOf" "variables.projectAnnotation" }}
{{- end }}

{{- /* CEL variables for the System and the Default project, the projects of kube-system and default. Put them after the project variables. */ -}}
{{- define "drover-policies.excludedProjectVariables" -}}
- name: excludedProjectIds
  expression: >-
    variables.nsAll.filter(ns, ns.metadata.name in ["kube-system", "default"])
      .map(ns, {{ include "drover-policies.projectAnnotation" "ns" }})
      .map(a, {{ include "drover-policies.projectOf" "a" }})
- name: excludedProjectsKnown
  expression: >-
    variables.excludedProjectIds.size() == 2 && !("" in variables.excludedProjectIds)
{{- end }}
