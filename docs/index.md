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

Requirements: `bash`, `git`, `curl`, `jq`. On Windows, run from Git Bash or WSL.

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

| Provider     | Selector                  | API key            |
|--------------|---------------------------|--------------------|
| Ollama       | `CHE_PROVIDER=ollama`     | none (local)       |
| OpenAI       | `CHE_PROVIDER=openai`     | `OPENAI_API_KEY`   |
| Anthropic    | `CHE_PROVIDER=anthropic`  | `ANTHROPIC_API_KEY`|

The HTTP request shapes that each provider speaks are also kept as ad-hoc REST
samples under [`client/http/`](https://github.com/chevp/che-cli/tree/main/client/http) —
useful for poking at a provider in VS Code REST Client or JetBrains HTTP Client
without going through the CLI.

For local Ollama setup, see the companion guide:
**[cura-llm-local](https://chevp.github.io/cura-llm-local/)**.

### `che doctor`

Verifies dependencies and providers, with platform-aware install hints.

```sh
che doctor               # all checks
che doctor provider      # only the active provider
che doctor ollama        # ollama install + reachability + model
che doctor docker        # docker install + daemon running
```

---

## Architecture

```
bin/che                         dispatcher (~30 lines)
lib/che/
  platform.sh                   OS detection: darwin | windows | wsl | linux
  provider.sh                   routes calls to the active provider
  git/        check.sh, commit.sh
  ollama/     check.sh, client.sh         <p>_ping / _generate / _has_model
  openai/     check.sh, client.sh           "
  anthropic/  check.sh, client.sh           "
  docker/     check.sh, client.sh
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
- `che explain` — summarize what a file or diff does
- `che review` — local LLM code review on staged changes
- `che branch` — name a new branch from a short intent description

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
