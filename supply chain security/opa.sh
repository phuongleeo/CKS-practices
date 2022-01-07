helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm install -n gatekeeper-system gatekeeper gatekeeper/gatekeeper --create-namespace