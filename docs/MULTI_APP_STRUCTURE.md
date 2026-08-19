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

Three things make this pattern possible:

1. **`.spacelift/config.yml` lives at the repo root only** — one shared hook config serves every stack, regardless of which app folder it targets.
2. **Hooks run with the stack's Project Root as the working directory, not the repo root.** Spacelift clones the repo to `/mnt/workspace/source/`; a real run's `env | sort` output confirmed this directly — `TF_VAR_spacelift_workspace_root=/mnt/workspace` and `PWD=/mnt/workspace/source/apps/networking`. Because of this, `scripts/select-env.sh` needs **zero per-app changes** — it already resolves `environments/${ENVIRONMENT}.tfvars` relative to cwd, and cwd is always the correct app folder.
3. **Never set `project_root` inside `stack_defaults`.** Settings in `config.yml` take precedence over per-stack UI settings, so a repo-wide default there would silently force every stack onto the same folder. Project Root stays a per-stack setting.

> **Watch out — UI hooks silently replace `stack_defaults`, they don't merge with it.** If a stack has *any* `before_init` hook added directly in Spacelift's UI (e.g. left over from testing), that fully overrides `stack_defaults.before_init` for that stack — no error, no log line, Terraform just falls back to `variables.tf` defaults since `spacelift.auto.tfvars` never gets created. Confirmed directly: a stack with 5 manually-added UI hooks (`ls -al`, `env | sort`, etc.) logged `Initializing workspace with 5 custom hooks...` and never ran the repo's script. **Every stack needs zero UI-defined hooks** for the shared config to take effect.

### Troubleshooting: resources created with default values

Symptom: the apply succeeds, but resources come up with `variables.tf` defaults instead of `environments/<env>.tfvars` values, and the init log never shows `Loaded variables from environments/<env>.tfvars`.

Check the **Initializing** phase of the run (separate from Plan/Apply, easy to miss) for `Initializing workspace with N custom hooks...`:
- `N` matches `config.yml`'s count (2 here — the `chmod` + script call) → the shared hook is running; look further down that phase for the actual failure.
- `N` is anything else → the stack has its own UI-defined hooks (see callout above). Remove them so `stack_defaults` takes over.

Sources: [Runtime Configuration](https://docs.spacelift.io/concepts/configuration/runtime-configuration), [Runtime YAML Reference](https://docs.spacelift.io/concepts/configuration/runtime-configuration/runtime-yaml-reference), [Stack Settings](https://docs.spacelift.io/concepts/stack/stack-settings), [Environment](https://docs.spacelift.io/concepts/configuration/environment), [Handling .tfvars](https://docs.spacelift.io/vendors/terraform/handling-tfvars).

---

## The Shared `.spacelift/config.yml`

```yaml
version: 1

stack_defaults:
  before_init:
    - chmod +x "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
    - "${TF_VAR_spacelift_workspace_root}/source/scripts/select-env.sh"
```

`TF_VAR_spacelift_workspace_root` is a dynamic variable Spacelift sets on every run — the run's workspace directory (`/mnt/workspace`), one level above where the repo is cloned (`/mnt/workspace/source/`). Appending `/source/scripts/select-env.sh` gives an absolute path that resolves correctly from any app's Project Root, at any nesting depth.

**Simpler alternative, if every app stays at the same depth:** since cwd during hooks is always the app's Project Root, a fixed relative path also works:
```yaml
before_init:
  - chmod +x ../../scripts/select-env.sh
  - ../../scripts/select-env.sh
```
`../..` from `apps/storage` (two segments below the repo root) lands back at the root — correct only as long as every app folder sits at that same fixed depth. The absolute form above has no such constraint, which is why it's the default here.

`scripts/select-env.sh` itself needs no changes either way.

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
2. Create three Spacelift stacks (`<name>-dev`, `<name>-staging`, `<name>-prod`), each with Project Root `apps/<name>`, with **no UI-defined hooks** on any of them
3. No changes needed to `.spacelift/config.yml` or `scripts/select-env.sh`

This is exactly how `apps/networking/` was added alongside `apps/storage/` — see its `main.tf` (VNet + subnet), `variables.tf`, and `environments/*.tfvars` for a working reference.
