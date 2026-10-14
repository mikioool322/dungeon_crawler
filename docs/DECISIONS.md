# Architectural decision log

Use one entry per accepted decision. Status values: `proposed`, `accepted`, `rejected`, `superseded`.

## ADR-000 — Minimal modular monolith (provisional)
Status: confirmed by ADR-001 (kept for history).
Context: Solo, AI-assisted Godot single-player development.
Decision: Components + Godot Resources + local signals. No full ECS.
Consequences: Faster iteration; review boundaries when scale requires it.

## ADR-001 — Confirm modular monolith and single-mutation ownership
Status: accepted (Sprint 01).
Context: ADR-000 was provisional; Sprint 01 adds the first gameplay components with several
agents able to work in parallel.
Decision: Components + Resources + local signals; no ECS, no service locator, no global event
bus in Sprint 01. Each node mutates only its own state:
`AttackController` owns attack phase and cooldown, `HealthComponent` owns HP,
`EnemyBrain` owns intent/FSM state and `velocity`, `PlayerController` owns movement transform
and camera pitch. `HealthComponent` only signals death; the owning actor performs the
consequences. Loot/reward events require a new ADR before they exist.
Consequences: Clear mutation ownership per file for parallel agents; revisit only with a
measured scale need.

## ADR-002 — Engine pin: Godot 4.7.2-stable
Status: accepted (Sprint 01).
Context: `GAME_DESIGN.md` lists the engine patch version as undecided; the verified local
binary is Godot 4.7.2-stable (official, `ed1daf0bf`), not on `PATH`; `project.godot` is new.
Decision: Pin Godot 4.7.2-stable for Sprint 01. `project.godot` declares
`config/features=("4.7", "Forward Plus")`; `README_SETUP.md` records the `GODOT_BIN` path and
the exact validation commands. Changing the engine requires an ADR plus an import/re-parse run.
Consequences: Reproducible import and tests on the reference machine; `.godot/` cache stays
untracked.

## ADR-003 — Sprint 01 scope is a combat slice subset
Status: accepted (Sprint 01).
Context: The `GAME_DESIGN.md` "first playable vertical slice" includes a greybox hub, a door
transition, save/load and a reward, which would inflate the first increment and mix ownership.
Decision: Sprint 01 delivers exactly one greybox arena with: first-person walk/look, visible
placeholder weapon, one melee attack, one telegraphed enemy, evasion by walking out of reach,
enemy HP/death, and a player HP/capture feedback path. Explicitly excluded: jump, dash, block,
parry, magic, hub/dungeon transition, save/load, loot, gallery, procedural generation,
external assets, animation pipeline. Player death freezes input; the arena offers a manual
scene restart (no save).
Consequences: `GAME_DESIGN.md` stays the target, Sprint 01 is its first decomposition;
reordering requires a new ADR. No empty subsystem folders are created.

## ADR-004 — Attack timing and hit resolution model
Status: accepted (Sprint 01).
Context: Attack timing units, phase ownership and hit-frame semantics were unspecified, and
the animation pipeline lands later.
Decision:
- All attack timings are in seconds, advanced by `_physics_process` (or explicitly by
  `advance(delta)` in tests). Animation never authoritatively times gameplay.
- `AttackController` owns phases `IDLE → WINDUP → ACTIVE → RECOVERY → IDLE` per actor, one
  swing at a time (requests during a swing are rejected, never queued), cooldown counted from
  swing start.
- Exactly one hit query per swing: on the first tick where the phase becomes `ACTIVE`.
- Range and occlusion are evaluated at that hit frame from live physics state, so a target
  that stepped away is a miss (`MeleeRules` is the range authority; the physics query only
  gathers candidates).
- Damage flows one way: `HitDetector.query_hits()` → `HitCandidate` → `AttackController`
  → `HealthComponent.apply_damage(DamageRequest)` → `DamageResult`.
- `HitRegistry` (one instance per swing) guarantees at most one damage application per target
  per swing.
- `AttackDefinition` resources are immutable at runtime.

Addendum (W2 implementation evidence):
- The physics shape query reports a target body's origin (at its feet), so the range gate
  compares the horizontal (XZ) distance from the hit origin to the reported contact point.
  Vertical separation between floors is out of scope for the flat Sprint 01 arena and would
  need its own ADR.
- Every attack declares `hit_arc_degrees` (half-angle of the frontal arc, measured on the
  horizontal plane). Candidates outside the arc miss with `out_of_arc`; this is what stops a
  forward swing from hitting a target behind the attacker.
- Line of sight is tested from the hit origin to swing height above the reported contact point
  (`HitDetector.occlusion_probe_height`, default 1.0 m), so low cover does not block a
  chest-height swing while walls and pillars still do.
- One swing may damage several targets. `attack_resolved` carries the nearest applied hit, or
  the closest rejection reason (`out_of_arc`, `out_of_reach`, `occluded`, `target_dead`,
  `duplicate`) when nothing was hit.
Consequences: Deterministic headless tests for phase timing and misses. Multi-tick hit windows
or invulnerability frames would require a new ADR.

## ADR-005 — Physics layers, damageable node contract and InputMap ownership
Status: accepted (Sprint 01).
Context: `project.godot` is shared by all agents; layer and action names are cross-module API.
Decision:
- 3D physics layers: 1 `world`, 2 `player_body`, 3 `enemy_body`, 4 `hurtbox` (reserved,
  unused in Sprint 01). Bit constants live only in `core/physics/physics_layers.gd`; scripts
  never use raw ints.
- Actor movement collision: the player and enemies collide with `world` and each other; hit
  queries mask `world | <opponent body layer>` so walls occlude hits in the same query.
- Damageable actors must expose a direct child node named `HealthComponent`. The name and the
  lookup are owned by the component itself (`HealthComponent.NODE_NAME`,
  `HealthComponent.find_on(actor)`); callers must not re-implement the lookup, and an attack that
  reaches a collider without one reports a warning instead of failing silently.
- InputMap actions (closed list): `move_forward`, `move_back`, `move_left`, `move_right`,
  `attack_primary`. They are written by `tools/setup_input_map.gd` and locked by
  `tests/unit/test_project_contract.gd`.
- `project.godot`, `core/physics/physics_layers.gd` and `docs/DECISIONS.md` are single-writer
  files (integrator only). Adding a layer or action requires updating this ADR.
Consequences: Merge-safe bootstrapping; no silent drift of actions or layers.

## ADR-006 — Test seams and multi-agent validation protocol
Status: accepted (Sprint 01).
Context: No git repository, no test addon and no CI existed before Sprint 01; several agents
work on the same project.
Decision:
- Zero external test dependencies: `tests/run_tests.gd` discovers `tests/**/test_*.gd` that
  extend `res://tests/test_case.gd` and runs them headless; async tests may await physics
  frames. Exit code 0/1 is the machine-readable result.
- Pure logic (value objects, `MeleeRules`, `HitRegistry`, `EnemyFsm`, `AttackDefinition`
  validation) must be testable without a `SceneTree`; physics behaviour is verified with
  minimal fixture bodies inside the runner.
- No fabricated results: a test counts as PASS only when the runner reports it.
- Work isolation: one branch (and worktree when parallel) per work item with declared file
  ownership; single-writer files listed in ADR-005; the coordinator merges only after tests
  pass. Commits require task authorization; no `git push` in Sprint 01.
Consequences: Evidence-based merges with a small per-item overhead; CI can be added later
without changing the contract.
