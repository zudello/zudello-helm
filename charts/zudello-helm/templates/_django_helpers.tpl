{{- define "zudello.django-liveness-rediness" -}}
{{/*

Typical set of liveness and rediness probes for django applications.

Automatically disables the checks if developmentMode is true

Normal usage:

{{ include "zudello.django-liveness-rediness" (list .) }}

If the health check URL is not at /<repo>/v1/alive/, use:

{{ include "zudello.django-liveness-rediness" (list . "/team-data/v0/alive") }}

If the path to use for health checks is not specified, it defaults to /<repo>/v1/alive/
Note, "?<service>" will _always_ be appended

A port can also be set as the third option, if not specified, it defaults to 8000

<repo> is extracted from .Values.repo

*/}}

{{/* Dumb hack so index for missing values will work */}}
{{- $forcedList := concat . (list nil nil) -}}
{{- $values := (index $forcedList 0).Values -}}
{{- $configPath := index $forcedList 1 -}}
{{- $port := default "8000" (index $forcedList 2) -}}
{{- $healthPath:= default (printf "/%s/v1/alive/" $values.repo) $configPath -}}
{{ if not $values.developmentMode }}
          livenessProbe:
            httpGet:
              path: {{ $healthPath }}?liveness
              port: {{ $port }}
            initialDelaySeconds: 10
            timeoutSeconds: 1
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: {{ $healthPath }}?readiness
              port: {{ $port }}
            initialDelaySeconds: 5
            timeoutSeconds: 1
            periodSeconds: 3
{{ end -}} {{/* if $values.developmentMode */}}
{{- end -}} {{/* zudello.django-liveness-rediness */}}





{{- define "zudello.django-lifecycle" -}}
{{/*

Typical lifecycle for a django service

Automatically disables the checks if developmentMode is true

Normal usage:

{{ include "zudello.django-lifecycle" (list .) }}

*/}}
{{- $values := (index . 0).Values -}}
{{ if not $values.developmentMode }}
          lifecycle:
            preStop:
              exec:
                # Take at least 20 seconds to shutdown as the AWS ELB can take that long to stop sending requests to the pod
                command: ["bash", "-c", "echo `date -Is` 'Terminating pod in 21s (lifecycle:preStop)' >> /proc/1/fd/1; sleep 21"]
{{ end -}} {{/* if $values.developmentMode */}}
{{ end -}} {{/* zudello.django-lifecycle */}}


{{- define "zudello.django-env" -}}
{{/*

Typical env for a django deployment

This is just the `REPO` env at the moment

Normal usage:

          env:
{{ include "zudello.django-env" (list .) }}
            - name: "AWS_STORAGE_BUCKET_NAME"
            ...

*/}}
{{- $values := (index . 0).Values }}
            - name: "REPO"
              value: {{ $values.repo | required "repo value required" | quote }}
            - name: "SENTRY_DSN"
              value: {{ .Values.sentryDsn | required "sentryDsn value required, see: https://github.com/zudello/devops/blob/develop/docs/SentrySetup.md" | quote }}
{{ end -}} {{/* zudello.django-env */}}


{{- define "zudello.django-volume-mounts" -}}
{{/*

Typical volumeMounts for a django deployment

This is the database certificate bundle

Normal usage is as follows, if templated volumes are used throughout the helm chart:

{{ define "local.volumemounts" }}
          volumeMounts:
{{ include "zudello.django-volume-mounts" (list .) }}
{{ end }}

*/}}
{{- $values := (index . 0).Values }}
            - name: database-certificate
              mountPath: /database-certificate/
{{ end -}} {{/* zudello.django-lifecycle */}}


{{- define "zudello.django-volumes" -}}
{{/*

Typical volumes for a django deployment

This mounting the database certificate bundle

Normal usage is as follows, if templated volumes are used throughout the helm chart:

{{ define "local.volumes" }}
          volumes:
{{ include "zudello.django-volumes" (list .) }}
{{ end }}

*/}}
{{- $values := (index . 0).Values }}
        - name: database-certificate
          configMap:
            name: database-certificate
{{ end -}} {{/* zudello.django-volumes */}}





{{- define "zudello.django-hpa" -}}
{{/*

Typical HorizontalPodAutoscaler and Service for a django web service

{{ include "zudello.django-hpa" (list (dict ) .) }}

A more advanced example using configuration overrides:

{{ include "zudello.django-hpa" (list (dict "name" "audit-web" "averageUtilization" 90) .) }}

Configuration options:
  name: Name of the deployment, if not set <repo>-web is used
  averageUtilization: CPU usage target, defaults to 70
  port: Port to use for the HPA Service, defaults to 8000
  servicePort: Port to serve the service on, defaults to 80

Note: minimumWebReplicas and maximumWebReplicas _must_ be set in the .Values config

*/}}

{{- $overrides:= (index . 0) -}}
{{- $values := (index . 1).Values -}}
{{- $name := default (printf "%s-web" $values.repo) $overrides.name -}}
{{- $averageUtilization := default 70 $overrides.averageUtilization -}}
{{- $port := default "8000" $overrides.port -}}
{{- $servicePort := int (default 80 $overrides.servicePort) -}}
{{ if not $values.developmentMode }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $name | quote }}
  namespace: {{ $values.namespace | quote }}
spec:
  minReplicas: {{ required "minimumWebReplicas must be set" $values.minimumWebReplicas }}
  maxReplicas: {{ required "maximumWebReplicas must be set" $values.maximumWebReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ $averageUtilization }}
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $name | quote }}
  # Limit scale down to 1 per 2 minutes, and use last 5 minutes of data for stabilisation
  # information to prevent flapping
  behavior:                  
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Pods
        value: 1
        periodSeconds: 120
      selectPolicy: Min
{{ end }} {{/* if $values.developmentMode */}}

---
apiVersion: v1
kind: Service
metadata:
  name: {{ $name | quote }}
  namespace: {{ $values.namespace | quote }}
  labels:
    app: {{ $name | quote }}
spec:
  selector:
    app: {{ $name | quote }}
  ports:
    - protocol: TCP
      port: {{ $servicePort }}
      targetPort: {{ $port }}
{{- end -}} {{/* zudello.django-hpa */}}