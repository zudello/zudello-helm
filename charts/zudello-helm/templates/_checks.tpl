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
{{- /* Always copy over the cluster-details configmap ====== */}}
{{ template "zudello.syncConfigMap" (dict
    "srcConfigMap" "cluster-details"
    "destNamespace" .Values.namespace
) }}

{{- end -}}