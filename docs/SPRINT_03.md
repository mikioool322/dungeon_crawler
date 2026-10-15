# Sprint 03 — dungeon progression and repeatable runs (plan of record)

Status: approved after the architecture audit; executed with `architect`, `gameplay-engineer`,
`godot-specialist`, `qa-engineer` and `reviewer` roles. ADR-012 is the normative starting point;
ADR-013 and ADR-014 record what it left open. Baseline: `master` at `ac86b0a`,
355 tests / 2608 assertions PASS.

## Goal

The full loop: hub shows a dungeon list → dungeon 01 is available, dungeon 02 locked → start a run →
enemies and ordinary loot reset for the run → fight, loot, satisfy an explicit completion objective →
first completion grants a one-time story reward and unlocks dungeon 02 → return to the hub → dungeon
02 is enterable → re-enter dungeon 01 → enemies and ordinary loot reset and are earned again → the
story reward is not granted again → save at the shrine → after a restart the unlocked dungeons,
completions and unique rewards persist.

Out of scope: procedural generation, new combat, magic, trade, NPC/dialogue, equipment, crafting,
boss AI, final assets, quest framework, autosave, multiplayer.

## Three data lifetimes (ADR-012)

| Kind | Type | Owner | Persisted |
|------|------|-------|-----------|
| Static content | `DungeonDefinition` (Resource) | `ContentManifest`/`ContentRegistry` (bucket `dungeons`) | as content |
| Durable story progress | `DungeonProgress` (RefCounted) | `GameSession.progress` | yes, save v2 `dungeon_progress` |
| Transient run | `DungeonRunState` (RefCounted) | `DungeonService` (`GameSession.dungeons`) | **never** |

## Contracts (frozen)

```gdscript
class_name DungeonDefinition extends Resource            # core/dungeon/dungeon_definition.gd
@export var dungeon_id: StringName                        # stable id, e.g. dungeon.01
@export var display_name: String
@export var world_id: StringName                          # references WorldDefinition, never duplicates it
@export var entry_spawn_id: StringName                    # SpawnMarker inside that world
@export var prerequisites: Array[StringName]              # completed dungeons required to enter
@export var first_clear_unlocks: Array[StringName]        # dungeons unlocked by the first completion
@export var repeatable: bool = true
@export var completion_objective: StringName              # objective id reported by the world
@export var regular_reward_id: StringName                 # granted on every completion (run scope)
@export var first_clear_reward_id: StringName             # granted once, ever (story scope)
func validation_errors() -> PackedStringArray             # self-contained field rules
func is_start_dungeon() -> bool

class_name DungeonProgress extends RefCounted            # core/dungeon/dungeon_progress.gd
func reset_to_new_game(start_dungeon_ids: Array[StringName]) -> void
func is_unlocked(id) -> bool;  func is_completed(id) -> bool
func was_first_clear_claimed(id) -> bool
func unlock(id) -> bool                                   # true when newly unlocked
func unlock_all(ids) -> int
func mark_completed(id) -> bool                           # true only on the first completion
func mark_first_clear_claimed(id) -> bool
func has_flag(flag) -> bool;  func set_flag(flag) -> bool
func completed_ids()/unlocked_ids()/first_clear_claimed_ids() -> Array[StringName]   # sorted
func to_save_dict() -> Dictionary                         # JSON-safe, stable order
static func from_save_dict(data: Dictionary) -> DungeonProgress   # tolerant, never fails

class_name DungeonRunState extends RefCounted            # core/dungeon/dungeon_run_state.gd
enum Status { NOT_STARTED, ACTIVE, COMPLETED, ABORTED }
var run_id: int;  var dungeon_id: StringName;  var status: Status;  var abort_reason: StringName
func begin(run_id, dungeon_id) -> bool
func mark_enemy_defeated(source_id) -> bool;  func mark_chest_opened(source_id) -> bool
func note_objective(objective_id) -> bool;  func is_objective_completed(objective_id) -> bool
func defeated_enemy_ids()/opened_chest_ids()/completed_objectives() -> Array[StringName]
func complete() -> bool;  func abort(reason) -> bool;  func is_active()/is_completed() -> bool
# every mutation is refused unless the run is ACTIVE: a stale run cannot mutate

class_name DungeonService extends RefCounted             # systems/dungeon/dungeon_service.gd
signal run_started(run_id, dungeon_id);  signal run_aborted(run_id, dungeon_id, reason)
signal dungeon_completed(dungeon_id, first_clear, run_id)
signal reward_granted(dungeon_id, scope, code)
const CODE_OK / CODE_UNKNOWN_DUNGEON / CODE_LOCKED / CODE_ALREADY_COMPLETED
      / CODE_NO_ACTIVE_RUN / CODE_OBJECTIVE_NOT_MET / CODE_NO_REWARD / CODE_UNKNOWN_REWARD
func setup(registry, progress, loot) -> void
func progress() -> DungeonProgress;  func current_run()/active_run() -> DungeonRunState
func can_enter(dungeon_id) -> StringName
func start_run(dungeon_id) -> DungeonRunState            # null when refused; aborts a previous run
func note_objective(objective_id) -> bool                # true when it completed the dungeon
func complete_run() -> bool                              # idempotent
func abort_run(reason) -> bool;  func leave_world() -> void
func claim_pending_first_clear_rewards() -> int
func dungeon_for_world(world_id) -> DungeonDefinition
```

Loot scopes (ADR-013):

```gdscript
class_name LootGrant                                     # systems/loot/loot_grant.gd
const SCOPE_RUN := &"run"      # repeatable, transient ledger, one claim per run
const SCOPE_STORY := &"story"  # one-time, persistent ledger
var scope: StringName = SCOPE_RUN;  var run_id: int = 0   # optional stale-run check
static func from_reward(key, reward, scope := SCOPE_RUN) -> LootGrant
# LootService: begin_run(run_id)/end_run(), is_claimed_in_run(key), is_claimed(key) = persistent,
# codes granted/duplicate/invalid/unknown_item/stale_run; run-scope without a run -> invalid
```

Save v2 (ADR-010 extension):

```json
{ "version": 2, "health": ..., "gold": ..., "items": [...], "world_id": ..., "spawn_id": ...,
  "claimed_reward_keys": ["<dungeon_id>/<reward_id>", ...],
  "dungeon_progress": { "completed": [...], "unlocked": [...], "first_clear_claimed": [...],
                        "story_flags": [...] } }
```
`dungeon_progress` is optional on read (a v1 shape yields empty progress). `MIGRATIONS[1]` bumps the
version, adds an empty section and **drops the legacy v1 `claimed_reward_keys`** (they were all
regular-reward keys with no story meaning; keeping them would leave dead data forever). Never invents
a completion; the session seeds the start dungeons so dungeon 01 stays available.

## Ownership and writers

| State | Writer |
|-------|--------|
| `DungeonProgress` | `DungeonService` only |
| `DungeonRunState` fields | `DungeonService` (lifecycle/objectives) and `WorldHost` facts (`mark_enemy_defeated`, `mark_chest_opened`) |
| `LootService` ledgers | `LootService` only |
| session gold/inventory/claimed keys | `LootService` only |
| session health/location/snapshot mapping | `GameSession` only |
| travel + run start/end + the locked gate | `WorldRouter` only |
| the dungeon list UI | `DungeonPanel`/`GameHud` (reads only, never decides unlocks) |

## Work items and state

| ID | Deliverable | Owner | State |
|----|-------------|-------|-------|
| W0 | Audit + contracts: ADR-013/ADR-014, this plan | coordinator | done |
| W1a | `DungeonDefinition`, `DungeonProgress`, `DungeonRunState` | coordinator | done |
| W1b | Loot scope split (`LootGrant.scope`, run ledger, `stale_run`) | coordinator | done |
| W1c | Save v2 + `MIGRATIONS[1]` | coordinator | done |
| W1d | Registry dungeon bucket + progression-graph validation (unreachable/cycles) | coordinator | done |
| W2 | `DungeonService`, session/router/host integration, `EnemyBrain.objective_id`, Main boot fallback | coordinator | done |
| W3 | Dungeon 02 scene + objective marker in dungeon 01 | coordinator | done |
| W4 | Content: 2 dungeons, 5 new rewards, manifest via the generator | coordinator | done |
| W5 | Hub board + selection panel + UI input focus | `godot-specialist` | in progress |
| W6 | Test updates (Sprint 02 expectations) + Sprint 03 suites + manual checklist | coordinator + `gameplay-engineer` | in progress |
| W7 | Independent review + fixes + re-validation | `reviewer` | planned |

## Sprint 02 expectations that must change (ADR-012 rule 7, not a weakening)

| Test | Why | Replacement |
|------|-----|-------------|
| `tests/unit/loot/test_loot_service.gd` | run-scope grants need an active run; the persistent ledger is story-only | add `begin_run`; split run vs story assertions (both ledgers) |
| `tests/integration/test_interaction_ray.gd` | chest/pickup grants are run-scoped | fixture opens a run ledger before interacting |
| `tests/unit/world/test_game_session.gd` | same | open a run in the fixture |
| `tests/unit/save/test_save_manager.gd` | v1 now has a migration path | keep an unmigratable case with version 0, add v1→v2 |
| `tests/integration/test_save_round_trip.gd` | version 2; regular keys no longer persist | assert the story key round trip + `dungeon_progress`; assert run keys do **not** persist |
| `tests/integration/test_death_respawn.gd` | the claimed key must be a story claim | use a story-scope grant or assert the run ledger is discarded |
| `tests/integration/test_sprint02_loop.gd` | completion rewards, re-loot and re-run semantics are new | rewritten as the Sprint 03 loop with stronger assertions |
| `tests/integration/test_content_graph.gd` | 3 worlds, 2 dungeons | assert the dungeon graph, objectives and rewards |

## Acceptance criteria

Domain and content: `DungeonDefinition` field validation; registry reports empty/duplicate dungeon
ids, unknown world, unknown prerequisite, unknown unlock target, unknown reward, unreachable
dungeon, duplicate world mapping, and keeps an empty bucket valid; the shipped manifest is valid with
`dungeon.01` as the only start dungeon.

Progress: a new game unlocks exactly the start dungeons and completes nothing; `mark_completed`
reports the first completion once; `unlock` is idempotent; `to_save_dict`/`from_save_dict` round trip
is tolerant and stable-ordered; unknown ids are dropped with warnings.

Run lifecycle: entering a dungeon starts an ACTIVE run with a fresh id; entering the hub leaves no
active run; a locked dungeon is refused with `blocked` before the swap and changes nothing; a second
entry creates a fresh run with no memory of the previous claims; death aborts the run and cannot
complete a dungeon; a stale run id cannot mutate.

Loot: one run-scope claim per run, repeatable in the next run; story-scope once ever and across
save/load; a persistent key never blocks a run-scope grant and vice versa; a run-scope grant without
an active run is `invalid` and mutates nothing; after N runs the persisted key count equals the story
claims only.

Completion: the objective enemy's death completes the dungeon; an ordinary enemy's death never does;
a double report completes once; the first clear grants the story reward once and unlocks the next
dungeon; a repeat clear grants the regular reward again and nothing else; a failed story grant leaves
a retryable state and the retry grants only the missing part.

Save/load: v1 migrates to v2 (progress seeded, dungeon 01 available, no invented completions, HP/gold/
items/world/spawn preserved, legacy keys dropped); v2 round trips completions, unlocks and story
claims through a fresh `Main`; a saved world that is a locked dungeon falls back to the hub; a future
version is refused untouched; corrupt data is quarantined; atomic write and backup recovery intact;
no run data in the snapshot.

End-to-end: hub → dungeon 01 → objective → story reward + unlock → hub → dungeon 02 enterable →
re-enter dungeon 01 with reset enemies/chest and re-earned ordinary loot → no second story reward →
save → relaunch restores progress; exactly one player rig and one world at every step; no leaks.

Manual/graphical checks (report **NOT RUN** when not performed): board readability and mouse
release/capture, walking both dungeons, recognising the objective enemy, HUD feedback after an
unlock, no runtime errors in a graphical session.

## Known constraints (Sprint 03)

- Run state is never persisted: re-entering a dungeon always starts a fresh run, even after a crash.
- Legacy v1 reward keys are dropped by the migration (documented data loss, required by ADR-012 r.7).
- The board is a hub interactable (no auto-open), so Sprint 01/02 input tests keep working.
- `prerequisites` are display/consistency metadata: the *unlock* state is the single gate, so a
  prerequisite is never a second gate.
- `repeatable = false` is implemented in `can_enter` but both shipped dungeons are repeatable.
