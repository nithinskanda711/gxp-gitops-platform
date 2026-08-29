CLUSTER      ?= gxp
IMAGE        ?= node-monitor
TAG          ?= 0.1.0
REPO         ?=

.DEFAULT_GOAL := help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

set-repo: ## Point every manifest at your fork: make set-repo REPO=https://github.com/you/repo.git
	@test -n "$(REPO)" || { echo "usage: make set-repo REPO=https://github.com/you/repo.git"; exit 1; }
	@grep -rl "REPLACE_ME" gitops | xargs sed -i.bak "s|https://github.com/REPLACE_ME/gxp-gitops-platform.git|$(REPO)|g"
	@find gitops -name '*.bak' -delete
	@echo "manifests now point at $(REPO) - commit and push before bootstrapping"

test: ## Run the application unit tests
	cd app && python -m pytest tests -q

build: ## Build the container image for the local architecture
	docker build -t $(IMAGE):$(TAG) app

build-amd64: ## Build an x86_64 image (needed when the target cluster is not ARM)
	docker buildx build --platform linux/amd64 -t $(IMAGE):$(TAG) app

load: build ## Build and side-load the image into the kind cluster
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

cluster-up: ## Create the kind cluster and install Argo CD
	./local/bootstrap.sh

argocd-password: ## Print the initial Argo CD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' | base64 -d; echo

argocd-ui: ## Forward the Argo CD UI to https://localhost:8081
	kubectl -n argocd port-forward svc/argocd-server 8081:443

lint: ## Lint and render the Helm chart for all three environments
	helm lint charts/node-monitor -f charts/node-monitor/values.yaml -f charts/node-monitor/values-dev.yaml
	@for env in dev qual prod; do \
		echo "--- rendering $$env ---"; \
		helm template node-monitor charts/node-monitor \
			-f charts/node-monitor/values.yaml \
			-f charts/node-monitor/values-$$env.yaml >/dev/null || exit 1; \
	done
	@echo "all environments render cleanly"

app-status: ## Show sync and health status of every Argo CD Application
	kubectl -n argocd get applications.argoproj.io -o wide

port-forward: ## Forward the dev workload to http://localhost:8080
	kubectl -n node-monitor-dev port-forward svc/node-monitor-dev-node-monitor 8080:80

drift-demo: ## Scale dev by hand and watch Argo CD put it back
	kubectl -n node-monitor-dev scale deploy/node-monitor-dev-node-monitor --replicas=5
	@echo "now run: watch kubectl -n node-monitor-dev get deploy"

cluster-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

# ---------------------------------------------------------------------------
# Phase 2 - supply chain
# ---------------------------------------------------------------------------

ecr-init: ## terraform init/plan for the ECR stack only (never touches EKS)
	cd infra/terraform/ecr && terraform init && terraform plan

ecr-apply: ## Create the ECR repository. Run `make ecr-init` and read the plan first.
	cd infra/terraform/ecr && terraform apply

ecr-url: ## Print the repository URL
	@cd infra/terraform/ecr && terraform output -raw repository_url && echo

cosign-keys: ## Generate the release signing key pair (needs COSIGN_PASSWORD set)
	./scripts/cosign-keygen.sh

jenkins-install: ## Install Jenkins into the cluster
	./platform/jenkins/install.sh

jenkins-ui: ## Forward Jenkins to http://localhost:8082
	kubectl -n jenkins port-forward svc/jenkins 8082:8080

jenkins-password: ## Print the Jenkins admin password
	@kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d; echo

kyverno-install: ## Install Kyverno and apply the platform policies
	./platform/kyverno/install.sh

kyverno-policies: ## Re-apply the policies after an edit
	kubectl apply -f platform/kyverno/policies/
	kubectl get clusterpolicies.kyverno.io

kyverno-refresh-creds: ## Refresh the 12-hour ECR token Kyverno uses to fetch signatures
	@kubectl -n kyverno create secret docker-registry ecr-creds \
		--docker-server="$$(cd infra/terraform/ecr && terraform output -raw repository_url | cut -d/ -f1)" \
		--docker-username=AWS \
		--docker-password="$$(aws ecr get-login-password --region eu-west-1)" \
		--dry-run=client -o yaml | kubectl apply -f -
	@kubectl -n kyverno rollout restart deploy/kyverno-admission-controller

policy-demo: ## Try to deploy an unsigned image and watch admission reject it
	@echo "==> attempting to run an unsigned nginx in node-monitor-dev"
	@kubectl -n node-monitor-dev run rogue --image=nginx:1.27 --restart=Never 2>&1 | head -20 || true
	@echo
	@echo "The request never reached the scheduler. That is the control working."

verify-image: ## Verify a signed image by hand: make verify-image IMAGE=<full-ref>
	@test -n "$(IMAGE)" || { echo "usage: make verify-image IMAGE=<account>.dkr.ecr.<region>.amazonaws.com/gxp/node-monitor@sha256:..."; exit 1; }
	cosign verify --key .keys/cosign.pub $(IMAGE)

.PHONY: help set-repo test build build-amd64 load cluster-up argocd-password argocd-ui lint app-status port-forward drift-demo cluster-down \
	ecr-init ecr-apply ecr-url cosign-keys jenkins-install jenkins-ui jenkins-password \
	kyverno-install kyverno-policies kyverno-refresh-creds policy-demo verify-image
