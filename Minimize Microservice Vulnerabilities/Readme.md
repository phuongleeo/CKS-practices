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
