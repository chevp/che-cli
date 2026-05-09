# che-cli

A thin wrapper that exposes [chevp/chi](https://github.com/chevp/chi) under the command name `che`. No source duplication — chi is pulled in as a normal npm dependency (git URL, no npm registry required), and `bin/che` just delegates to `chi/dist/index.js`.

> Same UX, same config, same workflows as `chi` — just typed as `che`.

## Install

Requires Node.js 20+. Works the same on macOS, Linux, and Windows.

### Via npm (recommended)

```sh
npm install -g github:chevp/che-cli
```

This fetches che-cli + chi (chi ships its prebuilt `dist/` in the github tarball) and wires `che` (and `che.cmd` on Windows) into npm's global bin directory.

To remove:

```sh
npm uninstall -g che-cli
```

Pin to a specific commit/tag of che-cli:

```sh
npm install -g github:chevp/che-cli#<sha-or-tag>
```

### From source (clone + script)

```sh
git clone https://github.com/chevp/che-cli.git
cd che-cli
./install.sh        # macOS / Linux / WSL
```

On Windows (PowerShell):

```powershell
git clone https://github.com/chevp/che-cli.git
cd che-cli
.\install.ps1
```

## First-time setup

Run **once** after install to enter your credentials:

```sh
che init
```

`che init` prompts for `BASIC_AUTH_USER` and `BASIC_AUTH_PASSWORD` (password input is masked), saves them to `~/.chi/config` (chmod 600), pings the configured LLM endpoint, and confirms the model is available. Re-run with `--force` to update saved credentials.

If you'd rather not be prompted, set both env vars before running `che init`:

```sh
export BASIC_AUTH_USER=<user>
export BASIC_AUTH_PASSWORD=<password>
che init
```

## Update

Once installed, che can update itself — works for both global and from-source installs:

```sh
che update
```

This detects the install layout and either runs `npm install -g github:chevp/che-cli` (global) or `git pull --ff-only && npm install` (workspace clone), pulling the latest chi as a dependency in either case.

## Usage

`che <args>` is functionally identical to `chi <args>`. Most-used commands:

```sh
che status                              # repo state + LLM reachability
che commit                              # stage all + AI-generated commit message
che commit --push                       # also push
che flow my-feature                     # cut a flow branch
che ship                                # add + commit + push (recursive)
che done                                # squash-merge the active flow PR

che issue                               # AI-drafted new issue (interactive)
che issue list --limit 20
che issue close 42

che explain                             # diagnose last failed che ship/commit
che explain "why is git push hanging?"  # ad-hoc question

che doctor                              # all checks (git, llm, workflow)

che config                              # list saved settings
che config llm_model smollm2:135m       # change a key
che config edit                         # open ~/.chi/config in $EDITOR
```

For workflows / worktrees, `che workflow list`, `che run <name>`, `che work <name>`, `che work list|rm|cd` work the same as the chi equivalents.

## Configuration

`che` shares chi's config (`~/.chi/config`). Env vars always win over the file.

| Key (`~/.chi/config`)  | Env var               | Default                                              |
|------------------------|-----------------------|------------------------------------------------------|
| `basic_auth_user`      | `BASIC_AUTH_USER`     | **required**                                         |
| `basic_auth_password`  | `BASIC_AUTH_PASSWORD` | **required**                                         |
| `llm_url`              | `CHI_LLM_URL`         | `https://cura-llm-3j2fyuwcdq-oa.a.run.app`           |
| `llm_model`            | `CHI_LLM_MODEL`       | `smollm2:135m`                                       |
| `max_diff_chars`       | `CHI_MAX_DIFF_CHARS`  | `8000`                                               |

## What this is

```
che-cli/
├── bin/
│   ├── che              # node shim → require.resolve("chi/dist/index.js")
│   └── che.cmd          # Windows shim
├── install.sh
├── install.ps1
└── package.json         # depends on  "chi": "github:chevp/chi"
```

## Why a wrapper?

So the source lives in exactly one place. If `chi` adds a new command, `che` gets it on the next `npm install -g github:chevp/che-cli` (which re-fetches chi's latest `main`). No duplicated source tree to maintain.

## License

MIT — see chi for full attribution; this repo is just a wrapper.
