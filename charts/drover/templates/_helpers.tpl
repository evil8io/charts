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
    - ""
  resources:
    - serviceaccounts/token
  resourceNames:
    - openbao
    - project-owner
    - project-member
    - read-only
  verbs:
    - create
- apiGroups:
    - rbac.authorization.k8s.io
  resources:
    - roles
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

{{- define "drover.openbao.name" -}}
{{- default "openbao" .Values.openbao.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "drover.openbao.fullname" -}}
{{- $name := include "drover.openbao.name" . }}
{{- if .Values.openbao.fullnameOverride }}
{{- .Values.openbao.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "drover.openbao.selectorLabels" -}}
app.kubernetes.io/name: {{ include "drover.openbao.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
component: server
{{- end }}

{{- define "drover.openbao.sealSecretName" -}}
{{- (first .Values.openbao.server.extraVolumes).name }}
{{- end }}

{{- define "drover.openbaoSeal.fullname" -}}
{{ include "drover.fullname" . }}-openbao-seal
{{- end }}

{{- define "drover.openbao.address" -}}
http://{{ include "drover.openbao.fullname" . }}-active.{{ .Release.Namespace }}:8200
{{- end }}

{{- define "drover.openbaoRoles.fullname" -}}
{{ include "drover.fullname" . }}-openbao-roles
{{- end }}

{{- define "drover.broker.rancherUrl" -}}
{{- if .Values.broker.rancherUrl }}
{{- .Values.broker.rancherUrl }}
{{- else if .Values.httpRoute.hostnames }}
{{- printf "https://%s" (first .Values.httpRoute.hostnames) }}
{{- else }}
{{- fail "projectSync.serviceAccounts.enabled needs broker.rancherUrl or httpRoute.hostnames, because OpenBao reaches the clusters through the Rancher proxy" }}
{{- end }}
{{- end }}

{{- define "drover.telemetryEnv" -}}
- name: POD_UID
  valueFrom:
    fieldRef:
      fieldPath: metadata.uid
- name: OTEL_RESOURCE_ATTRIBUTES
  value: k8s.pod.uid=$(POD_UID)
{{- end }}
