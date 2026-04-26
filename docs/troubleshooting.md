---
title: Troubleshooting — che-cli
---

# Troubleshooting

Symptom-first, fix-first. Run `che doctor` for a quick sweep before
digging into specifics.

> Source: [github.com/chevp/che-cli](https://github.com/chevp/che-cli) ·
> Back to [overview](./index.md)

---

## `zsh: command not found: che`

The dispatcher installed but its directory isn't on `$PATH`.

```sh
echo $PATH                      # does it contain ~/.local/bin?
ls -l ~/.local/bin/che          # is the file there?
```

Re-run the installer — it will write the right `export PATH=...` line to
your shell rc and tell you which file it touched.

```sh
./install.sh
source ~/.zshrc                 # or open a new terminal
```

If you want to handle PATH yourself, run `CHE_NO_PATH_EDIT=1 ./install.sh`
and add the printed line to your dotfiles.

---

## `che commit: nothing staged, nothing to commit`

`git diff --cached` came back empty. `che commit` always runs `git add -A`
first, so this means the working tree is genuinely clean. Make a change
and try again, or check that you're in the right repo with `git status`.

---

## `che commit: provider 'ollama' not reachable`

The local Ollama server isn't responding on `$CHE_OLLAMA_HOST`
(default `http://localhost:11434`).

```sh
che doctor ollama               # full diagnostics
curl http://localhost:11434/api/tags
ollama serve                    # start it manually if not running
```

If you haven't installed Ollama yet, follow the companion guide
[cura-llm-local](https://chevp.github.io/cura-llm-local/) — it walks
through the model pull as well.

---

## `che commit: provider 'openai' / 'anthropic' not reachable`

Either the API key is missing or the network call failed.

```sh
echo "${OPENAI_API_KEY:-MISSING}" | head -c 8
echo "${ANTHROPIC_API_KEY:-MISSING}" | head -c 8
che doctor provider             # confirms which key is missing
```

`che` reads `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` from the environment.
A `.env` next to the repo is **not** auto-loaded — export them in your
shell rc, or `source .env` before running `che`.

---

## `che commit: LLM returned empty message`

The provider responded but the parsed message was blank. Two common causes:

1. **The diff was huge and got truncated mid-token.** Bump
   `CHE_MAX_DIFF_CHARS` (default `8000`) or commit in smaller chunks.
2. **The model is too small / quantized to follow the prompt.** Try a
   different model (`CHE_OLLAMA_MODEL=llama3.1`) or switch providers.

Run with `--dry-run` to see what the model actually returned without
committing:

```sh
che commit --dry-run
```

---

## Spinner artifacts after Ctrl+C

`ui_spin` installs traps to restore the cursor and clear the line on
`EXIT` / `INT` / `TERM`. If you still see a leftover glyph, your terminal
multiplexer (tmux, screen) may have intercepted the signal. A fresh
prompt or `tput cnorm; clear` will fix the display.

---

## `che ship` skips a submodule

`che ship` skips submodules that are in **detached HEAD** state — there's
no branch to push to. Check the submodule out on a real branch first:

```sh
cd path/to/submodule
git checkout main               # or whichever branch you want
cd -
che ship
```

---

## Commit message looks wrong / not in the right style

The prompt asks for a title plus 2–5 bullet points (skipping the body for
trivial changes). If the model ignores the format, three things to try:

- Use `--edit` to open `$EDITOR` with the message pre-filled:
  `che commit --edit`.
- Switch to a more capable model — `gpt-4o-mini` and
  `claude-sonnet-4-6` follow format instructions much more reliably than
  small local models.
- Run `--dry-run` repeatedly to sample outputs and see whether the issue
  is the prompt or the model.

---

## `che doctor` says everything is fine, but commits still fail

Run the failing command with bash's trace flag to see exactly where it
breaks:

```sh
bash -x ~/.local/lib/che/git/commit.sh
```

If the error is in a provider client, do the same for that file:

```sh
bash -x ~/.local/lib/che/ollama/client.sh
```

If you find a reproducible bug, please open an issue at
[github.com/chevp/che-cli/issues](https://github.com/chevp/che-cli/issues)
with the trace output and your `che doctor` results.

---

© 2025 Patrice Chevillat ·
[Terms](https://chevp.github.io/site-policy/terms.html) ·
[Privacy](https://chevp.github.io/site-policy/privacy.html) ·
[Impressum](https://chevp.github.io/site-policy/impressum.html) ·
[Contact](https://chevp.github.io/site-policy/contact.html)
