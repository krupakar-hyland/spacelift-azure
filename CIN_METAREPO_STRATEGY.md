# CIN Spacelift Metarepo Strategy

This document outlines the variable management and stack configuration strategy used in the **cin-spacelift-metarepo**, which is the production approach for managing Spacelift across a multi-environment, multi-team organization.

## Overview

The CIN strategy is a **monorepo + IaC approach** that uses:
1. **Single source of truth**: All Spacelift stacks, contexts, and variables managed via Terraform provider in one repo
2. **Modular team structure**: Each team has a dedicated module in the monorepo
3. **Standard reusable module**: `standard_stack` provides consistent stack creation
4. **Consolidated environment configuration**: Single `environment_config` map drives all stacks across all environments
5. **Layered variable management**: Two distinct approaches for managed vs. pipeline-owned variables
6. **Automatic file-based tfvars injection**: Init hooks auto-select environment-specific tfvars files

---

## 1. MONOREPO ARCHITECTURE

### Repository Structure
```
cin-spacelift-metarepo/
├── locals.tf                          # Environment config, space IDs, region mappings
├── providers.tf                       # Custom provider setup
├── contexts.tf                        # Shared contexts (vault, AWS role, region, etc.)
├── policies.tf                        # OPA policies
├── <team-module>.tf                   # Module instantiation for each team
│
├── standard_stack/                    # Reusable Spacelift stack module
│   ├── vars.tf                        # Stack variables
│   ├── stack.tf                       # spacelift_stack resource + env vars
│   └── outputs.tf
│
├── contexts/                          # Context definitions (vault, aws_role, etc.)
│   ├── main.tf
│   ├── vars.tf
│   └── outputs.tf
│
├── <team_modules>/                    # Each team gets a directory
│   ├── agent_builder_platform/
│   ├── ccrepo/
│   ├── brama/
│   └── ...
│
├── custom_providers/                  # Custom provider configurations
├── api_keys/                          # API key management
└── cin_module/                        # CIN-specific module
```

### Key Files

**locals.tf** - Defines environments and consolidated configuration:
```hcl
locals {
  environments = toset(["sandbox", "dev", "staging", "prod", "prod-eu", "prod-au"])
  
  environment_config = {
    sandbox = {
      space_id       = "content-intelligence-sandbox-..."
      aws_region     = "us-east-1"
      replica_region = "us-west-2"
      account_id     = "407995386968"
    }
    dev = { ... }
    staging = { ... }
    prod = { ... }
    prod-eu = { ... }
    prod-au = { ... }
  }
  
  azure_environment_config = {
    sandbox = {
      client_id       = "6d790e43-..."
      tenant_id       = "8ca5db88-..."
      subscription_id = "ff55c2e2-..."
    }
  }
}
```

---

## 2. STANDARD_STACK MODULE

### Purpose
Reusable Terraform module that encapsulates all common Spacelift stack creation logic.

### Key Inputs
```hcl
variable "stack_name" {
  # Base name, e.g., "cin-agent-builder-infrastructure"
  # Gets expanded to: "cin-agent-builder-infrastructure-{env}-{region}"
}

variable "repository_name" {
  # GitHub repository name
}

variable "project_root" {
  # Path within repo to Terraform code (e.g., "deployment/terraform/agent-builder-infrastructure")
}

variable "space_id" {
  # Spacelift space ID for the environment
}

variable "environment_key" {
  # Environment identifier (dev, staging, prod, prod-eu, etc.)
}

variable "aws_region" {
  # AWS region for the stack
}

variable "additional_managed_environment_variables" {
  # Non-secret config managed by metarepo (Terraform is authoritative)
  # Changes here trigger plan updates
  type = map(string)
  # Example: { "cluster_config" = "..." }
}

variable "additional_environment_variables" {
  # Secret or pipeline-managed variables
  # Set once, then pipelines can override
  # Terraform ignores subsequent changes to initial_value
  type = map(object({
    initial_value = string
    secure        = bool  # true for write_only secrets
  }))
}
```

### Stack Naming Convention
```
<stack_name>-<environment_key>-<aws_region>

Examples:
- cin-eks-dev-us-east-1
- cin-eks-prod-us-east-1
- cin-eks-prod-eu-eu-central-1
- cin-eks-sandbox-us-east-1
```

### Automatic Labels
The module automatically attaches labels to enable context auto-attachment:
```hcl
labels = [
  var.secrets_backend_label,      # "vault" or "openbao"
  var.aws_region,                 # "us-east-1"
  var.environment_key,            # "dev", "prod", "prod-eu"
  "ignore_not_pr",                # PR-specific behavior
  "aws-${env}-${region}",         # AWS context auto-attachment
  "tfvars-file-${env}",           # Auto-select tfvars file
]
```

---

## 3. VARIABLE MANAGEMENT STRATEGY

### Pattern 1: Managed Variables (Metarepo is Authoritative)

**Use Case**: Configuration values fully owned by the metarepo team

**Implementation**:
```hcl
module "my_stack" {
  source = "../standard_stack"
  # ...
  
  additional_managed_environment_variables = {
    "cluster_config" = jsonencode({
      kubernetes_version = "1.34"
      private_eks_cluster = false
    })
    "vpc_cidr"    = "10.50.0.0/16"
    "domain_name" = "example.tools.hyland.dev"
  }
}
```

**Behavior**:
- Creates `TF_VAR_cluster_config`, `TF_VAR_vpc_cidr`, etc. with `write_only = false`
- **Terraform detects changes** on the next plan
- Pipeline cannot override (Terraform reverts changes)
- Non-sensitive (`write_only = false`)

**Terraform Resource**:
```hcl
resource "spacelift_environment_variable" "additional_managed_environment_variables" {
  for_each = var.additional_managed_environment_variables
  
  stack_id   = spacelift_stack.stack.id
  name       = "TF_VAR_${each.key}"
  value      = each.value
  write_only = false  # Changes detected on next plan
}
```

---

### Pattern 2: Pipeline-Managed Variables (Set Once, Pipelines Override)

**Use Case**: Secrets, database passwords, tokens — values that need to be updated by pipelines

**Implementation**:
```hcl
module "my_stack" {
  source = "../standard_stack"
  # ...
  
  additional_environment_variables = {
    "database_password" = {
      initial_value = "replace-me-in-pipeline"
      secure        = true  # write_only = true (masked in logs)
    }
    "feature_flags" = {
      initial_value = "{}"
      secure        = false  # Non-secret but pipeline-managed
    }
  }
}
```

**Behavior**:
- Creates environment variable with `write_only = ${secure}`
- Sets initial value only on resource creation
- **Terraform ignores changes** to `initial_value` (via `lifecycle { ignore_changes = [value] }`)
- Pipeline can update the variable without Terraform reverting it
- Secrets are masked in logs when `secure = true`

**Terraform Resource**:
```hcl
resource "spacelift_environment_variable" "additional_environment_variables" {
  for_each = var.additional_environment_variables
  
  stack_id   = spacelift_stack.stack.id
  name       = "TF_VAR_${each.key}"
  value      = each.value.initial_value
  write_only = each.value.secure
  
  lifecycle {
    ignore_changes = [value]  # Pipelines own the value after creation
  }
}
```

---

### Pattern 3: Context-Based Variables (Auto-Attached)

**Use Case**: Shared configuration attached to multiple stacks via labels

**Implementation**:
```hcl
# In contexts/main.tf
resource "spacelift_context" "aws_role" {
  for_each = var.environment_config
  
  name = "aws-role-${each.key}"
}

resource "spacelift_environment_variable" "aws_role_arn" {
  for_each = var.environment_config
  
  context_id = spacelift_context.aws_role[each.key].id
  name       = "AWS_ROLE_ARN"
  value      = "arn:aws:iam::${each.value.account_id}:role/spacelift"
}
```

**Auto-Attachment via Labels**:
- Stacks with label `aws-dev-us-east-1` automatically get the `aws-role-dev` context attached
- Stacks with label `aws-prod-us-east-1` automatically get the `aws-role-prod` context attached
- No manual attachment needed (label-based matching)

---

### Pattern 4: File-Based Terraform Variables (.auto.tfvars)

**Use Case**: Environment-specific tfvars files committed to the workload repo

**Implementation**:

**In Application Repo** (`agent-builder-platform`):
```
agent-builder-platform/
├── deployment/terraform/agent-builder-infrastructure/
│   ├── main.tf
│   ├── variables.tf
│   ├── tfvar_configs/
│   │   ├── dev.tfvars
│   │   ├── staging.tfvars
│   │   └── prod.tfvars
```

**Spacelift Init Hook** (automatic via label `tfvars-file-{env}`):
```bash
if [ -f "./tfvar_configs/${environment}.tfvars" ]; then 
  ln -s ./tfvar_configs/${environment}.tfvars ./${environment}.auto.tfvars
fi
```

**Example tfvar_configs/prod.tfvars**:
```hcl
instance_count      = 5
enable_high_availability = true
backup_retention_days = 30
log_retention_days   = 90
```

**Terraform loads automatically**:
```hcl
terraform init  # Loads *.auto.tfvars files automatically
terraform plan  # Uses values from prod.auto.tfvars
```

---

## 4. MULTI-ENVIRONMENT CONFIGURATION

### Consolidated environment_config

Single source of truth for all environments:
```hcl
locals {
  environment_config = {
    sandbox = {
      space_id       = "content-intelligence-sandbox-01JH8S9F9TPJKAS2NVGNYYS233"
      aws_region     = "us-east-1"
      replica_region = "us-west-2"
      account_id     = "407995386968"
      environment    = "sandbox"
      base_nucleus_account_id = "7025f370-1eaf-4ab3-a5a9-8c2cf3ecd61e"
    }
    dev = { ... }
    staging = { ... }
    prod = { ... }
    prod-eu = { ... }
    prod-au = { ... }
  }
}
```

### Team Module Pattern

**Example: agent_builder_platform.tf**
```hcl
module "agent-builder-infrastructure" {
  for_each = local.environment_config  # Iterates: sandbox, dev, staging, prod, prod-eu, prod-au
  
  source = "./standard_stack"
  
  stack_name      = "cin-agent-builder-infrastructure"
  repository_name = "agent-builder-platform"
  project_root    = "deployment/terraform/agent-builder-infrastructure"
  
  space_id        = each.value.space_id    # Gets environment-specific space ID
  environment     = each.key               # "sandbox", "dev", "prod", etc.
  aws_region      = each.value.aws_region  # "us-east-1", "eu-central-1", etc.
  environment_key = each.key               # Same as environment
  
  depends_on = [module.contexts]
}
```

**Creates stacks**:
- `cin-agent-builder-infrastructure-sandbox-us-east-1` (space: sandbox)
- `cin-agent-builder-infrastructure-dev-us-east-1` (space: dev)
- `cin-agent-builder-infrastructure-staging-us-east-1` (space: staging)
- `cin-agent-builder-infrastructure-prod-us-east-1` (space: prod)
- `cin-agent-builder-infrastructure-prod-eu-eu-central-1` (space: prod-eu)
- `cin-agent-builder-infrastructure-prod-au-ap-southeast-2` (space: prod-au)

---

## 5. CONTEXT AUTO-ATTACHMENT

### How It Works

**Contexts are created per environment**:
```hcl
# In contexts/main.tf
resource "spacelift_context" "aws_role" {
  for_each = var.environment_config
  name = "aws-role-${each.key}"
  # ...
}
```

**Stacks get matching labels automatically** (via standard_stack):
```
Labels on stack:
- "aws-dev-us-east-1"
- "aws-prod-us-east-1"
- "aws-prod-eu-eu-central-1"
```

**Contexts auto-attach** based on label matching (Spacelift feature):
- Stack with label `aws-dev-us-east-1` → automatically attaches `aws-role-dev` context
- Stack with label `aws-prod-us-east-1` → automatically attaches `aws-role-prod` context
- Stack with label `aws-prod-eu-eu-central-1` → automatically attaches `aws-role-prod-eu` context

**No manual attachment needed** — all automatic via label patterns.

---

## 6. POLICY MANAGEMENT

### OPA Policies

Attached to stacks or contexts for plan validation:
```hcl
resource "spacelift_policy" "require_backup_enabled" {
  space_id = local.root_ci_space_id
  name     = "Require backups in production"
  body     = file("${path.module}/policies/prod_backups.rego")
  type     = "PLAN"
}

resource "spacelift_policy_attachment" "require_backup_enabled" {
  policy_id = spacelift_policy.require_backup_enabled.id
  stack_id  = spacelift_stack.prod_infrastructure.id
}
```

---

## 7. KEY DIFFERENCES FROM OTHER STRATEGIES

| Aspect | CIN Strategy | Previous Approach |
|--------|-------------|-------------------|
| **Variable Source** | Monorepo IaC (Terraform provider) | Mixed (UI + IaC) |
| **Multi-Env Support** | Single `for_each` loop over environment_config | Multiple separate stacks |
| **Code Duplication** | Minimal (standard_stack reused) | High (repeated stack definitions) |
| **Secrets Handling** | Two-pattern: managed vs. pipeline-owned | One approach (all pipeline-owned) |
| **Context Attachment** | Automatic via labels | Manual or policy-based |
| **Tfvars Files** | Auto-selected via init hooks | Manual or environment variables |
| **Multi-Region** | Consolidated config with region per environment | Separate configs per region |
| **Team Scaling** | Easy (add module, iterate config) | Complex (add stack per env per region) |
| **State Management** | Single metarepo state (monorepo) | Multiple states (one per module) |

---

## 8. IMPLEMENTATION WORKFLOW

### For Teams Creating New Stacks

**Step 1: Create team module directory**
```bash
mkdir -p /Users/krupakar.reddy/Hyland/cin-spacelift-metarepo/my_team/
cd my_team/
```

**Step 2: Define module variables** (`my_team/variables.tf`)
```hcl
variable "environment_config" {
  type = map(object({
    space_id   = string
    aws_region = string
    account_id = string
  }))
}
```

**Step 3: Instantiate standard_stack for each environment** (`my_team/main.tf`)
```hcl
module "my_infrastructure" {
  for_each = var.environment_config
  
  source = "../standard_stack"
  
  stack_name      = "cin-my-infrastructure"
  repository_name = "my-repo"
  project_root    = "deployment/terraform/my-infrastructure"
  
  space_id        = each.value.space_id
  environment     = each.key
  aws_region      = each.value.aws_region
  environment_key = each.key
}
```

**Step 4: Add module to root** (root `my_team.tf`)
```hcl
module "my-team" {
  source = "./my_team"
  environment_config = local.environment_config
  depends_on = [module.contexts]
}
```

**Step 5: Commit and merge**
- Spacelift detects changes in metarepo
- Plan shows all new stacks to be created
- Apply creates stacks in all environments automatically

---

## 9. ADVANTAGES

✅ **Single Source of Truth**: All Spacelift config in one repo, version controlled
✅ **No UI Clicks**: 100% IaC, no manual stack creation
✅ **DRY**: `standard_stack` eliminates duplication
✅ **Scalable**: Add new environment by updating one config object
✅ **Audit Trail**: Every change tracked in git
✅ **Rollback-Safe**: Terraform state ensures consistency
✅ **Secret-Friendly**: Two-pattern variable approach handles both managed and secret variables
✅ **Multi-Env Capable**: Single loop creates stacks across all environments
✅ **Team Isolation**: Each team module self-contained
✅ **Auto-Context Attachment**: No manual wiring needed

---

## 10. DISADVANTAGES

❌ **Monorepo Complexity**: Single large repository, shared state
❌ **Learning Curve**: Teams need to understand standard_stack
❌ **Blast Radius**: Mistakes can affect multiple stacks
❌ **State Lock Risk**: Shared state can cause lock contention
❌ **Slow Plans**: Planning large monorepo can be slow
❌ **Limited Parallelism**: Some resources depend on others
❌ **Migration Effort**: Moving to this model from UI-based stacks is effort-intensive

---

## 11. BEST FOR

- **Large organizations** with many stacks and teams
- **Strict GitOps** requirements
- **Multi-environment deployments** (sandbox, dev, staging, prod, multi-region)
- **Consistency and standardization** across teams
- **Audit and compliance** needs
- **Infrastructure teams** with strong Terraform expertise

---

## 12. COMPARISON TO SPACELIFT-AZURE SETUP

### For spacelift-azure Project

**Current Approach** (what we created):
- Individual `environments/*.auto.tfvars` files
- Init hooks for dynamic selection
- Spacelift stacks created manually or via simple Terraform provider

**CIN Approach Would Be**:
```hcl
# locals.tf
locals {
  environment_config = {
    dev = {
      space_id         = "..."
      azure_region     = "eastus"
      subscription_id  = "..."
    }
    prod = {
      space_id         = "..."
      azure_region     = "eastus"
      subscription_id  = "..."
    }
  }
}

# spacelift-azure-stack.tf
module "azure_infrastructure" {
  for_each = local.environment_config
  
  source = "./standard_stack"
  
  stack_name      = "azure-infrastructure"
  repository_name = "spacelift-azure"
  project_root    = "."
  
  space_id        = each.value.space_id
  environment     = each.key
  # Azure-specific variables
  additional_managed_environment_variables = {
    "subscription_id" = each.value.subscription_id
    "region"          = each.value.azure_region
  }
}
```

---

## RESOURCES

- [CIN Spacelift Metarepo](https://github.com/HylandExperience/cin-spacelift-metarepo)
- [Spacelift Terraform Provider](https://docs.spacelift.io/vendors/terraform/terraform-provider)
- [spacelift_stack Resource](https://registry.terraform.io/providers/spacelift-io/spacelift/latest/docs/resources/stack)
- [spacelift_environment_variable Resource](https://registry.terraform.io/providers/spacelift-io/spacelift/latest/docs/resources/environment_variable)
- [Context Auto-Attachment Documentation](https://docs.spacelift.io/concepts/configuration/context)
