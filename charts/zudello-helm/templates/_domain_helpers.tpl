{{- define "zudello.getFullDomain" -}}
{{/* 
Takes a single argument, the domain name.
If the domain name contains a `.` it is assumed to be a FQDN.
If the domain name does not contain a `.` it is assumed to be a zone, and will have
the cluster baseDomainName appended to it.

For example:
host: {{- template "zudello.getFullDomain" "theservice" }}
or (with theServiceName set to "theservice" in values.ymal):
host: {{- template "zudello.getFullDomain" .Values.theServiceName -}}

*/}}
{{- $response := (lookup "v1" "ConfigMap" "default" "cluster-details") -}}
{{- if not (empty $response) -}}
    {{- if . -}}
        {{- if contains "." . -}}
            {{- . -}}
        {{- else -}}
            {{- $baseDomainName := $response.data.CLUSTER_BASE_DOMAIN_NAME -}}
            {{- . }}.{{ $baseDomainName -}}
        {{- end -}}
    {{- end -}}
{{- else -}}
    {{ print . "." "template.localhost" }}
{{- end -}}


{{- end -}}{{/* zudello.getFullDomain */}}
