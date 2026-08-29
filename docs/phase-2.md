# Phase 2 — supply chain

Phase 1 proved the cluster reconciles to Git. It did not prove the *image* is
trustworthy: anything you loaded into kind would run.

Phase 2 closes that. Four tools, one chain:

```
Jenkins builds (Kaniko, no Docker socket)
   ↓ pushes to ECR, gets a digest back
Syft   → SBOM of what is actually inside
Trivy  → scan; CRITICAL fails the build
Cosign → signs the DIGEST, and attests the SBOM to it
   ↓
Kyverno at admission → verifies the signature before scheduling
```

The order is the point. Signing is last, so a signature can only exist for an
image that passed the scan. Everything downstream of the build refers to the
digest, never the tag, so the thing scanned and the thing deployed are provably
the same artefact.

---

## Prerequisites

Phase 1 running, plus:

```bash
# cosign
curl -LO https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
sudo install -m 0755 cosign-linux-amd64 /usr/local/bin/cosign && rm cosign-linux-amd64

# aws cli
curl -L "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

aws configure   # region eu-west-1
```

**Set a budget alarm first.** AWS console → Billing → Budgets → €10/month with
an email alert. Two minutes, and it means a mistake tells you in a day rather
than at month end.

**Free some memory.** Jenkins wants ~1GB plus agent pods. Drop the kind worker:
delete the `- role: worker` block in `local/kind-cluster.yaml`, then
`make cluster-down && make cluster-up`.

---

## Step 1 — the registry

The ECR stack is deliberately separate from the EKS stack so that `apply` here
cannot create a control plane or a NAT gateway by accident.

```bash
cd infra/terraform/ecr
cp terraform.tfvars.example terraform.tfvars    # set owner
cd ../../..

make ecr-init      # read the plan
```

The plan should say **3 to add**: a repository, a lifecycle policy, and nothing
else. If it says 60-odd, you are in the wrong directory.

```bash
make ecr-apply
make ecr-url
```

Cost at this scale is small change — storage is billed per GB-month and the
lifecycle policy caps the repository at 20 images. There is no hourly charge for
a registry. The expensive things (EKS control plane, NAT gateway) live in
`infra/terraform/eks` and stay unapplied.

---

## Step 2 — the signing key

```bash
export COSIGN_PASSWORD=$(openssl rand -base64 24)
echo "$COSIGN_PASSWORD"     # store this somewhere you will not lose it
make cosign-keys
```

This creates the key pair, puts the private half in a Secret in the `jenkins`
namespace, copies the public half to `platform/kyverno/cosign.pub`, and injects
it into the signature policy.

Anyone can verify. Only the pipeline can sign. That asymmetry *is* the control.

Lose `COSIGN_PASSWORD` and the private key is unusable — you re-key, and every
signature made so far becomes unverifiable. `.keys/` is gitignored; keep it that
way.

```bash
git add platform/kyverno/ && git commit -m "publish release public key" && git push
```

---

## Step 3 — credentials for Jenkins

Create an IAM user with `AmazonEC2ContainerRegistryPowerUser` and nothing more,
then:

```bash
kubectl -n jenkins create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=... \
  --from-literal=AWS_SECRET_ACCESS_KEY=... \
  --from-literal=AWS_DEFAULT_REGION=eu-west-1
```

Static keys in a Secret are a known gap, recorded in the control matrix. On real
EKS this would be IRSA and there would be no long-lived credential at all.

---

## Step 4 — Jenkins

```bash
make jenkins-install
make jenkins-ui        # http://localhost:8082, admin/admin
```

Create a Pipeline job → Pipeline script from SCM → Git → your repo URL →
script path `Jenkinsfile`. Build with parameters, leaving `CHANGE_REF` empty for
now.

The first build is slow; it pulls six tool images. Watch for the digest printed
in the success banner.

**What the agent pod looks like and why.** Six containers, each doing one thing.
Builds run under Kaniko rather than a mounted Docker socket — a socket mount
hands every build root on the node, which is indefensible in a repo about
regulated controls. When someone asks how you build images in a locked-down
cluster, "Kaniko, no daemon, no privileged access" is the answer.

---

## Step 5 — enforcement

```bash
make kyverno-install
make kyverno-policies
```

Three policies land:

| Policy | What it rejects |
|---|---|
| `require-signed-images` | any node-monitor image without a valid signature from your key |
| `require-change-ref` | pods in qual/prod carrying the default `unset` change reference |
| `workload-baseline` | `:latest` tags, root containers, missing limits, undropped capabilities |

`mutateDigest: true` on the signature policy rewrites the tag to the digest it
just verified, so what gets scheduled is provably the artefact whose signature
was checked.

---

## Step 6 — prove it works

This is the part worth screenshotting.

```bash
make policy-demo
```

Tries to run an unsigned `nginx` in `node-monitor-dev`. Admission refuses it —
the request never reaches the scheduler.

Then deploy your signed image properly. Take the digest from the build output:

```bash
# in charts/node-monitor/values-dev.yaml
image:
  repository: <account>.dkr.ecr.eu-west-1.amazonaws.com/gxp/node-monitor
  digest: "sha256:..."
```

```bash
git commit -am "deploy signed build" && git push
make app-status
```

Argo CD syncs, Kyverno verifies, the pod starts. Nothing about that path
involved trusting anyone.

And verify by hand, the way an auditor would:

```bash
make verify-image IMAGE=<account>.dkr.ecr.eu-west-1.amazonaws.com/gxp/node-monitor@sha256:...
```

---

## Failure modes you will actually hit

**`no matching signatures`** — the policy's public key does not match the key
that signed. Check `platform/kyverno/cosign.pub` matches `.keys/cosign.pub`, and
that you pushed after `make cosign-keys`.

**`401 Unauthorized` from Kyverno** — the ECR token expired. It lasts 12 hours.
`make kyverno-refresh-creds`. On real EKS this would be IRSA; it is a gap, and
it is in the control matrix as one.

**Kaniko cannot push** — the `Registry auth` stage writes the token to a shared
`emptyDir`. If the token was minted more than 12 hours before the push, re-run
the build rather than debugging the layers.

**Trivy fails the build on a base-image CVE you cannot fix** — that is the gate
working. Either bump `python:3.12-slim` to a current digest, or, if the finding
genuinely has no fix, add a documented `.trivyignore` entry with an expiry date.
Never widen the severity filter; a gate you loosen under pressure is not a gate.

**Pod stuck `ImagePullBackOff` after the digest change** — the cluster needs its
own pull secret for a private registry. Create one in the workload namespace,
or push to ECR Public if you would rather the images be openly verifiable.

---

## What Phase 2 does not do

- The digest still reaches the values file by hand. Phase 3 automates the
  write-back, with an approval gate in front of it.
- Nothing is retained as evidence yet — the SBOM and scan report are Jenkins
  artefacts, which are mutable and expire. Phase 4 makes them a signed bundle in
  immutable storage.
- The base image is pinned by tag, not digest, so it can drift between the scan
  and a later rebuild. Worth fixing before Phase 3.
