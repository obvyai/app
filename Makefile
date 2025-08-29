# AWS Image Generation Platform - Makefile
# Usage: make <target> ENV=<dev|stage|prod>

.PHONY: help bootstrap tf-init tf-plan tf-apply tf-destroy deploy-api deploy-frontend model-build model-push dev-setup lint typecheck test-unit test-integration test-e2e clean

# Default environment
ENV ?= dev

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Project configuration
PROJECT_NAME := obvy-imggen
AWS_REGION := us-east-1

help: ## Show this help message
	@echo "$(BLUE)AWS Image Generation Platform$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC) make <target> ENV=<dev|stage|prod>"
	@echo ""
	@echo "$(YELLOW)Targets:$(NC)"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Bootstrap the project (install dependencies, setup tools)
	@echo "$(BLUE)Bootstrapping project...$(NC)"
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Terraform not found. Please install Terraform >= 1.8$(NC)"; exit 1; }
	@command -v aws >/dev/null 2>&1 || { echo "$(RED)AWS CLI not found. Please install AWS CLI$(NC)"; exit 1; }
	@command -v docker >/dev/null 2>&1 || { echo "$(RED)Docker not found. Please install Docker$(NC)"; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "$(RED)Node.js not found. Please install Node.js >= 20$(NC)"; exit 1; }
	@echo "$(GREEN)Installing Node.js dependencies...$(NC)"
	@npm install
	@cd services/api && npm install
	@cd services/worker && npm install
	@cd apps/web && npm install
	@cd packages/shared && npm install
	@echo "$(GREEN)Bootstrap complete!$(NC)"

tf-init: ## Initialize Terraform
	@echo "$(BLUE)Initializing Terraform for $(ENV)...$(NC)"
	@cd infra/terraform && terraform init -backend-config="key=$(PROJECT_NAME)/$(ENV)/terraform.tfstate"
	@cd infra/terraform && terraform workspace select $(ENV) || terraform workspace new $(ENV)

tf-plan: ## Plan Terraform changes
	@echo "$(BLUE)Planning Terraform changes for $(ENV)...$(NC)"
	@cd infra/terraform && terraform plan -var-file="environments/$(ENV).tfvars" -out="$(ENV).tfplan"

tf-apply: ## Apply Terraform changes
	@echo "$(BLUE)Applying Terraform changes for $(ENV)...$(NC)"
	@cd infra/terraform && terraform apply "$(ENV).tfplan"
	@echo "$(GREEN)Infrastructure deployed successfully!$(NC)"

tf-destroy: ## Destroy Terraform infrastructure
	@echo "$(RED)WARNING: This will destroy all infrastructure for $(ENV)!$(NC)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
	@cd infra/terraform && terraform destroy -var-file="environments/$(ENV).tfvars"

model-build: ## Build SageMaker model container
	@echo "$(BLUE)Building SageMaker model container...$(NC)"
	@cd services/model && docker build -t $(PROJECT_NAME)-model:latest .
	@echo "$(GREEN)Model container built successfully!$(NC)"

model-push: ## Push model container to ECR
	@echo "$(BLUE)Pushing model container to ECR for $(ENV)...$(NC)"
	@$(eval ECR_URI := $(shell cd infra/terraform && terraform output -raw ecr_repository_uri 2>/dev/null || echo ""))
	@if [ -z "$(ECR_URI)" ]; then echo "$(RED)ECR repository URI not found. Run 'make tf-apply' first.$(NC)"; exit 1; fi
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_URI)
	@docker tag $(PROJECT_NAME)-model:latest $(ECR_URI):latest
	@docker push $(ECR_URI):latest
	@echo "$(GREEN)Model container pushed successfully!$(NC)"

deploy-api: ## Deploy API services
	@echo "$(BLUE)Deploying API services for $(ENV)...$(NC)"
	@cd services/api && npm run build
	@cd services/worker && npm run build
	@cd infra/terraform && terraform apply -target=module.api -target=module.callbacks -var-file="environments/$(ENV).tfvars" -auto-approve
	@echo "$(GREEN)API services deployed successfully!$(NC)"

deploy-frontend: ## Deploy frontend application
	@echo "$(BLUE)Deploying frontend for $(ENV)...$(NC)"
	@cd apps/web && npm run build
	@$(eval S3_BUCKET := $(shell cd infra/terraform && terraform output -raw frontend_bucket_name 2>/dev/null || echo ""))
	@$(eval CLOUDFRONT_ID := $(shell cd infra/terraform && terraform output -raw cloudfront_distribution_id 2>/dev/null || echo ""))
	@if [ -z "$(S3_BUCKET)" ]; then echo "$(RED)S3 bucket not found. Run 'make tf-apply' first.$(NC)"; exit 1; fi
	@aws s3 sync apps/web/out s3://$(S3_BUCKET) --delete
	@if [ -n "$(CLOUDFRONT_ID)" ]; then aws cloudfront create-invalidation --distribution-id $(CLOUDFRONT_ID) --paths "/*"; fi
	@echo "$(GREEN)Frontend deployed successfully!$(NC)"

dev-setup: ## Setup local development environment
	@echo "$(BLUE)Setting up local development environment...$(NC)"
	@cp dev/.env.example dev/.env.local
	@echo "$(YELLOW)Please edit dev/.env.local with your configuration$(NC)"
	@cd apps/web && npm run dev &
	@echo "$(GREEN)Development environment ready!$(NC)"

lint: ## Run linting
	@echo "$(BLUE)Running linting...$(NC)"
	@cd services/api && npm run lint
	@cd services/worker && npm run lint
	@cd apps/web && npm run lint
	@cd packages/shared && npm run lint
	@cd infra/terraform && terraform fmt -check -recursive
	@echo "$(GREEN)Linting complete!$(NC)"

typecheck: ## Run TypeScript type checking
	@echo "$(BLUE)Running type checking...$(NC)"
	@cd services/api && npm run typecheck
	@cd services/worker && npm run typecheck
	@cd apps/web && npm run typecheck
	@cd packages/shared && npm run typecheck
	@echo "$(GREEN)Type checking complete!$(NC)"

test-unit: ## Run unit tests
	@echo "$(BLUE)Running unit tests...$(NC)"
	@cd services/api && npm test
	@cd services/worker && npm test
	@cd apps/web && npm test
	@cd packages/shared && npm test
	@echo "$(GREEN)Unit tests complete!$(NC)"

test-integration: ## Run integration tests
	@echo "$(BLUE)Running integration tests...$(NC)"
	@cd services/api && npm run test:integration
	@echo "$(GREEN)Integration tests complete!$(NC)"

test-e2e: ## Run end-to-end tests
	@echo "$(BLUE)Running E2E tests for $(ENV)...$(NC)"
	@cd apps/web && npm run test:e2e
	@echo "$(GREEN)E2E tests complete!$(NC)"

seed-data: ## Seed test data
	@echo "$(BLUE)Seeding test data for $(ENV)...$(NC)"
	@cd dev && node seed-data.js $(ENV)
	@echo "$(GREEN)Test data seeded!$(NC)"

clean: ## Clean build artifacts
	@echo "$(BLUE)Cleaning build artifacts...$(NC)"
	@rm -rf services/api/dist
	@rm -rf services/worker/dist
	@rm -rf apps/web/.next
	@rm -rf apps/web/out
	@rm -rf packages/shared/dist
	@rm -f infra/terraform/*.tfplan
	@echo "$(GREEN)Clean complete!$(NC)"

# Infrastructure shortcuts
infra: tf-plan tf-apply ## Plan and apply infrastructure

deploy: deploy-api deploy-frontend ## Deploy all services

all: bootstrap infra model-build model-push deploy ## Bootstrap, deploy infrastructure and services

# Development shortcuts
dev: dev-setup ## Start development environment

check: lint typecheck test-unit ## Run all checks

# Utility targets
outputs: ## Show Terraform outputs
	@cd infra/terraform && terraform output

logs-api: ## Tail API Lambda logs
	@aws logs tail /aws/lambda/$(PROJECT_NAME)-$(ENV)-submit-job --follow

logs-callback: ## Tail callback Lambda logs
	@aws logs tail /aws/lambda/$(PROJECT_NAME)-$(ENV)-callback --follow

logs-sagemaker: ## Tail SageMaker endpoint logs
	@aws logs tail /aws/sagemaker/Endpoints/$(PROJECT_NAME)-$(ENV)-async --follow

status: ## Show deployment status
	@echo "$(BLUE)Deployment Status for $(ENV):$(NC)"
	@cd infra/terraform && terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'