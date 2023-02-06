{{- define "zudello.syncConfigMap" -}}
{{/* 
Keeps in sync a configmap from the default namespace to the target namespace

Sample Usage:
{{ template "zudello.syncConfigMap" dict 
    "srcConfigMap" "cluster-web"
    "destNamespace" .Values.namespace
}}

Full Usage:
{{ template "zudello.syncConfigMap" dict 
    "srcConfigMap" "my-configmap"
    "srcNamespace" "some-namespace"
    "destNamespace" "my-namespace"
}}

srcConfigMap: the name of the configmap to sync
srcNamespace: namespace to sync from, defaults to default
destNamespace: the target namespace to sync to

This will run on every deployment to ensure the configmap is up to date
*/ -}}
{{ $srcNamespace := (default "default" .srcNamespace) }}
{{- $srcConfigMapObj := (lookup "v1" "ConfigMap" $srcNamespace .srcConfigMap ) -}}
{{ $destConfigMap := .srcConfigMap }}
{{- if $srcConfigMapObj -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $destConfigMap | quote }}
  namespace: {{ .destNamespace | quote }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-20"
data:
{{- range $key, $value := $srcConfigMapObj.data }}
  {{ $key | quote }}: {{ $value | quote }}
{{- end }}{{/* range */}}
{{- end }}{{/* if $srcConfigMap */}}
{{- end }}{{/* "zudello.syncConfigMap" */}}