# Generate server certificate which is used for Image Bouncer: https://github.com/kainlite/kube-image-bouncer

```shell
openssl genrsa -out server.key 2048
cat <<EOF >> csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
O = system:nodes
CN = system:node:image-bouncer-webhook.default.pod.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = image-bouncer-webhook.default.svc
DNS.2 = image-bouncer-webhook.default.svc.cluster.local
DNS.3 = image-bouncer-webhook.default.pod.cluster.local
IP.1 = 192.168.64.30
IP.2 = 192.168.64.1
EOF
openssl req -new -key server.key -out server.csr -config csr.conf

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: image-bouncer-webhook.default
spec:
  request: $(cat server.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kubelet-serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF
# Approve certificate
kubectl certificate approve image-bouncer-webhook.default

# Get certificate ready to use
kubectl get csr image-bouncer-webhook.default -o jsonpath='{.status.certificate}' | base64 --decode > server.crt

```

## ImagePolicyWebhook

```shell
# On your laptop
docker run --rm -v "`pwd`/server.key:/certs/server.key:ro" -v "`pwd`/server.crt:/certs/server.crt:ro" -p 1323:1323 --network host kainlite/kube-image-bouncer:latest -k /certs/server.key -c /certs/server.crt

# Create image policy configuration
cat <<EOF >> kube-image-bouncer.yml
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/minikube/certs/ca.crt
    server: https://192.168.64.1:1323/image_policy
  name: bouncer_webhook
contexts:
- context:
    cluster: bouncer_webhook
    user: api-server
  name: bouncer_validator
current-context: bouncer_validator
preferences: {}
users:
- name: api-server
  user:
    client-certificate: /var/lib/minikube/certs/apiserver.crt
    client-key:  /var/lib/minikube/certs/apiserver.key
EOF

minikube cp admission-config.yaml /var/lib/minikube/certs/admission-config.yaml
minikube cp event-rate-limit.yaml /var/lib/minikube/certs/event-rate-limit.yaml
minikube cp kube-image-bouncer.yml /var/lib/minikube/certs/kube-image-bouncer.yml


# ssh into minikube
minikube ssh
sudo -i
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# edit this line
 --enable-admission-plugins=...,ImagePolicyWebhook
 --admission-control-config-file=/var/lib/minikube/admission-config.yaml

```

### Test the image policy webhook

This controller will reject all the pods that are using images with `latest` tag.

```shell
??? kubectl run nginx --image=nginx --port=80
Images using latest tag are not allowed
```

## ValidatingAdmissionWebhook

```shell
# Create TLS secret
kubectl create secret tls tls-image-bouncer-webhook --key server.key --cert server.crt

# create ValidatingWebhookConfiguration
cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-bouncer-webook
webhooks:
  - name: image-bouncer-webhook.default.svc
    rules:
      - apiGroups:
          - ''
        apiVersions:
          - v1
        operations:
          - CREATE
        resources:
          - pods
    failurePolicy: Ignore
    sideEffects: None
    admissionReviewVersions: ['v1', 'v1beta1']
    clientConfig:
      caBundle: $(kubectl get csr image-bouncer-webhook.default -o jsonpath='{.status.certificate}')
      service:
        name: image-bouncer-webhook
        namespace: default
EOF

# Create deployment
kubectl apply -f image-bouncer-webhook.yaml
```

### Test the ValidatingAdmissionWebhook

```shell
??? kubectl run nginx --image=nginx
Error from server: admission webhook "image-bouncer-webhook.default.svc" denied the request: Images using latest tag are not allowed

??? kubectl run nginx --image=nginx:alpine
pod/nginx created
```

# Trivy

Look for images with `High` or `Critical` severity vulnerabilities, and delete the Pods that use those images.

```shell
# List all pods along with their images
kubectl get pod -A -o custom-columns='POD:.metadata.name,IMAGE:.spec.containers[*].image'
POD                                IMAGE
nginx                              nginx:alpine

# Scan the images
images=($(k get pod -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{" "}{end}'))
for i in "${images[@]}"; docker run -v ~/.cache/trivy:/root/.cache aquasec/trivy:0.22.0 i --light --severity=HIGH,CRITICAL --no-progress $i

```
