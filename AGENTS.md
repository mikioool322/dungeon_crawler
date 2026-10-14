# Project instructions — Dark Fantasy First-Person ARPG

## Intent and scope
Single-player Godot 4.x / GDScript first-person dark fantasy ARPG. One hub; isolated dungeons; melee attacks; evasion initially means walking backwards beyond actual attack reach (no invulnerability frames). Placeholder assets first. Mature-content gallery is a separate, optional presentation/reward subsystem; never couple it to combat.

## Sources of truth
- `ARCHITECTURE.md` — module boundaries and contracts
- `GAME_DESIGN.md` — current confirmed scope; do not invent requirements
- `docs/DECISIONS.md` — recorded decisions
- `.opencode/skills/` — task-specific instructions loaded when applicable

## Agent operating procedure
1. Inspect repository state (`git status --short`, relevant files, existing tests). Never overwrite uncommitted user work.
2. Explain a small execution plan for nontrivial tasks. Distinguish observed behavior from guesses.
3. Choose the minimum relevant skills. Inspect existing public APIs before changing them.
4. Implement a vertical, testable slice; avoid speculative features and frameworks.
5. Run actual available validation, capture command/results. When blocked, describe precise blocker; never fabricate PASS.
6. Review diff for accidental changes, generated files, reference breakages and scene metadata.
7. Report modified files, actual tests, risks, and manual checks.

## Architecture invariants
- Separate static `Resource` definitions, mutable runtime state, persistence DTOs, and presentation.
- Prefer composition and reusable components; use shallow inheritance for engine actors only.
- Combat decides damage; Health owns HP; Actor or encounter coordinator owns death consequences.
- Check range/line of sight at the actual hit frame; target movement can cause a miss.
- Use direct calls for immediate collaboration, local signals for notifications, and global events only for cross-module domain facts.
- Event listeners must not accidentally award loot twice; event identifiers and one-shot guards apply where needed.
- Content references use stable IDs, not display names or asset paths as persistent identity.
- Never store Godot Node references in save files. Version save data and design migrations.
- Core rules never depend on scene-specific visuals or adult gallery content.
- New assets must have clear import ownership and replaceable references.
- No full ECS, service locator, or premature plugin framework without a measured need.

## Git, safety and execution
- Never run `git reset --hard`, `git clean -fd`, force push, delete branches, or overwrite unrelated work without explicit approval.
- Do not commit, push, install remote code, or use paid cloud services without task authorization.
- Do not silently change engine version, dependency lockfiles, save format, or public module contracts.
- Multiple agents editing: isolate by branch/worktree and declare ownership; one integrator merges after tests.
- Do not modify secrets, environment files or personal data; keep generated caches out of Git.
- Keep external assets/license attribution in `docs/ASSET_LICENSES.md`.

## Testing contract
- Prefer pure GDScript tests for combat logic and data validation; add scene integration tests for collision/navigation.
- Run `godot --headless --path . --editor --quit` (or locally available Godot binary) after scene/resource changes.
- Run installed test runner if present; do not claim one exists before checking.
- Validate behavior in a graphical build for gameplay-sensitive features.

## Completion report format
STATUS: COMPLETE / PARTIAL / BLOCKED
CHANGED: file paths
BEHAVIOR: observed result
VALIDATION: commands, PASS/FAIL and environment
RISKS: uncovered cases
NEXT: smallest next increment
