{{- define "zudello.getTimeZone" -}}
{{/* 
Returns the configured timezone for the cluster.

For example:
- {{ template "zudello.getTimeZone" }}

*/}}
{{- $response := (lookup "v1" "ConfigMap" "default" "cluster-details") -}}
{{- if not (empty $response) -}}
    {{- $timeZone := $response.data.CLUSTER_TIMEZONE -}}
    {{- if empty $timeZone -}}
        {{- required "timeZone not set in cluster, rerun devops helm upgrade" $timeZone -}}
    {{- end -}}
    {{- $timeZone -}}
{{- else -}}
    {{- "getTimeZone dry-run not valid in production" -}}
{{- end -}}{{/* zudello.getTimezone */}}
{{- end -}}


{{- define "zudello.getPinnedAZ" -}}
{{/* 
Returns the configured pinnedAZ for the cluster.

For example:
- {{ template "zudello.getPinnedAZ" }}

*/}}
{{- $response := (lookup "v1" "ConfigMap" "default" "cluster-data-annotations") -}}
{{- if not (empty $response) -}}
    {{- $pinnedAz := $response.data.awsPinnedAZ -}}
    {{- if empty $pinnedAz -}}
        {{- required "pinnedAz not set in cluster, rerun devops helm upgrade" $pinnedAz -}}
    {{- end -}}
    {{- $pinnedAz -}}
{{- else -}}
    {{- "getPinnedAZ dry-run not valid in production" -}}
{{- end -}}{{/* zudello.getPinnedAZ */}}
{{- end -}}


{{- define "zudello.getAwsLbcVpcId" -}}
{{/* 
Returns the configured (in devops repo) awsLbcVpcId for the cluster.

For example:
vpcId: {{ template "zudello.getAwsLbcVpcId" }}

*/}}
{{- $response := (lookup "v1" "ConfigMap" "default" "cluster-data-annotations") -}}
{{- if not (empty $response) -}}
    {{-  $lbcVpcId := $response.data.awsLbcVpcId -}}
    {{- if empty $lbcVpcId -}}
    {{- required "awsLbcVpcId not set in cluster, rerun devops helm upgrade" $lbcVpcId -}}
    {{- end -}}
    {{- $lbcVpcId -}}
    {{- end -}}{{/* zudello.getAwsLbcVpcId */}}
{{- end -}}

{{- define "zudello.createNamespace" -}}
{{/*
Create the desired namespace, if it does not exist already.

For example
{{- template "zudello.createNamespace" "new-namespace" -}}

*/}}
{{- $response := (lookup "v1" "Namespace" "" . ) -}}
{{- if empty $response }}
---

apiVersion: v1
kind: Namespace
metadata:
  name: {{ . | quote }}
  annotations:
    "helm.sh/resource-policy": keep
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-20"
{{- end -}}
{{- end -}}