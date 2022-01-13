# PSP

[docs](https://kubernetes.io/docs/concepts/policy/pod-security-policy/#create-a-policy-and-a-pod)
Create psp named: `restrict-policy` which prevents the creation of privileged containers

```shell
# Enable admission
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
# edit this line
--enable-admission-plugins=...,PodSecurityPolicy
cat <<EOF | kubectl-admin apply -f -
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restrict-policy
spec:
  privileged: false
  seLinux:
    rule: RunAsAny
  supplementalGroups:
    rule: RunAsAny
  runAsUser:
    rule: RunAsAny
  fsGroup:
    rule: RunAsAny
  volumes:
  - '*'
EOF
```

2. Create a new Cluster role named : `restrict-access-role` which uses the newly created psp

```shell
kubectl create clusterrole restrict-access-role --verb=use --resource=podsecuritypolicies --resource-name=restrict-policy
```

3. Create a new service account name : `psp-denied-sa` in `staging` namespace

```shell
kubectl create sa psp-denied-sa --namespace=staging
```

4. Create a new Cluster role binding named : `deny-access-bind` which uses the newly created psp and the newly created service account

```shell
kubectl create clusterrolebinding deny-access-bind --clusterrole=restrict-access-role --serviceaccount=staging:psp-denied-sa
# Test
kubectl --as=system:serviceaccount:staging:psp-denied-sa auth can-i use podsecuritypolicies/restrict-policy
>>
yes

kubectl --as=system:serviceaccount:staging:psp-denied-sa create -f- <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pause
spec:
  containers:
    - name: pause
      image: k8s.gcr.io/pause
EOF
> pod "pause" created

kubectl --as=system:serviceaccount:staging:psp-denied-sa create -f- <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged
spec:
  containers:
    - name: pause
      image: k8s.gcr.io/pause
      securityContext:
        privileged: true
EOF
> Error from server (Forbidden): error when creating "STDIN": pods "privileged" is forbidden: PodSecurityPolicy: unable to admit pod: [spec.containers[0].securityContext.privileged: Invalid value: true: Privileged containers are not allowed]
```

# Secret

Retrieve the content of the secret named `db1-test` in `istio-system` namespace
Store the username field in a file named `/home/candidate/user.txt` and the password field in a file named `/home/candidate/pass.txt`

```shell
kubectl -n istio-system get secret generic db1-test -o jsonpath='{.data.user}' | base64 --decode > /home/candidate/user.txt
kubectl -n istio-system get secret generic db1-test -o jsonpath='{.data.pass}' | base64 --decode > /home/candidate/pass.txt
```

Create a new secret named `db2-test` in the `istio-system` namespace, with the content:

```yaml
username: production-instance
password: dsg239GSAD
```

```shell
kubectl -n istio-system create secret generic db2-test --from-literal=username=production-instance --from-literal=password=dsg239GSAD

```

Create a new pod that has access to the newly created secret

```yaml
pod name: secret-pod
namespace: istio-system
container: dev-container
image: nginx
volume: secret-volume
mountPath: /etc/secrets
```

```shell
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: secret-pod
  name: secret-pod
  namespace: istio-system
spec:
  runtimeClassName: untrusted
  containers:
    - image: nginx
      name: dev-container
      resources: {}
      volumeMounts:
        - mountPath: /etc/secrets
          name: secret-volume
      securityContext:
        allowPrivilegeEscalation: false
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  volumes:
    - name: secret-volume
      secret:
        secretName: db2-test
EOF
```

# Gvisor

[docs](https://kubernetes.io/docs/concepts/containers/runtime-class/)
[enable-gvisor](https://github.com/kubernetes/minikube/blob/master/deploy/addons/gvisor/README.md)

```shell
Containerd's default runtime is runc. Containerd had been prepared to support an additional runtime handler: runsc (gVisor)
```

Create a RuntimeClass named `untrusted` using prepared runtime handler named `runsc`
Update all pods in the namespace `server` to run on gVisor

## Create the corresponding RuntimeClass

```yaml
apiVersion: node.k8s.io/v1 # RuntimeClass is defined in the node.k8s.io API group
kind: RuntimeClass
metadata:
  name: untrusted # The name the RuntimeClass will be referenced by
  # RuntimeClass is a non-namespaced resource
handler: runsc
```

Then edit the manifest which is corresponding to the runtime class

```yaml
#Pod
---
spec:
  runtimeClassName: untrusted
  containers: {}
```
