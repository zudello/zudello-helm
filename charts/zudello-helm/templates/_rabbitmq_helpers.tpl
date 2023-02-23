{{ define "zudello.createQueueAndUser" -}}
{{/*
Create a new RabbitMQ queue (and associated exchange) and user for a consumer.
Producers should _not_ use this template.

Full config for example:

{{ template "zudello.createQueueAndUser" dict 
    "namespace" .Values.namespace 
    "queue" "ingestion" 
    "username" "ingestion"
    "priority" true
    "writeQueues" (list "document-worker" "team-data")
}} 

A secret named _<username>-user-credentials_ (eg: ingestion-user-credentials) will be 
created in the namespace. (Note: This name is used by the messaging-topology-operator)

Note: By default, the user can NOT write to their own queue, add the queue name to
the writeQueues list to allow this.

Note: the optional values below do not need to be included in the above

namespace: The namespace where the secret etc will be created
queue: The name of the queue (and exchange) to create
username: Optional, the username to create, defaults to queue
priority: Optional, if true (YAML bool), create a priority queue as well as the normal queue
    the priority queue will be named _<queue>-priority_
writeQueues: Optional, a list of queues username can also write to

The produced secret will have the following keys (note values are lowercase 
for compatibility with the rabbitmq messaging-topology-operator):
- username
- password
- host
- port
- queue

*/}}
{{ $namespace := required "namespace required" .namespace }}
{{ $queue := required "queue name required" .queue }}
{{ $username := (default .queue .username) }}
{{ $priority := (default false .priority) }}
{{ $writeQueues := (default (list) .writeQueues)}}
{{ $host := "rabbit.rabbitmq.svc.cluster.local" }}
{{ $port := "5672" }}
{{ $secretName := printf "%s-user-credentials" $username }}
{{- $rabbitPassword := (lookup "v1" "Secret" .namespace $secretName ) }}
# Start zudello.createQueueAndUser template
{{ if not $rabbitPassword }}
{{ $newPassword := (randAlphaNum 30) }}

---
apiVersion: v1
kind: Secret
data:
    username: {{ $username | b64enc }}
    password: {{ $newPassword | b64enc }}
    host: {{ $host | b64enc }}
    port: {{ $port | b64enc }}
    queue: {{ $queue | b64enc }}
metadata:
  name: {{ $secretName }}
  namespace: {{ $namespace }}
  annotations:
    "helm.sh/resource-policy": keep
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-11"
type: Opaque

{{ end }}{{/* if not $rabbitPassword */}}

---
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq
  importCredentialsSecret:
    name: {{ $secretName }}

---
{{ $writePermRegex := list -}}
{{- range $writeQueues -}}
    {{- $writePermRegex = printf "(%s)" . | append $writePermRegex -}}
{{- end }}

apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  vhost: "/"
  user: {{ $username }}
  permissions:
    {{ if $writeQueues }}
    write: "^{{ join "|" $writePermRegex }}$"
    {{ else }}
    write: ""
    {{ end }}
    configure: ""
    read: "^({{ $queue }}){{ if $priority }}|({{ $queue }}-priority){{ end }}$"
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: {{ $queue }}
  namespace: {{ $namespace }}
spec:
  name: {{ $queue }}
  type: quorum
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq


---
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata:
  name: {{ $queue }}
  namespace: {{ $namespace }}
spec:
  name: {{ $queue }}
  type: direct
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata:
  name: {{ $queue  }}
  namespace: {{ $namespace }}
spec:
  source: {{ $queue }}
  destination: {{ $queue }}
  destinationType: queue
  routingKey: {{ $queue }}
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ if $priority }}
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: {{ $queue }}-priority
  namespace: {{ $namespace }}
spec:
  name: {{ $queue }}-priority
  type: quorum
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata:
  name: {{ $queue }}-priority
  namespace: {{ $namespace }}
spec:
  source: {{ $queue }}
  destination: {{ $queue }}-priority
  destinationType: queue
  routingKey: {{ $queue }}-priority
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ end }}
{{ end }} {{/* ======================== End zudello.createQueueAndUser ======================== */}}

{{ define "zudello.createProducerUser" -}}
{{/*
Create a new RabbitMQ user for a producer, with write permissions to the listed queue(s)
Producers always also get access to the _<queue>-priority_ queue if it exists

Full config for example:

{{ template "zudello.createQueueAndUser" dict 
    "namespace" .Values.namespace 
    "username" "ingestion"
    "writeQueues" (list "document-worker" "team-data")
}} 

A secret named _<username>-user-credentials_ (eg: ingestion-user-credentials) will be 
created in the namespace. (Note: This name is used by the messaging-topology-operator)

namespace: The namespace where the secret etc will be created
username: The username to create, defaults to queue
writeQueues: A list of queues username can also write to

The produced secret will have the following keys (note values are lowercase 
for compatibility with the rabbitmq messaging-topology-operator):
- username
- password
- host
- port

*/}}
{{ $namespace := required "namespace required" .namespace }}
{{ $username := required "username required" .username }}
{{ $writeQueues := required "writeQueues list required" .writeQueues }}
{{ $host := "rabbit.rabbitmq.svc.cluster.local" }}
{{ $port := "5672" }}
{{ $secretName := printf "%s-user-credentials" .username }}
{{- $rabbitPassword := (lookup "v1" "Secret" .namespace $secretName ) }}
# Start zudello.createQueueAndUser template
{{ if not $rabbitPassword }}
{{ $newPassword := (randAlphaNum 30) }}

---
apiVersion: v1
kind: Secret
data:
    username: {{ $username | b64enc }}
    password: {{ $newPassword | b64enc }}
    host: {{ $host | b64enc }}
    port: {{ $port | b64enc }}
metadata:
  name: {{ $secretName }}
  namespace: {{ $namespace }}
  annotations:
    "helm.sh/resource-policy": keep
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-11"
type: Opaque

{{ end }}{{/* if not $rabbitPassword */}}

---

apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq
  importCredentialsSecret:
    name: {{ $secretName }}

---

{{ $writePermRegex := list -}}
{{- range $writeQueues -}}
    {{- $writePermRegex = printf "(%s)" . | append $writePermRegex -}}
    {{- $writePermRegex = printf "(%s-priority)" . | append $writePermRegex -}}
{{- end }}

apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  vhost: "/"
  user: {{ $username }}
  permissions:
    write: "^{{ join "|" $writePermRegex }}$"
    configure: ""
    read: ""
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ end }} {{/* ======================== End zudello.createProducerUser ======================== */}}

