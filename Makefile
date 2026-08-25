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

.PHONY: help set-repo test build build-amd64 load cluster-up argocd-password argocd-ui lint app-status port-forward drift-demo cluster-down
