{{/*
Vespa Helm チャート ヘルパーテンプレート
Helper templates for Vespa Helm chart
*/}}

{{/*
チャート名 / Chart name
*/}}
{{- define "vespa.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
リリース名ベース / Full name using release name
*/}}
{{- define "vespa.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
共通ラベル / Common labels
*/}}
{{- define "vespa.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "vespa.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Vespa イメージ参照 / Vespa image reference
*/}}
{{- define "vespa.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end }}

{{/*
内部ヘッドレスサービス名 / Internal headless service name
*/}}
{{- define "vespa.internalService" -}}
{{ include "vespa.fullname" . }}-internal
{{- end }}

{{/*
VESPA_CONFIGSERVERS 環境変数の値を生成する
Generate the value for VESPA_CONFIGSERVERS environment variable
引数: . (トップレベルコンテキスト)
*/}}
{{- define "vespa.configservers" -}}
{{- $release := .Release.Name -}}
{{- $svc := include "vespa.internalService" . -}}
{{- $ns := .Release.Namespace -}}
{{- $replicas := int .Values.configserver.replicas -}}
{{- $result := list -}}
{{- range $i := until $replicas -}}
  {{- $fqdn := printf "%s-configserver-%d.%s.%s.svc.cluster.local" $release $i $svc $ns -}}
  {{- $result = append $result $fqdn -}}
{{- end -}}
{{ join "," $result }}
{{- end }}
