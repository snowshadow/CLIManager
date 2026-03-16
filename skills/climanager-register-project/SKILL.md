---
name: climanager-register-project
description: Register a local command-line app as a CLIManager project by inferring or accepting a start command, then writing the project entry into CLIManager's projects.json. Use when the user asks to add/import/register a CLI app, coding project, local tool, or repo into CLIManager.
---

# CLIManager Project Registration

Use this skill when the user wants an AI agent to add a local CLI app into CLIManager without opening the app and filling the form manually.

## What this skill does

- Validates that the target path exists and is a directory
- Determines a project name and start command
- Calls CLIManager's official CLI import interface
- Avoids duplicates by `path + startCommand`

## Inputs to gather

Collect or infer these values:

- `path`: absolute path to the CLI project directory
- `name`: optional; default to the directory name when not provided
- `command`: optional only if it can be inferred confidently

If the start command is ambiguous, stop and ask the user instead of guessing.

## Command inference rules

Prefer deterministic signals in this order:

1. Existing repo docs or user instruction that explicitly name the command
2. `package.json`
   - `scripts.dev` -> `npm run dev`
   - `scripts.start` -> `npm start`
3. `Makefile`
   - target `dev` -> `make dev`
   - target `run` -> `make run`
4. `Cargo.toml` -> `cargo run`
5. `Package.swift` -> `swift run`
6. `go.mod` -> `go run .`
7. `deno.json` or `deno.jsonc`
   - task `dev` -> `deno task dev`
   - task `start` -> `deno task start`
8. `main.py` -> `python main.py`

If multiple plausible commands exist and no explicit preference is present, ask the user.

## Registration workflow

1. Inspect the target directory to infer the command if needed.
2. Run the bundled script:

```bash
./scripts/register_project.sh --path /absolute/project/path --name "Project Name" --command "swift run"
```

3. If the script reports the project already exists, return that result instead of rewriting.
4. Tell the user which entry was added and where it was written.

## Script behavior

The bundled script:

- Invokes `CLIManagerCLI import`
- Uses `swift run --package-path ... CLIManagerCLI -- import ...`
- Supports `CLIMANAGER_PACKAGE_PATH` when the CLIManager repo is not adjacent to the skill

## Notes

- CLIManager currently treats `path + startCommand` as the uniqueness key.
- The script accepts `--root` to target a different CLIManager data directory for testing.
- Use `--dry-run` when you only need to preview the inferred registration payload.
