# Spacelift Azure Repository - Complete Guide for New Team Members

Welcome! This guide explains how the `spacelift-azure` repository is organized and how everything connects together. Think of it as a map of the project.

---

## 📁 Repository Structure

Here's what you'll see when you open the repository:

```
spacelift-azure/
├── main.tf                          ← Main infrastructure code (Resource Group, Storage)
├── variables.tf                     ← Input variables (customizable settings)
├── outputs.tf                       ← Output values (what gets created)
├── terraform.tfvars.example         ← Template for variable values
├── spacelift.yml                    ← Spacelift-specific configuration
├── .terraform-version               ← Terraform version to use
├── .gitignore                       ← What NOT to commit to git
├── README.md                        ← Getting started guide
├── VARIABLE_STRATEGIES.md           ← Deep dive into variable management
├── CIN_METAREPO_STRATEGY.md        ← How to manage stacks at scale
├── REPO_STRUCTURE_GUIDE.md         ← This file!
├── environments/                    ← Environment-specific settings (DEV, PROD, etc.)
│   ├── dev.auto.tfvars
│   ├── staging.auto.tfvars
│   └── prod.auto.tfvars
└── .github/
    └── workflows/                   ← GitHub Actions automation (optional, for CI/CD)
```

---

## 🎯 What Does Each File Do?

### `main.tf` - The Heart of Your Infrastructure

**Purpose**: This file describes the Azure infrastructure you want to create.

**What's inside**:
- Resource Group (container for all your resources)
- Storage Account (where files are stored)
- Storage Container (inside the storage account)

**How it works**:
```
main.tf says:
  "Create a Resource Group called <name>"
  "Create a Storage Account called <name>"
  "Create a Container inside that Storage Account"
```

**When to edit**: Modify when you want to add/change Azure resources.

---

### `variables.tf` - Customization Settings

**Purpose**: Defines "knobs you can turn" to customize your infrastructure without editing `main.tf`.

**Think of it like**: A recipe's ingredient list, not the cooking instructions.

**Example variables**:
```
- location: Which Azure region? (eastus, westus, etc.)
- resource_group_name: What to name the resource group?
- storage_account_name: What to name the storage account?
- environment: Is this dev or prod?
```

**How it works**:
1. You define a variable in `variables.tf`
2. You use that variable in `main.tf`
3. You provide the actual value when running Terraform

**When to edit**: Add new variables when you want users to customize something.

---

### `outputs.tf` - Results of What Was Created

**Purpose**: Shows you the important information AFTER infrastructure is created.

**Example outputs**:
```
- Resource Group ID: The unique ID of the created resource group
- Storage Account Name: The name of the storage account
- Storage URL: Where to access the storage account
```

**How it works**: After `terraform apply`, you see these values displayed.

**When to edit**: Add new outputs when you want to expose important created values.

---

### `terraform.tfvars.example` - Template for Values

**Purpose**: A template showing what values you need to provide.

**How to use**:
1. Copy this file: `cp terraform.tfvars.example terraform.tfvars`
2. Edit `terraform.tfvars` with your actual values
3. Terraform reads `terraform.tfvars` automatically
4. **Important**: Never commit `terraform.tfvars` with real values to git!

**Why this pattern**: Protects secrets from being accidentally committed.

---

### `spacelift.yml` - Spacelift Configuration

**Purpose**: Tells Spacelift HOW to run your Terraform code.

**What's inside**:
```yaml
init:
  - A script that runs BEFORE Terraform plan/apply
  - Selects the right environment variables file
  - Ensures everything is set up correctly
```

**Example hook**:
```bash
if [ -f "./environments/${ENVIRONMENT}.auto.tfvars" ]; then
  cp "./environments/${ENVIRONMENT}.auto.tfvars" spacelift.auto.tfvars
fi
```

Translation: "If the environment file exists, copy it to the right place"

**When to edit**: Modify when you need to add setup steps before Terraform runs.

---

### `.terraform-version` - Terraform Compatibility

**Purpose**: Specifies which Terraform version to use.

**Content**: `1.9.0`

**Why it matters**: Ensures everyone (you, Spacelift, teammates) uses the same Terraform version to avoid compatibility issues.

**When to edit**: Only when updating Terraform to a new version.

---

### `.gitignore` - Don't Commit This Stuff

**Purpose**: Tells git "these files should NOT be committed to GitHub".

**What it ignores**:
```
*.tfstate          ← Terraform state files (contain sensitive info)
*.tfstate.*        ← Backup state files
terraform.tfvars   ← Your actual variable values (could have secrets)
.terraform/        ← Downloaded modules and providers
.env               ← Local environment files
```

**Why it matters**: Prevents accidental exposure of secrets and huge files.

---

## 📂 The `environments/` Folder - Environment Files

### Purpose

Different settings for different environments (dev, staging, prod).

### Structure

```
environments/
├── dev.auto.tfvars          ← Development environment settings
├── staging.auto.tfvars      ← Staging environment settings
└── prod.auto.tfvars         ← Production environment settings
```

### How It Works

**Example: `environments/dev.auto.tfvars`**
```hcl
location                      = "eastus"
resource_group_name          = "rg-dev-demo"
storage_account_name         = "stdevdemo123"
storage_account_tier         = "Standard"
storage_account_replication_type = "LRS"  # Cheaper, dev only

common_tags = {
  Environment = "development"
  Owner       = "DevTeam"
}
```

**Example: `environments/prod.auto.tfvars`**
```hcl
location                      = "eastus"
resource_group_name          = "rg-prod-demo"
storage_account_name         = "stproddemo123"
storage_account_tier         = "Standard"
storage_account_replication_type = "GRS"  # More expensive, but safe for prod

common_tags = {
  Environment = "production"
  Owner       = "OpsTeam"
}
```

### The Connection

**Spacelift runs like this**:

1. You create a stack in Spacelift with `ENVIRONMENT=dev`
2. Spacelift runs the init hook in `spacelift.yml`:
   ```bash
   cp environments/dev.auto.tfvars spacelift.auto.tfvars
   ```
3. Terraform sees `spacelift.auto.tfvars` and uses those values
4. Infrastructure is created with dev settings

**For Production**, same process but with `ENVIRONMENT=prod`.

### When to Edit

- Adding a new environment? Create `environments/new-env.auto.tfvars`
- Changing values for an environment? Edit the relevant file
- Adding a new variable? Add it to ALL environment files

---

## 🔗 How Files Connect Together

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     You Run Spacelift                        │
│        (or GitHub Actions, or local terraform)              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │   spacelift.yml        │
        │   (Init Hook)          │
        │                        │
        │ Copies environment     │
        │ file to right location │
        └────────┬───────────────┘
                 │
                 ▼
    ┌────────────────────────────────────┐
    │ environments/{ENVIRONMENT}.auto    │
    │         .tfvars                    │
    │                                    │
    │ Provides actual values             │
    │ (region, names, etc.)              │
    └────────┬───────────────────────────┘
             │
             ▼
    ┌────────────────────────────────────┐
    │       variables.tf                 │
    │                                    │
    │ Defines what values are available  │
    │ (which knobs can be turned?)       │
    └────────────────────────────────────┘
             │
             ▼
    ┌────────────────────────────────────┐
    │       main.tf                      │
    │                                    │
    │ Uses the values from variables to  │
    │ create Azure resources             │
    └────────┬───────────────────────────┘
             │
             ▼
    ┌────────────────────────────────────┐
    │       outputs.tf                   │
    │                                    │
    │ Shows you what was created         │
    │ (IDs, names, URLs, etc.)           │
    └────────────────────────────────────┘
```

### Step-by-Step Example

Let's trace what happens when you run a deployment:

**Step 1**: You tell Spacelift "Deploy to dev"
```
Set ENVIRONMENT variable = "dev"
```

**Step 2**: Spacelift runs the init hook (from `spacelift.yml`)
```bash
cp environments/dev.auto.tfvars spacelift.auto.tfvars
```

**Step 3**: Terraform reads the values
```
From spacelift.auto.tfvars:
  location = "eastus"
  resource_group_name = "rg-dev-demo"
  storage_account_name = "stdevdemo123"
```

**Step 4**: Terraform checks `variables.tf`
```
Variables defined:
  - location (default: eastus)
  - resource_group_name (default: rg-spacelift-demo)
  - storage_account_name (validates it's 3-24 characters)
```

**Step 5**: Terraform reads `main.tf`
```
Create:
  - azurerm_resource_group with location="eastus" and name="rg-dev-demo"
  - azurerm_storage_account with name="stdevdemo123"
  - azurerm_storage_container with name="data"
```

**Step 6**: Resources are created in Azure

**Step 7**: Terraform displays `outputs.tf`
```
Output:
  Resource Group ID: /subscriptions/.../resourceGroups/rg-dev-demo
  Storage Account Name: stdevdemo123
  Primary Blob Endpoint: https://stdevdemo123.blob.core.windows.net/
```

---

## 📋 Common Tasks for New Members

### Task 1: Add a New Environment (e.g., QA)

**Steps**:
1. Create `environments/qa.auto.tfvars`
2. Copy content from `environments/dev.auto.tfvars`
3. Change values to match QA requirements
4. Commit to git
5. Create a new Spacelift stack with `ENVIRONMENT=qa`

---

### Task 2: Change a Value (e.g., Storage Replication for Dev)

**Goal**: Change dev to use cheaper storage

**Steps**:
1. Open `environments/dev.auto.tfvars`
2. Change `storage_account_replication_type = "LRS"` (was "GRS")
3. Commit: `git add environments/dev.auto.tfvars && git commit -m "Change dev storage to LRS"`
4. Push: `git push`
5. Spacelift automatically detects the change
6. Run plan to review, then apply

---

### Task 3: Add a New Azure Resource

**Goal**: Add a new storage container

**Steps**:
1. Open `variables.tf`
2. Add a new variable:
   ```hcl
   variable "second_container_name" {
     description = "Name of the second container"
     default = "logs"
   }
   ```
3. Open `main.tf`
4. Add a new resource:
   ```hcl
   resource "azurerm_storage_container" "logs" {
     name                  = var.second_container_name
     storage_account_name  = azurerm_storage_account.main.name
     container_access_type = "private"
   }
   ```
5. Open `outputs.tf`
6. Add output:
   ```hcl
   output "logs_container_id" {
     value = azurerm_storage_container.logs.id
   }
   ```
7. Update all environment files if needed
8. Commit and push

---

### Task 4: Update a Variable for Prod Only

**Goal**: Change storage to GRS only for prod

**Steps**:
1. Open `environments/prod.auto.tfvars`
2. Change `storage_account_replication_type = "GRS"`
3. Make sure `environments/dev.auto.tfvars` has `storage_account_replication_type = "LRS"`
4. Commit and push
5. Dev keeps cheap storage, prod gets safe storage ✅

---

## 🔐 Secret Variables

### The Problem
Some variables contain secrets (API keys, passwords, connection strings).

**Never do this**:
```hcl
# ❌ WRONG - Don't put secrets in files
storage_account_key = "DefaultEndpointProtocol=https;AccountName=..."
database_password = "super-secret-123"
```

### The Solution

For secrets that shouldn't be in files:

1. **Use Spacelift context variables** (from README.md instructions)
2. **Set via GitHub Actions secrets** (from GitHub)
3. **Use Azure Key Vault** (best practice)

These values are:
- Never stored in git
- Masked in logs (shown as `***`)
- Managed separately from code

---

## 🚀 Quick Start Checklist

### Your First Week

- [ ] Clone the repository
- [ ] Read `README.md` (getting started guide)
- [ ] Understand the file structure (this guide!)
- [ ] Look at `environments/dev.auto.tfvars` (see an example)
- [ ] Create your own `terraform.tfvars` from the example
- [ ] Run `terraform init` and `terraform plan` locally
- [ ] Create a Spacelift stack for dev
- [ ] Run your first plan in Spacelift
- [ ] Run your first apply in Spacelift

### Your Second Week

- [ ] Read `VARIABLE_STRATEGIES.md` (understand variable options)
- [ ] Understand the `environments/` folder pattern
- [ ] Add a new environment (qa, uat, etc.)
- [ ] Add a new Azure resource
- [ ] Review Spacelift concepts (drift detection, policies)

### Your Third Week

- [ ] Read `CIN_METAREPO_STRATEGY.md` (optional, advanced)
- [ ] Understand how to scale this to multiple teams
- [ ] Learn about Spacelift contexts
- [ ] Set up GitHub Actions (if needed)

---

## 📞 Common Questions

### Q: Where do I put secret values?
**A**: Never in git files. Use Spacelift stack environment variables or GitHub secrets. See README.md "Configure Stack Environment Variables" section.

### Q: How do I test changes locally?
**A**: 
```bash
cp environments/dev.auto.tfvars terraform.tfvars
terraform init
terraform plan
```

### Q: What if I accidentally commit `terraform.tfvars` with secrets?
**A**: 
1. Stop immediately (don't push)
2. Run: `git rm --cached terraform.tfvars`
3. Run: `git commit --amend`
4. Rotate any exposed secrets in Azure
5. Tell your team lead

### Q: How do I add a new environment?
**A**: Create `environments/{env-name}.auto.tfvars`, add values, create a Spacelift stack with `ENVIRONMENT={env-name}`.

### Q: Can I manually change things in Azure, then import them?
**A**: Technically yes, but it breaks GitOps principle. Avoid it. Use `terraform import` if absolutely necessary.

### Q: What if two people edit the same file at the same time?
**A**: Git will flag a merge conflict. Discuss with your team and resolve. Spacelift prevents simultaneous applies with locks.

---

## 🎓 Next Steps

1. **Read related documentation**:
   - `README.md` — Getting started & Spacelift setup
   - `VARIABLE_STRATEGIES.md` — Different ways to manage variables
   - `CIN_METAREPO_STRATEGY.md` — Managing multiple teams/stacks

2. **Learn Azure basics**:
   - [Azure Resource Groups](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/overview)
   - [Azure Storage Accounts](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview)

3. **Learn Terraform basics**:
   - [Terraform official tutorial](https://learn.hashicorp.com/terraform)
   - [Terraform variables documentation](https://www.terraform.io/language/values/variables)

4. **Learn Spacelift basics**:
   - [Spacelift documentation](https://docs.spacelift.io/)
   - [Spacelift stacks](https://docs.spacelift.io/concepts/stack)

---

## 📊 Visual Overview

### Who Uses What?

```
┌─────────────────────────────────────────────────┐
│          New Team Member (You)                  │
│                                                 │
│  Edits: variables.tf, main.tf, outputs.tf       │
│  Edits: environments/*.auto.tfvars              │
│  Reads: spacelift.yml, README.md                │
└────────────────┬────────────────────────────────┘
                 │ Commits to Git
                 ▼
        ┌────────────────┐
        │   GitHub       │
        │   Repository   │
        └────────┬───────┘
                 │ Webhook notification
                 ▼
        ┌────────────────────┐
        │     Spacelift      │
        │                    │
        │ ✓ Reads files      │
        │ ✓ Runs hooks       │
        │ ✓ Plans Terraform  │
        │ ✓ Creates resources│
        └────────┬───────────┘
                 │
                 ▼
        ┌────────────────────┐
        │   Azure            │
        │   (Resources       │
        │    are created)    │
        └────────────────────┘
```

---

## 🤝 Need Help?

1. **For Terraform questions**: Ask your team lead
2. **For Azure questions**: Check Azure docs or ask cloud team
3. **For Spacelift questions**: Check docs.spacelift.io
4. **For git/GitHub questions**: Ask a teammate who knows git

Good luck! 🚀
