# Control matrix

Each row is a risk, the control that addresses it, where that control is
implemented, and its honest current state. Rows marked *planned* are not
implemented yet — they are listed so the gap is visible rather than discovered.

## Change control

| # | Risk | Control | Implementation | State |
|---|------|---------|----------------|-------|
| CC-1 | Undocumented change reaches a cluster | All desired state lives in Git; the cluster reconciles to the commit | `gitops/apps/*.yaml` | Phase 1 |
| CC-2 | Manual `kubectl` edit diverges from the approved state | Argo CD detects drift; dev self-heals, prod surfaces it | `syncPolicy` in each Application | Phase 1 |
| CC-3 | Change deployed without an approved change reference | `release.changeRef` required on the pod; admission rejects `unset` | `platform/kyverno/policies/02-require-change-ref.yaml` | **Phase 2 — done** |
| CC-4 | Drift corrected silently, leaving no record | Self-heal enabled on prod *and* an alert on every heal event | Alertmanager rule | Phase 5 |

## Supply chain integrity

| # | Risk | Control | Implementation | State |
|---|------|---------|----------------|-------|
| SC-1 | Deployed image differs from the reviewed source | Image built once in CI, referenced by digest thereafter | `Jenkinsfile`, `charts/node-monitor` | **Phase 2 — done** |
| SC-2 | Unapproved image reaches the cluster | Cosign signature verified at admission; unsigned images rejected | `platform/kyverno/policies/01-require-signed-images.yaml` | **Phase 2 — done** |
| SC-3 | Tag reused to point at different content | ECR repository set to `IMMUTABLE` | `infra/terraform/main.tf` | Phase 1 |
| SC-4 | Unknown dependency content | SBOM generated per build with Syft, attested to the digest with Cosign | `Jenkinsfile` SBOM stage | **Phase 2 — done** |
| SC-5 | Known vulnerability shipped to prod | Trivy scan fails the build on CRITICAL, before any signature exists | `Jenkinsfile` scan stage | **Phase 2 — done** |
| SC-6 | Base image drifts between scan and deploy | Base image pinned by digest in the Dockerfile | `app/Dockerfile` | **gap** |
| SC-7 | A build escapes to the node and tampers with other workloads | Images built with Kaniko — no Docker socket, no privileged container | `platform/jenkins/values.yaml` | **Phase 2 — done** |
| SC-8 | Long-lived registry credentials leak from the build | ECR token minted per build into an `emptyDir`, valid 12 hours | `Jenkinsfile` registry auth stage | **Phase 2 — done** |

## Access and segregation of duties

| # | Risk | Control | Implementation | State |
|---|------|---------|----------------|-------|
| AC-1 | Argo CD pulls from an untrusted repository | `sourceRepos` restricted on the AppProject | `gitops/bootstrap/project.yaml` | Phase 1 |
| AC-2 | An Application deploys into an unintended namespace | `destinations` restricted on the AppProject | `gitops/bootstrap/project.yaml` | Phase 1 |
| AC-3 | Author of a change also approves it | PR approval required, plus a distinct Argo CD sync role for prod | Branch protection + `prod-syncer` role | Phase 3 |
| AC-4 | Argo CD roles not tied to real identity | SSO integration binding project roles to directory groups | Argo CD `dex` config | Phase 3 |
| AC-5 | Cluster API reachable from the internet | Private-only EKS endpoint behind a bastion or VPN | `infra/terraform/eks/main.tf` | **gap** |
| AC-6 | Static AWS keys held in a cluster Secret | IRSA, so the build assumes a role and holds no long-lived credential | — | **gap** |
| AC-7 | Kyverno's registry token expires and verification silently fails open | `failurePolicy: Fail` — an unverifiable image is rejected, not admitted | `01-require-signed-images.yaml` | **Phase 2 — done** |

## Workload security

| # | Risk | Control | Implementation | State |
|---|------|---------|----------------|-------|
| WL-1 | Container escape via root process | `runAsNonRoot`, UID 10001, enforced at admission | Chart + `03-pod-security.yaml` | **Phase 2 — enforced** |
| WL-2 | Runtime tampering with container filesystem | `readOnlyRootFilesystem`, writable `emptyDir` for `/tmp` only | `charts/node-monitor/values.yaml` | Phase 1 |
| WL-3 | Privilege escalation | `allowPrivilegeEscalation: false`, all capabilities dropped | `charts/node-monitor/values.yaml` | Phase 1 |
| WL-4 | Noisy neighbour exhausts a node | CPU and memory limits required on every container | Chart + `03-pod-security.yaml` | **Phase 2 — enforced** |
| WL-5 | Secrets committed to Git | External Secrets Operator sourcing from AWS Secrets Manager via IRSA | — | planned |

## Evidence and retention

| # | Risk | Control | Implementation | State |
|---|------|---------|----------------|-------|
| EV-1 | Cannot prove what ran on a given date | Signed release bundle per deploy: commit, digest, SBOM, scan, approver, timestamp | Evidence job | Phase 4 |
| EV-2 | Evidence altered after the fact | S3 Object Lock in compliance mode | `infra/terraform` | Phase 4 |
| EV-3 | Evidence cannot be independently checked | `verify.sh` re-validates a bundle from its hashes alone | `scripts/verify.sh` | Phase 4 |
| EV-4 | Terraform state lost or concurrently modified | Remote state in S3 with DynamoDB locking | `infra/terraform/*` | **gap** |

---

## How to use this table

In an interview, expect to be asked to pick one row and explain it end to end:
what the risk actually is, why this control addresses it, what it does *not*
cover, and how you would demonstrate to an auditor that it is working. Rows
marked **gap** are fair game and answering them honestly is stronger than
pretending the platform is complete.
