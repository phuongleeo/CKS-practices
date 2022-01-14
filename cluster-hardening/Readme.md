# Manage cluster role

[docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

1. Create role bound to the service account name: `service-account-web` to only `get` operations, on resources of type: `Endpoints`

```shell
kubectl -n db create role role-1 --verb=get --resource=endpoints
kubectl -n db create rolebinding role-binding-1 --role=role-1 --serviceaccount=db:service-account-web
# Test
kubectl --as=system:serviceaccount:db:service-account-web get ep -n db
>>
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:db:service-account-web" cannot list resource "pods" in API group "" in the namespace "db"
```

2. Create role 2 in the `db` namespace which only allows `delete` operations, on resources of type: `namespaces`
   create role binding named `role-2-binding` the newly created Role

```shell
kubectl -n db create role role-2 --verb=delete --resource=namespaces
kubectl -n db create rolebinding role-2-binding --role=role-2 --serviceaccount=db:service-account-web
# Test
kubectl --as=system:serviceaccount:db:service-account-web  delete ns db --dry-run=server
>>
namespace "db" deleted (server dry run)
```

# AppArmor

[apparmor](https://gitlab.com/apparmor/apparmor/-/wikis/Documentation)
[k8s](https://kubernetes.io/docs/tutorials/security/apparmor/)

**This lab requires Vagrant cluster**

AppArmor is enabled on the cluster's worker node. An AppArmor profile is prepared, but not enforced yet
enforce the prepared AppArmor profile located at : `/etc/apparmor.d/nginx_apparmor`

```shell
# Propagate this file to every worker nodes
cat <<EOF | sudo tee /etc/apparmor.d/nginx_apparmor
#include <tunables/global>

profile k8s-apparmor-example-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>

  file,

  # Deny all file writes.
  deny /** w,
}
EOF

# Run on each worker node
sudo apparmor_parser /etc/apparmor.d/nginx_apparmor

# Verify the profile
sudo aa-status|grep deny-write
```

Edit the prepared manifest file `nginx-deploy.yaml` to apply the AppArmor profile

```yaml
#manifest: add this anotation to the object
# syntax: container.apparmor.security.beta.kubernetes.io/<container_name>: <profile_ref>
container.apparmor.security.beta.kubernetes.io/nginx: localhost/k8s-apparmor-example-deny-write
```

# Seccomp

[k8s](https://kubernetes.io/docs/tutorials/security/seccomp/)
[k8s-1.22](https://v1-22.docs.kubernetes.io/docs/tutorials/clusters/seccomp/)

Copy profiles from host to minikube node

```shell
minikube ssh mkdir -p /var/lib/kubelet/seccomp/profiles
minikube cp profiles/audit.json /var/lib/kubelet/seccomp/profiles/audit.json
minikube cp profiles/fine-grained.json /var/lib/kubelet/seccomp/profiles/fine-grained.json
minikube cp profiles/violation.json /var/lib/kubelet/seccomp/profiles/violation.json
```

Enable Seccomp on the kube-api manifest

```yaml
- --feature-gates=SeccompDefault=true
```

Enable Seccomp on the kubelet

```shell
minikube ssh
vi /var/lib/kubelet/config.yaml
# Add these lines
seccomp-default: RuntimeDefault
seccomp-profile-root: /var/lib/kubelet/seccomp

# Restart kubelet
systemctl restart kubelet
```

Test:

1. apply the audit.json profile, which will log all syscalls of the process, to a new Pod.
   This profile does not restrict any syscalls, so the Pod should start successfully.

```shell
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: audit-pod
  labels:
    app: audit-pod
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/audit.json
  containers:
  - name: test-container
    image: hashicorp/http-echo:0.2.3
    args:
    - "-text=just made some syscalls!"
    securityContext:
      allowPrivilegeEscalation: false
EOF
# Expose node port
kubectl expose pod/audit-pod --type NodePort --port 5678
```

Test:
On host machine, run the `curl`:

```shell
curl $(minikube ip):$(kgs audit-pod -o jsonpath='{.spec.ports[].nodePort}')
just made some syscalls!
```

View log:

```shell
minikube ssh dmesg|grep 'http-echo'
```

2. Test restricted profile

```shell
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: violation-pod
  labels:
    app: violation-pod
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/violation.json
  containers:
  - name: test-container
    image: hashicorp/http-echo:0.2.3
    args:
    - "-text=just made some syscalls!"
    securityContext:
      allowPrivilegeEscalation: false
EOF
```

Here seccomp has been instructed to error on any syscall by setting `"defaultAction": "SCMP_ACT_ERRNO"`

3. Create Pod that uses the Container Runtime Default seccomp Profile

Most container runtimes provide a sane set of default syscalls that are allowed or not. The defaults can easily be applied in Kubernetes by using the runtime/default annotation or setting the seccomp type in the security context of a pod or container to RuntimeDefault.

```shell
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: audit-pod
  labels:
    app: audit-pod
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: test-container
    image: hashicorp/http-echo:0.2.3
    args:
    - "-text=just made some syscalls!"
    securityContext:
      allowPrivilegeEscalation: false
EOF
```

# Service Account

A pod failed to run because of an incorestly specified service account.
Create a new service account named: `backend-sa` in `qa` namespace, which must not have access to **any** secrets

```shell
kubectl create sa backend-sa -n qa --dry-run=client -o yaml | vi -

#Append this line
automountServiceAccountToken: false

# Add this service account into pod manifest
# syntax: serviceAccountName: backend-qa
```
