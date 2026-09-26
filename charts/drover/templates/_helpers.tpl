{{- define "drover.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "drover.fullname" -}}
{{- if contains .Chart.Name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "drover.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "drover.version" -}}
{{- default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{- define "drover.selectorLabels" -}}
app.kubernetes.io/name: {{ include "drover.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "drover.labels" -}}
helm.sh/chart: {{ include "drover.chart" . }}
{{ include "drover.selectorLabels" . }}
app.kubernetes.io/version: {{ include "drover.version" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "drover.componentSelectorLabels" -}}
{{ include "drover.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "drover.componentLabels" -}}
{{ include "drover.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "drover.image" -}}
{{ .Values.image.repository }}:{{ include "drover.version" . }}
{{- end }}

{{- define "drover.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "drover.securityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end }}

{{- define "drover.tokenSecretName" -}}
{{- printf "%s-token" (include "drover.fullname" .) }}
{{- end }}

{{- define "drover.credentialsName" -}}
{{- printf "%s-credentials" (include "drover.fullname" .) }}
{{- end }}

{{- define "drover.tokenFile" -}}
/var/run/secrets/drover/token/token
{{- end }}

{{- define "drover.apiFilter.fullname" -}}
{{ include "drover.fullname" . }}-api-filter
{{- end }}

{{- define "drover.rotateToken.fullname" -}}
{{ include "drover.fullname" . }}-rotate-token
{{- end }}

{{- define "drover.projectSync.fullname" -}}
{{ include "drover.fullname" . }}-project-sync
{{- end }}

{{- define "drover.projectSync.user" -}}
u-drover-project-sync
{{- end }}

{{- define "drover.projectSync.tokenSecretName" -}}
{{- printf "%s-token" (include "drover.projectSync.fullname" .) }}
{{- end }}

{{- define "drover.projectSync.credentialsName" -}}
{{- printf "%s-credentials" (include "drover.projectSync.fullname" .) }}
{{- end }}

{{- define "drover.serviceUser.rancherRbac.fullname" -}}
{{ include "drover.fullname" . }}-rancher-rbac
{{- end }}

{{- define "drover.apiFilter.rules" -}}
- apiGroups:
    - ""
  resources:
    - namespaces
  verbs:
    - get
    - list
    - watch
{{- end }}

{{- define "drover.projectSync.rules" -}}
{{- if .Values.projectSync.serviceAccounts.enabled -}}
- apiGroups:
    - ""
  resources:
    - namespaces
  verbs:
    - "*"
- apiGroups:
    - management.cattle.io
  resources:
    - projects
  verbs:
    - get
    - list
    - watch
    - create
    - manage-namespaces
- apiGroups:
    - ""
  resources:
    - serviceaccounts
  verbs:
    - get
    - list
    - watch
    - create
    - delete
- apiGroups:
    - rbac.authorization.k8s.io
  resources:
    - rolebindings
    - clusterrolebindings
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - delete
- apiGroups:
    - rbac.authorization.k8s.io
  resources:
    - clusterroles
  resourceNames:
    - admin
    - edit
    - view
    - create-ns
  verbs:
    - bind
{{- else -}}
- apiGroups:
    - ""
  resources:
    - namespaces
  verbs:
    - get
    - list
    - watch
    - patch
- apiGroups:
    - management.cattle.io
  resources:
    - projects
  verbs:
    - get
    - list
    - watch
{{- end }}
{{- end }}

{{- define "drover.serviceUser.hookAnnotations" -}}
helm.sh/hook: {{ .hook }}
helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
helm.sh/hook-weight: {{ .weight | quote }}
{{- end }}

{{- define "drover.celLiteral" -}}
{{- if kindIs "slice" . -}}
{{- $items := list -}}
{{- range . -}}
{{- $items = append $items (include "drover.celLiteral" .) -}}
{{- end -}}
{{- printf "[%s]" (join ", " $items) -}}
{{- else if kindIs "map" . -}}
{{- $map := . -}}
{{- $items := list -}}
{{- range $key := (keys . | sortAlpha) -}}
{{- $items = append $items (printf "%q: dyn(%s)" $key (include "drover.celLiteral" (index $map $key))) -}}
{{- end -}}
{{- printf "{%s}" (join ", " $items) -}}
{{- else -}}
{{- toJson . -}}
{{- end -}}
{{- end }}
