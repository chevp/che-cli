---
title: Installation — che-cli
---

# Installation

`che-cli` is a pure shell project. Installing it copies the dispatcher
(`bin/che`) and the support tree (`lib/che/`) into a prefix, then makes
sure that prefix is on your `PATH`.

> Source: [github.com/chevp/che-cli](https://github.com/chevp/che-cli) ·
> Back to [overview](./index.md)

---

## Quick install

```sh
git clone https://github.com/chevp/che-cli.git
cd che-cli
./install.sh
che doctor
```

The default prefix is `~/.local`, so the installer writes:

- `~/.local/bin/che` — the dispatcher
- `~/.local/lib/che/` — the full support tree (provider clients, helpers)

If `~/.local/bin` is not already on your `$PATH`, the installer appends an
`export PATH=...` line to your shell rc — `~/.zshrc` for zsh, or
`~/.bash_profile` (macOS) / `~/.bashrc` (Linux) for bash. Open a new
terminal afterwards (or `source` the file) to pick it up.

---

## Custom prefix

```sh
PREFIX=/usr/local ./install.sh        # system-wide (needs sudo)
PREFIX="$HOME/tools/che" ./install.sh  # somewhere else entirely
```

Anything that exists and is on your `PATH` works. The installer never
modifies your shell rc when the chosen prefix is already on `PATH`.

---

## Opt out of the rc edit

If you manage your shell rc by hand (e.g. via dotfiles), set
`CHE_NO_PATH_EDIT=1` and the installer prints the export line instead of
writing it.

```sh
CHE_NO_PATH_EDIT=1 ./install.sh
```

---

## Requirements

| Tool   | Why                                            |
|--------|------------------------------------------------|
| `bash` | every script targets bash, not POSIX `sh`      |
| `git`  | `che commit` / `che ship` operate on staged diffs |
| `curl` | provider clients speak HTTP                    |
| `jq`   | request/response JSON shaping                  |

On macOS these are usually pre-installed (or available via Homebrew).
On Linux: `apt install bash git curl jq` (or your distro's equivalent).
On Windows: run from Git Bash or WSL — pure Windows `cmd`/PowerShell is
not supported.

---

## Provider configuration

`che` defaults to a **local Ollama server**, so the zero-config path needs
no API keys. To use OpenAI or Anthropic, drop a `.env` next to the repo
or export the variables in your shell.

```sh
# .env  (see .env.example)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

```sh
CHE_PROVIDER=openai     che commit
CHE_PROVIDER=anthropic  che commit
```

For the local Ollama setup itself, follow the companion guide:
**[cura-llm-local](https://chevp.github.io/cura-llm-local/)** — about
five minutes from zero to a working `llama3.2` server.

---

## Verifying the install

```sh
che doctor          # full sweep
che doctor provider # only the active provider
```

If `che doctor` reports anything red, see [troubleshooting](./troubleshooting.md).

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
