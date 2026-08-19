# Structuring a Repo for Multiple Terraform Apps (Each With Its Own Environments)

This repo currently holds one Terraform application (a resource group + storage account + container) with a working multi-environment pattern — see `environments/*.tfvars`, `.spacelift/config.yml`, and `scripts/select-env.sh`. This doc extends that pattern to answer: **what happens when a second, third, or Nth independent Terraform application needs to live alongside it, each with its own dev/staging/prod tiers?**

For variable-management strategies in general (contexts, mounted files, OPA policies, CI/CD injection, etc.), see [`VARIABLE_STRATEGIES.md`](./VARIABLE_STRATEGIES.md). This doc is scoped specifically to **folder and stack structure**, not variable strategy.

---

## The Pattern: Monorepo of App Folders

One repo, one folder per app under `apps/`. Each app folder is a **fully self-contained Terraform root** — its own `main.tf`/`variables.tf`/`outputs.tf`, its own `environments/`, its own Terraform state. One Spacelift stack per (app × environment), pointed at that app's folder via the stack's **Project Root** setting.

```
spacelift-azure/
├── apps/
│   ├── storage/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── environments/
│   │       ├── dev.tfvars
│   │       ├── staging.tfvars
│   │       └── prod.tfvars
│   └── networking/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── environments/
│           ├── dev.tfvars
│           ├── staging.tfvars
│           └── prod.tfvars
├── modules/                      # optional — see "When to Add modules/" below
│   └── tagging/
├── scripts/
│   └── select-env.sh             # single shared script, unchanged per app
├── .spacelift/
│   └── config.yml                # single shared file, repo root only
└── docs/
```

**Naming convention:** `apps/` is recommended over `stacks/` — the latter overloads Spacelift's own term "stack," which here means one (app × environment) deployable unit, not a folder. `projects/` or `components/` are acceptable synonyms if `apps/` doesn't fit your domain language.

Each app folder makes no assumptions about sibling folders (no relative references to `../other-app`, except optionally to a shared `../../modules/*`). This gives full state isolation per app — a bad apply in `networking` can't touch `storage`'s state.

---

## How Spacelift Actually Resolves This (verified against docs.spacelift.io)

Three behaviors matter here, and getting them wrong silently breaks the whole setup:

1. **`.spacelift/config.yml` must live at the repo root, never inside a Project Root subfolder.** There is exactly one shared hook config for every stack in the repo, regardless of which app folder each stack targets. There's no per-folder config file mechanism.

2. **The working directory for hooks (`before_init`, etc.) is the stack's Project Root, not the repo root**, whenever Project Root is set. Per Spacelift's docs: *"Your Git repository is cloned into `/mnt/workspace/source/`, which also serves as the working directory for your project, unless explicitly overridden by the project root configuration setting."* This is Spacelift's own documented pattern for monorepos with per-project tfvars — exactly the `select-env.sh` approach already used in this repo.

3. **Don't set `project_root` inside `stack_defaults` in the shared `config.yml`.** Settings in `config.yml` take precedence over per-stack UI settings — a repo-wide default there would silently force every stack onto the same folder, breaking the multi-app setup. Project Root stays a **per-stack** setting (configured per stack in the UI, or via `spacelift_stack.project_root` if stacks are later managed via the Spacelift Terraform provider).

**Practical fallout:** `scripts/select-env.sh`'s own logic (`environments/${ENVIRONMENT}.tfvars`, resolved relative to cwd) needs **zero changes** to work per-app — cwd automatically becomes the correct app folder once Project Root is set. Only the **hook's invocation path** in `config.yml` needs adjusting, since `scripts/` stays at the repo root while cwd moves into `apps/<name>/`.

Sources: [Runtime Configuration](https://docs.spacelift.io/concepts/configuration/runtime-configuration), [Runtime YAML Reference](https://docs.spacelift.io/concepts/configuration/runtime-configuration/runtime-yaml-reference), [Stack Settings](https://docs.spacelift.io/concepts/stack/stack-settings), [Environment](https://docs.spacelift.io/concepts/configuration/environment), [Handling .tfvars](https://docs.spacelift.io/vendors/terraform/handling-tfvars).

---

## The Shared `.spacelift/config.yml`

```yaml
version: 1

stack_defaults:
  before_init:
    - chmod +x ../../scripts/select-env.sh
    - ../../scripts/select-env.sh
```

**Why `../../`:** cwd during hook execution equals the stack's Project Root (e.g. `apps/storage`), which sits exactly two path segments below the repo root under the `apps/<name>/` convention above. `../..` from `apps/storage` lands back at the repo root, where `scripts/select-env.sh` lives. This is guaranteed correct as long as every app folder stays at that fixed depth.

**Fallback for inconsistent nesting:** if an app ever needs deeper nesting (e.g. `apps/team-a/storage`), that stack's hook path breaks and needs a per-stack override in the `stacks:` block of the same `config.yml`. Spacelift also exposes `TF_VAR_spacelift_workspace_root` (the repo clone root, `/mnt/workspace/source`) as a dynamic variable, which could anchor an absolute path instead:
```yaml
before_init:
  - chmod +x "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
  - "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
```
This isn't the default recommendation — Spacelift's docs don't explicitly confirm this variable is populated as a shell environment variable before the first `before_init` line runs (as opposed to only being materialized once `terraform init/plan` actually executes). The fixed relative-path form has no such dependency and is pure, always-correct filesystem math given the flat `apps/<name>/` layout, so it's the safer default. Only reach for the env-var-anchored form if folder depth genuinely varies across apps.

**`scripts/select-env.sh` itself needs no changes** — same content as today's single-app version.

---

## Spacelift Stack Configuration per App × Environment

**Naming convention:** `<app>-<env>`, e.g. `storage-dev`, `storage-staging`, `storage-prod`, `networking-dev`, `networking-staging`, `networking-prod`.

| Setting | Value |
|---|---|
| Name | `<app>-<env>` |
| Repository / branch | same repo, `main`, for every stack |
| **Project Root** | `apps/<app>` (e.g. `apps/storage`, `apps/networking`) |
| Stack variable `ENVIRONMENT` | `dev` / `staging` / `prod` |
| Labels (optional) | `app:<app>`, `env:<env>` — for filtering/search in the Spacelift UI |

**No `APP` stack variable is needed.** Project Root already fully determines which app's code and `environments/` folder a stack runs against — `select-env.sh` never needs to know "which app am I," because it only ever sees its own app's `environments/` directory (cwd-relative). If app identity needs to appear as a resource tag, put it in that app's own `variables.tf` default or `environments/*.tfvars` (e.g. `common_tags.Project = "networking"`) — not as a Spacelift-level variable. Labels are the right tool for UI grouping, not a `TF_VAR_`-injected value.

Total stack count for N apps × M environments = N×M stacks, all sharing the one `.spacelift/config.yml`.

---

## When to Add `modules/`

Don't add it preemptively. With two apps, duplicating a small `common_tags` block or a resource-group resource is cheap and keeps each app's lifecycle fully independent — a tagging change for `storage` shouldn't require touching `networking`.

Add `modules/` once **≥2 apps need identical, nontrivial, multi-resource logic** that would otherwise drift out of sync — e.g. a `modules/tagging` module enforcing mandatory tag keys plus merging in app-specific tags, or a `modules/naming` module enforcing an Azure resource-naming convention across apps. Reference with a local relative path since everything is one repo: `source = "../../modules/tagging"` — no registry or versioning needed at this scale. Promote it to Spacelift's Module Registry only if the module needs to be consumed *outside* this repo (see [Spacelift's module documentation](https://docs.spacelift.io/concepts/module/)).

Rule of thumb: 3+ apps sharing the exact same block, or any cross-app governance rule a platform team wants centrally enforced → module it. Two apps sharing 5 lines of tag map → leave it duplicated.

---

## Trade-offs vs Other Patterns

| Dimension | Monorepo of apps (this doc) | One repo per app | CIN-style metarepo |
|---|---|---|---|
| Setup complexity | Low — one repo, one `config.yml`, N×M stacks via Project Root | Low per-repo, but linear setup cost per new app | High — requires the Spacelift Terraform provider, API keys, a `standard_stack`-style module |
| Blast radius / isolation | Good — each app is its own Terraform root/state | Best — full repo-level isolation (permissions, CI, history) | Good — same state isolation, but stack *definitions* are centrally managed |
| State isolation | Per-app-per-env state | Per-app-per-env state | Per-app-per-env state (stack *management* is centralized, not state) |
| Discoverability | Good — one place to see every app | Poor at scale — must know which of N repos to check | Best — single source of truth across the org |
| CI/CD complexity | Low — Spacelift triggers per-stack on path changes natively | Low per-repo, but N pipelines to maintain | Higher — the metarepo needs its own guarded pipeline |
| Graduate here when | You have >1 logically-independent app in one place | Apps have different owners/release cadences/access needs | Managing Spacelift *itself* at scale, across many teams |

---

## Worked Example: Adding a Second App (`networking`)

### App 1 — `apps/storage/`
Today's repo-root code (`main.tf`, `variables.tf`, `outputs.tf`, `environments/*.tfvars`), relocated under `apps/storage/` with no content changes.

### App 2 — `apps/networking/` (illustrative)

`apps/networking/main.tf`:
```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "network" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.common_tags
}

resource "azurerm_subnet" "app" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_address_prefixes
}
```

`apps/networking/variables.tf` follows the same shape as the storage app's: `location`, `resource_group_name`, `vnet_name`, `vnet_address_space` (list(string)), `subnet_name`, `subnet_address_prefixes` (list(string)), `common_tags`.

`apps/networking/outputs.tf`: `resource_group_id`, `vnet_id`, `subnet_id`.

`apps/networking/environments/dev.tfvars`:
```hcl
location                = "eastus"
resource_group_name     = "rg-spacelift-demo-network-dev"
vnet_name                = "vnet-spacelift-demo-dev"
vnet_address_space       = ["10.0.0.0/16"]
subnet_name              = "snet-app-dev"
subnet_address_prefixes  = ["10.0.1.0/24"]

common_tags = {
  Environment = "dev"
  ManagedBy   = "Spacelift"
  Project     = "Spacelift-Demo-Networking"
}
```
`staging.tfvars` / `prod.tfvars` follow the same shape with `10.1.0.0/16` / `10.2.0.0/16` and `staging`/`production` tags — mirroring the storage app's dev/staging/prod tiering exactly.

**Spacelift stacks for app 2:**

| Stack name | Project Root | `ENVIRONMENT` | Labels |
|---|---|---|---|
| `networking-dev` | `apps/networking` | `dev` | `app:networking`, `env:dev` |
| `networking-staging` | `apps/networking` | `staging` | `app:networking`, `env:staging` |
| `networking-prod` | `apps/networking` | `prod` | `app:networking`, `env:prod` |

**No changes to `.spacelift/config.yml` or `scripts/select-env.sh` are needed to add this app** — only a new folder plus three new stacks. This mirrors the "adding a new environment requires no code changes" property the single-app pattern already has, now extended to "adding a new app requires no code changes" either.
