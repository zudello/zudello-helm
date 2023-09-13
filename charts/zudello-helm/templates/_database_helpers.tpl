{{ define "zudello.createDatabaseAndUser" -}}
{{/*
If the secret does not exist, create a new DB, and associated username and password.
This is also used to create additional users in the DB

Full config for example:

{{ template "zudello.createDatabaseAndUser" dict 
    "namespace" .Values.namespace 
    "secretName" "database" 
    "dbName" "middleware_server" 
    "dbUsername" "middleware_server_user" 
    "dbReadWriteUser" true
    "dbNameKey" "DATABASE_NAME" 
    "dbUsernameKey" "DATABASE_USERNAME" 
    "dbPasswordKey" "DATABASE_PASSWORD"
    "dbHostnameKey" "DATABASE_HOSTNAME"
    "dbHostnameReadOnlyKey" "DATABASE_HOSTNAME_READ_ONLY"
    "dbPortKey" "DATABASE_PORT"
    "dbEngineKey" "DATABASE_ENGINE"
}} 

Note, the optional values below do not need to be included in the above

namespace: The namespace where the secret will be created
secretName: Name of the secret to check/create in the namespace
dbName: Name of the database to create
dbUsername: The username in the database to create, defaults to the dbName
dbReadWriteUser: If true (YAML bool), create a read-write user, otherwise defaults to read-only
dbNameKey: The key in the secret to store the database name, default DATABASE_NAME
dbUsernameKey: The key in the secret to store the database username, default DATABASE_USERNAME
dbPasswordKey: The key in the secret to store the database password, default DATABASE_PASSWORD
dbHostnameKey: The key in the secret to store the database hostname, default DATABASE_HOSTNAME
dbHostnameReadOnlyKey: The key in the secret to store the database hostname for read-only users and access, default DATABASE_HOSTNAME_READ_ONLY
dbPortKey: The key in the secret to store the database port, default DATABASE_PORT
dbEngineKey: The key in the secret to store the database engine (the value could be "mysql" or "postgresql"), default DATABASE_ENGINE
dbEngineFormat: The format of the database engine names, currently "full" (default), "grafana"
    full: mysql or postgresql
    grafana: mysql or postgres
dbExtraCommands: Extra SQL commands to run after creating the database and user, only for Postgres. NOTE: This is passed as a shell command
dbReset: If the string "yes", then the database will be dropped and recreated, and the user will be dropped and recreated, only for Postgres

This _always_ uses the default database host at mysql-service.default.svc.cluster.local,
and requires the admin password to be in the database-admin secret in the default namespace


The database-admin secret should have the following keys:
    USERNAME: 
    PASSWORD: 
    DATABASE_ENGINE:  (defaults to mysql)
    DATABASE_HOST_READ_WRITE:  (defaults to mysql-service.default.svc.cluster.local)
    DATABASE_HOST_READ_ONLY: 
    DATABASE_PORT:  (defaults to 3306)
*/}}

{{ $dbReset := (eq .dbReset "yes" )}}
{{- $dbpassword := (lookup "v1" "Secret" .namespace .secretName) }}
{{- if (or (not $dbpassword) $dbReset ) }}
{{- $newdbpassword := (randAlphaNum 30) -}}
{{ $dbAdminSecret := (lookup "v1" "Secret" "default" "database-admin") }}
{{- if $dbAdminSecret }}{{/* Second check is here to allow for missing admin secrets, and allow --dry-run to work */}}

{{ $dbEngine := (default ("mysql" | b64enc) $dbAdminSecret.data.DATABASE_ENGINE) | b64dec }}
{{ $dbUsername := (default .dbName .dbUsername ) }}
{{ $dbNameKey := (default "DATABASE_NAME" .dbNameKey) }}
{{ $dbUsernameKey := (default "DATABASE_USERNAME" .dbUsernameKey) }}
{{ $dbPasswordKey := (default "DATABASE_PASSWORD" .dbPasswordKey) }}
{{ $dbHostnameKey := (default "DATABASE_HOSTNAME" .dbHostnameKey) }}
{{ $dbHostnameReadOnlyKey := (default "DATABASE_HOSTNAME_READ_ONLY" .dbHostnameReadOnlyKey) }}
{{ $dbPortKey := (default "DATABASE_PORT" .dbPortKey) }}
{{ $dbEngineKey := (default "DATABASE_ENGINE" .dbEngineKey) }}
{{ $dbEngineFormat := (default "full" .dbEngineFormat) }}
{{ $dbReadWriteUser := (eq .dbReadWriteUser true )}}
{{ $dbExtraCommands := (default "" .dbExtraCommands) }}

{{ $dbHostName := (default "mysql-service.default.svc.cluster.local" (default "" $dbAdminSecret.data.DATABASE_HOST_READ_WRITE | b64dec)) }}
{{ $dbHostNameReadOnly := (default "mysql-service.default.svc.cluster.local" (default "" $dbAdminSecret.data.DATABASE_HOST_READ_ONLY | b64dec)) }}
{{ $dbPort := (default "3306" (default "" $dbAdminSecret.data.DATABASE_PORT | b64dec)) }}

{{/* Validate the dbEngineFormat */}}
{{ if and (ne $dbEngineFormat "full") (ne $dbEngineFormat "grafana")}}
{{fail "invalid dbEngineFormat set"}}
{{ end }}

---
apiVersion: v1
data:
  {{ $dbNameKey }}: {{ .dbName | b64enc }}
  {{ $dbUsernameKey }}: {{ $dbUsername | b64enc }}
  {{ $dbPasswordKey }}: {{ $newdbpassword | b64enc }}
  {{ $dbHostnameKey }}: {{ $dbHostName | b64enc }}
  {{ $dbHostnameReadOnlyKey }}: {{ $dbHostNameReadOnly | b64enc }}
  {{ $dbPortKey }}: {{ $dbPort | b64enc }}
  {{ $dbEngineKey }}: {{ (ternary (ternary "postgres" $dbEngine (eq $dbEngineFormat "grafana")) $dbEngine (eq $dbEngine "postgresql")) | b64enc }}
kind: Secret
metadata:
  name: {{ .secretName }}
  namespace: {{ .namespace }}
  annotations:
    "helm.sh/resource-policy": keep
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-11"
type: Opaque

---

{{- if eq $dbEngine "mysql" -}}

# Create the database for mysql
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ kebabcase .dbName }}-db-create
  namespace: default
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-10"
spec:
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: {{ kebabcase .dbName }}-db-create
    spec:
      restartPolicy: OnFailure
      containers:
        - name: {{ kebabcase .dbName }}-db-create
          image: mariadb
          command: ["bash"]
          args: ["-c", "cat > /tmp/script.sh << EOF\n$SCRIPT\nEOF\nbash /tmp/script.sh"]

          env:
            - name: ADMIN_PASSWORD
              value: {{ $dbAdminSecret.data.PASSWORD | b64dec | quote }}
            - name: ADMIN_USERNAME
              value: {{ $dbAdminSecret.data.USERNAME | b64dec | quote }}
            - name: DATABASE
              value: {{ .dbName | quote }}
            - name: USERNAME
              value: {{ $dbUsername | quote }}
            - name: PASSWORD
              value: {{ $newdbpassword | quote }}
            - name: DATABASE_HOSTNAME
              value: {{ $dbHostName | quote }}
            - name: DATABASE_PORT
              value: {{ $dbPort | quote }}
            {{- if $dbReadWriteUser }}
            - name: WRITE_PERMISSIONS
              value: "true"
            {{- end }}
            - name: SCRIPT
              value: |
                mysqlexec() {
                  mysql --verbose --host $DATABASE_HOSTNAME --port $DATABASE_PORT  --user=$ADMIN_USERNAME --password=$ADMIN_PASSWORD -e "$1"
                }

                mysqlexec "CREATE DATABASE IF NOT EXISTS $DATABASE;"
                mysqlexec "CREATE USER '$USERNAME' IDENTIFIED BY '$PASSWORD';"
                if [ "${WRITE_PERMISSIONS}" = "true" ]; then
                  mysqlexec "GRANT ALL PRIVILEGES ON $DATABASE.* TO '$USERNAME'; "
                else
                  mysqlexec "GRANT SELECT, SHOW VIEW ON $DATABASE.* TO '$USERNAME'; "
                fi

{{- else if eq $dbEngine "postgresql" -}}


---

# Create the database and users for postgresql
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ kebabcase .dbName }}-db-{{ kebabcase .dbUsername }}-create
  namespace: "default"
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-10"
spec:
  activeDeadlineSeconds: 600
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: {{ kebabcase .dbName }}-db-create
    spec:
      restartPolicy: OnFailure
      containers:
        - name: {{ kebabcase .dbName }}-db-create
          image: postgres
          command: ["bash"]
          args: ["-c", "cat > /tmp/script.sh << EOF\n$SCRIPT\nEOF\nbash /tmp/script.sh"]
          env:
            - name: NEW_DATABASE
              value: {{ .dbName | quote }}
            - name: NEW_USERNAME
              value: {{ $dbUsername | quote }}
            - name: NEW_PASSWORD
              value: {{ $newdbpassword }}
            - name: EXTRA_COMMANDS
              value: {{ $dbExtraCommands | quote }}
            {{- if $dbReadWriteUser }}
            - name: WRITE_PERMISSIONS
              value: "true"
            {{- end }}
            {{- if $dbReset }}
            - name: FULL_RESET
              value: "true"
            {{- end }}
            - name: SCRIPT
              value: |
                pgexec() {
                  local cmd=$1
                  psql --no-psqlrc --no-align --tuples-only \
                    --echo-queries --command="$cmd" \
                    "postgresql://${USERNAME}:${PASSWORD}@${DATABASE_HOST_READ_WRITE}:${DATABASE_PORT}/${dbname}?sslmode=verify-full&sslrootcert=/database-certificate/dbcert.pem"
                }

                # If FULL_RESET is true, drop the database and user
                if [ "${FULL_RESET}" = "true" ]; then
                  pgexec "DROP DATABASE IF EXISTS ${NEW_DATABASE};"
                  pgexec "DROP USER IF EXISTS \"${NEW_USERNAME}\";"
                fi

                # Create the database
                export dbname=template1
                pgexec "CREATE DATABASE ${NEW_DATABASE};"

                export dbname=${NEW_DATABASE}
                pgexec "REVOKE ALL PRIVILEGES ON DATABASE ${NEW_DATABASE} FROM public;"
                pgexec "REVOKE ALL ON schema public FROM public;"
                pgexec "REVOKE CREATE ON SCHEMA public FROM public;"

                pgexec "CREATE USER \"${NEW_USERNAME}\" LOGIN ENCRYPTED PASSWORD '${NEW_PASSWORD}';"
                pgexec "GRANT CONNECT ON DATABASE ${NEW_DATABASE} TO \"${NEW_USERNAME}\";"
                pgexec "GRANT USAGE ON SCHEMA public TO public ;"
                # Roles: https://www.postgresql.org/docs/current/predefined-roles.html#PREDEFINED-ROLES-TABLE
                pgexec "GRANT pg_read_all_data TO \"${NEW_USERNAME}\";"

                # If user has WRITE_PERMISSIONS, grant write permissions
                if [ "${WRITE_PERMISSIONS}" = "true" ]; then
                  pgexec "GRANT pg_write_all_data TO \"${NEW_USERNAME}\";"
                  pgexec "GRANT CREATE ON SCHEMA public TO \"${NEW_USERNAME}\";"
                  pgexec "GRANT CREATE ON DATABASE ${NEW_DATABASE} TO \"${NEW_USERNAME}\";"
                  pgexec "GRANT TEMPORARY ON DATABASE ${NEW_DATABASE} TO \"${NEW_USERNAME}\";"
                fi

                # Run any extra commands
                if [ -n "${EXTRA_COMMANDS}" ]; then
                  pgexec "${EXTRA_COMMANDS}"
                fi

          envFrom:
            - secretRef:
                name: database-admin
          volumeMounts:
            - name: database-certificate
              mountPath: /database-certificate/
      volumes:
        - name: database-certificate
          configMap:
            name: database-certificate

{{ end }}{{/* $dbEngine "postgresql" */}}

{{ end }}{{/* if $dbAdminSecret */}}
{{ end }}{{/* if not $existinggrafanapassword */}}

{{ end }}{{/* zudello.createDatabaseAndUser */}}

