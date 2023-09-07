{{ define "zudello.createQueueAndUser" -}}
{{/*
For details on using these features, see:
https://www.rabbitmq.com/kubernetes/operator/using-topology-operator.html


Create a new RabbitMQ queue (and associated exchange) and user for a consumer.
Producers should _not_ use this template.

Full config for example:

{{ template "zudello.createQueueAndUser" dict 
    "namespace" .Values.namespace 
    "queue" "ingestion" 
    "username" "ingestion"
    "priority" true
    "writeQueues" (list "document-worker" "team-data")
    "events" (list "created.*" "*.expenses")
    "eventsOnly" false
    "configure" ""
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
events: Optional, a list of events to create bindings for. For more information see:
    https://docs.google.com/document/d/1BZv1Yr3tD-uF6i5mob7tLNBxjSF-QoEcr3pr0KiMz7w/edit?usp=sharing
eventsOnly: Optional, if true (YAML bool), only create bindings for the events, do not create
    the queue or exchange. The queue name is still required for the internal event queues to
    be created.
configure: Optional, a regex to allow configure permissions on. If not set, no configure
    permissions will be granted. Otherwise follows RabbitMQ configure regex rules.

The produced secret will have the following keys (note values are lowercase 
for compatibility with the rabbitmq messaging-topology-operator):
- username
- password
- host
- port
- queue

To mount the secret, use the following in your deployment:

          volumeMounts:
            - name: rabbit
              mountPath: "/run/secrets/rabbit"
              readOnly: true
      volumes:
        - name: rabbit
          secret:
           secretName: <username>-user-credentials

A liveness probe should also be created with:

{{ if not .Values.developmentMode }}
          livenessProbe:
            exec:
              command:
              - python3
              - -m
              - zudello_rabbit.heartbeat
            initialDelaySeconds: 30
            periodSeconds: 60
            timeoutSeconds: 30
{{ end }} 


*/}}
{{ $namespace := required "namespace required" .namespace }}
{{ $queue := required "queue name required" .queue }}
{{ $username := (default .queue .username) }}
{{ $priority := (default false .priority) }}
{{ $writeQueues := (default (list) .writeQueues)}}
{{ $events:= (default (list) .events)}}
{{ $eventsOnly := (default false .eventsOnly) }}
{{ $configure := (default ("") .configure)}}
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
  {{- if $priority }}
    priority: {{ "true" | b64enc }}
  {{- else }}
    priority: {{ "false" | b64enc }}
  {{- end }}
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
    write: "^
      {{- if $writeQueues -}}
        {{- join "|" $writePermRegex -}}
        |
      {{- end -}}
        (events)|({{ $queue }})
      {{- if or $events $eventsOnly -}}
        |(events-{{ $queue }})
      {{- end -}}$"
    configure: {{ $configure | quote }}
    read: "^({{ $queue }})|(events-{{ $queue }}){{ if $priority }}|({{ $queue }}-priority){{ end }}$"
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ if not $eventsOnly }}
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
{{ end }} {{/* if not $eventsOnly */}}

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

{{ end }} {{/* if $priority */}}

{{ if or $events $eventsOnly }}
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata:
  name: events-{{ $queue }}
  namespace: {{ $namespace }}
spec:
  name: events-{{ $queue }}
  type: quorum
  autoDelete: false
  durable: true
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ range $events }}
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata:
  name: events-{{ $queue }}-{{ (trunc 10 (sha256sum .)) }}
  namespace: {{ $namespace }}
spec:
  source: events
  destination: events-{{ $queue }}
  destinationType: queue
  routingKey: {{ . | quote }}
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq
{{ end }} {{/* range $events */}}

---
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata:
  name: events-{{ $queue }}
  namespace: {{ $namespace }}
spec:
  name: events-{{ $queue }}
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
  name: events-{{ $queue }}
  namespace: {{ $namespace }}
spec:
  source: events-{{ $queue }}
  destination: events-{{ $queue }}
  destinationType: queue
  routingKey: events-{{ $queue }}
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ end }} {{/* if or $events $eventsOnly */}}

{{ end }} {{/* ======================== End zudello.createQueueAndUser ======================== */}}

{{ define "zudello.createProducerUser" -}}
{{/*
Create a new RabbitMQ user for a producer, with write permissions to the listed queue(s)
Producers always also get access to the _<queue>-priority_ queue if it exists, as well as
the _events_ exchange.

Full config for example:

{{ template "zudello.createProducerUser" dict 
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
    write: "^{{ join "|" $writePermRegex }}|(events)$"
    configure: ""
    read: ""
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

{{ end }} {{/* ======================== End zudello.createProducerUser ======================== */}}


{{- define "zudello.scaleRabbitQueue" -}}
{{/* 
Creates an entire ScaledObject given the name of the deployment, and a list of queues
and their target length.

The preferred method to call this by passing a key from values.yaml, and passing as an 
argument to the template, along with all values. 

For examples, values.ymal may look like this (with comments):

queueMain:
  name: django-document-worker-queue # The EXACT name of the deployment to scale
  minimumReplicas: 1    # The minimum number of replicas to keep, typically 1
  maximumReplicas: 5    # The maximum number of replicas to keep, can be overridden by cluster
  scaleDownDelay: 300   # Optional: The time in seconds to wait before scaling down, default: 60 seconds
  scaleCpu: 100         # Optional: The CPU threshold to scale up, if <= 0, no scaling will be done, default is disabled
  queues:               # A list of queues to scale, and their target length
    - name: document-worker # The name of the queue to scale
      length: 5             # The target length of the queue
      priority: true        # Optional: If true, will also scale the <queue>-priority queue, default: false

Priority queues are scaled twice as fast as the default queues.

To scale on event queues, use a name of "events-<queue>", and set priority to false.

The template would then be called with:
{{ include "zudello.scaleRabbitQueue" (list .Values.queueMain .) }}

NOTE: The trailing "." in the list is critical as this will pass in the full context
of the deployment.

To override a specific item in a cluster, eg: maximumReplicas, in that cluster.yaml, put:

queueDefault:
  maximumReplicas: 30

Implemenation note: The choice of using config in values.yaml is deliberate, as it
makes the confiuration much easier to read and understand and allow values to be 
overridden per cluster.
*/}}
{{- $queue := (index . 0) -}}
{{- $values := (index . 1).Values -}}
{{- $scaleCpu := default 0.0 $queue.scaleCpu }}
{{ $namespace := $values.namespace }}
{{- $password := randAlphaNum 50 }}
{{/* This dumb thing on the end of the username is to force rabbit to update the password */}}
{{ $username := printf "scaledobject-%s-%s" $queue.name (trunc 10 (sha256sum $password)) }}
{{ $secretName := printf "%s-user" $username }}
---
apiVersion: v1
kind: Secret
data:
    username: {{ $username | b64enc }}
    password: {{ $password | b64enc }}
    host: {{ printf "http://%s:%s@rabbit.rabbitmq.svc.cluster.local:15672/" $username $password | b64enc }}
metadata:
  name: {{ $secretName }}
  namespace: {{ $namespace }}
type: Opaque

---
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  tags:
  - monitoring
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq
  importCredentialsSecret:
    name: {{ $secretName }}

---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata:
  name: {{ $username }}
  namespace: {{ $namespace }}
spec:
  vhost: "/"
  user: {{ $username }}
  permissions:
    write: ""
    configure: ""
    read: ".*"
  rabbitmqClusterReference:
    name: rabbit
    namespace: rabbitmq

---
# Generated by zudello.scaleQueue template
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $queue.name }}
  namespace: {{ $values.namespace | quote }}
spec:
  scaleTargetRef:
    name: {{ $queue.name }}
{{- if $values.developmentMode }}
  minReplicaCount: 1
  maxReplicaCount: 1
{{- else }} {{/* if $values.developmentMode */}}
{{- if $values.workingHours }}

  minReplicaCount: 0
{{ else }} {{/* if $values.workingHours */}}
  minReplicaCount: {{ $queue.minimumReplicas }}
{{- end }} {{/* if $values.workingHours */}}
{{- end }} {{/* if $values.developmentMode */}}
  maxReplicaCount: {{ $queue.maximumReplicas }}
  advanced:
    horizontalPodAutoscalerConfig:  
      behavior:
        scaleDown:
          stabilizationWindowSeconds: {{ mul 2 (default 60 $queue.scaleDownDelay) }}
          policies:
          - type: Pods
            value: 1
            periodSeconds: {{ default 60 $queue.scaleDownDelay }}
          selectPolicy: Min
  triggers:
{{- range $queue.queues }}
    - type: rabbitmq
      authenticationRef:
        name: {{ $queue.name }}
      metadata:
        queueName: {{ .name | quote }}
        value: "{{ .length }}"
        mode: QueueLength
{{- if .priority }}
    - type: rabbitmq
      authenticationRef:
        name: {{ $queue.name }}
      metadata:
        queueName: {{ printf "%s-priority" .name | quote }}
        value: "{{ div .length 2 }}"
        mode: QueueLength
{{- end }} {{/* if .priority */}}
{{- end }}
{{ if and (not $values.workingHours) (gt $scaleCpu 0.0) }}
    - type: cpu
      metricType: "Utilization"
      metadata:
        value: "{{ $scaleCpu }}"
{{ end }} {{/* if not $values.workingHours */}}
{{ if and $values.workingHours (gt $queue.minimumReplicas 0.0) }}
    - type: cron
      metadata:
        timezone: {{ template "zudello.getTimeZone" }}
        start: {{ $values.workingHours.start | quote }}
        end: {{ $values.workingHours.end | quote }}
        desiredReplicas: {{ $queue.minimumReplicas | quote }}
{{ end }} {{/* if $values.workingHours */}}
--- 
# Setup for keda to access RabbitMQ
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: {{ $queue.name }}
  namespace: {{ $values.namespace | quote }}
spec:
  secretTargetRef:
    - parameter: host
      name: {{ $secretName }}
      key: host

# End zudello.scaleQueue template
{{ end }} {{/* if $values.scaleRabbitQueue */}}


{{- define "zudello.rabbit-liveness" -}}
{{/*

Typical liveness probes for applications.

Automatically disables the checks if developmentMode is true

Normal usage:
  
{{ include "zudello.rabbit-liveness" (list .) }}

*/}}

{{- $values := (index . 0).Values -}}
{{ if not $values.developmentMode }}
          livenessProbe:
            exec:
              command:
              - python3
              - -m
              - zudello_rabbit.heartbeat
            initialDelaySeconds: 5
            periodSeconds: 60
            timeoutSeconds: 30
{{ end -}} {{/* if $values.developmentMode */}}
{{- end -}} {{/* zudello.rabbit-liveness */}}
