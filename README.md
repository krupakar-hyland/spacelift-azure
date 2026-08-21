# Spacelift Azure Infrastructure Demo

This repository contains Terraform code to provision basic Azure infrastructure using Spacelift with managed identity and federated credentials.

Each app lives in its own folder under `apps/`, with its own `environments/`, and every Spacelift stack sets its **Project Root** to that app's folder.

## Apps

| App | Path | Resources |
|---|---|---|
| `storage` | `apps/storage/` | Resource Group, Storage Account, Storage Container |
| `networking` | `apps/networking/` | Resource Group, Virtual Network, Subnet |

## Prerequisites

1. **Azure Subscription**: You need an active Azure subscription
2. **Spacelift Account**: https://moviepotter.app.spacelift.io
3. **Managed Identity**: Created in Azure with federated credentials configured
4. **Stacks**: one Spacelift stack per (app × environment) — see [Spacelift Stack Configuration](./docs/MULTI_APP_STRUCTURE.md#spacelift-stack-configuration-per-app--environment) for the naming convention and settings table

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

### Multi-Environment Variables (Init Hook + .auto.tfvars)

Environment-specific values live in `apps/<app>/environments/<env>.tfvars` and are committed to the repo (non-secret config only). Each Spacelift stack is pointed at one app (via **Project Root**) and one environment (via a single `ENVIRONMENT` stack variable) — no Terraform code hardcodes either.

**How it works:**

1. `.spacelift/config.yml` (at the repo root, shared by every stack) defines a `before_init` hook that runs on every plan/apply
2. Because the stack's Project Root is set to `apps/<app>`, the hook runs with that folder as its working directory
3. The hook reads the `ENVIRONMENT` variable set on the stack (e.g. `dev`, `staging`, `prod`) and copies `environments/${ENVIRONMENT}.tfvars` → `./spacelift.auto.tfvars` — both paths relative to the app folder
4. Terraform auto-loads `*.auto.tfvars` files — no `-var-file` flag needed

See [`docs/MULTI_APP_STRUCTURE.md`](./docs/MULTI_APP_STRUCTURE.md) for why the hook is anchored on `TF_VAR_spacelift_workspace_root` (a dynamic variable Spacelift sets on every run) rather than a relative path, and the full per-stack settings table.

**Setup per stack:**

1. Create one Spacelift stack per (app × environment), e.g. `storage-dev`, `storage-staging`, `storage-prod`, `networking-dev`, etc. — set each stack's **Project Root** to `apps/storage` or `apps/networking` accordingly
2. On each stack, set the environment variable:
   ```
   ENVIRONMENT = dev      # or staging, prod
   ```
3. Run Plan — the hook output confirms which file was loaded:
   ```
   Loaded variables from environments/dev.tfvars
   ```

**Adding a new environment to an existing app:**

1. Create `apps/<app>/environments/qa.tfvars` with the required variables (see that app's `variables.tf`)
2. Create a new Spacelift stack (or reuse an existing one) with `ENVIRONMENT=qa` and Project Root `apps/<app>`
3. No changes needed to `.spacelift/config.yml` or Terraform code

**Adding a new app:** create a new `apps/<name>/` folder (its own `main.tf`/`variables.tf`/`outputs.tf`/`environments/`) and new Spacelift stacks pointed at it — again, no changes needed to `.spacelift/config.yml` or `scripts/select-env.sh`.

For local testing without Spacelift, see **Running Locally** below.

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

The `.spacelift/config.yml` hook only runs inside Spacelift. Locally, `cd` into the app you want to run and load an environment file yourself:

```bash
cd apps/storage   # or apps/networking

# Pick an environment
cp environments/dev.tfvars terraform.tfvars

terraform init
terraform plan
terraform apply

# Destroy when done
terraform destroy
```

Or use `apps/storage/terraform.tfvars.example` as a starting point for one-off values that don't belong to any committed environment.

## Authentication Flow

1. Spacelift generates an OIDC token based on the run type and scope
2. Token is written to `/mnt/workspace/spacelift.oidc` during execution
3. Azure provider exchanges token with Azure AD for an access token
4. Terraform uses the access token to provision resources
5. No secrets stored - purely token-based OIDC authentication

## Spacelift Environment Variables Reference

Every run exposes a set of variables in the shell environment (visible to hooks) and, for anything prefixed `TF_VAR_`, as Terraform input variables too. Captured from a real run's `env | sort` output:

**Workspace & path resolution:**

| Variable | Example value | Purpose |
|---|---|---|
| `PWD` | `/mnt/workspace/source/apps/networking` | Confirms cwd during hooks is the stack's Project Root, not the repo root |
| `TF_VAR_spacelift_workspace_root` | `/mnt/workspace` | The run's workspace directory — one level above the repo clone. `.spacelift/config.yml`'s hook is anchored on this |
| `TF_VAR_spacelift_project_root` | `apps/networking` | The Project Root configured on the stack |

**Azure authentication (OIDC):**

| Variable | Purpose |
|---|---|
| `ARM_USE_OIDC` | Tells the azurerm provider to use OIDC instead of a client secret |
| `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` | Identify which managed identity/tenant/subscription to authenticate as |
| `ARM_OIDC_TOKEN_FILE_PATH` | Where Spacelift writes the signed OIDC token for the provider to read |
| `SPACELIFT_OIDC_TOKEN` | The raw Spacelift-issued OIDC token (masked in logs) |

**Run identity & metadata:**

| Variable | Example value | Purpose |
|---|---|---|
| `TF_VAR_spacelift_run_id` | `01M0CVT6FR8AN34ZTGWJZ2T35T` | Unique ID for this run |
| `TF_VAR_spacelift_run_type` | `TRACKED` | Push-triggered run (vs `PROPOSED` for PRs, `TASK`, `DESTROY`) |
| `TF_VAR_spacelift_run_state` | `INITIALIZING` | Current run phase |
| `TF_VAR_spacelift_run_trigger` | your email | Who/what triggered the run |
| `TF_VAR_spacelift_commit_sha` / `commit_branch` | commit SHA / `feature/multi-app-structure` | Exact commit and branch being run |
| `TF_VAR_spacelift_stack_id` | `azure-multiapp-demo-stack` | Which stack this is |

**Account & platform context:**

| Variable | Example value | Purpose |
|---|---|---|
| `TF_VAR_spacelift_account_name` | `moviepotter` | Your Spacelift account slug |
| `TF_VAR_spacelift_space_id` | `root` | Which Spacelift space the stack lives in |
| `TF_IN_AUTOMATION` | `1` | Tells Terraform it's running non-interactively |
| `ENVIRONMENT` | `dev` | Not Spacelift-native — our own variable that `scripts/select-env.sh` reads |

Since every `TF_VAR_spacelift_*` variable is automatically usable as a Terraform input (`var.spacelift_run_trigger`, etc.), these can drive resource tags or naming without any extra wiring — e.g. `common_tags.DeployedBy = var.spacelift_run_trigger`.

## Useful Links

- [Multi-App Repo Structure](./docs/MULTI_APP_STRUCTURE.md) — how this branch is organized and why
- [Variable Management Strategies](./docs/VARIABLE_STRATEGIES.md)
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
- Change `storage_account_name` in `apps/storage/terraform.tfvars` (must be unique globally)

**Issue: Terraform state conflicts**
- In Spacelift UI, go to stack and click **Unlock** if state is locked
