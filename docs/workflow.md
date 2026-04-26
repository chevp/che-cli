---
title: Workflows — che-cli
---

# Workflows

`che workflow` runs a YAML manifest of shell-script steps. The manifest is a
**pointer** — it declares order, args, and inputs, but never contains inline
bash. The actual logic stays in your `scripts/` tree, executable on its own.

> Source: [github.com/chevp/che-cli](https://github.com/chevp/che-cli) ·
> Back to [overview](./index.md)

---

## Why a separate folder

Most repos already mix three dispatch layers — `package.json` scripts, a
`scripts/` directory of shell files, and one or more `docker-compose*.yml`
flavours. Each layer answers a different kind of question, and none of them
makes the **build → test → deploy pipeline** discoverable.

`.che/workflows/` is that missing layer. It mirrors `.github/workflows/` so
intent is obvious — *this is a pipeline, run with `che`* — but it stays
local: no runner, no minutes, no commit required to iterate.

The workflow files reference your existing scripts. They don't replace them.

---

## Layout

```
<repo>/
├── .che/
│   └── workflows/
│       ├── release-desktop.yml
│       ├── deploy-installers.yml
│       └── demo.yml
└── scripts/
    ├── build-electron-mac-thin-local.sh
    ├── build-electron-windows-thin-local.sh
    └── desktop/
        └── deploy-cyon-installers.sh
```

`che` walks up from `$PWD` looking for `.che/workflows/`, so workflows can be
invoked from anywhere inside the repo.

---

## File shape

```yaml
name: release-desktop
description: Build mac + windows installers and publish a GitHub release

inputs:
  - name: tag
    required: true
    description: Release tag (vX.Y.Z)

steps:
  - name: macOS build (native)
    script: scripts/build-electron-mac-thin-local.sh
    args: ["--release", "${tag}"]

  - name: Windows build (docker/wine)
    script: scripts/build-electron-windows-thin-local.sh
    args: ["--release", "${tag}"]
```

### Top-level fields

| Field         | Required | Description                                                       |
|---------------|----------|-------------------------------------------------------------------|
| `name`        | yes      | Workflow identifier. Should match the filename.                   |
| `description` | no       | One-line summary, shown by `che workflow list`.                   |
| `inputs`      | no       | List of input parameters, see below.                              |
| `steps`       | yes      | Non-empty list of steps, executed in order.                       |

### `inputs[]`

| Field         | Required | Description                                                       |
|---------------|----------|-------------------------------------------------------------------|
| `name`        | yes      | Input identifier. Pass at the CLI as `--<name>=value`.            |
| `required`    | no       | If `true`, the workflow refuses to run when the input is absent.  |
| `description` | no       | Shown by `che workflow show`.                                     |

### `steps[]`

| Field    | Required | Description                                                                          |
|----------|----------|--------------------------------------------------------------------------------------|
| `name`   | no       | Human-readable label printed before the step runs.                                   |
| `script` | yes      | Path to an executable shell script, relative to the workflow root (the folder containing `.che/`). No inline bash is allowed — *this is the rule that makes the format normalized.* |
| `args`   | no       | List of strings passed to the script. Each entry is shell-substituted for `${input}` placeholders before exec. |

### Substitution

Only one form is supported: `${input_name}`. There are no expressions, no
defaults, no `if`. If you find yourself needing logic, push it into the script.

---

## Commands

### `che workflow list`

Lists every workflow in the repo with its `description`.

```sh
$ che workflow list
/Users/me/cura/.che/workflow
  demo              — Modus 3 standalone demo (no Docker)
  demo-jvm          — Demo in JVM mode (skip GraalVM)
  dev-up            — Bring up the local Cura dev stack
  release-desktop   — Build mac + windows installers, publish GitHub release
  deploy-installers — Upload built installers to my.cyon
```

### `che workflow show <name>`

Validates the file shape and prints the **normalized step plan** — what `che`
will actually execute, with the input slots still as `${...}` placeholders.

```sh
$ che workflow show release-desktop
name        release-desktop
description Build mac + windows installers and publish a GitHub release
file        /Users/me/cura/.che/workflows/release-desktop.yml
root        /Users/me/cura

inputs
  - tag  (required)  Release tag (vX.Y.Z)

steps
  1. macOS build (native)
     script scripts/build-electron-mac-thin-local.sh
     args   --release ${tag}
  2. Windows build (docker/wine)
     script scripts/build-electron-windows-thin-local.sh
     args   --release ${tag}
```

### `che workflow run <name>` (alias: `che run <name>`)

Executes the workflow.

```sh
che run release-desktop --tag=v0.4.0
che workflow run release-desktop --tag=v0.4.0     # equivalent
che run release-desktop --tag=v0.4.0 --dry-run    # print plan, do not exec
```

Each step is a separate `bash <script> <substituted-args...>` invocation.
Steps run sequentially with the workflow root as `$PWD`. The first failing
step aborts the run with that step's exit code.

Required inputs are checked **before** the first step runs — a missing input
exits 1 immediately, with no side effects.

---

## Authoring guidelines

The point of a workflow is to make a pipeline visible. Three rules keep that
property:

1. **One pipeline per file.** If two scripts always run together to ship one
   thing, that's a workflow. Don't fold ten unrelated scripts into a single
   `dev.yml` — write one workflow per intent.
2. **Step scripts stay independently runnable.** A teammate without `che`
   installed must still be able to run any step by hand. Workflows orchestrate;
   they never become a barrier to the underlying scripts.
3. **No logic in the YAML.** If a step needs a conditional, the conditional
   belongs in the script. The YAML only declares order, args, and inputs.

When in doubt: imagine a teammate reading the YAML cold. They should be able
to predict what runs without opening a single shell script.

---

## Doctor

```sh
che doctor workflow
```

Verifies that `python3` (or `python`) and [PyYAML](https://pypi.org/project/PyYAML/)
are available. Workflow files are parsed by a tiny in-tree helper
([lib/che/workflow/yaml_get.py](https://github.com/chevp/che-cli/blob/main/lib/che/workflow/yaml_get.py))
that depends only on PyYAML — no external `yq` binary required.

| Platform   | Install                                                          |
|------------|------------------------------------------------------------------|
| macOS      | `brew install python && pip3 install pyyaml`                     |
| Windows    | `winget install --id Python.Python.3.12 && pip install pyyaml`   |
| Linux/WSL  | `apt install python3 python3-yaml` (or `pip3 install pyyaml`)    |

---

## Why not just a `Makefile` or `npm scripts`?

Both work for one-shot dispatch (`make build`, `npm run build`) and `che`
deliberately does not try to replace them.

The thing they don't give you is a **stage manifest**. A `Makefile` target
that calls four scripts is opaque — you have to read the recipe to learn the
order. `package.json` flattens everything to one-liners and forces multi-step
pipelines to be expressed by chaining script names with `&&`.

A workflow file makes the pipeline first-class:

- `che workflow show <name>` prints the parsed plan before you run anything.
- `--dry-run` walks the steps with substituted args, never invoking them.
- `che workflow list` advertises every pipeline in the repo, with descriptions.

If your project only needs `make build`, you don't need workflows. If it has
a `release-desktop.sh` orchestrator at the bottom calling three other scripts,
that's the case workflows were built for.

---

## Comparison with GitHub Actions

The format is intentionally close to `.github/workflows/*.yml` but stripped to
the minimum:

| GitHub Actions          | che workflow              | Notes                                                      |
|-------------------------|---------------------------|------------------------------------------------------------|
| `on:`                   | —                         | Always triggered manually by `che run`.                    |
| `jobs:` + `steps:`      | `steps:` only             | One job. Sequential. No matrix.                            |
| `runs-on:`              | —                         | Always the local host.                                     |
| `uses: <action>`        | —                         | No action library. Use `script:` and write the script.     |
| `run: <bash>`           | `script: <path>`          | Inline bash is rejected — every step must be a script file.|
| `${{ inputs.x }}`       | `${x}`                    | Plain substitution, no expressions.                        |
| `needs:` / parallelism  | —                         | v1 is sequential by design.                                |

If you outgrow the local format, the same scripts can be wrapped by an actual
GitHub Actions workflow without changes — that was the design goal.

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
