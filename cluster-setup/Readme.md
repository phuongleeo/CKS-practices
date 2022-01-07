# Create namespace

```shell
k create ns frontend
k create ns backend
```

# Create service

```shell
k run frontend --image=nginx:alpine --replicas=1 --port=80 --namespace=frontend
k run backend --image=nginx:alpine --replicas=1 --port=80 --namespace=backend
```

# Test network policy

1. Deny all

```shell
k apply -f 1-np-deny-all.yaml
```

2. Allow frontend only

```shell
k apply -f 2-np-allow-frontend.yaml
```

3. Allow backend only

```shell
k apply -f 3-np-allow-backend.yaml
```

4. Block backend app from accessing instance metadata

```shell
k apply -f 4-np-protect-node-metadata.yaml
```

5. enable ingress HTTPS

```shell
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
kubectl create secret tls secure-ingress --cert=cert.pem --key=key.pem

# Create 2 separate backend resources: podinfo and httpbin
helm upgrade --install frontend  --namespace default --set replicaCount=1 --set backend=http://backend-podinfo:9898/echo --set ingress.enabled=true podinfo/podinfo
kubectl apply -f https://raw.githubusercontent.com/istio/istio/master/samples/httpbin/httpbin.yaml

# Apply HTTPS
kubectl apply -f 5-secure-ingress.yaml
```
