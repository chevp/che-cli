# `.che/workflows/`

This folder is the local equivalent of `.github/workflows/` — but for shell
pipelines you run on your own machine via `che run <name>`.

See the full guide: <https://chevp.github.io/che-cli/workflow.html>

## TL;DR

```yaml
# .che/workflows/<name>.yml
name: <name>
description: One-line summary
trigger: <name>          # optional — exposes `che <name>` as a shortcut

inputs:
  - name: tag
    required: true

steps:
  - name: Build
    script: scripts/build.sh
    args: ["--tag", "${tag}"]
```

```sh
che workflow list                       # discover workflows
che workflow show <name>                # print parsed plan
che run <name> --tag=v1.2.3             # execute
che run <name> --tag=v1.2.3 --dry-run   # plan only
che <trigger> --tag=v1.2.3              # if `trigger:` is set
```

## Rules

1. **No inline bash.** Each step uses `script:` pointing at an executable
   shell file. The YAML declares order, args, and inputs — never logic.
2. **Step scripts must stay independently runnable.** A teammate without `che`
   should still be able to `bash scripts/foo.sh` directly.
3. **`${input_name}` is the only substitution form.** No expressions, no
   defaults, no conditionals. Push logic into the script.
4. **`trigger:` is optional and may shadow built-ins.** A workflow with
   `trigger: ship` claims `che ship` for itself; the original `git ship`
   built-in is still reachable from inside the workflow by referencing
   `~/.local/lib/che/git/ship.sh` as a step. Multiple workflows declaring
   the same trigger is an error — `che <trigger>` will refuse to run.

## Files here

- [`example.yml`](./example.yml) — copy-paste template, three steps, two inputs.
