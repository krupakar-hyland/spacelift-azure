# Spacelift Azure Infrastructure Demo

This repository contains Terraform code to provision basic Azure infrastructure using Spacelift with managed identity and federated credentials.

## Resources Included

- **Resource Group**: Basic Azure resource container
- **Storage Account**: Azure Storage with multiple replication options
- **Storage Container**: Blob storage container within the storage account

## Prerequisites

1. **Azure Subscription**: You need an active Azure subscription
2. **Spacelift Account**: Created in your Hyland organization (https://krupakar-hyland.app.spacelift.io)
3. **Service Principal**: For Spacelift to authenticate with Azure using federated credentials

## Initial Setup Steps

### Step 1: Create Azure Service Principal for Spacelift

```bash
# Login to Azure
az login

# Get your subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Create service principal
az ad sp create-for-rbac \
  --name "spacelift-sp" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID"

# Note: Save the output - you'll need the appId and objectId
```

### Step 2: Create Manual Stack in Spacelift (Portal Method)

1. Go to your Spacelift account: https://krupakar-hyland.app.spacelift.io
2. Click **Create Stack** → **New Stack**
3. Configure:
   - **Name**: `azure-demo-stack`
   - **Repository**: Select this repository
   - **Branch**: `main`
   - **Project**: Create or select existing project
4. Click **Create Stack**

### Step 3: Configure Federated Credentials in Spacelift

1. In Spacelift, go to **Settings** → **Integrations** → **Azure**
2. Choose **Federated Credentials** authentication
3. Fill in:
   - **Tenant ID**: Your Azure tenant ID
   - **Subscription ID**: Your Azure subscription ID
   - **Client ID**: Service principal app ID
4. Create the federated credential relationship between Spacelift and Azure

### Step 4: Configure Stack Environment Variables

In the Spacelift UI, set these as Stack Environment Variables:

```
ARM_CLIENT_ID = <your-service-principal-client-id>
ARM_TENANT_ID = <your-azure-tenant-id>
ARM_SUBSCRIPTION_ID = <your-subscription-id>
ARM_USE_OIDC = true
```

### Step 5: Create terraform.tfvars

```bash
# Copy the example file and customize
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

Update the storage account name to be globally unique (lowercase alphanumeric only).

### Step 6: Initialize and Plan

In Spacelift UI:

1. Go to your stack
2. Click **Actions** → **Plan**
3. Review the proposed changes
4. If approved, click **Actions** → **Apply**

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

## Spacelift Integration Details

### Managed Identity vs Federated Credentials

- **Managed Identity**: Works when Spacelift runs on Azure infrastructure (Azure VM, App Service)
- **Federated Credentials**: Recommended for external Spacelift (uses OIDC tokens)

Since you're using the cloud-hosted Spacelift, **federated credentials** is the right approach.

### Authentication Flow

1. Spacelift generates an OIDC token
2. Token is exchanged with Azure AD for an access token
3. Terraform uses the access token to provision resources
4. No secrets stored - purely token-based authentication

## Outputs

After applying, you'll get:

- Resource Group ID and name
- Storage Account ID and name
- Primary blob endpoint
- Storage Container ID

## Next Steps

1. Create the manual stack in Spacelift first
2. Test planning and applying
3. Explore Spacelift features:
   - **Policies**: Enforce infrastructure standards
   - **Drift Detection**: Monitor real vs declared state
   - **Scheduled Runs**: Automate regular deployments
   - **Notifications**: Slack, Teams, PagerDuty integration

## Useful Links

- [Spacelift Azure Integration](https://docs.spacelift.io/integrations/cloud-providers/azure)
- [Spacelift Stacks Documentation](https://docs.spacelift.io/concepts/stack)
- [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## Troubleshooting

**Issue: Authentication fails**
- Verify federated credential is configured in Spacelift
- Check ARM_* environment variables are set correctly
- Ensure service principal has Contributor role on subscription

**Issue: Storage account name already exists**
- Change `storage_account_name` in terraform.tfvars (must be unique globally)

**Issue: Terraform state conflicts**
- In Spacelift UI, go to stack and click **Unlock** if state is locked
