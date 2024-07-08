{{- define "zudello.standardChecks" -}}
{{/*

This MUST be included in all charts, using the following syntax:
{{- include "zudello.standardChecks" . -}}

*/}}
{{- /* Standard checks ====== */}}
{{- if ne .Release.Name .Values.repo -}}
{{ required (print "Release Name MUST be " .Values.repo) .null }}
{{- end -}}
{{- if ne .Release.Namespace .Values.namespace -}}
{{ required (print "Namespace (-n) MUST be " .Values.namespace) .null }}
{{- end -}}
{{- if lookup "v1" "svc" "" "" }}
  {{- $remoteClusterName := (lookup "v1" "ConfigMap" "default" "cluster-data-annotations").data.clustername -}}
  {{/* Perform check only if against a real cluster, ie, not a Template */}}
  {{- if ne .Values.clusterName $remoteClusterName -}}
    {{ fail (print "Cluster Name (" .Values.clusterName ") MUST match target cluster name (" (lookup "v1" "ConfigMap" "default" "cluster-data-annotations").data.clustername ")") }}
  {{- end -}}
  {{- if hasSuffix "-global" $remoteClusterName -}}
    {{/* Global cluster, check this repo is global */}}
    {{- if not .Values.globalCluster -}}
      {{ fail "This cluster is global, so the repo must have `globalCluster: True` in values.yaml or _global.yaml" }}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- /* Standard checks end ====== */}}
{{- /* Always copy over the cluster-details and database-certificate configmap ====== */}}
{{ template "zudello.syncConfigMap" (dict
    "srcConfigMap" "cluster-details"
    "destNamespace" .Values.namespace
) }}

{{ template "zudello.syncConfigMap" (dict 
    "srcConfigMap" "database-certificate"
    "destNamespace" .namespace
) }}

{{- if .Values.zudelloActiveRepoGitBranch }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: "zudello-active-repo-git-{{ .Values.repo }}"
  namespace: default
data:
  branch: {{ .Values.zudelloActiveRepoGitBranch | quote }}
---

{{ end -}}

{{- end -}} {{- /* End of zudello.standardChecks */ -}}

{{/*
Template the verify a base URL, that is, it starts with a protocol, and does
not have a trailing slash
*/}}
{{- define "zudello.validateBaseUrl" -}}
  {{- if not (regexMatch "^(http|https)://[^/]+$" .) -}}
    {{- fail (printf "Base URL %s is invalid. It must start with http:// or https:// and not have a trailing slash" .) -}}
  {{- end -}}
{{- end -}}