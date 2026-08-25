{{- define "node-monitor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "node-monitor.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "node-monitor.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "node-monitor.labels" -}}
app.kubernetes.io/name: {{ include "node-monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: regulated-delivery-platform
platform.internal/environment: {{ .Values.release.environment | quote }}
platform.internal/change-ref: {{ .Values.release.changeRef | quote }}
{{- end -}}

{{- define "node-monitor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "node-monitor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "node-monitor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "node-monitor.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
