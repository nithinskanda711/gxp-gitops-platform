#!/usr/bin/env bash
# Installs Jenkins into the cluster from the checked-in values file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART_VERSION="${CHART_VERSION:-5.5.2}"

command -v kubectl >/dev/null || { echo "kubectl not installed" >&2; exit 1; }
command -v helm >/dev/null    || { echo "helm not installed" >&2; exit 1; }

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl -n jenkins get secret cosign-key >/dev/null 2>&1; then
  echo "cosign-key secret missing. Run scripts/cosign-keygen.sh first." >&2
  exit 1
fi

if ! kubectl -n jenkins get secret aws-credentials >/dev/null 2>&1; then
  cat >&2 <<MSG
aws-credentials secret missing. Create it with an IAM user that can push to ECR:

  kubectl -n jenkins create secret generic aws-credentials \\
    --from-literal=AWS_ACCESS_KEY_ID=... \\
    --from-literal=AWS_SECRET_ACCESS_KEY=... \\
    --from-literal=AWS_DEFAULT_REGION=eu-west-1

Give that user AmazonEC2ContainerRegistryPowerUser and nothing more.
MSG
  exit 1
fi

echo "==> installing Jenkins ${CHART_VERSION}"
helm repo add jenkins https://charts.jenkins.io >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --version "${CHART_VERSION}" \
  --values "${ROOT}/platform/jenkins/values.yaml" \
  --wait --timeout 15m

cat <<MSG

Jenkins is up.

  UI       : make jenkins-ui   (then http://localhost:8082)
  user     : admin
  password : admin

Create a Pipeline job pointing at this repository with script path
"Jenkinsfile", then run it. The first build pulls several tool images and is
slower than the rest.
MSG
