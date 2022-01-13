# Sysdig and Falco

```shell
# Install Sysdig and Falco
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco
curl -s https://s3.amazonaws.com/download.draios.com/stable/install-sysdig | sudo bash
apt-get install -y falco --allow-unauthenticated
```

# Sysdig CLI

```shell
sysdig -l |grep k8s
```

## Detect anomaly process

```shell
# create a test pod
kubectl run nginx --image=nginx:alpine --port 80

# get the pod id
crictl ps
container_id=$(docker ps -qf label="io.kubernetes.pod.name=nginx" -f ancestor=nginx:alpine)

# Log the process
sysdig -M 30 -p "*%evt.time,%user.uid,%proc.name" k8s.pod.name=nginx
sysdig -M 30 -p "*%evt.time\t%user.uid\t%proc.name\t%k8s.pod.name\t%container.name" container.id=$container_id
>>
15:55:14.320679213	0	echo	nginx	k8s_nginx_nginx_default_342889a2-cec3-4256-ae23-56978345b3ed_6

# Test the pod
docker exec -it $container_id echo a
```

## Falco

```shell
# Create sample rule
sudo vi /etc/falco/falco_rules.local.yaml
```

```yaml
- rule: shell_in_container
  desc: notice shell activity within a container
  condition: k8s.pod.name=nginx
  output: shell in a container (user=%user.name container_id=%container.id container_name=%container.name shell=%proc.name parent=%proc.pname cmdline=%proc.cmdline)
  priority: WARNING
```

```shell
# Run the rule
sudo falco -r /etc/falco/falco_rules.local.yaml
>>
16:27:00.095718180: Warning shell in a container (user=root container_id=fb151ac325d7 container_name=k8s_nginx_nginx_kube-system_210b721a-ae34-409f-aa16-fcf2cd554f09_0 shell=echo parent=<NA> cmdline=echo a)

# perform arbitrary command
kubectl exec -it po/nginx -- echo a
```

# Pod security

Delete pods in particular namespace that is either `not stateless` or `not immutable`

- Pods being able to store data inside containers must be treated as `not stateless`

```shell
# search for pods that have volumes
JSONPATH='{range .items[*]}{@.metadata.name}{"\t"}{range @.spec.volumes[*]} {@.name}{"\t"}{end}{"\n\n\n"}{end}'
kubectl get pod -A -o jsonpath="$JSONPATH"
```

- Pods being configured to be privilegeds in any way must be treated as `not immutable`

```shell
# Search for pods that are privileged
JSONPATH='{range .items[*]}{@.metadata.name}{"\t"}{@.spec.containers[*].securityContext.privileged}{"\n"}{end}'
kubectl get pod -A -o jsonpath="$JSONPATH"|grep true
```

# Audit

[docs](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/)
Enable log backend:

- Loggs are stored at `/var/log/kubernetes/audit-logs.txt`
- Logs files are retained for 10 days
- at maximum, a number of `2` old audit log files are retained

- A basic policy is provided at `/etc/kubernetes/logpolicy/sample-policy.yaml`. It only specifies what `not` to log. Edit and extend the policy to log:
  - `namespaces` changes at RequestResponse level
  - the request body of `persistentvolumes` changes in `front-apps` namespace
  - ConfigMap and Secret changes in all namespaces at `Metadata` level

Also, add a catch-all rule to log all other requests at `Metadata` level

```yaml
# Edit kube-api manifest
    args:
      ...
      - --audit-log-path=/var/log/kubernetes/audit-logs.txt
      - --audit-policy-file=/etc/kubernetes/logpolicy/sample-policy.yaml
      - --audit-log-maxage=2
      - --audit-log-maxbackup=10
    volumeMounts:
      - mountPath: /etc/kubernetes/logpolicy/audit-policy.yaml
        name: audit-policy
        readOnly: true
      - mountPath: /var/log/kubernetes
        name: audit-log
  volume:
    - name: audit-policy
      hostPath:
        path: /etc/kubernetes/logpolicy/sample-policy.yaml
        type: File
    - name: audit-log
      hostPath:
        path: /var/log/kubernetes
        type: DirectoryOrCreate
```

```yaml
# Sample policy
apiVersion: audit.k8s.io/v1 # This is required.
kind: Policy
# Don't generate audit events for all requests in RequestReceived stage.
omitStages:
  - 'RequestReceived'
rules:
  # Log pod changes at RequestResponse level
  - level: RequestResponse
    resources:
      - group: ''
        resources: ['namespaces']
  - level: Request
    resources:
      - group: ''
        resources: ['persistentvolumes']
    namespaces: ['front-apps']
  - level: Metadata
    resources:
      - group: ''
        resources: ['configmaps', 'secrets']
  - level: Metadata
    omitStages:
      - 'RequestReceived'
```
