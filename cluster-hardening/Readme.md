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
