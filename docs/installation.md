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

## Quick install — Linux / macOS / WSL

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

## Quick install — Windows (PowerShell)

```powershell
git clone https://github.com/chevp/che-cli.git
cd che-cli
.\install.ps1
# Restart your terminal, then:
che doctor
```

The default prefix is `%LOCALAPPDATA%\che`, so the installer writes:

- `%LOCALAPPDATA%\che\bin\che` — the dispatcher
- `%LOCALAPPDATA%\che\lib\che\` — the full support tree

The installer adds `%LOCALAPPDATA%\che\bin` to your user `PATH`. 
**Restart your PowerShell/terminal for the change to take effect.**

---

## Custom prefix

### Unix-like (Bash)

```sh
PREFIX=/usr/local ./install.sh        # system-wide (needs sudo)
PREFIX="$HOME/tools/che" ./install.sh  # somewhere else entirely
```

### Windows (PowerShell)

```powershell
.\install.ps1 "C:\Program Files\che"
# or
$env:PREFIX = "C:\custom\path"; .\install.ps1
```

Anything that exists and is on your `PATH` works.

---

## Opt out of PATH modification (Unix only)

If you manage your shell rc by hand (e.g. via dotfiles), set
`CHE_NO_PATH_EDIT=1` and the installer prints the export line instead of
writing it.

```sh
CHE_NO_PATH_EDIT=1 ./install.sh
```

---

## Requirements

| Tool      | Why                                              |
|-----------|--------------------------------------------------|
| `bash`    | every script targets bash, not POSIX `sh`        |
| `git`     | `che commit` / `che ship` operate on staged diffs |
| `curl`    | provider clients speak HTTP                      |
| `python3` | request/response JSON shaping (or `python`)      |

**Linux:** `apt install bash git curl python3` (or your distro's equivalent).  
**macOS:** All four ship with the OS or are available via Homebrew.  
**Windows:** Use Git Bash or WSL for the Bash-based `che commit` / `che ship` tools. Windows PowerShell is supported for installation only; running che commands requires bash. Install Python via `winget install Python.Python.3` if it isn't already present.  

---

## Provider configuration

`che` defaults to a **local Ollama server**, so the zero-config path needs
no API keys. For cloud LLMs, `che` only supports the official CLIs — auth
stays inside the CLI you've installed, never in `che`'s environment.

### Claude Code (cloud, via CLI)

Install the [Claude Code CLI](https://docs.claude.com/claude-code) and log
in once with `claude` itself; `che` shells out to that binary.

```sh
export CHE_PROVIDER=claude-code
che commit
```

To always escalate to Claude Code (instead of using the local provider as
a fallback), set:

```sh
export CHE_FORCE_CLAUDE_CODE=1
```

For the local Ollama setup itself, follow the companion guide:
**[cura-llm-local](https://chevp.github.io/cura-llm-native/)** — about
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
