{{ define "zudello.createRedisUser" -}}
{{/*
If the secret does not exist, create a new Redis user and password in the secret
and associated ACLs in the Redis server group

Full config for example:

{{ template "zudello.createRedisUser" dict 
    "namespace" .Values.namespace 
    "secretName" "redis" 
    "redisUsername" "middleware_server" 
    "readWritePrefixes" (list "td" "gs")
    "readOnlyPrefixes" (list "auth")
    "redisURLKey" "REDIS_URL"
    "redisReadOnlyURLKey" "REDIS_URL_READ_ONLY"
    "redisUsernameKey" "REDIS_USERNAME" 
    "redisPasswordKey" "REDIS_PASSWORD"
    "redisHostnameKey" "REDIS_HOSTNAME"
    "redisPortKey" "REDIS_PORT"
    "redisReadOnlyHostnameKey" "REDIS_HOSTNAME_READ_ONLY"
    "redisReadOnlyPortKey" "REDIS_PORT_READ_ONLY"
}} 

Note, the optional values below do not need to be included in the above

namespace: The namespace where the secret will be created
secretName: Name of the secret to check/create in the namespace
redisUsername: The username to create in the Redis server, must be unique across the cluster, typically will be the same as the repo name
readWritePrefixes: List of prefixes to allow read-write access to, this must *not* include the trailing ":"
readOnlyPrefixes: List of prefixes to allow read-only access to, this must *not* include the trailing ":"
additionalACLs: List of additional ACLs to apply to the Redis user, see below for more details/examples
redisURLKey: The key in the secret to store the Redis URL, default REDIS_URL (this is built up from the username, password, hostname and port etc)
redisReadOnlyURLKey: The key in the secret to store the Redis URL for read-only Redis instances
redisUsernameKey: The key in the secret to store the Redis username, default REDIS_USERNAME
redisPasswordKey: The key in the secret to store the Redis password, default REDIS_PASSWORD
redisHostnameKey: The key in the secret to store the Redis hostname, default REDIS_HOSTNAME
redisPortKey: The key in the secret to store the Redis port, default REDIS_PORT
redisReadOnlyHostnameKey: The key in the secret to store the Redis hostname for read-only Redis instances - these should be separate replicas
redisReadOnlyPortKey: The key in the secret to store the Redis port for read-only Redis instances
redisReset: If the string "yes", will reset the password and recreate the user, default false, used if there was an invalid config/password, note this does _not_ change an existing secret, if it needs to be updated, delete the secret before re-deploying

More typical usage (Note the use of noMigrate to wrap it speed up normal development):

{{- if not .Values.noMigrate }}
{{ template "zudello.createRedisUser" dict 
    "namespace" .Values.namespace
    "redisUsername" .Values.repo
    "readWritePrefixes" (list "td" "auth")
}}
{{- end }}

Then mount the secret in the pod, eg:

          envFrom:
            - secretRef:
                name: redis

additionalACLs: List of additional ACLs to apply to the Redis user, these are applied after the read-write and read-only prefixes, so can be used to further restrict or grant access, for example:

    "additionalACLs": (list "+EVAL" "+EVALSHA")


*/}}

{{- $redisReset := (eq .redisReset "yes") -}}
{{- $secretName := (default "redis" .secretName) -}}
{{- $namespace := (required "namespace Required!" .namespace) -}}
{{- $redisURLKey := (default "REDIS_URL" .redisURLKey) }}
{{- $redisReadOnlyURLKey := (default "REDIS_URL_READ_ONLY" .redisReadOnlyURLKey) }}
{{- $redisUsernameKey := (default "REDIS_USERNAME" .redisUsernameKey) }}
{{- $redisPasswordKey := (default "REDIS_PASSWORD" .redisPasswordKey) }}
{{- $redisHostnameKey := (default "REDIS_HOSTNAME" .redisHostnameKey) }}
{{- $redisPortKey := (default "REDIS_PORT" .redisPortKey) }}
{{- $redisReadOnlyHostnameKey := (default "REDIS_HOSTNAME_READ_ONLY" .redisReadOnlyHostnameKey) }}
{{- $redisReadOnlyPortKey := (default "REDIS_PORT_READ_ONLY" .redisReadOnlyPortKey) }}

{{- $currentRedisPasswordSecret := (lookup "v1" "Secret" .namespace $secretName) }}
{{- $currentRedisPassword := (get ($currentRedisPasswordSecret.data) $redisPasswordKey) | b64dec -}}
{{- $redisPassword := (default  (randAlphaNum 100) $currentRedisPassword) -}}

{{- $redisAdminSecret := (lookup "v1" "Secret" "redis" "redis-admin") -}}
{{- if $redisAdminSecret }}

{{- $redisUsername := (required "redisUsername Required!" .redisUsername ) }}
{{- $readWritePrefixes := (default (list) .readWritePrefixes ) }}
{{- $readOnlyPrefixes := (default (list) .readOnlyPrefixes ) }}


{{- $redisHostname := "redis-master.redis.svc.cluster.local" -}}
{{- $redisPort := "6379" }}
{{- $redisReadOnlyHostname := "redis-replicas.redis.svc.cluster.local" -}}
{{- $redisReadOnlyPort := "6379" }}
{{- $additionalACLs := (default (list ) .additionalACLs) -}}


{{/* Validate the prefixes */}}
{{- template "zudello.validatePrefixes" $readWritePrefixes  -}}
{{- template "zudello.validatePrefixes" $readOnlyPrefixes  -}}

{{- $redisURL := printf "redis://%s:%s@%s:%s" $redisUsername $redisPassword $redisHostname $redisPort -}}
{{- $redisReadOnlyURL := printf "redis://%s:%s@%s:%s" $redisUsername $redisPassword $redisReadOnlyHostname $redisReadOnlyPort -}}

{{- if not $currentRedisPassword }}
---
apiVersion: v1
data:
  {{ $redisUsernameKey }}: {{ $redisUsername | b64enc }}
  {{ $redisPasswordKey }}: {{ $redisPassword | b64enc }}
  {{ $redisURLKey }}: {{ $redisURL | b64enc }}
  {{ $redisReadOnlyURLKey }}: {{ $redisReadOnlyURL | b64enc }}
  {{ $redisHostnameKey }}: {{ $redisHostname | b64enc }}
  {{ $redisPortKey }}: {{ $redisPort | b64enc }}
  {{ $redisReadOnlyHostnameKey }}: {{ $redisReadOnlyHostname | b64enc }}
  {{ $redisReadOnlyPortKey }}: {{ $redisPort | b64enc }}
kind: Secret
metadata:
  name: {{ $secretName }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/resource-policy": keep
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-11"
type: Opaque

{{ end }} {{/* if not $currentRedisPassword */}}

{{/* Create the Redis user and ACLs */}}
---

apiVersion: batch/v1
kind: Job
metadata:
  name: {{ kebabcase $redisUsername }}-redis-user
  namespace: "redis"
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-10"
spec:
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: {{ kebabcase $redisUsername }}-redis-user
    spec:
      restartPolicy: OnFailure
      containers:
        - name: {{ kebabcase $redisUsername }}-redis-user
          image: redis
          command: ["bash"]
          args: ["-c", "cat > /tmp/script.sh << EOF\n$SCRIPT\nEOF\nbash /tmp/script.sh"]
          env:
            - name: REDIS_USERNAME
              value: {{ $redisUsername | quote }}
            - name: REDIS_PASSWORD
              value: {{ $redisPassword | quote }}
            - name: REDIS_READ_WRITE_PREFIXES
              value: "{{ range $prefix := $readWritePrefixes }}~{{ $prefix }}:* {{ end }}"
            - name: REDIS_READ_ONLY_PREFIXES
              value: "{{ range $prefix := $readOnlyPrefixes }}%R~{{ $prefix }}:* {{ end }}"
            - name: REDIS_MASTER_HOSTNAME
              value: {{ $redisHostname | quote }}
            - name: REDIS_ADDITIONAL_ACL
              value: '{{ range $acl := $additionalACLs }}{{ $acl }} {{ end }}'
{{ if $redisReset}}
            - name: REDIS_DO_RESET
              value: "True"
{{ end }}
            - name: REDIS_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-admin
                  key: redis-password
            - name: SCRIPT
              value: |
                set -e

                echo Applying:
                echo "    REDIS_USERNAME: ${REDIS_USERNAME}"
                echo "    REDIS_READ_WRITE_PREFIXES: ${REDIS_READ_WRITE_PREFIXES}"
                echo "    REDIS_READ_ONLY_PREFIXES: ${REDIS_READ_ONLY_PREFIXES}"
                echo "    REDIS_ADDITIONAL_ACL: ${REDIS_ADDITIONAL_ACL}"
                echo Updating: Master
                if [ -n "$REDIS_DO_RESET" ]; then
                  redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h $REDIS_MASTER_HOSTNAME ACL DELUSER ${REDIS_USERNAME}
                fi
                redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h $REDIS_MASTER_HOSTNAME ACL SETUSER ${REDIS_USERNAME} on '>'$REDIS_PASSWORD '+@read' '+@write' ${REDIS_READ_WRITE_PREFIXES} ${REDIS_READ_ONLY_PREFIXES} '+ACL|WHOAMI' '+PING' ${REDIS_ADDITIONAL_ACL};
                redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h $REDIS_MASTER_HOSTNAME ACL SAVE;

                redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h $REDIS_MASTER_HOSTNAME INFO replication | grep ^slave | awk -F '[=,:]' '{print $3 ":" $5}' | while IFS=: read -r host port; do
                    echo Updating: $host
                    if [ -n "$REDIS_DO_RESET" ]; then
                      redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h $REDIS_MASTER_HOSTNAME ACL DELUSER ${REDIS_USERNAME}
                    fi
                    redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h "$host" -p "$port" ACL SETUSER ${REDIS_USERNAME} on '>'$REDIS_PASSWORD '+@read' '+@write' ${REDIS_READ_WRITE_PREFIXES} ${REDIS_READ_ONLY_PREFIXES} '+ACL|WHOAMI' '+PING' ${REDIS_ADDITIONAL_ACL};
                    redis-cli -e --pass $REDIS_ADMIN_PASSWORD --no-auth-warning -h "$host" -p "$port" ACL SAVE;
                done

---


{{ end }} {{/* if $redisAdminSecret */}}

{{ end }} {{/* zudello.createRedisUser */}}

{{ define "zudello.validatePrefixes" }}
{{- range . -}}
  {{- if or (lt (len .) 2) (hasSuffix ":" .) (contains "*" .) (contains "?" .) }}
    {{ fail (printf "Invalid prefix (must be at least 2 characters, not contain wildcards, and not have a trailing :): %s" .) }}
  {{- end -}}
{{- end -}}
{{- end -}}
