#!/usr/bin/env bash
# Stands up a local kind cluster with Argo CD and hands control to Git.
# Everything after this script runs is driven by commits, not by kubectl.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-gxp}"
ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need kind; need kubectl; need docker

if grep -rq "REPLACE_ME" "${ROOT}/gitops"; then
  echo "gitops manifests still contain REPLACE_ME." >&2
  echo "Run: make set-repo REPO=https://github.com/<you>/gxp-gitops-platform.git" >&2
  exit 1
fi

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "==> creating kind cluster ${CLUSTER_NAME}"
  kind create cluster --config "${ROOT}/local/kind-cluster.yaml"
else
  echo "==> kind cluster ${CLUSTER_NAME} already exists"
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null

echo "==> installing Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> waiting for Argo CD to become ready (this takes a few minutes on ARM)"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=600s
kubectl -n argocd rollout status deploy/argocd-server --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s 2>/dev/null \
  || kubectl -n argocd rollout status deploy/argocd-application-controller --timeout=600s

echo "==> applying AppProject and root Application"
kubectl apply -f "${ROOT}/gitops/bootstrap/project.yaml"
kubectl apply -f "${ROOT}/gitops/bootstrap/root-app.yaml"

cat <<MSG

Bootstrap complete.

  admin password : make argocd-password
  UI             : make argocd-ui   (then https://localhost:8081)

Argo CD is now pulling from Git. dev syncs itself; qual and prod wait for a
manual sync. Nothing else should be applied to this cluster by hand.
MSG
