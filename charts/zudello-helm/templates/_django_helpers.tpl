{{- define "zudello.django-liveness-readiness" -}}
{{/*

Typical set of liveness and readiness probes for django applications.

Automatically disables the checks if developmentMode is true

Normal usage:

{{ include "zudello.django-liveness-readiness" (list .) }}

If the health check URL is not at /<repo>/v1/alive/, use:

{{ include "zudello.django-liveness-readiness" (list . "/team-data/v0/alive") }}

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
            timeoutSeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: {{ $healthPath }}?readiness
              port: {{ $port }}
            initialDelaySeconds: 5
            timeoutSeconds: 5
            periodSeconds: 3
{{ end -}} {{/* if $values.developmentMode */}}
{{- end -}} {{/* zudello.django-liveness-readiness */}}

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

Normal usage:

          env:
{{ include "zudello.django-env" (list .) }}
            - name: "AWS_STORAGE_BUCKET_NAME"
            ...

*/}}
{{- $values := (index . 0).Values }}
            - name: "REPO"
              value: {{ $values.repo | required "repo value required" | quote }}
            - name: "AWS_STORAGE_BUCKET_NAME"
              value: {{ printf "zudello-%s-shared" $values.clusterName | quote }} ## S3 Bucket Name
            - name: "SENTRY_DSN"
{{/* The value of sentryDsn may be "None" to disable sentry alerting */}}
{{- if eq (upper $values.sentryDsn) "NONE"}}
              value: ""
{{ else }}
              value: {{ $values.sentryDsn | required "sentryDsn value required, see: https://github.com/zudello/devops/blob/develop/docs/SentrySetup.md" | quote }}
{{ end -}}
{{ end -}} {{/* zudello.django-env */}}


{{- define "zudello.django-env-from" -}}
{{/*

Typical env from section for a django deployment

Normal usage:

          envFrom:
{{ include "zudello.django-env-from" (list .) }}

            - secretRef:
                name: database
            ...

*/}}
{{- $values := (index . 0).Values }}
{{/* Provides: GLOBAL_CLUSTER_HOSTNAME, CLUSTER_BASE_DOMAIN_NAME, CLUSTER_NAME, CLUSTER_TIMEZONE, AWS_DEFAULT_REGION, AWS_ACCOUNT_ID, ALLOWED_CORS_HEADERS, CORS_ALLOWED_ORIGINS, CORS_ALLOWED_ORIGIN_REGEXES, CSRF_TRUSTED_ORIGINS */}}
            - configMapRef:
                name: cluster-details
                optional: false
{{/* Provides: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY */}}
            - secretRef:
                name: aws
{{/*        Provides ZUDELLO_SERVICE_TOKEN, ZUDELLO_SERVICE_TOKEN_DATE */}}
            - secretRef:
                name: zudello-service-token
                optional: true
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