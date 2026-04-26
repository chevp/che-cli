---
title: Architecture — che-cli
---

# Architecture

`che-cli` is intentionally small. There is no plugin manifest, no daemon,
no configuration file — just a dispatcher script, a provider router, and
a flat tree of single-purpose shell modules.

> Source: [github.com/chevp/che-cli](https://github.com/chevp/che-cli) ·
> Back to [overview](./index.md)

---

## Components

```
bin/che                      dispatcher (~30 lines)
lib/che/
  platform.sh                OS detection: darwin | windows | wsl | linux
  provider.sh                routes calls to the active provider
  ui.sh                      shared UI helpers (spinner)
  doctor.sh                  che doctor — runs all checks
  git/
    check.sh                 git availability check
    commit.sh                che commit
    ship.sh                  che ship (recurses into submodules)
  ollama/
    check.sh
    client.sh                ollama_ping / _has_model / _generate
  openai/
    check.sh
    client.sh                openai_ping / _has_model / _generate
  anthropic/
    check.sh
    client.sh                anthropic_ping / _has_model / _generate
  docker/
    check.sh
    client.sh
```

Every provider folder follows the same convention:

- `<provider>_ping`       — is the service reachable?
- `<provider>_has_model`  — is the configured model available?
- `<provider>_generate`   — send a prompt, return text on stdout

`provider.sh` reads `$CHE_PROVIDER` and dispatches to the matching
function set, so the rest of the codebase never branches on provider name.

---

## Control flow: `che commit`

```
┌────────────┐    ┌─────────────┐    ┌──────────────────┐
│ user types │ ─► │  bin/che    │ ─► │ lib/che/git/     │
│ che commit │    │ (dispatch)  │    │  commit.sh       │
└────────────┘    └─────────────┘    └────────┬─────────┘
                                              │
       ┌──────────────────────────────────────┘
       ▼
   git add -A
       │
       ▼
   git diff --cached  ──►  truncate at CHE_MAX_DIFF_CHARS
       │
       ▼
   build prompt (commit-format rules + diff)
       │
       ▼
   provider_ping?  ── no ──►  exit with hint
       │ yes
       ▼
   provider_generate (in background)  ◄── ui_spin shows spinner
       │
       ▼
   parse: first line = title, remaining = body bullets
       │
       ▼
   confirm? ─ Y ─►  git commit -F <tmpfile>
            ─ N ─►  abort
            ─ E ─►  git commit -e -F <tmpfile>
       │
       ▼
   --push?  ──►  git push
```

The commit message is written to a tempfile and passed via `git commit -F`,
which preserves the title/body structure exactly as the model produced it.

---

## Control flow: `che ship`

`che ship` is a thin wrapper that recurses through git submodules
**before** doing the work in the outer repo:

```
.gitmodules?
  yes ─►  for each submodule:
            init if missing
            ff-pull if on a branch (skip if detached HEAD)
            ( cd <submodule> && che ship )           ◄── recursion
  ─────►  che commit --push --yes  in the outer repo
```

This is why a single `che ship` at the top of a workspace can update
every nested repo in one shot — each submodule self-ships, then the
parent commits the updated pointers.

---

## Provider router

`provider.sh` is the only file that knows the set of valid provider names.
Adding a new provider is a three-step change:

1. Create `lib/che/<name>/client.sh` that exports `<name>_ping`,
   `<name>_has_model`, and `<name>_generate`.
2. Create `lib/che/<name>/check.sh` for `che doctor`.
3. Add `<name>` to the `case` arm in [`provider.sh`](https://github.com/chevp/che-cli/blob/main/lib/che/provider.sh)
   and register a default model in `provider_active_model`.

No registration in the dispatcher, no manifest, no module index.

---

## Cross-cutting helpers

- **`platform.sh`** detects the OS once at source time and exports
  `$CHE_OS` (`darwin` / `linux` / `wsl` / `windows`). Used by `doctor.sh`
  to print platform-appropriate install hints.
- **`ui.sh`** exposes `ui_spin <pid> <msg>`: shows a braille spinner on
  stderr while a background PID runs, hides the cursor, restores it on
  Ctrl+C, and silently no-ops when stderr is not a TTY (CI, redirects).

---

## Design choices

- **Bash, not POSIX `sh`.** Arrays, `[[ ]]`, and `read -d` keep the
  scripts short. Targeting `sh` would double the line count for no real
  portability win — Git Bash and WSL both ship bash.
- **Tempfiles over here-strings.** `git commit -F <tmp>` preserves
  multi-line bodies exactly; here-strings can mangle whitespace.
- **No streaming.** Providers are called with `stream: false`. Streaming
  would complicate the spinner and the parsing for a one-line title.
- **stderr for UI.** Spinners and diagnostics go to stderr so stdout can
  be captured cleanly (e.g. `che commit --dry-run > msg.txt`).

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
