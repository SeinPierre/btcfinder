# Bitcoin Address Matcher - Makefile
# Author: Bitcoin Matcher Team
# Description: Build, test, and deployment automation

# ============================================================================
# Configuration
# ============================================================================

# Project configuration
PROJECT_NAME := bitcoin-address-matcher
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")

# Environment configuration
ENV ?= dev
AWS_REGION ?= us-east-1
DOCKER_REGISTRY ?= ghcr.io
DOCKER_IMAGE := $(DOCKER_REGISTRY)/$(shell echo $(PROJECT_NAME) | tr '[:upper:]' '[:lower:]')

# Rust configuration
CARGO_TARGET_DIR ?= target
RUST_BACKTRACE ?= 1
RUST_LOG ?= info

# Terraform configuration
TF_VAR_environment := $(ENV)
TF_VAR_aws_region := $(AWS_REGION)
TF_VAR_project_name := $(PROJECT_NAME)

# Build flags
CARGO_BUILD_FLAGS := --release
DOCKER_BUILD_FLAGS := --pull --no-cache
TERRAFORM_FLAGS := -auto-approve

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
PURPLE := \033[0;35m
CYAN := \033[0;36m
WHITE := \033[1;37m
NC := \033[0m # No Color

# ============================================================================
# Help
# ============================================================================

.PHONY: help
help: ## Display this help message
	@echo "$(CYAN)Bitcoin Address Matcher - Build System$(NC)"
	@echo "$(CYAN)=====================================$(NC)"
	@echo ""
	@echo "$(WHITE)Available targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(WHITE)Environment Variables:$(NC)"
	@echo "  $(YELLOW)ENV$(NC)             Environment (dev/staging/prod) [$(ENV)]"
	@echo "  $(YELLOW)AWS_REGION$(NC)      AWS Region [$(AWS_REGION)]"
	@echo "  $(YELLOW)DOCKER_REGISTRY$(NC) Docker registry [$(DOCKER_REGISTRY)]"
	@echo ""
	@echo "$(WHITE)Examples:$(NC)"
	@echo "  make build"
	@echo "  make test"
	@echo "  make deploy ENV=staging"
	@echo "  make docker-build"

# ============================================================================
# Prerequisites Check
# ============================================================================

.PHONY: check-prereqs
check-prereqs: ## Check if all required tools are installed
	@echo "$(BLUE)Checking prerequisites...$(NC)"
	@command -v rustc >/dev/null 2>&1 || { echo "$(RED)Error: Rust is not installed$(NC)"; exit 1; }
	@command -v cargo >/dev/null 2>&1 || { echo "$(RED)Error: Cargo is not installed$(NC)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)Error: Docker is not installed$(NC)"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Error: Terraform is not installed$(NC)"; exit 1; }
	@command -v aws >/dev/null 2>&1 || { echo "$(RED)Error: AWS CLI is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ All prerequisites are installed$(NC)"

.PHONY: check-aws
check-aws: ## Check AWS credentials and connectivity
	@echo "$(BLUE)Checking AWS credentials...$(NC)"
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo "$(RED)Error: AWS credentials not configured$(NC)"; exit 1; }
	@echo "$(GREEN)✓ AWS credentials are configured$(NC)"

# ============================================================================
# Rust Build & Test
# ============================================================================

.PHONY: clean
clean: ## Clean build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	cargo clean
	rm -rf target/
	rm -f *.log
	@echo "$(GREEN)✓ Clean complete$(NC)"

.PHONY: fmt
fmt: ## Format Rust code
	@echo "$(BLUE)Formatting Rust code...$(NC)"
	cargo fmt --all
	@echo "$(GREEN)✓ Code formatted$(NC)"

.PHONY: fmt-check
fmt-check: ## Check Rust code formatting
	@echo "$(BLUE)Checking Rust code formatting...$(NC)"
	cargo fmt --all -- --check
	@echo "$(GREEN)✓ Code formatting is correct$(NC)"

.PHONY: clippy
clippy: ## Run Clippy linter
	@echo "$(BLUE)Running Clippy...$(NC)"
	cargo clippy --all-targets --all-features -- -D warnings
	@echo "$(GREEN)✓ Clippy checks passed$(NC)"

.PHONY: build
build: ## Build the Rust application
	@echo "$(BLUE)Building Rust application...$(NC)"
	RUST_BACKTRACE=$(RUST_BACKTRACE) cargo build $(CARGO_BUILD_FLAGS)
	@echo "$(GREEN)✓ Build complete$(NC)"

.PHONY: build-debug
build-debug: ## Build debug version
	@echo "$(BLUE)Building debug version...$(NC)"
	RUST_BACKTRACE=$(RUST_BACKTRACE) cargo build
	@echo "$(GREEN)✓ Debug build complete$(NC)"

.PHONY: test
test: ## Run all tests
	@echo "$(BLUE)Running tests...$(NC)"
	RUST_BACKTRACE=$(RUST_BACKTRACE) cargo test --all-features --verbose
	@echo "$(GREEN)✓ All tests passed$(NC)"

.PHONY: test-unit
test-unit: ## Run unit tests only
	@echo "$(BLUE)Running unit tests...$(NC)"
	RUST_BACKTRACE=$(RUST_BACKTRACE) cargo test --lib --verbose
	@echo "$(GREEN)✓ Unit tests passed$(NC)"

.PHONY: test-integration
test-integration: ## Run integration tests only
	@echo "$(BLUE)Running integration tests...$(NC)"
	RUST_BACKTRACE=$(RUST_BACKTRACE) cargo test --test integration_tests --verbose
	@echo "$(GREEN)✓ Integration tests passed$(NC)"

.PHONY: bench
bench: ## Run benchmarks
	@echo "$(BLUE)Running benchmarks...$(NC)"
	cargo bench
	@echo "$(GREEN)✓ Benchmarks complete$(NC)"

.PHONY: coverage
coverage: ## Generate test coverage report
	@echo "$(BLUE)Generating test coverage...$(NC)"
	@command -v cargo-tarpaulin >/dev/null 2>&1 || cargo install cargo-tarpaulin
	cargo tarpaulin --verbose --all-features --workspace --timeout 120 --out html --output-dir target/coverage/
	@echo "$(GREEN)✓ Coverage report generated in target/coverage/$(NC)"

.PHONY: audit
audit: ## Run security audit
	@echo "$(BLUE)Running security audit...$(NC)"
	@command -v cargo-audit >/dev/null 2>&1 || cargo install cargo-audit
	cargo audit
	@echo "$(GREEN)✓ Security audit passed$(NC)"

.PHONY: deny
deny: ## Run cargo deny checks
	@echo "$(BLUE)Running cargo deny checks...$(NC)"
	@command -v cargo-deny >/dev/null 2>&1 || cargo install cargo-deny
	cargo deny check
	@echo "$(GREEN)✓ Cargo deny checks passed$(NC)"

# ============================================================================
# Docker Operations
# ============================================================================

.PHONY: docker-build
docker-build: ## Build Docker image
	@echo "$(BLUE)Building Docker image...$(NC)"
	docker build $(DOCKER_BUILD_FLAGS) \
		--build-arg VERSION=$(VERSION) \
		--build-arg COMMIT_SHA=$(COMMIT_SHA) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		-t $(PROJECT_NAME):latest \
		-t $(PROJECT_NAME):$(VERSION) \
		.
	@echo "$(GREEN)✓ Docker image built$(NC)"

.PHONY: docker-test
docker-test: docker-build ## Test Docker image
	@echo "$(BLUE)Testing Docker image...$(NC)"
	docker run --rm $(PROJECT_NAME):latest --help
	@echo "$(GREEN)✓ Docker image test passed$(NC)"

.PHONY: docker-scan
docker-scan: docker-build ## Scan Docker image for vulnerabilities
	@echo "$(BLUE)Scanning Docker image for vulnerabilities...$(NC)"
	@command -v trivy >/dev/null 2>&1 || { echo "$(YELLOW)Warning: trivy not installed, skipping scan$(NC)"; exit 0; }
	trivy image $(PROJECT_NAME):latest
	@echo "$(GREEN)✓ Docker image scan complete$(NC)"

.PHONY: docker-push
docker-push: docker-build check-aws ## Push Docker image to registry
	@echo "$(BLUE)Pushing Docker image to registry...$(NC)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(shell terraform output -raw ecr_repository_url 2>/dev/null || echo "$(DOCKER_REGISTRY)")
	docker tag $(PROJECT_NAME):latest $(DOCKER_IMAGE):latest
	docker tag $(PROJECT_NAME):latest $(DOCKER_IMAGE):$(VERSION)
	docker push $(DOCKER_IMAGE):latest
	docker push $(DOCKER_IMAGE):$(VERSION)
	@echo "$(GREEN)✓ Docker image pushed$(NC)"

.PHONY: docker-run-local
docker-run-local: docker-build ## Run Docker container locally
	@echo "$(BLUE)Running Docker container locally...$(NC)"
	docker run --rm -it \
		-e RUST_LOG=$(RUST_LOG) \
		-e BUCKET_NAME=test-bucket \
		-e THREADS=2 \
		-e BATCH_SIZE=100 \
		-e NETWORK=testnet \
		-v ~/.aws:/home/appuser/.aws:ro \
		$(PROJECT_NAME):latest

# ============================================================================
# Terraform Operations
# ============================================================================

.PHONY: tf-fmt
tf-fmt: ## Format Terraform code
	@echo "$(BLUE)Formatting Terraform code...$(NC)"
	terraform fmt -recursive
	@echo "$(GREEN)✓ Terraform code formatted$(NC)"

.PHONY: tf-fmt-check
tf-fmt-check: ## Check Terraform formatting
	@echo "$(BLUE)Checking Terraform formatting...$(NC)"
	terraform fmt -check -recursive
	@echo "$(GREEN)✓ Terraform formatting is correct$(NC)"

.PHONY: tf-init
tf-init: check-aws ## Initialize Terraform
	@echo "$(BLUE)Initializing Terraform...$(NC)"
	terraform init -upgrade
	@echo "$(GREEN)✓ Terraform initialized$(NC)"

.PHONY: tf-validate
tf-validate: tf-init ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(NC)"
	terraform validate
	@echo "$(GREEN)✓ Terraform configuration is valid$(NC)"

.PHONY: tf-plan
tf-plan: tf-validate ## Plan Terraform changes
	@echo "$(BLUE)Planning Terraform changes for $(ENV)...$(NC)"
	terraform workspace select $(ENV) || terraform workspace new $(ENV)
	terraform plan \
		-var="environment=$(ENV)" \
		-var="aws_region=$(AWS_REGION)" \
		-var="project_name=$(PROJECT_NAME)" \
		-out=tfplan-$(ENV)
	@echo "$(GREEN)✓ Terraform plan created$(NC)"

.PHONY: tf-apply
tf-apply: tf-plan ## Apply Terraform changes
	@echo "$(BLUE)Applying Terraform changes for $(ENV)...$(NC)"
	terraform apply tfplan-$(ENV)
	@echo "$(GREEN)✓ Terraform changes applied$(NC)"

.PHONY: tf-destroy
tf-destroy: tf-init ## Destroy Terraform infrastructure
	@echo "$(RED)WARNING: This will destroy all infrastructure for $(ENV)!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		terraform workspace select $(ENV); \
		terraform destroy \
			-var="environment=$(ENV)" \
			-var="aws_region=$(AWS_REGION)" \
			-var="project_name=$(PROJECT_NAME)" \
			$(TERRAFORM_FLAGS); \
	else \
		echo "$(YELLOW)Destroy cancelled$(NC)"; \
	fi

.PHONY: tf-output
tf-output: ## Show Terraform outputs
	@echo "$(BLUE)Terraform outputs for $(ENV):$(NC)"
	terraform workspace select $(ENV)
	terraform output

.PHONY: tf-lint
tf-lint: ## Lint Terraform code with tflint
	@echo "$(BLUE)Linting Terraform code...$(NC)"
	@command -v tflint >/dev/null 2>&1 || { echo "$(YELLOW)Warning: tflint not installed, skipping$(NC)"; exit 0; }
	tflint --init
	tflint
	@echo "$(GREEN)✓ Terraform linting complete$(NC)"

.PHONY: tf-security
tf-security: ## Run Terraform security scan
	@echo "$(BLUE)Running Terraform security scan...$(NC)"
	@command -v tfsec >/dev/null 2>&1 || { echo "$(YELLOW)Warning: tfsec not installed, skipping$(NC)"; exit 0; }
	tfsec .
	@echo "$(GREEN)✓ Terraform security scan complete$(NC)"

# ============================================================================
# Deployment Operations
# ============================================================================

.PHONY: deploy-infra
deploy-infra: tf-apply ## Deploy infrastructure only
	@echo "$(GREEN)✓ Infrastructure deployed for $(ENV)$(NC)"

.PHONY: deploy-app
deploy-app: docker-push ## Deploy application only
	@echo "$(BLUE)Deploying application for $(ENV)...$(NC)"
	$(eval CLUSTER_NAME := $(shell terraform output -raw ecs_cluster_name))
	$(eval SERVICE_NAME := $(shell terraform output -raw ecs_service_name))
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--force-new-deployment \
		--region $(AWS_REGION)
	@echo "$(GREEN)✓ Application deployed for $(ENV)$(NC)"

.PHONY: deploy
deploy: build test docker-build tf-apply deploy-app ## Full deployment (infra + app)
	@echo "$(GREEN)✓ Full deployment complete for $(ENV)$(NC)"

.PHONY: deploy-staging
deploy-staging: ## Deploy to staging environment
	@$(MAKE) deploy ENV=staging

.PHONY: deploy-prod
deploy-prod: ## Deploy to production environment
	@echo "$(RED)WARNING: Deploying to production!$(NC)"
	@read -p "Are you sure you want to deploy to production? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(MAKE) deploy ENV=prod; \
	else \
		echo "$(YELLOW)Production deployment cancelled$(NC)"; \
	fi

.PHONY: rollback
rollback: ## Rollback to previous deployment
	@echo "$(BLUE)Rolling back $(ENV) deployment...$(NC)"
	$(eval CLUSTER_NAME := $(shell terraform output -raw ecs_cluster_name))
	$(eval SERVICE_NAME := $(shell terraform output -raw ecs_service_name))
	@read -p "Enter the task definition revision to rollback to: " REVISION; \
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--task-definition $(PROJECT_NAME)-$(ENV):$$REVISION \
		--region $(AWS_REGION)
	@echo "$(GREEN)✓ Rollback complete$(NC)"

# ============================================================================
# Monitoring & Operations
# ============================================================================

.PHONY: logs
logs: ## Show application logs
	@echo "$(BLUE)Showing logs for $(ENV)...$(NC)"
	aws logs tail /ecs/$(PROJECT_NAME)-$(ENV) --follow --region $(AWS_REGION)

.PHONY: logs-recent
logs-recent: ## Show recent application logs
	@echo "$(BLUE)Showing recent logs for $(ENV)...$(NC)"
	aws logs tail /ecs/$(PROJECT_NAME)-$(ENV) --since 1h --region $(AWS_REGION)

.PHONY: status
status: ## Show deployment status
	@echo "$(BLUE)Deployment status for $(ENV):$(NC)"
	$(eval CLUSTER_NAME := $(shell terraform output -raw ecs_cluster_name))
	$(eval SERVICE_NAME := $(shell terraform output -raw ecs_service_name))
	aws ecs describe-services \
		--cluster $(CLUSTER_NAME) \
		--services $(SERVICE_NAME) \
		--region $(AWS_REGION) \
		--query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}'

.PHONY: scale
scale: ## Scale ECS service (usage: make scale REPLICAS=3)
	@echo "$(BLUE)Scaling $(ENV) to $(REPLICAS) replicas...$(NC)"
	$(eval CLUSTER_NAME := $(shell terraform output -raw ecs_cluster_name))
	$(eval SERVICE_NAME := $(shell terraform output -raw ecs_service_name))
	aws ecs update-service \
		--cluster $(CLUSTER_NAME) \
		--service $(SERVICE_NAME) \
		--desired-count $(REPLICAS) \
		--region $(AWS_REGION)
	@echo "$(GREEN)✓ Scaling complete$(NC)"

.PHONY: stop
stop: ## Stop all running tasks
	@$(MAKE) scale REPLICAS=0

.PHONY: start
start: ## Start service with 1 replica
	@$(MAKE) scale REPLICAS=1

# ============================================================================
# Development Helpers
# ============================================================================

.PHONY: dev-setup
dev-setup: check-prereqs ## Set up development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	rustup component add rustfmt clippy
	cargo install cargo-tarpaulin cargo-audit cargo-deny
	@echo "$(GREEN)✓ Development environment setup complete$(NC)"

.PHONY: upload-test-data
upload-test-data: check-aws ## Upload test addresses to S3
	@echo "$(BLUE)Uploading test data to S3...$(NC)"
	$(eval BUCKET_NAME := $(shell terraform output -raw s3_bucket_name))
	@echo "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa" > test_addresses.txt
	@echo "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy" >> test_addresses.txt
	@echo "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" >> test_addresses.txt
	aws s3 cp test_addresses.txt s3://$(BUCKET_NAME)/bitcoin_addresses.txt
	rm test_addresses.txt
	@echo "$(GREEN)✓ Test data uploaded$(NC)"

.PHONY: local-run
local-run: build ## Run application locally with test parameters
	@echo "$(BLUE)Running application locally...$(NC)"
	RUST_LOG=$(RUST_LOG) \
	BUCKET_NAME=dummy \
	./target/release/bitcoin-matcher \
		--bucket test-bucket \
		--threads 2 \
		--batch-size 100 \
		--network testnet \
		--report-interval 5

.PHONY: watch
watch: ## Watch for changes and rebuild
	@echo "$(BLUE)Watching for changes...$(NC)"
	@command -v cargo-watch >/dev/null 2>&1 || cargo install cargo-watch
	cargo watch -x 'build' -x 'test'

# ============================================================================
# CI/CD Helpers
# ============================================================================

.PHONY: ci-build
ci-build: fmt-check clippy test build ## CI build pipeline
	@echo "$(GREEN)✓ CI build pipeline complete$(NC)"

.PHONY: ci-test
ci-test: test coverage audit deny ## CI test pipeline
	@echo "$(GREEN)✓ CI test pipeline complete$(NC)"

.PHONY: ci-docker
ci-docker: docker-build docker-test docker-scan ## CI Docker pipeline
	@echo "$(GREEN)✓ CI Docker pipeline complete$(NC)"

.PHONY: ci-terraform
ci-terraform: tf-fmt-check tf-validate tf-lint tf-security ## CI Terraform pipeline
	@echo "$(GREEN)✓ CI Terraform pipeline complete$(NC)"

.PHONY: ci-full
ci-full: ci-build ci-test ci-docker ci-terraform ## Full CI pipeline
	@echo "$(GREEN)✓ Full CI pipeline complete$(NC)"

# ============================================================================
# Utilities
# ============================================================================

.PHONY: version
version: ## Show version information
	@echo "$(CYAN)Project Information:$(NC)"
	@echo "  Project: $(PROJECT_NAME)"
	@echo "  Version: $(VERSION)"
	@echo "  Commit:  $(COMMIT_SHA)"
	@echo "  Built:   $(BUILD_DATE)"
	@echo "  Env:     $(ENV)"
	@echo "  Region:  $(AWS_REGION)"

.PHONY: info
info: version ## Show detailed project information
	@echo ""
	@echo "$(CYAN)Build Information:$(NC)"
	@rustc --version 2>/dev/null || echo "  Rust: Not installed"
	@cargo --version 2>/dev/null || echo "  Cargo: Not installed"
	@docker --version 2>/dev/null || echo "  Docker: Not installed"
	@terraform --version 2>/dev/null | head -1 || echo "  Terraform: Not installed"
	@aws --version 2>/dev/null || echo "  AWS CLI: Not installed"

.PHONY: clean-all
clean-all: clean ## Clean everything including Docker
	@echo "$(BLUE)Cleaning all artifacts...$(NC)"
	docker system prune -f
	rm -f tfplan-*
	rm -rf .terraform/
	@echo "$(GREEN)✓ All artifacts cleaned$(NC)"

# ============================================================================
# Default target
# ============================================================================

.DEFAULT_GOAL := help

# Make variables available to sub-processes
export