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

Addendum (Sprint 02): the closed lists are amended with layer 5 `interactable`
(`PhysicsLayers.INTERACTABLE = 1 << 4`) and the action `interact` (physical E). Interactables are
`Area3D`s: never damageable, never blockers, never part of any movement mask. Layers 1-4 and the five
Sprint 01 actions keep their meaning. `tools/setup_input_map.gd` remains the generator of the action
list; `tests/unit/test_project_contract.gd` and `tests/integration/test_project_scripts.gd` remain
the lock. The single-writer rule (project.godot, physics_layers.gd, DECISIONS.md, setup_input_map.gd)
is unchanged.

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

## ADR-007 — Session ownership, world routing, player lifecycle and respawn
Status: accepted (Sprint 02).
Context: Sprint 02 needs hub<->dungeon travel, HP/inventory continuity across a scene swap, save/load
and a death outcome that cannot brick the run. ADR-001 forbids globals; `ARCHITECTURE.md` mandates
one transition coordinator and explicit spawn IDs.
Decision:
- `GameSession` (`RefCounted`) is created and owned by the composition root `Main` (`world/main.tscn`,
  the new main scene). No autoload, no service locator. `Main` never unloads; only the child of
  `WorldRouter.world_slot` is swapped.
- `PlayerSessionState` holds the durable run state (health, gold, inventory, world/spawn ids,
  claimed reward keys) and never references a Node. Only `GameSession` and `LootService` write it.
- `WorldRouter` is the only component that instantiates or frees a world or a player. Exactly one
  player rig exists, as a child of the current world, recreated on every world load with the session
  HP applied AFTER `add_child` (because `HealthComponent._ready()` resets to full).
- Spawn coordinates live in `SpawnMarker` nodes inside world scenes; `WorldDefinition` carries the
  world id, the scene and the default spawn id, never coordinates.
- Travel is one synchronous prepare-then-swap: validate definition/scene/marker, build world+player,
  add the new world, apply HP, then remove and free the old world in the same call. Any failure before
  the swap frees the candidate and leaves the current world untouched. `request_travel` is
  single-flight (`busy`) and clears the guard just before emitting `world_loaded`.
- Enemies receive their target from the world host at `_ready` via `set_target`; combat and AI rules
  are untouched.
- Death/respawn: on the current player's `HealthComponent.died` the router travels to
  `respawn_world_id` (`world.hub`) at its default spawn with full HP; inventory, gold and claimed keys
  are preserved; HP is never captured from the dead rig. No in-place revive, no death penalty, no
  corpse run, no checkpoint - the ordinary swap destroys the dead rig.
Consequences: one lifecycle owner for worlds and actors; one durable state object for save/load;
`world/prototype/proto_arena.tscn` stays the Sprint 01 regression fixture with its embedded player;
standing position and world state are not persisted; threaded loading would break the synchronous
swap assumption and needs a new decision.

## ADR-008 — Interaction contract
Status: accepted (Sprint 02).
Context: pickups, a chest, a save shrine and portals need one small testable "walk up and press E"
path without a dialogue/quest system and without coupling the general interaction system to loot.
Decision:
- `Interactable extends Area3D` (layer 5) with `prompt`, `enabled` and `one_shot`. `interact()` is
  final and owns the guard/one-shot bookkeeping; subclasses only implement `_perform_interact()`.
- `InteractionController` is a direct child of the player rig
  (`InteractionController.find_on()` mirrors `HealthComponent.find_on()`), ray-queries once per
  physics tick with mask `world|interactable` (walls occlude by construction), handles the `interact`
  action in `_unhandled_input`, and emits `focus_changed` / `prompt_changed` / `interaction_resolved`.
  At most one interaction per physics frame, synchronous, no awaits.
- A dead interactor is detected via `HealthComponent.find_on(interactor).is_alive()`, so the
  interaction system never imports `PlayerController`.
- Services are injected per type by the world host:
  `PortalInteractable.set_travel_provider(Callable)`,
  `PickupInteractable/ChestInteractable.configure(reward, grant_key, LootService)`,
  `SaveShrineInteractable.set_save_provider(Callable)`. `systems/interaction/**` never imports
  `world/**`.
Rejected: string-keyed action dispatch, a global interaction manager, portals importing `WorldRouter`,
UI-driven prompts.
Consequences: a new interactable kind is one subclass plus one host binding line; the base contract
stays domain-free; layer 5 and `interact` are added to the ADR-005 closed list.

## ADR-009 — Inventory, currency and loot idempotency
Status: accepted (Sprint 02).
Context: a reward must be collected exactly once despite duplicate signals, repeated interactions,
save/load and re-entering a world; Sprint 02 excludes rarity, equipment slots, affixes and vendors.
Decision:
- `ItemDefinition` (id, display name, description, kind, stackable, max_stack, optional icon) and
  `RewardDefinition` (id, optional item+count, gold) are immutable Resources.
- `Inventory` is a pure counted bag with stack awareness: entries are filled up to
  `ItemDefinition.max_stack`, non-stackable items always occupy their own entry; no slot cap.
  Only its own methods mutate it; it validates ids through the passed definition.
- Currency is `PlayerSessionState.gold`, never an inventory item.
- `LootGrant` is the only transfer object and `LootService.grant()` the only loot entry point,
  idempotent per `grant_key` recorded in the persisted `PlayerSessionState.claimed_reward_keys`.
  Validation completes before the first mutation: a rejected grant neither mutates nor consumes the key.
- `grant_key = LootGrant.key_for(world_id, loot_source_id)` = `"<world_id>/<loot_source_id>"`;
  `loot_source_id` is authored per placement and is never a node name, display name or asset path.
- Enemy death emits `defeated(reward, loot_source_id, position)`; the world host spawns the pickup
  (unless the key is claimed) and combat never touches inventory. Save load rebuilds a fresh bag
  instead of granting.
Consequences: double loot is impossible by construction; drops are not persisted, so a claimed drop
never reappears while an unclaimed one is gone after re-entering the world; per-placement reward
overrides and stack/slot caps are deferred.

## ADR-010 — Save format, atomic write and corruption policy
Status: accepted (Sprint 02).
Context: Sprint 02 must restore HP, inventory, gold and location after a relaunch without storing
Nodes, and a corrupt or future save must never brick the boot.
Decision:
- One slot `user://save_slot0.json`, JSON object, `version: 1`: health, gold, items[{id,count}],
  world_id, spawn_id, claimed_reward_keys[]. No Node or scene-path data.
- `SaveSnapshot.to_dict()/from_dict()` is the only (de)serialisation point; `SaveManager` is
  content-agnostic.
- Atomic write: write `<path>.tmp` (flush+close) then rename the existing file to `<path>.bak`, rename
  tmp to `<path>`, delete `.bak`. Any failure restores `.bak` and returns `IO_ERROR`; a partial file
  never becomes the save.
- Load policy: missing -> `MISSING` (new game); unreadable/unparseable/wrong shape -> best-effort
  quarantine to `<path>.corrupt` and `CORRUPT`; `version > CURRENT_VERSION` -> `UNSUPPORTED_VERSION`;
  `version < CURRENT` -> the `MIGRATIONS` chain (empty in Sprint 02; adding a table entry plus a
  migration test is the extension point).
- Semantic filtering happens in `GameSession.apply_snapshot`: unknown item ids, claimed keys and
  invalid world ids are dropped with warnings; a missing spawn id falls back to the world default.
  A saved `health <= 0` is kept in the snapshot and is turned into full health when the next rig
  spawns (`GameSession.apply_to_player`), because only there is the rig's `max_health` known.
- Saving is explicit in-world (the hub shrine calls `GameSession.save_now()`); loading happens at
  boot. No autosave, no save-on-quit, no keybinds.
Consequences: corruption or a future version degrades to a new game with a diagnostic instead of a
crash; the DTO stays inspectable JSON; multiple slots and world-state persistence are deferred.

## ADR-011 — Content registry, manifest and id stability
Status: accepted (Sprint 02).
Context: portals, save restore, loot and the HUD resolve content by stable id, and the project has
loose `.tres` files with no duplicate detection.
Decision:
- An explicit `content/definitions/content_manifest.tres` lists attacks, enemies, items, rewards and
  worlds. `ContentRegistry.build(manifest)` builds typed id->resource maps and reports duplicate ids,
  empty ids, null/invalid entries and unresolved cross-references as data (`errors`, `is_valid()`);
  a bad manifest degrades to missing lookups plus a diagnostic, never a crash.
- Gameplay resolves ids through the registry; ids are authored literals (`world.*`, `spawn.*`,
  `item.*`, `reward.*`, `enemy.*`, `attack.*`), never node names, display names or asset paths.
- An integration test validates the shipped manifest: uniqueness, cross-references, portal targets,
  default spawn ids and loot source ids.
Rejected: runtime folder scanning as the lookup path (non-deterministic order, no duplicate
detection), id derivation from names or paths.
Consequences: content drift fails tests instead of surfacing as a runtime miss; adding content is a
deliberate manifest edit; hot reload and an editor validator are deferred.

## ADR-012 - Repeatable dungeons with persistent story progress
Status: accepted (decision recorded before Sprint 03; no code, no save-format change yet).
Context: The game ships isolated dungeons reached from the hub. A single-clear model would waste the
existing content and force new geometry for every story beat, while a pure reset model would lose
story progress. `GAME_DESIGN.md` therefore needed an explicit repeatability rule before any dungeon
progression is built.
Decision:
1. The player starts with access to the first dungeon.
2. Completing a dungeon for the first time is a story event.
3. A first clear unlocks the next dungeon according to the progression configuration.
4. Once unlocked, a dungeon stays available.
5. A dungeon can be entered and completed repeatedly.
6. Starting a new run resets ordinary enemies, bosses and ordinary loot for that run.
7. Repeating a dungeon re-earns ordinary rewards, XP and gold.
8. One-time story rewards can never be granted a second time.
9. The first-clear story events must not fire again on a repeat.
10. Persistent story progress is saved independently of the transient run state.

Future contracts (concept only - do NOT implement until the dungeon increment is scheduled; no
runtime or save-format change is authorised by this ADR):
- `DungeonDefinition` (static content, `Resource`): dungeon id, scene reference, prerequisites,
  first-clear unlocks, repeatable flag, reward references.
- `DungeonProgress` (persistent, per save): completed dungeon ids, unlocked dungeon ids,
  first-clear reward claims, durable story progress.
- `DungeonRunState` (transient, per run): current dungeon, enemy state for this run, chests opened
  in this run, loot collected in this run. Never persisted.

Cooperation with the existing systems:
- `GameSession` owns `DungeonProgress` next to `PlayerSessionState`; `DungeonRunState` lives with the
  run and is destroyed with the world, never written to a save.
- `SaveManager`: a later version bump adds a `dungeon_progress` section through the existing
  `MIGRATIONS` extension point; version 1 files stay loadable, and no field is added now.
- `ContentRegistry`/`ContentManifest`: `DungeonDefinition` becomes another manifest bucket under
  ADR-011, with the same duplicate/cross-reference validation.
- `WorldRouter`: entering a dungeon keeps using the existing world and spawn ids; the progress record
  only decides which dungeons are offered.
- `LootService`: ordinary repeatable rewards keep per-run grant keys; one-time story rewards use
  persistent claim keys that survive runs, re-entry and save/load (the same idempotency rule as
  ADR-009).

Rejected: resetting story progress on every run; persisting transient run state; deriving unlocks
from scene names or node paths; a procedural generator as a prerequisite for repeatability.
Consequences: repeatability and story progress get separate owners and separate lifetimes; the first
dungeon increment is a definition plus a progress record plus a gate, not a generator; procedural
generation and the progression formula stay undecided.

## ADR-013 - Reward ledgers: repeatable run rewards vs one-time story rewards
Status: accepted (Sprint 03).
Context: ADR-012 makes ordinary loot repeatable per run while story rewards stay one-time. The
Sprint 02 model had a single *persistent* ledger (`PlayerSessionState.claimed_reward_keys`) keyed by
`<world>/<source>`, so a second visit could never re-earn a chest or a drop; keying by run id in that
same ledger would grow the save without bound.
Decision:
- `LootGrant.scope` selects the ledger: `SCOPE_RUN` (default, repeatable) or `SCOPE_STORY` (one-time).
- Run-scoped claims live in a **transient** ledger owned by `LootService` (`_run_claims`), opened by
  `begin_run(run_id)` and closed by `end_run()`. The ledger is never serialised, so ordinary rewards
  cannot grow the save and a new run cannot see an old run's claims.
- Story-scoped claims keep using the persistent `claimed_reward_keys`. Story keys are
  `"<dungeon_id>/<reward_id>"`; the session accepts a prefix that is a listed world *or* dungeon.
- `LootService.grant()` is still the only loot entry point and the only writer of bag/gold/claims.
  Validation completes before the first mutation. New code `stale_run` refuses a run-scoped grant
  whose optional `run_id` is not the current run; a run-scoped grant without an active run is
  `invalid` (it would create a claim no run owns).
- A rejected grant never consumes a key and never partially mutates.
Consequences: double rewards stay impossible per ledger; ordinary loot repeats per run; the save
grows only with story rewards (bounded by the dungeon count); `WorldHost` checks the run ledger for
drops, and the old persistent-key gate no longer blocks a legal reward in a new run.

## ADR-014 - Dungeon run lifecycle, travel gate and completion seam
Status: accepted (Sprint 03).
Context: ADR-012 needs one owner for the active run, a single gate against entering locked dungeons
and a completion trigger that is not "some enemy died".
Decision:
- `DungeonService` (RefCounted, session-scoped, owned by `GameSession` next to `DungeonProgress`)
  owns the policy: `can_enter`, `start_run`, `note_objective`, `complete_run`, `abort_run`,
  `leave_world`, `claim_pending_first_clear_rewards`. One active run at a time; a new run aborts the
  previous one. `DungeonRunState` is transient and never serialised.
- `WorldRouter` applies the lifecycle after a successful swap: entering a dungeon world starts a run,
  entering any other world calls `leave_world()` (an unfinished run becomes ABORTED, a completed one
  stays as a record). Death respawn therefore aborts the run and cannot complete a dungeon.
- The router also owns the **logic gate**: a destination world that maps to a dungeon whose
  `can_enter` is not `CODE_OK` is refused with `blocked` *before* anything is instantiated, so a
  crafted portal or a UI bug cannot enter a locked dungeon.
- Completion is objective-driven: `DungeonDefinition.completion_objective` must be reported by the
  world. `WorldHost` reports it from `HealthComponent.died` (once per life, unconditional) plus
  `EnemyBrain.objective_id`, not from the reward-gated `defeated` signal, so an objective enemy
  without loot still completes the dungeon. An ordinary enemy (empty `objective_id`) never completes.
- Commit order: mark the objective and complete the run, record the completion, unlock the
  first-clear targets, then grant the rewards. A failed story grant leaves "completed without the
  claim" (the retryable direction) and `claim_pending_first_clear_rewards()` repairs it at boot.
  The forbidden state (claim recorded without progress) cannot occur.
Rejected: completion on any enemy death; the gate only in the UI; keying runs by a persisted counter;
a second service for story rewards.
Consequences: one lifecycle owner, one gate, one completion seam; a future objective type only has to
report its own objective id; the board reads progress and never decides unlocks.

## ADR-005 addendum (Sprint 04)

The closed lists gain the action `inventory` (physical TAB): it opens/closes the character panel
(inventory + equipment + stats), while `ui_cancel` closes any open panel. No new layer is added;
`interactable` stays layer 5. The single-writer rule and the lock tests are unchanged
(`tools/setup_input_map.gd` regenerates the list, `tests/unit/test_project_contract.gd` and
`tests/integration/test_project_scripts.gd` lock it).

## ADR-015 - Character stats, equipment ownership and stat modifiers
Status: accepted (Sprint 04).
Context: Sprint 04 needs base stats, equipment that changes them, and a durable record of what is
worn, without turning into a modifier framework or breaking the count-based inventory.
Decision:
- `PlayerDefinition` (content, manifest bucket `players`) owns the base stats and the default attack
  profile. `CharacterStats` (derived runtime, owned by `GameSession`) computes
  `effective = max(MINIMUM[stat], base + sum(buckets))`; it is additive only, and `set_modifiers()`
  *replaces* one source's bucket, so repeated equip can never stack a bonus.
- One bucket per equipment slot, keyed by the stable slot name: a weapon swap replaces the
  `main_hand` bucket, which is how the old bonus disappears. No bookkeeping, no unbounded buckets.
- Ownership semantics A: an equipped item leaves the bag (`equip` removes one copy, `unequip` returns
  it, a swap returns the previous item in the same atomic operation). The invariant
  `is_equipped(id) => count_of(id) == 0` is local and testable, the count-based `Inventory` API is
  untouched, and selling an equipped item is impossible by construction.
- `EquipmentState` is durable runtime state inside `PlayerSessionState`, Node-free, and serialised as
  stable slot names -> item ids. On load the equipment record is authoritative: an unknown id or slot
  is dropped with a warning, a slot mismatch returns the copy to the bag, and a bagged duplicate is
  removed (the record wins).
- `CharacterStats` is never saved: it is recomputed from the definition plus the equipment.
- `HealthComponent.set_max_health()` raises the ceiling without healing and clamps current HP down
  without emitting `died`; stats are applied to a freshly spawned rig **after** `add_child`, because
  the component resets to the scene maximum in `_ready()`.
Rejected: per-instance item identity (the inventory has no instance ids); a modifier framework with
multiplicative/conditional sources (the bucket seam already allows a future source to register);
persisting effective stats.
Consequences: adding a future slot or stat is a data plus enum change; buffs/debuffs later only need
another `set_modifiers(source_id, ...)` caller.

## ADR-016 - Combat integration: swing snapshot, stat-driven damage and receiver-side defense
Status: accepted (Sprint 04).
Context: Equipment must change damage and mitigation without rebuilding combat, and a weapon change
must not alter a swing that is already resolving.
Decision:
- The stats owner's swing damage is `stats.effective(ATTACK_DAMAGE)`; an actor without stats (every
  enemy) keeps `AttackDefinition.damage`. A weapon's `AttackDefinition` owns reach, arc and timings
  only and must declare `damage == 0`, so the same number never has two sources.
- `AttackController.request_attack()` pins the active profile **and** the damage value for the whole
  swing; phase timings, reach, arc, the hit-frame damage and the cooldown that follows all read the
  pin, so a mid-swing weapon change cannot affect the swing and cannot bypass the cooldown.
- Mitigation lives on the receiver: `HealthComponent` subtracts via
  `amount * (100 / (100 + defense))`, with `defense >= 0` clamped from the provider. The formula is
  monotonic, never reduces a positive hit to zero, and with `defense == 0` (every actor without
  stats, including the player before armour) it is identical to the previous behaviour.
- The viewmodel only reacts to the equipment change (visibility/scale of a placeholder); it never
  times an attack and never participates in the evade-by-leaving-reach mechanic.
Rejected: attacker-side mitigation (the attacker would need the target's stats); a subtractive
formula (armour could reach immunity); reading the damage live at the hit frame (a mid-swing swap
would change it).
Consequences: combat keeps its ownership of phases, reach, cooldowns, hit validation and damage
application; Sprint 01/02 combat suites pass unchanged.

## ADR-017 - NPC and trading contract
Status: accepted (Sprint 04).
Context: One hub merchant must sell and buy items without giving the NPC knowledge of the player, the
bag, the save or combat, and without opening gold exploits.
Decision:
- `NpcDefinition` (id, display name, one greeting line, optional `MerchantDefinition`) and
  `NpcInteractable` (an `Interactable` subclass) emit `dialogue_requested`; the world host re-emits it
  and the HUD opens a dialogue panel with an optional shop button. The NPC never reads gold, the bag,
  the save or the player controller.
- `TradingService` is the only trade writer and the only place with a price rule:
  `buy_price = ItemDefinition.base_value`, `sell_price = max(1, floor(base_value * SELL_RATE))` with
  `SELL_RATE = 0.5`; `base_value <= 0` means "not tradable". The UI only reads prices.
- Stock is transient per merchant binding (Sprint 04: unlimited stock of the configured items, one
  counter per item), never saved: a reload resets stock and gold together, so no buy/sell loop exists.
- Every operation re-validates internally (never trusting `can_buy`/`can_sell`), and is atomic:
  full validation, then bag, then gold, then stock, then the signal. A refusal mutates nothing; a
  duplicate UI event fails on the second attempt (stock or gold).
Rejected: per-merchant inventory in the save (a new writer and more surface); price computation in the
UI or the NPC; a shop database or backend.
Consequences: a future vendor only needs another `MerchantDefinition` plus a placement; dynamic
economy, reputation and dialogue trees stay out of scope.

