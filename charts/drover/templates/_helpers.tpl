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
    - management.cattle.io
  resources:
    - clusters
  verbs:
    - get
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

{{- define "drover.durationSeconds" -}}
{{- $units := dict "h" 3600 "m" 60 "s" 1 }}
{{- $seconds := 0 }}
{{- range $part := regexFindAll "[0-9]+[hms]" . -1 }}
{{- $unit := regexFind "[hms]$" $part }}
{{- $seconds = add $seconds (mul (trimSuffix $unit $part | int) (get $units $unit)) }}
{{- end }}
{{- $seconds }}
{{- end }}

{{- define "drover.rotateToken.podTemplate" -}}
{{- if ge (include "drover.durationSeconds" .Values.tokenRotation.renewBefore | int) (include "drover.durationSeconds" .Values.tokenRotation.ttl | int) }}
{{- fail "tokenRotation.renewBefore must be shorter than tokenRotation.ttl, because a longer window renews the token at every run" }}
{{- end }}
{{- $component := dict "root" . "component" "rotate-token" }}
{{- $containers := list
  (dict
    "name" "rotate-api-filter"
    "volume" "credentials"
    "credentialsSecret" (include "drover.credentialsName" .)
    "tokenSecret" (printf "%s/%s" .Release.Namespace (include "drover.tokenSecretName" .))
    "passwordSecret" "cattle-local-user-passwords/u-drover")
  (dict
    "name" "rotate-project-sync"
    "volume" "project-sync-credentials"
    "credentialsSecret" (include "drover.projectSync.credentialsName" .)
    "tokenSecret" (printf "%s/%s" .Release.Namespace (include "drover.projectSync.tokenSecretName" .))
    "passwordSecret" (printf "cattle-local-user-passwords/%s" (include "drover.projectSync.user" .)))
-}}
metadata:
  labels:
    {{- include "drover.componentLabels" $component | nindent 4 }}
spec:
  restartPolicy: OnFailure
  serviceAccountName: {{ include "drover.rotateToken.fullname" . }}
  automountServiceAccountToken: true
  securityContext:
    {{- include "drover.podSecurityContext" . | nindent 4 }}
  containers:
    {{- range $c := $containers }}
    - name: {{ $c.name }}
      image: {{ include "drover.image" $ | quote }}
      imagePullPolicy: IfNotPresent
      args:
        - rotate-token
        - "--rancher-url={{ $.Values.rancher.url }}"
        - "--credentials-dir=/var/run/secrets/drover/credentials"
        - "--token-secret={{ $c.tokenSecret }}"
        - "--token-key=token"
        - "--password-secret={{ $c.passwordSecret }}"
        - "--ttl={{ $.Values.tokenRotation.ttl }}"
        - "--renew-before={{ $.Values.tokenRotation.renewBefore }}"
        - "--keep={{ $.Values.tokenRotation.keep }}"
        - "--log-level={{ $.Values.logLevel }}"
        {{- if $.Values.rancher.insecureSkipVerify }}
        - "--rancher-insecure-skip-verify"
        {{- end }}
        {{- if $.Values.otlp.endpoint }}
        - "--otlp-endpoint={{ $.Values.otlp.endpoint }}"
        - "--otlp-traces=true"
        - "--otlp-metrics=true"
        - "--service-name={{ $.Values.otlp.serviceName }}"
        {{- end }}
      {{- if $.Values.otlp.endpoint }}
      env:
        {{- include "drover.telemetryEnv" $ | nindent 8 }}
      {{- end }}
      securityContext:
        {{- include "drover.securityContext" $ | nindent 8 }}
      resources:
        {{- toYaml $.Values.tokenRotation.resources | nindent 8 }}
      volumeMounts:
        - name: {{ $c.volume }}
          mountPath: /var/run/secrets/drover/credentials
          readOnly: true
    {{- end }}
  volumes:
    {{- range $c := $containers }}
    - name: {{ $c.volume }}
      secret:
        secretName: {{ $c.credentialsSecret }}
    {{- end }}
{{- end }}

{{- define "drover.routes" -}}
{{- $fanout := .Values.apiFilter.fanout.enabled }}
{{- $rancherBackend := dict "name" .Values.httpRoute.rancherBackendRef.name "port" (.Values.httpRoute.rancherBackendRef.port | int) }}
{{- with .Values.httpRoute.rancherBackendRef.namespace }}
{{- $_ := set $rancherBackend "namespace" . }}
{{- end -}}
[
  {
    "apiVersion": dyn("gateway.networking.k8s.io/v1"),
    "kind": dyn("HTTPRoute"),
    "metadata": dyn({
      "name": dyn({{ printf "%s-" (include "drover.fullname" .) | quote }} + object.metadata.name + "-" + variables.revision),
      "namespace": dyn({{ .Release.Namespace | quote }}),
      "labels": dyn({
        {{- range $key, $value := include "drover.selectorLabels" . | fromYaml }}
        {{ $key | quote }}: dyn({{ $value | quote }}),
        {{- end }}
        "drover-route-revision": dyn(variables.revision)
      })
    }),
    "spec": dyn({
      {{- with .Values.httpRoute.parentRefs }}
      "parentRefs": dyn({{ include "drover.celLiteral" . }}),
      {{- end }}
      {{- with .Values.httpRoute.hostnames }}
      "hostnames": dyn({{ include "drover.celLiteral" . }}),
      {{- end }}
      "rules": dyn([
        dyn({
          "matches": dyn([
            dyn({
              "path": dyn({"type": dyn("Exact"), "value": dyn(variables.prefix + "/api/v1/namespaces")}),
              "method": dyn("GET")
            }),
            dyn({
              "path": dyn({"type": dyn("Exact"), "value": dyn(variables.prefix + "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews")}),
              "method": dyn("POST")
            })
            {{- if $fanout }},
            dyn({
              "path": dyn({"type": dyn("PathPrefix"), "value": dyn(variables.prefix + "/api/v1")}),
              "method": dyn("GET")
            }),
            dyn({
              "path": dyn({"type": dyn("PathPrefix"), "value": dyn(variables.prefix + "/apis")}),
              "method": dyn("GET")
            })
            {{- end }}
          ]),
          {{- with .Values.httpRoute.timeouts }}
          "timeouts": dyn({{ include "drover.celLiteral" . }}),
          {{- end }}
          "backendRefs": dyn([
            dyn({
              "name": dyn({{ include "drover.apiFilter.fullname" . | quote }}),
              "port": dyn(8080)
            })
          ])
        })
        {{- if $fanout }},
        dyn({
          "matches": dyn([
            dyn({
              "path": dyn({"type": dyn("PathPrefix"), "value": dyn(variables.prefix + "/api/v1/namespaces")}),
              "method": dyn("GET")
            })
          ]),
          {{- with .Values.httpRoute.timeouts }}
          "timeouts": dyn({{ include "drover.celLiteral" . }}),
          {{- end }}
          "backendRefs": dyn([
            dyn({{ include "drover.celLiteral" $rancherBackend }})
          ])
        })
        {{- end }}
      ])
    })
  }
]
{{- end }}

{{- define "drover.routes.revision" -}}
{{- include "drover.routes" . | sha256sum | trunc 8 }}
{{- end }}
