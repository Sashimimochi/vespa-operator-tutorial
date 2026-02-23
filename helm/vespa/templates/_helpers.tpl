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

{{/*
レプリカ数に基づいて hosts.xml を動的生成する
Dynamically generate hosts.xml based on replica counts
引数: . (トップレベルコンテキスト)
*/}}
{{- define "vespa.hostsXml" -}}
{{- $release := .Release.Name -}}
{{- $svc := include "vespa.internalService" . -}}
{{- $ns := .Release.Namespace -}}
{{- $csReplicas := int .Values.configserver.replicas -}}
{{- $adminReplicas := int .Values.admin.replicas -}}
{{- $feedReplicas := int .Values.feedContainer.replicas -}}
{{- $queryReplicas := int .Values.queryContainer.replicas -}}
{{- $contentReplicas := int .Values.content.replicas -}}
{{- $adminOffset := $csReplicas -}}
{{- $feedOffset := add $csReplicas $adminReplicas -}}
{{- $queryOffset := add $csReplicas $adminReplicas $feedReplicas -}}
{{- $contentOffset := add $csReplicas $adminReplicas $feedReplicas $queryReplicas -}}
<?xml version="1.0" encoding="utf-8" ?>
<hosts>
{{- range $i := until $csReplicas }}
  <host name="{{ $release }}-configserver-{{ $i }}.{{ $svc }}.{{ $ns }}.svc.cluster.local">
    <alias>node{{ $i }}</alias>
  </host>
{{- end }}
{{- range $i := until $adminReplicas }}
  <host name="{{ $release }}-admin-{{ $i }}.{{ $svc }}.{{ $ns }}.svc.cluster.local">
    <alias>node{{ add $adminOffset $i }}</alias>
  </host>
{{- end }}
{{- range $i := until $feedReplicas }}
  <host name="{{ $release }}-feed-container-{{ $i }}.{{ $svc }}.{{ $ns }}.svc.cluster.local">
    <alias>node{{ add $feedOffset $i }}</alias>
  </host>
{{- end }}
{{- range $i := until $queryReplicas }}
  <host name="{{ $release }}-query-container-{{ $i }}.{{ $svc }}.{{ $ns }}.svc.cluster.local">
    <alias>node{{ add $queryOffset $i }}</alias>
  </host>
{{- end }}
{{- range $i := until $contentReplicas }}
  <host name="{{ $release }}-content-{{ $i }}.{{ $svc }}.{{ $ns }}.svc.cluster.local">
    <alias>node{{ add $contentOffset $i }}</alias>
  </host>
{{- end }}
</hosts>
{{- end }}

{{/*
レプリカ数に基づいて services.xml を動的生成する
Dynamically generate services.xml based on replica counts
引数: . (トップレベルコンテキスト)
*/}}
{{- define "vespa.servicesXml" -}}
{{- $csReplicas := int .Values.configserver.replicas -}}
{{- $adminReplicas := int .Values.admin.replicas -}}
{{- $feedReplicas := int .Values.feedContainer.replicas -}}
{{- $queryReplicas := int .Values.queryContainer.replicas -}}
{{- $contentReplicas := int .Values.content.replicas -}}
{{- $adminOffset := $csReplicas -}}
{{- $feedOffset := add $csReplicas $adminReplicas -}}
{{- $queryOffset := add $csReplicas $adminReplicas $feedReplicas -}}
{{- $contentOffset := add $csReplicas $adminReplicas $feedReplicas $queryReplicas -}}
{{- $feedJvm := .Values.feedContainer.jvmArgs -}}
{{- $queryJvm := .Values.queryContainer.jvmArgs -}}
{{- $ccJvm := .Values.configserver.clusterControllerJvmArgs -}}
<?xml version="1.0" encoding="utf-8" ?>
<services version="1.0">

  <admin version="2.0">
    <configservers>
{{- range $i := until $csReplicas }}
      <configserver hostalias="node{{ $i }}" />
{{- end }}
    </configservers>
    <cluster-controllers>
{{- range $i := until $csReplicas }}
      <cluster-controller hostalias="node{{ $i }}" jvm-options="{{ $ccJvm }}" />
{{- end }}
    </cluster-controllers>
    <slobroks>
{{- range $i := until $csReplicas }}
      <slobrok hostalias="node{{ $i }}" />
{{- end }}
    </slobroks>
    <adminserver hostalias="node{{ $adminOffset }}" />
  </admin>

  <container id="feed" version="1.0">
    <document-api />
    <document-processing />
    <nodes>
      <jvm options="{{ $feedJvm }}" />
{{- range $i := until $feedReplicas }}
      <node hostalias="node{{ add $feedOffset $i }}" />
{{- end }}
    </nodes>
  </container>

  <container id="query" version="1.0">
    <search />
    <nodes>
      <jvm options="{{ $queryJvm }}" />
{{- range $i := until $queryReplicas }}
      <node hostalias="node{{ add $queryOffset $i }}" />
{{- end }}
    </nodes>
  </container>

  <content id="music" version="1.0">
    <min-redundancy>{{ $contentReplicas }}</min-redundancy>
    <documents>
      <document type="music" mode="index" />
      <document-processing cluster="feed" />
    </documents>
    <nodes>
{{- range $i := until $contentReplicas }}
      <node hostalias="node{{ add $contentOffset $i }}" distribution-key="{{ $i }}" />
{{- end }}
    </nodes>
  </content>

</services>
{{- end }}
