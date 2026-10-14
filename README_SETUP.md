# OpenCode V2 — agent starter pack

Copy the *contents* of this pack to the root of your Godot repository (merge, do not overwrite your existing `AGENTS.md` or `.opencode/` blindly).

## What is included
- `AGENTS.md`: repository-wide rules
- `.opencode/agents/*.md`: 6 V2-compatible subagent profiles (plus optional primary coordinator)
- `.opencode/skills/*/SKILL.md`: 10 task-specific skills loaded on demand
- `ARCHITECTURE.md`, `GAME_DESIGN.md`, `docs/*`: design boundaries
- `tools/validate_pack.py`: offline structure/frontmatter validation
- `.gitignore.fragment`: recommended cache exclusions, merge manually

## Getting started
1. Back up/merge any existing instructions. Avoid duplicate skill IDs across sources.
2. Launch OpenCode V2 from your repository root.
3. Ask: `Use @architect to review ARCHITECTURE.md and create a minimal milestone plan; do not modify game code.`
4. Ask the implementation agent to make only the first greybox movement/combat slice.
5. Run `python3 tools/validate_pack.py` to check this pack's structure.

## Compatibility note
This pack targets OpenCode **V2**. Its agent frontmatter uses `permissions` as an ordered list with `action`, `resource`, `effect`. Do not replace with V1 `permission`, `temperature`, or `tools` fields. No model IDs are forced; subagents inherit the parent model unless you set one. Skills use `.opencode/skills/<id>/SKILL.md`.

## Safety
Read-only architect/reviewer profiles cannot edit via agent permissions. Primary coordinator can orchestrate; executable tools are still bound by the user's OpenCode runtime and task authorization. Never run destructive Git operations implicitly.

## Repository bootstrap — verified on this machine (Sprint 01)

| Item | Value |
|------|-------|
| Engine binary (`GODOT_BIN`) | `C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe` (windowed build in the same folder) |
| Engine version | `4.7.2.stable.official.ed1daf0bf` (pinned by ADR-002) |
| Godot on `PATH` | no — always call the binary by full path |
| Python | `python` 3.12 available for `tools/validate_pack.py` |

Validation commands (run from the repository root; exit code 0 means success):

```powershell
$GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

# 1. import / parse the whole project (scenes, scripts, resources)
& $GODOT --headless --path . --editor --quit

# 2. full headless test suite (unit + integration)
& $GODOT --headless --path . -s res://tests/run_tests.gd

# 3. boot the main scene headless for a fixed number of frames (runtime error smoke test)
& $GODOT --headless --path . --quit-after 300

# 4. instructions/skills pack structure check
python tools/validate_pack.py
```

Maintenance helpers:

```powershell
# rewrite the agreed InputMap actions into project.godot (ADR-005)
& $GODOT --headless --path . -s res://tools/setup_input_map.gd
```

Test conventions: `tests/**/test_*.gd` extending `res://tests/test_case.gd`; the runner is
`tests/run_tests.gd` and needs no external addon (ADR-006).
