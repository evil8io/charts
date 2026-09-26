{{/*
The config of the events collector.
*/}}
{{- define "opentelemetry-collectors.events.config" -}}
{{- $detection := include "opentelemetry-collectors.resourceDetection" (dict "root" . "scope" "cluster") }}
{{- $global := include "opentelemetry-collectors.resourceGlobal" . }}
receivers:
  k8s_objects:
    include_initial_state: true
    storage: file_storage
    objects:
      - name: events
        mode: watch
        group: events.k8s.io
        exclude_watch_type:
          - DELETED

exporters:
  # Local troubleshooting only. Do not add it to a pipeline.
  debug:
    verbosity: detailed
    sampling_initial: 5
    sampling_thereafter: 200
  otlp_http:
    {{- include "opentelemetry-collectors.exporterConfig" . | nindent 4 }}
    sending_queue:
      storage: file_storage

extensions:
  file_storage:
    directory: /var/lib/otelcol/file_storage
  {{- include "opentelemetry-collectors.basicAuthExtension" . | nindent 2 }}

processors:
  batch:
    send_batch_size: 8192
    timeout: 2s
  k8s_attributes:
    wait_for_metadata: true
    wait_for_metadata_timeout: 10s
    {{- include "opentelemetry-collectors.k8sAttributes" (dict "daemonset" false "profiles" false) | nindent 4 }}
  groupbyattrs:
    keys:
      {{- include "opentelemetry-collectors.k8sMetadata" . | nindent 6 }}
  resource/k8s_cluster_name:
    attributes:
      - action: insert
        key: k8s.cluster.name
        value: {{ .Values.clusterName | quote }}
  {{- with $detection }}
  resource_detection/env:
    {{- . | nindent 4 }}
  {{- end }}
  {{- with $global }}
  resource/global:
    {{- . | nindent 4 }}
  {{- end }}
  transform/kubernetes_events:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(resource.attributes["service.name"], "kubernetes-events")
      - context: log
        statements:
          - set(log.cache, log.body)
          - flatten(log.cache)
          - delete_key(log.attributes, "event.domain")
          - delete_key(log.attributes, "event.name")
          - delete_key(log.attributes, "k8s.resource.name")
          - set(log.time, Time(log.cache["object.metadata.creationTimestamp"], "%Y-%m-%dT%H:%M:%SZ"))
          - set(log.time, Time(log.cache["object.deprecatedLastTimestamp"], "%Y-%m-%dT%H:%M:%SZ")) where log.cache["object.deprecatedLastTimestamp"] != nil
          - set(log.time, Time(log.cache["object.eventTime"], "%Y-%m-%dT%H:%M:%S.%fZ")) where log.cache["object.eventTime"] != nil
          - set(log.time, Time(log.cache["object.series.lastObservedTime"], "%Y-%m-%dT%H:%M:%S.%fZ")) where log.cache["object.series.lastObservedTime"] != nil
          - set(log.severity_text, ConvertCase(log.cache["object.type"], "lower"))
          - set(log.severity_text, "info") where log.cache["object.type"] == "Normal"
          - set(log.severity_text, "error") where IsMatch(log.cache["object.reason"], "(?i)(error|emerg|fatal)")
          - set(log.severity_number, SEVERITY_NUMBER_INFO) where log.severity_text == "info"
          - set(log.severity_number, SEVERITY_NUMBER_WARN) where log.severity_text == "warning"
          - set(log.severity_number, SEVERITY_NUMBER_ERROR) where log.severity_text == "error"
          # https://opentelemetry.io/docs/specs/semconv/registry/attributes/k8s/
          - set(log.attributes["k8s.event.name"], log.cache["object.metadata.name"])
          - set(log.attributes["k8s.event.uid"], log.cache["object.metadata.uid"])
          - set(log.attributes["k8s.event.reason"], log.cache["object.reason"])
          - set(log.attributes["k8s.event.action"], log.cache["object.action"]) where log.cache["object.action"] != nil
          - set(log.attributes["k8s.event.start_time"], log.cache["object.metadata.creationTimestamp"])
          # series.count replaces deprecatedCount for a repeated event.
          - set(log.attributes["k8s.event.count"], log.cache["object.deprecatedCount"]) where log.cache["object.deprecatedCount"] != nil
          - set(log.attributes["k8s.event.count"], log.cache["object.series.count"]) where log.cache["object.series.count"] != nil
          - set(log.attributes["k8s.event.regarding.kind"], log.cache["object.regarding.kind"])
          - set(log.attributes["k8s.event.regarding.name"], log.cache["object.regarding.name"])
          # events.k8s.io allows an event outside the namespace of the regarding object.
          - set(log.attributes["k8s.event.regarding.namespace"], log.cache["object.regarding.namespace"]) where log.cache["object.regarding.namespace"] != nil
          - set(log.attributes["k8s.event.regarding.uid"], log.cache["object.regarding.uid"])
          - set(log.attributes["k8s.event.regarding.field_path"], log.cache["object.regarding.fieldPath"]) where log.cache["object.regarding.fieldPath"] != nil
          - set(log.attributes["k8s.event.reporting_controller"], log.cache["object.reportingController"]) where log.cache["object.reportingController"] != nil
          - >-
            set(
              log.attributes[
                Concat(
                  [
                    "k8s",
                    ConvertCase(log.cache["object.regarding.kind"], "lower"),
                    "name"
                  ],
                  "."
                )
              ],
              log.cache["object.regarding.name"]
            ) where (
              log.cache["object.regarding.kind"] != nil
              and log.cache["object.regarding.name"] != nil
            )
          - >-
            set(
              log.attributes[
                Concat(
                  [
                    "k8s",
                    ConvertCase(log.cache["object.regarding.kind"], "lower"),
                    "uid"
                  ],
                  "."
                )
              ],
              log.cache["object.regarding.uid"]
            ) where (
              log.cache["object.regarding.kind"] != nil
              and log.cache["object.regarding.uid"] != nil
            )
          # semconv names the HorizontalPodAutoscaler kind k8s.hpa.*
          - set(log.attributes["k8s.hpa.name"], log.attributes["k8s.horizontalpodautoscaler.name"]) where log.attributes["k8s.horizontalpodautoscaler.name"] != nil
          - set(log.attributes["k8s.hpa.uid"], log.attributes["k8s.horizontalpodautoscaler.uid"]) where log.attributes["k8s.horizontalpodautoscaler.uid"] != nil
          - delete_key(log.attributes, "k8s.horizontalpodautoscaler.name")
          - delete_key(log.attributes, "k8s.horizontalpodautoscaler.uid")
          # The raw object is dropped. The attributes above have every queryable field.
          - set(log.body, log.cache["object.note"]) where log.cache["object.note"] != nil
          - set(log.body, log.cache["object.reason"]) where log.cache["object.note"] == nil

service:
  extensions:
    - file_storage
    {{- if .Values.exporter.basicAuth.username }}
    - basicauth
    {{- end }}
  telemetry:
    {{- include "opentelemetry-collectors.serviceTelemetry" (dict "root" . "endpoint" .Values.selfTelemetry.endpoint) | nindent 4 }}
  pipelines:
    logs/k8sevents:
      receivers:
        - k8s_objects
      processors:
        - resource/k8s_cluster_name
        - transform/kubernetes_events
        - batch
        - groupbyattrs
        - k8s_attributes
        {{- if $detection }}
        - resource_detection/env
        {{- end }}
        {{- if $global }}
        - resource/global
        {{- end }}
      exporters:
        - otlp_http
{{- end }}
