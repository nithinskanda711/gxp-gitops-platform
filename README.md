# gxp-gitops-platform

A GitOps delivery platform for regulated environments, built to the constraint
that **every production change must be traceable, approved, and provably
unchanged since approval**.

In pharma manufacturing and retail banking this is normally satisfied with
Confluence pages, ticket numbers and screenshots pasted into a change record.
That evidence is manual, produced after the fact, and trusted rather than
verified. This repository takes the opposite approach: the controls are
technical, they run in the delivery path, and the evidence falls out of the
pipeline as a by-product of deploying.

The workload itself — a small Flask service exposing host metrics — is
deliberately uninteresting. The platform is the deliverable.

---

## Status

| Phase | Scope | State |
|-------|-------|-------|
| **1** | Terraform, Helm, Argo CD — app deploys via GitOps | **complete** |
| 2 | Supply chain: SBOM, scan, Cosign signing, Kyverno admission verification | planned |
| 3 | Promotion path: dev auto-sync, qual/prod gated, segregation of duties | planned |
| 4 | Evidence bundles signed and written to immutable S3 | planned |
| 5 | Prometheus/Grafana, DORA metrics, drift alerting | planned |

Phase 1 established the spine: the cluster reconciles to Git. Phase 2 makes the
*artefact* trustworthy — images are built without a Docker socket, scanned,
signed, and verified cryptographically at admission. See `docs/phase-2.md` for
the runbook.

---

## What Phase 1 gives you

- A **kind** cluster (or an EKS cluster) running Argo CD
- One Helm chart deployed to three namespaces from three value files
- An **AppProject** constraining which repos Argo CD may pull from and which
  namespaces it may write to
- **dev** self-heals automatically; **qual** and **prod** require a manual sync
- Pods that already run non-root, read-only-rootfs, with dropped capabilities
  and enforced resource limits
- Provenance (`version`, `environment`, `change_ref`) carried on the pod and
  exposed at `/metrics` — the hooks Phase 4 reads when building evidence

---

## Quick start (local, free)

Requires `docker`, `kind`, `kubectl`, `helm`, `make`. Runs entirely inside a
Linux VM or on Docker Desktop; no AWS account needed.

```bash
# 1. Point the manifests at your own fork, then commit and push.
#    Argo CD pulls from Git, so it must be able to see your repo.
make set-repo REPO=https://github.com/<you>/gxp-gitops-platform.git
git commit -am "point manifests at my fork" && git push

# 2. Build the image and stand up the cluster
make test          # unit tests
make cluster-up    # kind cluster + Argo CD + root Application
make load          # build node-monitor:0.1.0 and side-load it into kind

# 3. Look at it
make argocd-password
make argocd-ui     # https://localhost:8081, user: admin
make app-status
```

`make port-forward` then exposes the dev workload on <http://localhost:8080>.

Endpoints: `/` (JSON snapshot), `/healthz`, `/readyz`, `/metrics`.

> **Step 1 is not optional.** The bootstrap script refuses to run while the
> manifests still contain `REPLACE_ME`, because Argo CD would otherwise sit in
> a permanent `ComparisonError` against a repository that does not exist.

### Demonstrating the control

```bash
make drift-demo    # scale dev to 5 replicas by hand
watch kubectl -n node-monitor-dev get deploy
```

Argo CD reverts it within a minute. Do the same against `node-monitor-prod`
and the change **stays** — prod has `selfHeal` off in Phase 1 so that drift is
visible rather than silently corrected. Phase 5 turns self-heal on and fires an
alert instead, which is the behaviour you actually want in a validated system:
correct the drift *and* record that it happened.

---

## Quick start (AWS, chargeable)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # set `owner` at minimum
terraform init && terraform apply
$(terraform output -raw kubeconfig_command)
```

Then run `./local/bootstrap.sh` against the EKS context to install Argo CD.

**Set a billing alarm before you run this.** An EKS control plane bills per
hour whether or not you use it, and NAT gateways bill per hour plus per GB.
The intended pattern is create → demo → capture screenshots → `terraform
destroy` the same day.

Nodes default to **t4g** (Graviton/ARM64) so that images built on Apple Silicon
run natively with no `--platform` gymnastics and no QEMU emulation. If you
target x86 nodes instead, build with `make build-amd64`.

---

## Layout

```
app/                     Flask + psutil workload, Dockerfile, unit tests
charts/node-monitor/     one chart, values.yaml + values-{dev,qual,prod}.yaml
gitops/bootstrap/        AppProject and the app-of-apps root Application
gitops/apps/             one Argo CD Application per environment
infra/terraform/ecr/     the registry — cheap, always on
infra/terraform/eks/     the cluster — expensive, create and destroy same day
platform/jenkins/        controller config as code, Kaniko agent pod template
platform/kyverno/        admission policies and the release public key
Jenkinsfile              build → SBOM → scan → sign → verify
scripts/                 cosign key generation
local/                   kind cluster config and the bootstrap script
docs/control-matrix.md   each control, the risk it addresses, its current state
docs/phase-2.md          supply-chain runbook
```

`make help` lists every target.

---

## Design decisions worth defending

**One chart, three value files.** Separate charts per environment drift apart
and make a qual-to-prod diff unreviewable. With shared defaults, the diff
between two environments is only what genuinely differs — for this workload,
replica count and resource limits.

**Immutable ECR tags.** The evidence story in Phase 4 depends on a tag meaning
exactly one image forever. A mutable tag makes "we deployed 0.1.0" an
unverifiable claim.

**Non-root and read-only rootfs from commit one.** Phase 2 adds Kyverno
policies that reject pods without them. Retrofitting security context onto a
chart that already works is significantly more painful than starting there.

**The AppProject is a real control, not boilerplate.** Without it, anyone who
can create an Application in the `argocd` namespace can deploy anything from
anywhere to any namespace. Constraining `sourceRepos` and `destinations` is the
difference between GitOps and "a thing that applies YAML".

**Kaniko, not a mounted Docker socket.** Almost every Jenkins-on-Kubernetes
tutorial mounts `/var/run/docker.sock` into the build agent. That hands every
build root on the node. In a repository about regulated delivery it would be
the loudest thing in the diff.

**Signing happens after the scan, and signs the digest.** A signature can only
exist for an image that passed the gate, and a digest cannot be repointed the
way a tag can. Scanning one artefact and deploying another is the specific
failure this ordering prevents.

**`failurePolicy: Fail` on the signature policy.** If Kyverno cannot reach the
registry to check a signature, the pod is rejected. A verification control that
fails open is not a control.

---

## Known gaps

Documented rather than hidden — see `docs/control-matrix.md` for the full list.

- The EKS API endpoint is public. A real regulated cluster would be
  private-only, reached via bastion or VPN.
- Terraform state is local. A shared environment needs S3 plus DynamoDB
  locking.
- Argo CD RBAC roles are declared in the AppProject but not yet bound to real
  identities — that arrives with the Phase 3 SSO integration.
- Jenkins holds static AWS keys in a Secret. On real EKS this would be IRSA and
  there would be no long-lived credential to leak.
- The base image is pinned by tag rather than digest, so it can drift between a
  scan and a later rebuild.
- The verified digest still reaches the values file by hand. Phase 3 automates
  the write-back with an approval gate in front of it.
- SBOMs and scan reports are Jenkins artefacts — mutable and expiring. Phase 4
  turns them into signed bundles in immutable storage.
