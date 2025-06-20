# ---- CONFIG  ----
AWS_STACK         := budget-teardown-service
AWS_BUCKET        := organization-deployment-artifacts
AWS_REGION        := us-east-1
BUDGET_LIMIT      := 20
BUDGET_THRESHOLD  := 80
CF_TEMPLATE       := infrastructure/budget-teardown-service.yaml

SERVICES_DIR      := services
BUILD_DIR         := build

# AWS CLI commands
AWSCLI            := aws

# ---- INTERNAL HELPER VARIABLES ----

# Find all service directories under SERVICES_DIR (only first-level dirs)
SERVICE_PATHS     := $(wildcard $(SERVICES_DIR)/*)
SERVICE_NAMES     := $(notdir $(SERVICE_PATHS))

# Given a service name, define its BUILD_DIR and ZIP and S3 key
# BUILD_DIR per service: build/<service_name>
define BUILD_DIR_for
$(BUILD_DIR)/$(1)
endef

# ZIP file path: build/<service_name>/<service_name>.zip
define ZIP_FILE_for
$(call BUILD_DIR_for,$(1))/$(1).zip
endef

# S3 key: "<service_name>.zip"
define S3_KEY_for
$(1).zip
endef

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
	  echo "Error: no services found under '$(SERVICES_DIR)'"; \
	  exit 1; \
	fi
	@echo "Found services: [$(SERVICE_NAMES)]"
	@echo "Packaging services under '$(SERVICES_DIR)/'..."
	@for service in $(SERVICE_NAMES); do \
		echo "  Packaging $$service..."; \
	  BUILD_SUBDIR="$(BUILD_DIR)/$$service"; \
	  echo "    BUILD_SUBDIR: $$BUILD_SUBDIR"; \
	  mkdir -p "$$BUILD_SUBDIR"; \
	  ZIP_FILE="$$BUILD_SUBDIR/$$service.zip"; \
	  echo "    ZIP_FILE: $$ZIP_FILE"; \
	  SERVICE_PATH="$(SERVICES_DIR)/$$service"; \
	  echo "    SERVICE_PATH: $$SERVICE_PATH"; \
	  if [ ! -d "$$SERVICE_PATH" ]; then \
	    echo "    Error: directory $$SERVICE_PATH not found."; \
	    exit 1; \
	  fi; \
	  rm -f "$$ZIP_FILE"; \
	  cd "$$SERVICE_PATH" && zip -r "$$OLDPWD/$$ZIP_FILE" "$$service" > /dev/null 2>&1; \
	  echo "    Created $$ZIP_FILE"; \
	done
	@echo "All services packaged."


# 3. Upload all service ZIPs to S3
upload-all: package-all
	@echo "Uploading packages to s3://$(AWS_BUCKET)/"
	@for service in $(SERVICE_NAMES); do \
	  ZIP_FILE=$(call ZIP_FILE_for,$$service); \
	  if [ ! -f $$ZIP_FILE ]; then \
	    echo "    Error: $$ZIP_FILE not found. Run make package-all first."; exit 1; \
	  fi; \
	  S3_KEY=$(call S3_KEY_for,$$service); \
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
	    BudgetThresholdPercentage=$(BUDGET_THRESHOLD)
	@echo "Deployment of stack '$(AWS_STACK)' complete."

