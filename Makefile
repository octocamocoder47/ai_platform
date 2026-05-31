# =============================================================================
# AI Platform Makefile
# =============================================================================

.PHONY: help bootstrap validate plan apply destroy lint config-generate docs

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

CONFIG ?= config/demo.yaml
ENV ?= dev

## === Bootstrap ===

bootstrap: ## One-command deploy: ./scripts/bootstrap.sh --config $(CONFIG) --env $(ENV)
	./scripts/bootstrap.sh --config $(CONFIG) --env $(ENV)

bootstrap-auto: ## Bootstrap with auto-approve
	./scripts/bootstrap.sh --config $(CONFIG) --env $(ENV) --auto-approve

## === Validation ===

validate: ## Validate config file
	python3 scripts/validate-config.py $(CONFIG)

config-generate: ## Generate config from YAML
	python3 terraform/scripts/generate-config.py $(CONFIG) --env $(ENV)

lint: ## Lint YAML files
	yamllint config/ platform/ ai/

## === Helm ===

helm-deps: ## Build Helm chart dependencies
	./scripts/build-charts.sh

helm-lint: ## Lint Helm charts
	helm lint charts/ai-platform/ $(shell find charts/ -name Chart.yaml -not -path "*/ai-platform/*" -exec dirname {} \;)

helm-dry-run: ## Dry run install
	helm install --dry-run --debug ai-platform ./charts/ai-platform --values charts/ai-platform/values.yaml

helm-install: helm-deps ## Install AI Platform via Helm
	helm install ai-platform ./charts/ai-platform --values charts/ai-platform/values.yaml

helm-upgrade: helm-deps ## Upgrade AI Platform
	helm upgrade ai-platform ./charts/ai-platform --values charts/ai-platform/values.yaml

helm-uninstall: ## Uninstall AI Platform
	helm uninstall ai-platform

helm-template: ## Render chart templates
	helm template ai-platform ./charts/ai-platform --values charts/ai-platform/values.yaml

## === Terraform ===

plan: ## Terraform plan
	cd terraform/envs/$(ENV) && terraform init -upgrade && terraform plan

apply: ## Terraform apply
	cd terraform/envs/$(ENV) && terraform init -upgrade && terraform apply

destroy: ## Terraform destroy
	cd terraform/envs/$(ENV) && terraform init -upgrade && terraform destroy

apply-all: ## Apply all Terraform in dependency order
	./terraform/scripts/apply-all.sh --env $(ENV) --auto-approve

## === Backend ===

backend-init: ## Initialize Terraform S3 backend
	cd terraform/bootstrap && terraform init -upgrade && terraform apply -auto-approve

## === Git ===

git-init: ## Initialize git repo
	git init
	git add .
	git commit -m "Initial commit: AI Platform Engineering project"

git-init-full: git-init ## Initialize and set up git hooks
	pre-commit install

## === Utility ===

dry-run: ## Dry run bootstrap (validate only, no changes)
	./scripts/bootstrap.sh --config $(CONFIG) --env $(ENV) --dry-run

docs: ## Serve docs locally
	python3 -m http.server 8080 -d docs/

tree: ## Show directory tree
	tree -d -I ".git|node_modules|__pycache__" --charset utf-8
