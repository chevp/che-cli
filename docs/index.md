---
title: che-cli
---

# che-cli

A small collection of CLI utilities, glued together by one dispatcher binary
(`che`). Each tool is a subcommand. No plugin system, no manifest — drop a
script in `lib/che/<topic>/`, add a case arm in `bin/che`, done.

> **Source:** [github.com/chevp/che-cli](https://github.com/chevp/che-cli)
>
> **Pages:** [installation](./installation.md) ·
> [workflows](./workflow.md) ·
> [architecture](./architecture.md) ·
> [troubleshooting](./troubleshooting.md)

---

## Install

```sh
git clone https://github.com/chevp/che-cli.git
cd che-cli
./install.sh
che doctor
```

Default install prefix is `~/.local`. Override with `PREFIX=/usr/local ./install.sh`.

Requirements: `bash`, `git`, `curl`, `python3` (or `python`). On Windows, run from Git Bash or WSL.

---

## Commands

### `che commit`

Stages all changes, generates a commit message via the configured LLM provider,
asks for confirmation, commits, optionally pushes.

```sh
che commit
che commit --push
che commit --dry-run
che commit --edit
```

Provider defaults to **Ollama (local)**. Switch via `CHE_PROVIDER`:

| Provider       | Selector                    | Auth                                                |
|----------------|-----------------------------|-----------------------------------------------------|
| Ollama         | `CHE_PROVIDER=ollama`       | none (local server)                                 |
| Claude Code    | `CHE_PROVIDER=claude-code`  | handled by the `claude` CLI (subscription / login)  |
| GitHub Copilot | `CHE_PROVIDER=copilot`      | handled by the `copilot` CLI (Copilot subscription) |

`che` never handles API keys directly. Cloud LLMs are reached only through
their official CLIs — install `claude` or `copilot` and let it own auth.
To remove the local fallback and force every prompt through Claude Code,
set `CHE_FORCE_CLAUDE_CODE=1`.

The HTTP request shape Ollama speaks is kept as an ad-hoc REST sample under
[`client/http/`](https://github.com/chevp/che-cli/tree/main/client/http) —
useful for poking at the local server in VS Code REST Client or JetBrains
HTTP Client without going through the CLI.

For local Ollama setup, see the companion guide:
**[cura-llm-local](https://chevp.github.io/cura-llm-local/)**.

### `che issue`

Drafts a GitHub issue via the configured LLM, prints it for review, and
opens it through `gh issue create`. Subcommands cover listing and closing.

```sh
che issue "race condition in workflow loader"   # AI drafts title + body, asks to confirm
che issue create --dry-run                      # draft from current branch + diff, do not open
che issue list --limit 5                        # list open issues for this repo
che issue close 42 --reason "fixed in v1.4"     # close issue with comment
```

Requires `gh` installed and authenticated (`gh auth login`).

The drafted issue body always begins with a small YAML frontmatter block:

```markdown
---
status: open            # open | in-progress | blocked
progress: 0%            # free-form, e.g. "0%" or "0/3 steps"
---

<rest of the body>
```

`che issue list` and `che status` parse that block and render the same
status badge as plans — so you can track progress finer than GitHub's
open/closed without inventing labels. Edit the frontmatter directly in
the issue body to update status. GitHub's closed state always wins:
closed issues never appear in the list, regardless of frontmatter.

### `che status`

One-screen overview of the current repo + che-cli configuration:

- active provider, model, reachability
- git: branch, upstream, ahead/behind, working-tree state, short status
- submodules with sync state
- last 5 commits
- **issues** — top 5 open GitHub issues for this repo (via `gh`), with a
  status badge parsed from the issue body's YAML frontmatter (when present)
- **pull requests** — top 5 open PRs with draft / review-decision state
- **plans** — local `.che/plans/*.md` files with status badge
  (`open` / `in-progress` / `done` / `blocked`)

Issues, plans, and (after refactor) anything else that carries a
frontmatter block share a single parser at
[`lib/che/frontmatter.sh`](https://github.com/chevp/che-cli/blob/main/lib/che/frontmatter.sh)
and render through one common `frontmatter_status_badge` helper —
add a new state once, it shows up everywhere.

```sh
che status            # full overview, including GitHub + plans
che status --short    # one-line summary, no network calls
```

GitHub sections are silently skipped if `gh` is missing, unauthenticated,
or the repo has no GitHub remote. Plan files use a small YAML frontmatter
(`name`, `status`, optional `progress`); see
[`.che/plans/README.md`](https://github.com/chevp/che-cli/blob/main/.che/plans/README.md)
for the format.

### `che run` / `che workflow`

Runs a YAML pipeline of shell-script steps from `.che/workflows/<name>.yml`.
The workflow file declares order, args, and inputs — *never inline bash* —
so your existing `scripts/` stay executable on their own.

```sh
che workflow list                       # discover workflows in this repo
che workflow show <name>                # print parsed step plan
che run <name> --tag=v1.2.3             # execute (alias: che workflow run)
che run <name> --tag=v1.2.3 --dry-run   # plan only
```

Full guide: **[workflows](./workflow.md)**.

### `che doctor`

Verifies dependencies and providers, with platform-aware install hints.

```sh
che doctor               # all checks
che doctor provider      # only the active provider
che doctor ollama        # ollama install + reachability + model
che doctor docker        # docker install + daemon running
che doctor workflow      # python + PyYAML for che workflow / che run
```

---

## Architecture

```
bin/che                         dispatcher (~30 lines)
lib/che/
  platform.sh                   OS detection: darwin | windows | wsl | linux
  provider.sh                   routes calls to the active provider
  git/        check.sh, commit.sh
  ollama/      check.sh, client.sh        <p>_ping / _generate / _has_model
  claude-code/ check.sh, client.sh        wraps the `claude` CLI binary
  copilot/     check.sh, client.sh        wraps the `copilot` CLI binary
  docker/      check.sh, client.sh
  workflow/   check.sh, loader.sh, list.sh, show.sh, run.sh
  workflow.sh                   `che workflow` sub-dispatcher
  doctor.sh                     `che doctor` — runs all checks
```

Each `<provider>/client.sh` exposes the same three functions, which
`provider.sh` routes to based on `$CHE_PROVIDER`. To support a new provider:
drop a folder, implement those three functions, register it in `provider.sh`.

---

## Related projects

- [cura-llm-local](https://chevp.github.io/cura-llm-local/) — local LLM server setup (Ollama)
- [chevp-mcp-suite](https://github.com/chevp/chevp-mcp-suite) — MCP server collection
- [chevp-blender-mcp](https://github.com/chevp/chevp-blender-mcp) — Blender MCP integration
- [quon-cli](https://github.com/chevp/quon-cli) — companion CLI tooling

---

## Roadmap

`che-cli` is meant to grow organically. Candidates:

- `che pr` — open a PR with an LLM-generated title and body
- `che review` — local LLM code review on staged changes
- `che branch` — name a new branch from a short intent description

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
