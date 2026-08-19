# Structuring a Repo for Multiple Terraform Apps (Each With Its Own Environments)

This repo holds two Terraform apps — `apps/storage/` and `apps/networking/` — each with its own dev/staging/prod tiers, sharing one Spacelift configuration. This doc explains the pattern, why it works, and how to extend it.

For variable-management strategies in general (contexts, mounted files, OPA policies, CI/CD injection, etc.), see [`VARIABLE_STRATEGIES.md`](./VARIABLE_STRATEGIES.md). This doc is scoped specifically to **folder and stack structure**.

**Contents:** [The Pattern](#the-pattern-monorepo-of-app-folders) · [Why It Works](#why-it-works) · [The Shared config.yml](#the-shared-spaceliftconfigyml) · [Stack Settings](#spacelift-stack-configuration-per-app--environment) · [Adding a `modules/` Folder](#when-to-add-modules) · [Adding an App](#adding-a-new-app)

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
├── modules/                      # optional — added only once ≥2 apps need shared logic
├── scripts/
│   └── select-env.sh             # single shared script, unchanged per app
├── .spacelift/
│   └── config.yml                # single shared file, repo root only
└── docs/
```

- **Naming:** `apps/` is recommended over `stacks/`, which overloads Spacelift's own term "stack" (here meaning one app × environment deployable unit, not a folder). `projects/` or `components/` are fine synonyms.
- **Isolation:** each app folder makes no assumptions about siblings — no `../other-app` references, only an optional shared `../../modules/*`. This gives full state isolation per app: a bad apply in `networking` can't touch `storage`'s state.

---

## Why It Works

Three Spacelift behaviors make this pattern possible — get any of them wrong and the setup breaks silently:

1. **`.spacelift/config.yml` lives at the repo root only**, never inside a Project Root subfolder. One shared hook config serves every stack, regardless of which app folder it targets — there's no per-folder config file mechanism.
2. **The working directory for hooks (`before_init`, etc.) is the stack's Project Root, not the repo root.** Spacelift clones the repo to `/mnt/workspace/source/` and uses that as the working directory *unless* Project Root overrides it — which it does here, for every app stack.
3. **Never set `project_root` inside `stack_defaults` in the shared `config.yml`.** Settings in `config.yml` take precedence over per-stack UI settings, so a repo-wide default there would silently force every stack onto the same folder. Project Root stays a **per-stack** setting.

**Practical effect:** `scripts/select-env.sh`'s own logic (`environments/${ENVIRONMENT}.tfvars`, resolved relative to cwd) needs **zero changes** to work per-app — cwd automatically becomes the correct app folder. Only the hook's *invocation path* in `config.yml` needs adjusting, since `scripts/` stays at the repo root while cwd moves into `apps/<name>/`.

### Confirmed by a live run

A real `TRACKED` run on the `networking` app showed exactly this behavior:

```
PWD=/mnt/workspace/source/apps/networking
ENVIRONMENT=dev
TF_VAR_spacelift_workspace_root=/mnt/workspace
TF_VAR_spacelift_project_root=apps/networking
```

`PWD` is the app's Project Root, not the repo root — matching the design above exactly.

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

**Why `../../`:** cwd during hook execution is the stack's Project Root (e.g. `apps/storage`), exactly two path segments below the repo root under the `apps/<name>/` convention. `../..` from there lands back at the repo root, where `scripts/select-env.sh` lives — correct as long as every app folder stays at that fixed depth.

**If depth ever varies** (e.g. `apps/team-a/storage` nested deeper than `apps/networking`), anchor on the confirmed `TF_VAR_spacelift_workspace_root` variable instead of a relative path:
```yaml
before_init:
  - chmod +x "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
  - "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
```
The fixed relative-path form stays the default recommendation — it's simpler and doesn't depend on any variable being set, so use the absolute form only when folder depth genuinely isn't uniform across apps.

`scripts/select-env.sh` itself needs no changes from the single-app version.

---

## Spacelift Stack Configuration per App × Environment

**Naming convention:** `<app>-<env>` — e.g. `storage-dev`, `storage-staging`, `storage-prod`, `networking-dev`, `networking-staging`, `networking-prod`.

| Setting | Value |
|---|---|
| Name | `<app>-<env>` |
| Repository / branch | same repo, same branch, for every stack |
| **Project Root** | `apps/<app>` (e.g. `apps/storage`, `apps/networking`) |
| Stack variable `ENVIRONMENT` | `dev` / `staging` / `prod` |
| Labels (optional) | `app:<app>`, `env:<env>` — for filtering/search in the Spacelift UI |

**No `APP` stack variable is needed.** Project Root already determines which app's code and `environments/` folder a stack runs against — `select-env.sh` never needs to know "which app am I," since it only ever sees its own app's `environments/` directory. If app identity needs to appear as a resource tag, put it in that app's own `variables.tf` default or `environments/*.tfvars` (e.g. `common_tags.Project = "networking"`) rather than as a Spacelift-level variable. Labels are the right tool for UI grouping, not a `TF_VAR_`-injected value.

Total stack count for N apps × M environments = N×M stacks, all sharing the one `.spacelift/config.yml`.

---

## When to Add `modules/`

Don't add it preemptively. With two apps, duplicating a small `common_tags` block or a resource-group resource is cheap and keeps each app's lifecycle fully independent — a tagging change for `storage` shouldn't require touching `networking`.

Add it once **≥2 apps need identical, nontrivial, multi-resource logic** that would otherwise drift out of sync — e.g. a `modules/tagging` module enforcing mandatory tag keys, or a `modules/naming` module enforcing an Azure naming convention across apps. Reference with a local relative path (`source = "../../modules/tagging"`) — no registry or versioning needed at this scale. Promote to Spacelift's [Module Registry](https://docs.spacelift.io/concepts/module/) only if the module needs to be consumed *outside* this repo.

**Rule of thumb:** 3+ apps sharing the exact same block, or any cross-app governance rule a platform team wants centrally enforced → module it. Two apps sharing 5 lines of tag map → leave it duplicated.

---

## Adding a New App

1. Create `apps/<name>/` with its own `main.tf`/`variables.tf`/`outputs.tf`/`environments/{dev,staging,prod}.tfvars`
2. Create three Spacelift stacks (`<name>-dev`, `<name>-staging`, `<name>-prod`), each with Project Root `apps/<name>`
3. No changes needed to `.spacelift/config.yml` or `scripts/select-env.sh`

This is exactly how `apps/networking/` was added alongside `apps/storage/` — see its `main.tf` (VNet + subnet), `variables.tf`, and `environments/*.tfvars` for a working reference.
