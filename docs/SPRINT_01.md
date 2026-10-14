# Sprint 01 — combat slice (approved plan)

Status: approved by the project owner; executed by the coordinator with `architect`, `gameplay-engineer`,
`godot-specialist`, `qa-engineer` and `reviewer` roles. Decisions referenced as ADR-xxx live in
`docs/DECISIONS.md`.

## Goal

One greybox arena proving the core combat loop end-to-end: first-person movement, a visible placeholder
weapon, one melee attack, one telegraphed enemy whose damage can be avoided by physically walking out of
reach before the hit frame, and a correct death outcome. No hub, no save, no loot, no gallery, no external
assets (ADR-003).

## Work items, ownership and order

| ID | Deliverable | Owner | Declared file ownership | State |
|----|-------------|-------|-------------------------|-------|
| W0 | Bootstrap: git repo, `.gitignore`, `project.godot`, InputMap, physics layers, test seam, ADRs, sprint plan, first commit | `arpg-coordinator` (+`godot-specialist` for `project.godot`) | `.gitignore`, `project.godot`, `core/physics/physics_layers.gd`, `tools/setup_input_map.gd`, `tests/test_case.gd`, `tests/run_tests.gd`, `docs/**`, `README_SETUP.md` | done |
| W1 | Combat domain: `DamageRequest`, `DamageResult`, `HitCandidate`, `MeleeRules`, `HitRegistry`, `AttackDefinition`, `HealthComponent` + unit tests | `gameplay-engineer` | `core/combat/**`, `systems/combat/attack_definition.gd`, `systems/combat/health_component.gd`, `tests/unit/combat/**` | done (4183670) |
| W2 | `AttackController` + `HitDetector` + unit tests | `gameplay-engineer` | `systems/combat/attack_controller.gd`, `systems/combat/hit_detector.gd`, `tests/unit/combat/**` | done (5274864) |
| W3 | Player rig: scene, walk/look, backpedal evasion, viewmodel placeholder, `attack_player_basic.tres` | `godot-specialist` | `actors/player/**` | in progress (worktree `feat/w3-player`) |
| W4 | Enemy rig: `EnemyFsm`, `EnemyDefinition`, scene, telegraph, damage reaction, death | `gameplay-engineer` | `systems/ai/**`, `actors/enemies/**`, `content/definitions/attack_enemy_basic.tres`, `content/definitions/enemy_grunt.tres` | done (772d6d7) |
| W5 | Greybox arena scene + wiring + debug HUD | `godot-specialist` | `world/prototype/**`, `content/definitions/sprint01_arena*` (if any), one `main_scene` line in `project.godot` (single-writer) | in progress |
| W6 | QA: integration tests, parser/import validation, scene boot smoke, runtime error check, manual checklist, evidence | `qa-engineer` | `tests/integration/**`, `tests/manual/**` | planned |
| W7 | Independent review, CRITICAL/HIGH fixes, re-validation | `reviewer` (read-only) + coordinator fixes | fixes only in the owning files of the findings | planned |

W3 and W4 have disjoint file sets and may run in parallel in separate worktrees; W5 requires both merged.
`project.godot`, `core/physics/physics_layers.gd` and `docs/DECISIONS.md` are single-writer (ADR-005).

## Module contracts (summary — full detail in source)

| Element | Owner of state | Contract highlights |
|---------|----------------|---------------------|
| `DamageRequest` / `DamageResult` | none (value objects) | no Node references; stable `StringName` ids; `miss_reason` vocabulary `out_of_reach`, `occluded`, `target_dead`, `duplicate` |
| `MeleeRules` | none (pure) | `within_reach(origin, target_point, reach, contact_tolerance)` — the range authority at the hit frame |
| `HitRegistry` | none (pure, one per swing) | `register_once(instance_id)` — one damage application per target per swing |
| `HitCandidate` | none (runtime-only) | carries `collider`, contact point, distance, `occluded` flag; never serialized |
| `AttackDefinition` (Resource) | none (immutable at runtime) | `id`, `damage`, `reach`, `hit_radius`, `windup`, `active_window`, `recovery`, `cooldown`, `is_valid()` |
| `HealthComponent` (Node) | `current_health` | `apply_damage(request) -> DamageResult`, `died(request)` exactly once, clamps to `[0, max]`, no death consequences |
| `AttackController` (Node) | `phase`, cooldown | `request_attack()`, `abort(reason)`, `advance(delta)`, signals `phase_changed(phase)`, `attack_resolved(result)`; one swing at a time; one hit query per swing |
| `HitDetector` (Node3D) | none (stateless query) | `query_hits(definition, origin, exclude_rids)`, sphere-shape candidate gathering + world raycast occlusion; never applies damage |
| `EnemyFsm` (pure) | none | `step(current, inputs, params) -> Decision`; states `IDLE/CHASE/ATTACK/DEAD`; DEAD terminal |
| `EnemyBrain` (CharacterBody3D) | FSM state, velocity | adapter around `EnemyFsm`; calls `AttackController`; never touches player HP directly; presentation-only telegraph. Plants its feet while in ATTACK (`force_stop`) so the windup escape window actually exists; a retreating target is not a cancellation, it resolves as `out_of_reach` at the hit frame |
| `PlayerController` (CharacterBody3D) | transform, pitch | walk/look/backpedal only (no jump/dash); forwards `attack_primary` to `AttackController` |
| `PlayerViewModel` (Node3D) | viewmodel transform | reacts to `phase_changed`; removal must not change combat behaviour |

Scene contract: every damageable actor exposes a direct child named `HealthComponent` (ADR-005).

## Acceptance criteria

| AC | Criterion | Evidence |
|----|-----------|----------|
| AC-01 | Target inside reach at hit frame ⇒ `applied`, HP down by `damage` | `tests/unit/combat/test_melee_rules.gd`, `test_health_component.gd` + integration |
| AC-02 | Target outside `reach` ⇒ no damage, reason `out_of_reach` | `test_melee_rules.gd`, integration |
| AC-03 | Target retreats before the first ACTIVE tick ⇒ miss, no HP change | `tests/integration/test_combat_scenarios.gd` (physics) |
| AC-04 | Duplicate contact / repeat query ⇒ exactly one damage application | `test_hit_registry.gd` + integration |
| AC-05 | Attack during cooldown rejected; accepted after cooldown | `test_attack_controller.gd` |
| AC-06 | Enemy killed during windup aborts the swing; no hit after death | `test_attack_controller.gd`, `test_enemy_fsm.gd` |
| AC-07 | Enemy losing target (distance > lose radius or freed target) returns to IDLE and stops | `test_enemy_fsm.gd` |
| AC-08 | `died` emitted exactly once; damage after death ignored; HP clamps at 0 | `test_health_component.gd` |
| AC-09 | Attack/enemy resource validation (non-empty id, non-negative times, `lose_radius >= detection_radius`) | `test_attack_definition.gd`, data tests |
| AC-10 | Player and enemy scenes load in headless without parser/script errors | `tests/integration/test_scene_boot.gd` |
| AC-11 | Arena scene boots headless with `main_scene` set, no runtime errors | `tests/integration/test_scene_boot.gd`, runtime error log check |
| AC-12 | Full suite PASS + manual checklist executed with notes | runner output, `tests/manual/sprint01_checklist.md` |
| AC-13 | Independent review without open CRITICAL/HIGH findings; no out-of-ownership edits | reviewer report in the completion summary |

## Validation commands (verified on this machine)

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

# import / parse the project (also validates scene and resource syntax)
"%GODOT%" --headless --path . --editor --quit

# full test suite (unit + integration), exit code 0 = PASS
"%GODOT%" --headless --path . -s res://tests/run_tests.gd

# arena boot smoke test without a window
"%GODOT%" --headless --path . --quit-after 300
```

## Manual checks (require a graphical session)

1. Mouse look and WASD movement are smooth; pitch limited to ±89°.
2. The placeholder weapon is visible and follows the attack phases.
3. The enemy telegraph (windup indication) is readable at combat distance.
4. Standing inside reach when the enemy's active frame arrives deals damage (HP HUD drops).
5. Backpedaling away from the start of WINDUP avoids all damage.
6. Killing the enemy stops it, with no further attacks.
7. A pillar blocks melee attacks (no damage through geometry).
8. Breaking line of sight / distance returns the enemy to IDLE.
9. No runtime errors in the Godot Output panel during a ~2 minute session.

## Known constraints

- Numbers (damage, reach, timings) are placeholders; balance is out of scope.
- Escape window math: the enemy gate is `reach + hit_radius = 1.95 m` with a 0.7 s windup, so
  leaving reach needs roughly 2.0 m of backpedal — the player's 4.0 m/s walk gives ~0.8 m of
  margin. The enemy stops moving during ATTACK for this reason (`EnemyFsm` ATTACK rows set
  `force_stop`”; recorded as a documented deviation from the first draft of the transition table).
- No animation pipeline: phases are driven by code timing plus placeholder transforms (ADR-004).
- Player death freezes input; restarting is the arena's `R` key (`ProtoArena._restart`).
- Manual visual checks are recorded as NOT RUN when no graphical verification was performed.
