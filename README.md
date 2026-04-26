# che-cli

A small, growing collection of personal command-line utilities — each one a
subcommand of a single `che` binary.

The first tool, `che commit`, automates the boring `git add . && git commit -m "..."`
loop by asking an **LLM provider** to summarize the diff into a commit message.
The default provider is a **local Ollama server** — no cloud calls, no API
keys, no telemetry. OpenAI and Anthropic are also supported.

```sh
$ che commit --push

→ refactor: extract ollama client into lib/che/llm.sh

commit with this message? [Y/n/e=edit] y
[main 3f1a2b8] refactor: extract ollama client into lib/che/llm.sh
```

> **Docs:** [chevp.github.io/che-cli](https://chevp.github.io/che-cli/)
> **Local LLM setup:** [cura-llm-local](https://chevp.github.io/cura-llm-local/)

---

## Install

The installers do more than copy files: they detect missing dependencies
(`git`, `curl`, `python3`, PyYAML, **ollama**, the default model) and install
them through the platform's native package manager. Each install is
confirmed interactively unless you pass `--yes` / `-AssumeYes`.

| Common flag           | Effect                                                  |
|-----------------------|---------------------------------------------------------|
| `--yes` / `-AssumeYes`| say yes to every "install X?" prompt (unattended)       |
| `--no-deps`           | skip OS-package installs (don't touch git/python/ollama)|
| `--no-ollama`         | leave ollama alone (don't install / serve / pull)       |
| `--no-model`          | install ollama but skip the multi-GB model pull         |

### Linux / macOS / WSL

```sh
git clone https://github.com/chevp/che-cli.git
cd che-cli
./install.sh                  # interactive — confirms each install
./install.sh --yes            # unattended (CI-friendly)
PREFIX=/usr/local ./install.sh
```

This installs:

- `~/.local/bin/che`              — the dispatcher
- `~/.local/lib/che/`              — full subcommand tree
- (if missing & confirmed) `git`, `curl`, `python3`, `PyYAML`, `ollama`, `gh`
- starts `ollama serve` in the background and pulls `$CHE_OLLAMA_MODEL`
  (default `llama3.2`)

Package-manager support: `brew` (macOS), `apt-get`, `dnf`/`yum`, `pacman`,
`zypper`, `apk`. If `~/.local/bin` is not already on your `PATH`, the
installer appends an `export PATH=...` line to your shell rc (`~/.zshrc`,
`~/.bash_profile`/`~/.bashrc`, or `~/.config/fish/config.fish`) — open a new
terminal afterwards. Pass `--no-path-edit` (or `CHE_NO_PATH_EDIT=1`) to opt
out.

### Windows (PowerShell)

```powershell
git clone https://github.com/chevp/che-cli.git
cd che-cli
.\install.ps1                 # interactive
.\install.ps1 -AssumeYes      # unattended
.\install.ps1 -Prefix "C:\Program Files\che"
```

This installs to `%LOCALAPPDATA%\che` and adds it to your user `PATH`.
When dependencies are missing, it uses **winget** to install Git for
Windows, Python 3, and Ollama (with a direct `OllamaSetup.exe` download as
fallback), then installs PyYAML via `pip --user` and pulls the default
model. Restart your terminal afterwards, then run **`che doctor`**.

### Windows (Inno Setup installer)

A proper Windows installer is also available — it bundles the same
dependency bootstrapper and runs it post-install.

```powershell
cd installer
.\build.ps1
```

Output lands in [installer/Output/](installer/Output/). Double-click the
`.exe`. Two opt-in tasks during the wizard:

- **Install missing dependencies (Git, Python, Ollama)** — checked by default
- **Also pull the default Ollama model** — unchecked by default (multi-GB)

Build prerequisites: [Inno Setup 6](https://jrsoftware.org/isdl.php).

**Manual prerequisites (only if you opt out of dependency install):**
`bash`, `git`, `curl`, `python3` (or `python`), and `ollama` for the default
provider.

---

## Commands

### `che commit` — AI-summarized commit

Stages all changes, sends the diff to the configured LLM provider, gets back a
one-line commit message, asks for confirmation, commits, and (optionally) pushes.

```sh
che commit              # stage + summarize + confirm + commit
che commit --push       # ... and push afterwards
che commit --dry-run    # just print the suggested message
che commit --edit       # open $EDITOR with the message pre-filled
che commit --yes        # skip the confirmation prompt
```

### `che ship` — recursive add + commit + push

For the current repo **and every submodule** (depth-first, recursively):

1. Initializes any uninitialized submodules (`submodule update --init`).
2. Fast-forward pulls if HEAD is on a branch (skipped if detached).
3. Runs `che commit --push --yes` — stage, AI-message, commit, push.

Submodules are processed before the parent so the parent's pointer-update
commit references already-pushed children.

```sh
che ship                # one-shot recursive add + commit + push
```

Provider is selected via `CHE_PROVIDER`:

```sh
CHE_PROVIDER=ollama     che commit          # default — local llama3.2
CHE_PROVIDER=openai     che commit          # needs OPENAI_API_KEY
CHE_PROVIDER=anthropic  che commit          # needs ANTHROPIC_API_KEY
```

Configuration (all environment variables, all optional):

| Variable                  | Default                   |
|---------------------------|---------------------------|
| `CHE_PROVIDER`            | `ollama`                  |
| `CHE_OLLAMA_HOST`         | `http://localhost:11434`  |
| `CHE_OLLAMA_MODEL`        | `llama3.2`                |
| `CHE_OPENAI_HOST`         | `https://api.openai.com/v1`     |
| `CHE_OPENAI_MODEL`        | `gpt-4o-mini`             |
| `CHE_ANTHROPIC_HOST`      | `https://api.anthropic.com/v1`  |
| `CHE_ANTHROPIC_MODEL`     | `claude-sonnet-4-6`       |
| `CHE_MAX_DIFF_CHARS`      | `8000`                    |

API keys come from `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` — see
[`.env.example`](.env.example).

If you don't have a local LLM running yet, follow
[cura-llm-local](https://chevp.github.io/cura-llm-local/) — about five minutes.

### `che run` / `che workflow` — local pipelines

Runs a YAML manifest of shell-script steps from `.che/workflows/<name>.yml`.
The workflow file is a **pointer** — it declares order, args, and inputs but
contains no inline bash, so your existing `scripts/` stay executable on their
own. Mirrors `.github/workflows/` for local pipelines.

```sh
che workflow list                       # discover workflows in this repo
che workflow show <name>                # print parsed step plan
che run <name> --tag=v1.2.3             # execute (alias: che workflow run)
che run <name> --tag=v1.2.3 --dry-run   # plan only
```

A workflow can also declare a `trigger:` (string or list) that registers
`che <trigger>` as a top-level shortcut, including over built-ins like
`che ship`:

```yaml
# .che/workflows/ship.yml
name: ship
trigger: ship                # `che ship` now runs this file
steps:
  - name: tests
    script: scripts/test.sh
  - name: built-in ship
    script: ~/.local/lib/che/git/ship.sh   # original behavior, still reachable
```

A copy-paste template lives at [`.che/workflows/example.yml`](.che/workflows/example.yml).
Full guide: [chevp.github.io/che-cli/workflow.html](https://chevp.github.io/che-cli/workflow.html).

Requires `python3` plus [PyYAML](https://pypi.org/project/PyYAML/) (`pip install pyyaml`).
Run `che doctor workflow` to check.

### `che doctor` — health check

Verifies dependencies and providers. Platform-aware install hints (different
suggestions for macOS vs Windows vs Linux/WSL).

```sh
che doctor               # everything
che doctor provider      # only the currently active provider
che doctor ollama        # specific target
che doctor docker        # ditto
```

Sample output:

```
platform: darwin
active provider: ollama (model: llama3.2)

git:
  ✓ git 2.39.5
docker:
  ✓ docker installed (29.3.1)
  ✓ docker daemon is running
ollama:
  ✓ ollama binary found
  ✓ server responding at http://localhost:11434
  ✓ model available: llama3.2
```

---

## Project layout

```
che-cli/
├── bin/
│   └── che                       # dispatcher
├── client/http/                  # REST request samples (VS Code / JetBrains)
│   ├── ollama.http
│   ├── openai.http
│   └── anthropic.http
├── lib/che/
│   ├── platform.sh               # OS detection (darwin/windows/wsl/linux)
│   ├── provider.sh               # provider router (ollama/openai/anthropic)
│   ├── doctor.sh                 # `che doctor`
│   ├── git/
│   │   ├── check.sh
│   │   └── commit.sh             # `che commit`
│   ├── ollama/
│   │   ├── check.sh
│   │   └── client.sh             # ollama_ping / ollama_generate / ollama_has_model
│   ├── openai/
│   │   ├── check.sh
│   │   └── client.sh
│   ├── anthropic/
│   │   ├── check.sh
│   │   └── client.sh
│   └── docker/
│       ├── check.sh
│       └── client.sh
├── docs/
│   └── index.md                  # GitHub Pages source
├── .env.example
├── install.sh
└── README.md
```

Each provider folder exposes the same three functions
(`<p>_ping`, `<p>_has_model`, `<p>_generate`) so `provider.sh` can route to
whichever is selected by `CHE_PROVIDER`.

---

## Adding a new tool

1. Drop a script at `lib/che/<topic>/<name>.sh`.
2. Add a `case` arm in `bin/che` that execs it.
3. Re-run `./install.sh`.

No plugin manifest, no registration step — the dispatcher is short enough to
read in one sitting ([`bin/che`](bin/che)).

---

## Related

- [cura-llm-local](https://chevp.github.io/cura-llm-local/) — local Ollama setup guide
- [chevp-mcp-suite](https://github.com/chevp/chevp-mcp-suite) — MCP server collection
- [quon-cli](https://github.com/chevp/quon-cli) — companion CLI tooling
