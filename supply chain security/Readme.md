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


# Add to kubeconfig
kubectl config set-credentials myuser --client-key=myuser.key --client-certificate=myuser.crt --embed-certs=true
```

# Test the webhook

This controller will reject all the pods that are using images with `latest` tag.

kubectl run nginx --image=nginx --port=80
