# Manage cluster role

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
