#!/usr/bin/env bash
# Generates the release signing key pair and installs it where each half belongs.
#
#   private key -> a Secret in the jenkins namespace, and nowhere else
#   public key  -> committed to this repository and baked into the Kyverno policy
#
# Anyone can verify a signature. Only the pipeline can make one. That asymmetry
# is the entire control.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYDIR="${ROOT}/.keys"
NAMESPACE="${NAMESPACE:-jenkins}"

command -v cosign >/dev/null || { echo "cosign not installed - see docs/phase-2.md" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl not installed" >&2; exit 1; }

if [[ -f "${KEYDIR}/cosign.key" ]]; then
  echo "A key already exists at ${KEYDIR}/cosign.key"
  echo "Regenerating invalidates every signature made so far. Delete it by hand if that is what you want."
  exit 1
fi

mkdir -p "${KEYDIR}"
chmod 700 "${KEYDIR}"

if [[ -z "${COSIGN_PASSWORD:-}" ]]; then
  echo "Set COSIGN_PASSWORD first, e.g.:"
  echo "  export COSIGN_PASSWORD=\$(openssl rand -base64 24)"
  echo "Store that value somewhere you will not lose it."
  exit 1
fi

echo "==> generating key pair"
( cd "${KEYDIR}" && cosign generate-key-pair )

echo "==> creating the Secret in namespace ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" create secret generic cosign-key \
  --from-file=cosign.key="${KEYDIR}/cosign.key" \
  --from-file=cosign.pub="${KEYDIR}/cosign.pub" \
  --from-literal=password="${COSIGN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> publishing the public half"
cp "${KEYDIR}/cosign.pub" "${ROOT}/platform/kyverno/cosign.pub"

PUB_INDENTED=$(sed 's/^/                      /' "${KEYDIR}/cosign.pub")
POLICY="${ROOT}/platform/kyverno/policies/01-require-signed-images.yaml"
python3 - "$POLICY" <<PY
import sys, pathlib
p = pathlib.Path(sys.argv[1])
pub = pathlib.Path("${KEYDIR}/cosign.pub").read_text().rstrip("\n")
indented = "\n".join("                      " + l for l in pub.splitlines()).lstrip()
text = p.read_text().replace("REPLACE_WITH_COSIGN_PUB", indented)
p.write_text(text)
PY

cat <<MSG

Key pair created.

  private : ${KEYDIR}/cosign.key   (gitignored - never commit this)
  public  : ${ROOT}/platform/kyverno/cosign.pub   (commit this)

The Kyverno policy now carries the public key. Commit and push, then apply the
policies. Keep COSIGN_PASSWORD safe: without it the private key is unusable and
you will have to re-key, invalidating every signature made so far.
MSG
