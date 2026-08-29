#!/usr/bin/env bash
# Installs Kyverno and applies the platform policies.
#
# Kyverno needs registry credentials of its own: verifying a signature means
# fetching it from ECR, which is a private registry. Those credentials are
# separate from Jenkins' and read-only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KYVERNO_VERSION="${KYVERNO_VERSION:-3.2.6}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

command -v kubectl >/dev/null || { echo "kubectl not installed" >&2; exit 1; }
command -v helm >/dev/null    || { echo "helm not installed" >&2; exit 1; }
command -v aws >/dev/null     || { echo "aws cli not installed" >&2; exit 1; }

if grep -q "REPLACE_WITH_COSIGN_PUB" "${ROOT}/platform/kyverno/policies/01-require-signed-images.yaml"; then
  echo "The signature policy has no public key yet." >&2
  echo "Run scripts/cosign-keygen.sh first." >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "==> installing Kyverno ${KYVERNO_VERSION}"
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

echo "==> creating the registry pull secret Kyverno uses to fetch signatures"
kubectl -n kyverno create secret docker-registry ecr-creds \
  --docker-server="${REGISTRY}" \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region "${AWS_REGION}")" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno \
  --version "${KYVERNO_VERSION}" \
  --set "admissionController.container.extraArgs.imagePullSecrets=ecr-creds" \
  --set admissionController.replicas=1 \
  --set backgroundController.replicas=1 \
  --set cleanupController.replicas=1 \
  --set reportsController.replicas=1 \
  --wait --timeout 10m

echo "==> applying policies"
kubectl apply -f "${ROOT}/platform/kyverno/policies/"

kubectl get clusterpolicies.kyverno.io

cat <<MSG

Kyverno is enforcing.

NOTE: the ECR token in the ecr-creds secret expires after 12 hours. Re-run
      make kyverno-refresh-creds
when signature verification starts failing with an authentication error. A
production cluster would use IRSA instead of a static secret; that gap is
recorded in docs/control-matrix.md rather than glossed over.
MSG
