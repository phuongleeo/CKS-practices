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
