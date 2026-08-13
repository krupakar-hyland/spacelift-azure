# Spacelift Azure Infrastructure Demo

This repository contains Terraform code to provision basic Azure infrastructure using Spacelift with managed identity and federated credentials.

## Resources Included

- **Resource Group**: Basic Azure resource container
- **Storage Account**: Azure Storage with multiple replication options
- **Storage Container**: Blob storage container within the storage account

## Prerequisites

1. **Azure Subscription**: You need an active Azure subscription
2. **Spacelift Account**: https://moviepotter.app.spacelift.io
3. **Managed Identity**: Created in Azure with federated credentials configured
4. **Stack**: `azure-demo-stack` created in Spacelift

## Configuration

### Azure Federated Credentials

This setup uses OIDC-based federated credentials for authentication. Five separate credentials are configured for different purposes:

| Purpose | Subject | Scope |
| --- | --- | --- |
| **Terraform Apply** | `space:<space-id>:stack:azure-demo-stack:run_type:TRACKED:scope:write` | Write |
| **Terraform Plan** | `space:<space-id>:stack:azure-demo-stack:run_type:TRACKED:scope:read` | Read |
| **Pull Request Plan** | `space:<space-id>:stack:azure-demo-stack:run_type:PROPOSED:scope:read` | Read |
| **Manual Task** | `space:<space-id>:stack:azure-demo-stack:run_type:TASK:scope:write` | Write |
| **Destroy** | `space:<space-id>:stack:azure-demo-stack:run_type:DESTROY:scope:write` | Write |

**OIDC Issuer Details:**
- **Issuer URL**: `https://moviepotter.app.spacelift.io`
- **Audience**: `moviepotter.app.spacelift.io`

### Stack Environment Variables

Configure these in the Spacelift stack settings:

```
ARM_CLIENT_ID = <managed-identity-client-id>
ARM_TENANT_ID = <azure-tenant-id>
ARM_SUBSCRIPTION_ID = <azure-subscription-id>
ARM_USE_OIDC = true
ARM_OIDC_TOKEN_FILE_PATH = /mnt/workspace/spacelift.oidc
```

### Terraform Configuration

1. Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Update with your values (storage account name must be globally unique, lowercase alphanumeric only)

### GitHub Integration & Webhooks

For automatic runs when pushing code or opening pull requests, you need to connect Spacelift to GitHub via the **GitHub App integration** (not raw Git).

**Why it matters:**
- **Raw Git URL**: Spacelift can clone the repo, but GitHub has no way to notify Spacelift about changes. Runs only trigger manually or on schedule.
- **GitHub App**: Installs an app on your GitHub account that automatically delivers push and pull request events to Spacelift based on the app's configured permissions and event subscriptions.

**Setup:**

1. **Install GitHub App Integration**
   - Go to: `https://moviepotter.app.spacelift.io/vcs/integrations`
   - Click **Create Integration** → **GitHub App**
   - Authorize and grant access to your GitHub organization and repository

2. **Configure Stack Source Code**
   - Go to: `https://moviepotter.app.spacelift.io/stack/azure-demo-stack/settings/source-code`
   - Change from **Raw Git** to the **GitHub App** integration
   - Specify branch: `main`

3. **Verify GitHub App Configuration**
   - The webhook is configured at the **app level**, not per-repository
   - To verify: Go to GitHub Settings → **Installed GitHub Apps** → Click the Spacelift app
   - The app automatically delivers all subscribed events (push, pull_request) to Spacelift
   - An empty "Webhooks" section under the repo settings is expected — the app handles event delivery

**Automatic Run Triggers:**
- **Push to main branch**: Triggers a `TRACKED` run (proposed changes can be applied)
- **Pull Request**: Triggers a `PROPOSED` run (plan-only, no apply until merged)
- **Direct Apply**: Manually trigger in Spacelift UI with **Actions** → **Apply**
- **Destroy**: Manually trigger in Spacelift UI with **Actions** → **Destroy**

## Running Locally (Development)

If you want to test locally before creating the stack:

```bash
# Install Terraform
terraform init

# Plan the deployment
terraform plan

# Apply if satisfied
terraform apply

# Destroy when done
terraform destroy
```

## Authentication Flow

1. Spacelift generates an OIDC token based on the run type and scope
2. Token is written to `/mnt/workspace/spacelift.oidc` during execution
3. Azure provider exchanges token with Azure AD for an access token
4. Terraform uses the access token to provision resources
5. No secrets stored - purely token-based OIDC authentication

## Useful Links

- [Spacelift Azure Integration](https://docs.spacelift.io/integrations/cloud-providers/azure)
- [Spacelift Stacks Documentation](https://docs.spacelift.io/concepts/stack)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Troubleshooting

**Issue: OIDC authentication fails**
- Verify federated credentials are configured in Azure for all required purposes
- Check that Subject claims match your space ID and stack name
- Ensure Issuer URL and Audience match Azure federated credential configuration
- Verify `ARM_OIDC_TOKEN_FILE_PATH` points to `/mnt/workspace/spacelift.oidc`

**Issue: Insufficient permissions**
- Verify managed identity has appropriate RBAC roles on the subscription
- Check that federated credential scope (read/write) matches the operation type

**Issue: Storage account name already exists**
- Change `storage_account_name` in terraform.tfvars (must be unique globally)

**Issue: Terraform state conflicts**
- In Spacelift UI, go to stack and click **Unlock** if state is locked
