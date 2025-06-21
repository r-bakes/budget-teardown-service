AWS_STACK         := budget-teardown-service
AWS_BUCKET        := organization-deployment-artifacts
AWS_REGION        := us-east-1
BUDGET_LIMIT      := 20
BUDGET_THRESHOLD  := 80
CF_TEMPLATE       := infrastructure/budget-teardown-service.yaml

SERVICES_DIR      := services
BUILD_DIR         := build

AWSCLI            := aws

# ---- INTERNAL HELPER VARIABLES ----

# Find all service directories under SERVICES_DIR (only first-level dirs)
SERVICE_PATHS     := $(wildcard $(SERVICES_DIR)/*)
SERVICE_NAMES     := $(notdir $(SERVICE_PATHS))
# Get the git SHA to increment the version of the lambdas. 
GIT_SHA 					:= $(shell git rev-parse --short HEAD)

# ---- PHONY TARGETS ----
.PHONY: help sync install test clean package-all upload-all deploy do-deploy 

help:
	@echo "Makefile targets:"
	@echo "  make sync                # uv sync --all-packages --dev"
	@echo "  make install             # uv pip install -r requirements.txt"
	@echo "  make test                # uv run pytest"
	@echo "  make clean               # Remove build artifacts"
	@echo "  make deploy              # Package, upload, and deploy the entire app."

sync:
	@echo "Running uv sync --all-packages --dev"
	uv sync --all-packages --dev

install:
	@echo "Installing requirements.txt in uv venv"
	uv pip install -r requirements.txt

test:
	@echo "Running pytest"
	uv run pytest

deploy: do-deploy

# ---- HELPER TARGETS ----

# 1. Clean build artifacts
clean:
	@echo "Cleaning build artifacts under $(BUILD_DIR)..."
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)
	@echo "Cleaned."

# 2. Package all services
# Zip the service code: assumes code folder is services/<service>/<service>/
package-all: clean
	@if [ -z "$(SERVICE_NAMES)" ]; then \
	  echo "Error: no services under $(SERVICES_DIR)"; exit 1; \
	fi
	@echo "Found services: $(SERVICE_NAMES)"
	@for service in $(SERVICE_NAMES); do \
	  echo "Building $$service via scripts/build.sh"; \
	  ./scripts/build.sh $$service; \
	done
	@echo "All services packaged."


# 3. Upload all service ZIPs to S3
upload-all: package-all
	@echo "Uploading packages to s3://$(AWS_BUCKET)/"
	@for service in $(SERVICE_NAMES); do \
	  ZIP_FILE="$(BUILD_DIR)/$$service.zip"; \
	  if [ ! -f $$ZIP_FILE ]; then \
	    echo "    Error: $$ZIP_FILE not found. Run make package-all first."; exit 1; \
	  fi; \
	  S3_KEY="$${service}_$(GIT_SHA).zip"; \
	  echo "  Uploading $$service: $$ZIP_FILE -> s3://$(AWS_BUCKET)/$$S3_KEY"; \
	  $(AWSCLI) s3 cp $$ZIP_FILE s3://$(AWS_BUCKET)/$$S3_KEY; \
	done
	@echo "All service packages uploaded."


# 5. Deploy single stack containing all services
do-deploy: upload-all
	@echo "Deploying CloudFormation stack '$(AWS_STACK)' in region $(AWS_REGION)..."
	$(AWSCLI) cloudformation deploy \
	  --template-file $(CF_TEMPLATE) \
	  --stack-name $(AWS_STACK) \
	  --capabilities CAPABILITY_NAMED_IAM \
	  --region $(AWS_REGION) \
	  --parameter-overrides \
	    DeploymentArtifactsBucket=$(AWS_BUCKET) \
	    BudgetLimit=$(BUDGET_LIMIT) \
	    BudgetThresholdPercentage=$(BUDGET_THRESHOLD) \
			LambdaCodeVersion=$(GIT_SHA)
	@echo "Purging deployment artifacts from S3 bucket $(AWS_BUCKET)..."
	$(AWSCLI) s3 rm s3://$(AWS_BUCKET) --recursive
	@echo "Deployment of stack '$(AWS_STACK)' complete."

