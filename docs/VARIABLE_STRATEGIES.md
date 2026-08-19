# Spacelift Multi-Environment Variable Management Strategies

A comprehensive guide to passing variables to Spacelift for multi-environment Terraform deployments without using the UI.

---

## 1. ⭐ TERRAFORM PROVIDER (IaC for Spacelift)

**Best for:** Full version control of Spacelift configuration across environments

Infrastructure-as-code approach using the official Spacelift Terraform provider to manage stacks, contexts, and variables.

**Example:**
```hcl
# spacelift-config/main.tf
resource "spacelift_context" "prod" {
  name        = "production-context"
  description = "Production environment variables"
}

resource "spacelift_environment_variable" "azure_region" {
  context_id = spacelift_context.prod.id
  name       = "ARM_SUBSCRIPTION_ID"
  value      = var.prod_subscription_id
}

resource "spacelift_stack" "prod_infrastructure" {
  name              = "prod-infrastructure"
  repository        = "spacelift-azure"
  branch            = "main"
  terraform_version = "1.9.0"
  labels            = ["prod", "critical"]
  
  # Auto-attach production context
  context_ids = [spacelift_context.prod.id]
}

resource "spacelift_environment_variable" "db_password" {
  context_id = spacelift_context.prod.id
  name       = "TF_VAR_db_password"
  value      = var.db_password
  write_only = true  # Only show masked in logs
}
```

**Setup Process:**
1. Create separate `spacelift-config` repository
2. Store Spacelift Terraform provider code there
3. Use API keys for authentication
4. Commit and plan/apply through Spacelift itself (dog-fooding)

**Pros:**
- ✅ Full version control and audit trail
- ✅ Write-only secrets with masking
- ✅ Multi-environment setups with code reuse
- ✅ Programmatic stack creation
- ✅ CI/CD-friendly (GitOps model)

**Cons:**
- ❌ API key management required
- ❌ State management for Spacelift config itself
- ❌ Learning curve for provider resources

**Multi-Environment Example:**
```hcl
# spacelift-config/environments.tf
variable "environments" {
  default = {
    dev = {
      subscription_id = "..."
      region          = "eastus"
      instance_count  = 1
    }
    staging = {
      subscription_id = "..."
      region          = "eastus2"
      instance_count  = 2
    }
    prod = {
      subscription_id = "..."
      region          = "westus"
      instance_count  = 5
    }
  }
}

# Create stack for each environment
resource "spacelift_stack" "infrastructure" {
  for_each = var.environments

  name       = "${each.key}-infrastructure"
  repository = "spacelift-azure"
  branch     = "main"
  
  environment_variables = merge(
    { ENVIRONMENT = each.key },
    { TF_VAR_region = each.value.region },
    { TF_VAR_instance_count = each.value.instance_count }
  )
}
```

---

## 2. CONTEXT-BASED VARIABLE MANAGEMENT

**Best for:** Sharing configuration across multiple stacks, minimal duplication

Reusable bundles of environment variables, mounted files, and initialization hooks that attach to multiple stacks.

**Pattern:**
```hcl
# Via Terraform provider
resource "spacelift_context" "dev" {
  name = "dev-context"
}

resource "spacelift_context" "prod" {
  name = "prod-context"
}

# Define environment variables in contexts
resource "spacelift_environment_variable" "dev_vars" {
  context_id = spacelift_context.dev.id
  name       = "TF_VAR_environment"
  value      = "development"
}

resource "spacelift_environment_variable" "prod_vars" {
  context_id = spacelift_context.prod.id
  name       = "TF_VAR_environment"
  value      = "production"
}

# Auto-attach contexts based on labels
resource "spacelift_context_attachment" "prod" {
  context_id = spacelift_context.prod.id
  stack_id   = spacelift_stack.prod.id
}
```

**How Auto-Attachment Works:**
```hcl
# Attach context to multiple stacks using labels
resource "spacelift_context_attachment" "auto_prod" {
  for_each = {
    stack1 = spacelift_stack.app1_prod.id
    stack2 = spacelift_stack.app2_prod.id
    stack3 = spacelift_stack.app3_prod.id
  }

  context_id = spacelift_context.prod.id
  stack_id   = each.value
}
```

**Pros:**
- ✅ DRY - Share config across many stacks
- ✅ Hierarchical precedence clear
- ✅ Supports mounted files for complex configs
- ✅ Context auto-attachment feature
- ✅ Hooks for initialization scripts

**Cons:**
- ❌ Precedence rules can get complex
- ❌ Mounted files still need manual sync
- ❌ Not purely declarative if using UI for attachments

---

## 3. INITIALIZATION HOOKS + TERRAFORM.AUTO.TFVARS

**Best for:** Dynamic variable injection based on environment, works with standard Terraform

Use Spacelift initialization hooks to automatically select and inject correct tfvars file.

**Repository Structure:**
```
spacelift-azure/
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── scripts/
│   └── select-env.sh       # Hook logic lives in a real script, not inline YAML
├── .spacelift/
│   └── config.yml          # Spacelift runtime configuration (the real filename)
├── main.tf
├── variables.tf
└── outputs.tf
```

**`.spacelift/config.yml`:**
```yaml
version: 1

stack_defaults:
  before_init:
    - chmod +x ./scripts/select-env.sh
    - ./scripts/select-env.sh
```

> `before_init` (and the other hook phases) take a **list of single-line shell commands**. A multi-line block scalar containing blank lines will break: Spacelift's hook runner splits it by newline and rejoins the pieces with `&&`, and blank lines become empty strings in that join — producing `&& &&` and a shell syntax error. Keep multi-step logic in an actual script and call it as one line, as above.

**scripts/select-env.sh:**
```bash
#!/bin/sh
set -e

if [ -z "$ENVIRONMENT" ]; then
  echo "ERROR: ENVIRONMENT variable is not set on this stack."
  echo "Set it under Stack Settings > Environment (e.g. ENVIRONMENT=dev)."
  exit 1
fi

TFVARS_FILE="environments/${ENVIRONMENT}.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
  echo "ERROR: $TFVARS_FILE not found. Available environments:"
  ls -1 environments/ | sed 's/\.tfvars$//'
  exit 1
fi

cp "$TFVARS_FILE" ./spacelift.auto.tfvars
echo "Loaded variables from $TFVARS_FILE"
```

**environments/dev.tfvars:**
```hcl
location                          = "eastus"
resource_group_name               = "rg-spacelift-demo-dev"
storage_account_name              = "stspldemodev001"
storage_account_replication_type  = "LRS"

common_tags = {
  Environment = "dev"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo"
}
```

**environments/prod.tfvars:**
```hcl
location                          = "eastus"
resource_group_name               = "rg-spacelift-demo-prod"
storage_account_name              = "stspldemoprod001"
storage_account_replication_type  = "GRS"

common_tags = {
  Environment = "production"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo"
}
```

**Spacelift Stack Configuration (via Terraform Provider):**
```hcl
resource "spacelift_stack" "dev" {
  name       = "dev-infrastructure"
  repository = "spacelift-azure"
  branch     = "main"
  
  environment_variables = {
    ENVIRONMENT = "dev"
  }
}

resource "spacelift_stack" "prod" {
  name       = "prod-infrastructure"
  repository = "spacelift-azure"
  branch     = "main"
  
  environment_variables = {
    ENVIRONMENT = "prod"
  }
}
```

**Pros:**
- ✅ Works with standard Terraform tooling
- ✅ Files version controlled in repo
- ✅ Clear environment selection via ENV variable
- ✅ Terraform's precedence is familiar
- ✅ Easy to debug (can inspect spacelift.auto.tfvars)

**Cons:**
- ❌ Secrets in tfvars need careful handling
- ❌ Requires .auto.tfvars pattern knowledge
- ❌ Hook complexity for complex setups

---

## 4. MOUNTED FILES (Non-Repository Secrets)

**Best for:** Sensitive data that shouldn't be in version control

Store sensitive tfvars files in Spacelift mounted files instead of repo.

**Via Terraform Provider:**
```hcl
resource "spacelift_context" "prod_secrets" {
  name = "prod-secrets-context"
}

resource "spacelift_mounted_file" "prod_tfvars" {
  context_id   = spacelift_context.prod_secrets.id
  relative_path = "prod.tfvars"
  content      = file("${path.module}/secrets/prod.tfvars")
  write_only   = true  # Mask in logs
}

# Init hook to use mounted file
resource "spacelift_context" "prod_hooks" {
  name = "prod-hooks-context"
  
  # Script to use mounted file
  # ...setup here...
}
```

**Init Hook to Use Mounted Files:**
```bash
#!/bin/bash
# Combine repo tfvars with mounted secrets
cat /mnt/context/prod.tfvars >> spacelift.auto.tfvars
# Mounted files available in /mnt/context/
```

**Pros:**
- ✅ Secrets never in git
- ✅ Write-only masking
- ✅ Supports large files
- ✅ Binary files supported

**Cons:**
- ❌ Not version controlled
- ❌ Requires UI push or API for updates
- ❌ Less GitOps-friendly

---

## 5. POLICY-AS-CODE (OPA/Rego)

**Best for:** Validating variable values, enforcing constraints

Use Open Policy Agent to validate that variables meet requirements.

**Example Policy - Validate Production Variables:**
```rego
# policies/prod_variables.rego
package spacelift

deny[msg] {
  input.environment == "prod"
  input.terraform.variables.storage_account_replication_type != "GRS"
  msg := "Production storage must use GRS replication"
}

deny[msg] {
  input.environment == "prod"
  input.terraform.variables.location not in ["eastus", "westus", "eastus2"]
  msg := "Production can only deploy to approved regions"
}

deny[msg] {
  input.terraform.variables.storage_account_name == ""
  msg := "Storage account name is required"
}
```

**Spacelift Policy Configuration:**
```hcl
resource "spacelift_policy" "prod_variables" {
  space_id  = spacelift_space.default.id
  name      = "Enforce prod variables"
  body      = file("${path.module}/policies/prod_variables.rego")
  type      = "PLAN"  # Run on plan phase
}

resource "spacelift_policy_attachment" "prod_variables" {
  policy_id = spacelift_policy.prod_variables.id
  stack_id  = spacelift_stack.prod.id
}
```

**Pros:**
- ✅ Declarative, enforceable rules
- ✅ Prevents invalid configs
- ✅ Audit trail of validations
- ✅ Works with any variable source

**Cons:**
- ❌ Steep learning curve (Rego language)
- ❌ Validation only during plan (not upfront)
- ❌ Additional latency in pipeline

---

## 6. CI/CD INTEGRATION (GitHub Actions + Spacectl)

**Best for:** Event-driven deployments with dynamic variable injection

Use GitHub Actions with Spacelift CLI (spacectl) to trigger runs with variables.

**Setup Spacectl:**
```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ['infrastructure/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        environment: [dev, staging, prod]
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Spacectl
        uses: spacelift-io/setup-spacectl@v2
        with:
          version: latest
      
      - name: Authenticate with Spacelift
        env:
          SPACELIFT_API_TOKEN: ${{ secrets.SPACELIFT_API_TOKEN }}
        run: |
          spacectl profile login \
            --token $SPACELIFT_API_TOKEN \
            --account moviepotter
      
      - name: Trigger Stack Deployment
        run: |
          spacectl stack deploy \
            --stack ${{ matrix.environment }}-infrastructure \
            --wait \
            --tail
```

**Dynamic Variable Injection via GitHub Secrets:**
```yaml
      - name: Create Run with Variables
        env:
          SPACELIFT_API_TOKEN: ${{ secrets.SPACELIFT_API_TOKEN }}
          # Environment-specific secrets
          PROD_SUBSCRIPTION_ID: ${{ secrets.PROD_SUBSCRIPTION_ID }}
          PROD_DB_PASSWORD: ${{ secrets.PROD_DB_PASSWORD }}
        run: |
          # Set variable before deployment
          spacectl stack set-var \
            --stack prod-infrastructure \
            --name ARM_SUBSCRIPTION_ID \
            --value $PROD_SUBSCRIPTION_ID
          
          spacectl stack set-var \
            --stack prod-infrastructure \
            --name TF_VAR_db_password \
            --value $PROD_DB_PASSWORD
          
          # Trigger deployment
          spacectl stack deploy --stack prod-infrastructure
```

**Alternative: Matrix Strategy for Multi-Environment:**
```yaml
jobs:
  deploy:
    strategy:
      matrix:
        include:
          - env: dev
            stack: dev-infrastructure
            region: eastus
            instance_count: 1
          - env: staging
            stack: staging-infrastructure
            region: eastus2
            instance_count: 2
          - env: prod
            stack: prod-infrastructure
            region: westus
            instance_count: 5
    
    steps:
      - name: Deploy ${{ matrix.env }}
        env:
          SPACELIFT_API_TOKEN: ${{ secrets.SPACELIFT_API_TOKEN }}
          SUBSCRIPTION_ID: ${{ secrets[format('{0}_SUBSCRIPTION_ID', matrix.env)] }}
        run: |
          spacectl stack set-var \
            --stack ${{ matrix.stack }} \
            --name TF_VAR_region \
            --value ${{ matrix.region }}
          
          spacectl stack deploy --stack ${{ matrix.stack }}
```

**Pros:**
- ✅ Event-driven (push, PR, schedule)
- ✅ GitHub secrets management
- ✅ Just-in-time variable injection
- ✅ Audit trail in GitHub
- ✅ Matrix support for parallel deployments

**Cons:**
- ❌ Requires GitHub Actions knowledge
- ❌ Another system managing variables
- ❌ API token management overhead

---

## 7. ENVIRONMENT VARIABLE FILE (.env) + Docker/Container

**Best for:** Local development and testing before Spacelift

Define variables in `.env` files that can be sourced or passed to Spacelift.

**.env.dev:**
```bash
ARM_SUBSCRIPTION_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ARM_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
TF_VAR_environment=dev
TF_VAR_region=eastus
```

**Load in Script:**
```bash
#!/bin/bash
set -a
source .env.${ENVIRONMENT:=dev}
set +a

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Pros:**
- ✅ Simple, familiar approach
- ✅ Works with standard tooling
- ✅ Easy local testing

**Cons:**
- ❌ Secrets management issues
- ❌ Not Spacelift-native
- ❌ Manual loading required

---

## 8. WORKSPACE + BACKEND CONFIGURATION

**Best for:** Terraform state separation by environment

Use Terraform workspaces with backend configuration per environment.

**Configuration:**
```hcl
terraform {
  required_version = ">= 1.0"
  
  cloud {
    organization = "moviepotter"
    
    workspaces {
      pattern = "[a-z]+-*"
    }
  }
}

# Variables based on workspace
locals {
  workspace_config = {
    dev = {
      region   = "eastus"
      instance_count = 1
    }
    prod = {
      region   = "westus"
      instance_count = 5
    }
  }
  
  env_config = local.workspace_config[terraform.workspace]
}

variable "region" {
  default = local.env_config.region
}
```

**Spacelift Stack per Workspace:**
```hcl
resource "spacelift_stack" "workspace_dev" {
  name              = "dev-workspace"
  repository        = "spacelift-azure"
  branch            = "main"
  terraform_workspace = "dev"
}

resource "spacelift_stack" "workspace_prod" {
  name              = "prod-workspace"
  repository        = "spacelift-azure"
  branch            = "main"
  terraform_workspace = "prod"
}
```

**Pros:**
- ✅ Clear state separation
- ✅ Reduces risk of cross-env mistakes
- ✅ Standard Terraform pattern

**Cons:**
- ❌ Workspace per stack overhead
- ❌ Harder to validate across workspaces

---

## COMPARISON TABLE

| Strategy | Version Control | Secrets | Setup Complexity | Reusability | Real-time Updates | Best For |
|----------|-----------------|---------|------------------|-------------|-------------------|----------|
| **Terraform Provider** | ✅ Excellent | ✅ Write-only | Medium | Excellent | Git-based | Full IaC of Spacelift |
| **Contexts** | Partial | ✅ Yes | Low | Excellent | Manual | Multiple stacks |
| **Init Hooks** | ✅ Yes | Partial | Medium | Good | Git-based | Auto file selection |
| **Mounted Files** | ❌ No | ✅ Yes | Medium | Good | Manual API | Secrets only |
| **Policies** | ✅ Yes | ❌ No | High | Excellent | Git-based | Validation rules |
| **CI/CD (GitHub)** | ✅ Yes | ✅ Excellent | High | Good | Event-based | Event-driven |
| **.env Files** | ⚠️ Careful | ❌ No | Low | Poor | Manual | Local dev |
| **Workspaces** | ✅ Yes | Partial | Medium | Good | Git-based | State separation |

---

## RECOMMENDED MULTI-ENVIRONMENT SETUP

### For Your Azure Demo (spacelift-azure)

**Recommended: Hybrid Approach**

**Phase 1 - Foundation (Immediate)**
```
spacelift-azure/
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── scripts/
│   └── select-env.sh
├── .spacelift/
│   └── config.yml (with before_init hook)
├── main.tf
├── variables.tf
└── outputs.tf
```

1. Commit non-sensitive tfvars to repo with environment naming
2. Use init hook to select correct file per environment
3. Define stacks via Terraform provider in separate repo

**Phase 2 - Infrastructure as Code (Next)**
```
spacelift-infrastructure/  (separate repo)
├── environments.tf        (dev, staging, prod stacks)
├── contexts.tf           (dev, staging, prod contexts)
├── policies.tf           (validation rules)
└── versions.tf           (Spacelift provider config)
```

1. Create `spacelift-infrastructure` repository
2. Use Terraform provider to define stacks and contexts
3. Each environment gets one context
4. Contexts auto-attach to stacks via labels

**Phase 3 - CI/CD Automation (Advanced)**
```
.github/workflows/
├── deploy-dev.yml
├── deploy-staging.yml
└── deploy-prod.yml
```

1. Use GitHub Actions with spacectl CLI
2. Trigger from push/PR events
3. GitHub secrets for temporary values
4. Spacectl for just-in-time variable injection

**Phase 4 - Validation (Production-Ready)**
1. Add OPA policies for prod constraints
2. Require approval for prod deployments
3. Policy-as-code for variable validation

---

## IMPLEMENTATION ROADMAP

### Week 1: Local Development
- [ ] Create environments/*.tfvars files
- [ ] Add .spacelift/config.yml with before_init hook calling scripts/select-env.sh
- [ ] Test with `terraform init && terraform plan`
- [ ] Verify ENVIRONMENT variable switching works

### Week 2: Spacelift Stacks
- [ ] Create Spacelift API token
- [ ] Set up spacelift-infrastructure repo
- [ ] Write Terraform provider code for stacks
- [ ] Create dev, staging, prod stacks

### Week 3: Contexts & Variables
- [ ] Create contexts per environment (Terraform provider)
- [ ] Define common variables in contexts
- [ ] Auto-attach contexts to stacks
- [ ] Verify variables pass through correctly

### Week 4: GitHub Actions
- [ ] Set up spacectl in GitHub Actions
- [ ] Create workflow for deploy-dev
- [ ] Test matrix strategy for all environments
- [ ] Add merge-only trigger for prod

### Week 5: Validation & Policies
- [ ] Write OPA policies for prod constraints
- [ ] Attach policies to prod stack
- [ ] Test policy validation on plans
- [ ] Add approval workflow for prod

---

## QUICK START CODE SNIPPETS

### Spacelift Infrastructure Repo Setup
```hcl
# spacelift-infrastructure/main.tf
terraform {
  required_providers {
    spacelift = {
      source  = "spacelift-io/spacelift"
      version = "~> 1.0"
    }
  }
}

provider "spacelift" {
  api_key_endpoint = "https://moviepotter.app.spacelift.io"
  api_key_id       = var.spacelift_api_key_id
  api_key_secret   = var.spacelift_api_key_secret
}

# Create contexts for each environment
resource "spacelift_context" "environments" {
  for_each = toset(["dev", "staging", "prod"])
  
  name        = "${each.value}-context"
  description = "${each.value} environment variables"
}

# Create stacks for each environment
resource "spacelift_stack" "infrastructure" {
  for_each = toset(["dev", "staging", "prod"])
  
  name              = "${each.value}-infrastructure"
  repository        = "spacelift-azure"
  branch            = "main"
  terraform_version = "1.9.0"
  context_ids       = [spacelift_context.environments[each.key].id]
  
  labels = [each.key, "infrastructure"]
  
  environment_variables = {
    ENVIRONMENT = each.key
  }
}

# Attach contexts to stacks
resource "spacelift_context_attachment" "infrastructure" {
  for_each = {
    dev = {
      context = spacelift_context.environments["dev"].id
      stack   = spacelift_stack.infrastructure["dev"].id
    }
    staging = {
      context = spacelift_context.environments["staging"].id
      stack   = spacelift_stack.infrastructure["staging"].id
    }
    prod = {
      context = spacelift_context.environments["prod"].id
      stack   = spacelift_stack.infrastructure["prod"].id
    }
  }
  
  context_id = each.value.context
  stack_id   = each.value.stack
}
```

### Init Hook for Auto-Selection

`.spacelift/config.yml`:
```yaml
version: 1

stack_defaults:
  before_init:
    - chmod +x ./scripts/select-env.sh
    - ./scripts/select-env.sh
```

`scripts/select-env.sh`:
```bash
#!/bin/sh
set -e

if [ -z "$ENVIRONMENT" ]; then
  echo "ERROR: ENVIRONMENT variable not set"
  exit 1
fi

TFVARS_FILE="environments/${ENVIRONMENT}.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
  echo "ERROR: $TFVARS_FILE not found"
  echo "Available environments:"
  ls -1 environments/*.tfvars | sed 's/.*\///; s/\.tfvars//'
  exit 1
fi

cp "$TFVARS_FILE" spacelift.auto.tfvars
echo "Loaded variables from $TFVARS_FILE"
```

> Keep hook logic in a real script called as a single-line command. A multi-line YAML block scalar with blank lines will break — Spacelift's hook runner joins split lines with `&&`, and blank lines become empty strings in that join, producing a shell syntax error.

### GitHub Actions Deployment
```yaml
# .github/workflows/deploy.yml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ['environments/**', '*.tf']

jobs:
  deploy:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, staging, prod]
    
    steps:
      - uses: spacelift-io/setup-spacectl@v2
      
      - name: Deploy ${{ matrix.environment }}
        env:
          SPACELIFT_API_TOKEN: ${{ secrets.SPACELIFT_API_TOKEN }}
        run: |
          spacectl profile login --token $SPACELIFT_API_TOKEN
          spacectl stack deploy \
            --stack ${{ matrix.environment }}-infrastructure \
            --wait
```

---

## RESOURCES

- [Spacelift Terraform Provider Docs](https://docs.spacelift.io/vendors/terraform/terraform-provider)
- [spacelift_stack Resource](https://registry.terraform.io/providers/spacelift-io/spacelift/latest/docs/resources/stack)
- [spacelift_environment_variable Resource](https://registry.terraform.io/providers/spacelift-io/spacelift/latest/docs/resources/environment_variable)
- [Spacelift Contexts](https://docs.spacelift.io/concepts/configuration/context)
- [Handling .tfvars in Spacelift](https://docs.spacelift.io/vendors/terraform/handling-tfvars)
- [Spacelift Policy as Code](https://docs.spacelift.io/concepts/policy)
- [Spacectl CLI Reference](https://docs.spacelift.io/integrations/source-control/github)
- [Setup-spacectl GitHub Action](https://github.com/spacelift-io/setup-spacectl)
