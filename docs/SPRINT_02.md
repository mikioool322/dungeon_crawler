# Sprint 02 — session, world flow, loot and persistence (plan of record)

Status: approved by the coordinator after the architecture audit; executed with `architect`,
`gameplay-engineer`, `godot-specialist`, `qa-engineer` and `reviewer` roles.
Decisions live in `docs/DECISIONS.md` as ADR-007..ADR-011 plus the ADR-005 addendum.
Baseline: `master` at `655b0c7`, 178 tests / 1153 assertions PASS.

## Goal (definition of done, from the owner)

Boot into a HUB → enter a dungeon through a portal → spawn at the correct spawn point → fight the
existing combat enemy → gain an item and gold → pick the reward up through the interaction system →
return to the HUB → keep HP, inventory and gold → save → quit, relaunch, restore progress.
Placeholder art only; Sprint 01 combat is a regression fence and must keep passing.

Out of scope (must not be built): procedural generation, multiple hubs/dungeons, dialogue/NPCs,
crafting, durability, rarity, equipment slots, affixes, vendors, inventory UI screens, item
models/icons beyond an optional texture reference, transition VFX, world-state persistence,
threaded loading, multiple save slots, autosave, save/load keybinds, AI changes.

## Architecture decisions (frozen)

| Area | Decision |
|------|----------|
| Session ownership | `GameSession` (`RefCounted`) owned by the composition root `Main` (`world/main.tscn`, new main scene). **No autoloads.** `Main` never unloads; only the child of `WorldSlot` is swapped |
| Durable state | `PlayerSessionState` (health, gold, inventory, world/spawn ids, claimed reward keys). No Node references, ever |
| Writers | `GameSession` writes health/location; `LootService` writes inventory/gold/claimed keys; `Inventory` writes its own bag. Nothing else mutates session state |
| Player lifecycle | `WorldRouter` instantiates exactly one `player.tscn` per world load as `Player` under the world root. The arena keeps its embedded player (Sprint 01 fixture) |
| HP sync | Capture from the live rig before the swap/save; apply with `HealthComponent.restore()` **after** `add_child` (its `_ready()` resets to full) |
| Death | On the current player's `died`: travel to `world.hub` default spawn with full HP; inventory/gold/claimed keys kept; no capture from the dead rig; no in-place revive, no penalty, no checkpoint |
| Spawns | `SpawnMarker` nodes in world scenes carry `spawn_id`; `WorldDefinition` carries `id`, `scene`, `default_spawn_id`. Coordinates are never in the definition or in portal logic |
| Travel | One synchronous prepare-then-swap in `WorldRouter.request_travel`; single-flight (`busy`); every failure before the swap frees the candidate and leaves the current world untouched; no `await` between adding the new world and freeing the old |
| Enemies | The world host binds `set_target(player)` at `_ready`; combat/AI untouched |
| Interaction | `Interactable extends Area3D` on layer 5 with a final `interact()` and a virtual `_perform_interact()`; one ray per physics tick from `InteractionController` (mask `world|interactable`, mask makes walls occlude); the base knows nothing about loot, travel or save |
| Binding | Per-type, done by the world host: portals get a travel `Callable`, chests/pickups get `(reward, grant_key, LootService)`, the shrine gets a save `Callable`. `systems/interaction` never imports `world/` |
| Currency | Gold lives on the session, never in the inventory |
| Loot idempotency | `LootService.grant(grant)` is the only entry point, idempotent per `grant_key = "<world_id>/<loot_source_id>"` recorded in the persisted `claimed_reward_keys`; validation completes before the first mutation |
| Rewards | `RewardDefinition` (id, optional item+count, gold) is immutable content; `EnemyDefinition.reward` + per-placement `loot_source_id` |
| Save | One slot `user://save_slot0.json`, `version: 1`, JSON only; atomic write via `.tmp` → `.bak` → rename → delete `.bak`; corrupt → quarantine to `.corrupt` + new game; `version > CURRENT` → refuse; semantic filtering (unknown ids dropped with warnings) in `GameSession.apply_snapshot` |
| Saving trigger | In-world shrine interaction in the hub (`SaveShrineInteractable`). Loading happens at boot. No autosave, no F5/F9 |
| Content | Explicit `content/definitions/content_manifest.tres`; `ContentRegistry.build(manifest)` with duplicate/empty/null/invalid/cross-reference detection as data (`errors`, `is_valid()`); no folder scanning |
| HUD | `presentation/hud/game_hud.tscn` + `game_hud.gd` owned by `Main`; reads models/signals only, owns no state, survives a freed player via `is_instance_valid` |
| Layers/actions | ADR-005 addendum: layer 5 `interactable` (`PhysicsLayers.INTERACTABLE = 1 << 4`), action `interact` (E). Nothing else is added or renamed |

## Module contracts (frozen; implement exactly, no required `_init` arguments)

### Definitions (Resources, immutable at runtime)

```gdscript
class_name ItemDefinition extends Resource            # core/content/item_definition.gd
enum Kind { MISC, CONSUMABLE, WEAPON, KEY }
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.MISC
@export var stackable: bool = true
@export var max_stack: int = 1
@export var icon: Texture2D = null                    # optional, presentation only
func validation_errors() -> PackedStringArray
func is_valid() -> bool
# rules: id non-empty; display_name non-empty; max_stack >= 1; stackable => max_stack >= 2;
#        not stackable => max_stack == 1

class_name RewardDefinition extends Resource          # core/content/reward_definition.gd
@export var id: StringName = &""
@export var item: ItemDefinition = null               # null => gold-only reward
@export var item_count: int = 0
@export var gold: int = 0
func validation_errors() -> PackedStringArray
# rules: id non-empty; gold >= 0; item == null => item_count == 0;
#        item != null => item_count >= 1 and item.is_valid(); at least one of item/gold

class_name WorldDefinition extends Resource           # core/content/world_definition.gd
@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var default_spawn_id: StringName = &""
func validation_errors() -> PackedStringArray
```

### Inventory and session

```gdscript
class_name Inventory extends RefCounted               # core/inventory/inventory.gd
signal changed()
func add(definition: ItemDefinition, count: int = 1) -> int   # returns amount added; <=0 / invalid => 0
func remove(item_id: StringName, count: int) -> int           # returns amount actually removed
func count_of(item_id: StringName) -> int
func stack_count(item_id: StringName) -> int
func ids() -> PackedStringArray                       # sorted, unique
func entries() -> Array[Dictionary]                   # [{"id": String, "count": int}], one per stack
func total_item_count() -> int
func is_empty() -> bool
func clear() -> void
# Stacks: entries are appended until a stack reaches definition.max_stack; non-stackable items always
# get their own entry. remove() drains the newest stacks first. No slot cap in Sprint 02.

class_name PlayerSessionState extends RefCounted      # core/session/player_session_state.gd
var health: float = 100.0
var gold: int = 0
var inventory: Inventory = Inventory.new()
var world_id: StringName = &"world.hub"
var spawn_id: StringName = &""                        # "" => the world's default spawn
var claimed_reward_keys: Dictionary = {}              # StringName -> true
func reset_to_new_game(default_health: float) -> void
func claim(key: StringName) -> bool                   # false when already claimed
func is_claimed(key: StringName) -> bool
# invariants: primitives/StringName/Inventory only; never a Node

class_name GameSession extends RefCounted             # world/game_session.gd
signal gold_changed(gold: int)
signal inventory_changed()
signal location_changed(world_id: StringName, spawn_id: StringName)
var state: PlayerSessionState = PlayerSessionState.new()
var loot: LootService = LootService.new()
func setup(registry: ContentRegistry, save_manager: SaveManager) -> void
func new_game() -> void
func load_or_new() -> SaveResult
func save_now() -> SaveResult
func note_location(world_id: StringName, spawn_id: StringName) -> void
func capture_from_player(player: Node3D) -> bool      # live HP -> state (false when no rig/health)
func apply_to_player(player: Node3D) -> bool          # restore(clamp); <=0 => full HP + warning
func add_gold(amount: int) -> int                     # returns new total, ignores <= 0
func to_snapshot() -> SaveSnapshot
func apply_snapshot(snapshot: SaveSnapshot) -> PackedStringArray   # warnings; rebuilds a fresh bag
```

### Loot

```gdscript
class_name LootGrant extends RefCounted               # systems/loot/loot_grant.gd
var grant_key: StringName = &""
var reward_id: StringName = &""
var item_id: StringName = &""
var item_count: int = 0
var gold: int = 0
static func key_for(world_id: StringName, loot_source_id: StringName) -> StringName  # "<world>/<source>"
static func from_reward(grant_key: StringName, reward: RewardDefinition) -> LootGrant
func is_valid() -> bool

class_name LootService extends RefCounted             # systems/loot/loot_service.gd
signal reward_granted(grant: LootGrant, gold_total: int)
const CODE_GRANTED := &"granted"
const CODE_DUPLICATE := &"duplicate"
const CODE_INVALID := &"invalid"
const CODE_UNKNOWN_ITEM := &"unknown_item"
func setup(state: PlayerSessionState, registry: ContentRegistry) -> void
func is_claimed(grant_key: StringName) -> bool
func grant(grant: LootGrant) -> StringName            # codes above; atomic: never a partial grant
```

### Save

```gdscript
class_name SaveSnapshot extends RefCounted            # systems/save/save_snapshot.gd
const CURRENT_VERSION: int = 1
var version: int = CURRENT_VERSION
var health: float = 0.0
var gold: int = 0
var items: Array = []                                  # [{"id": String, "count": int}]
var world_id: StringName = &""
var spawn_id: StringName = &""
var claimed_reward_keys: PackedStringArray = PackedStringArray()
func to_dict() -> Dictionary                           # JSON-safe values only
static func from_dict(data: Dictionary) -> SaveSnapshot   # null when the shape is unusable

class_name SaveResult extends RefCounted              # systems/save/save_result.gd
enum Status { OK, MISSING, CORRUPT, UNSUPPORTED_VERSION, IO_ERROR }
var status: Status = Status.IO_ERROR
var message: String = ""
var warnings: PackedStringArray = PackedStringArray()
var snapshot: SaveSnapshot = null
func ok() -> bool

class_name SaveManager extends RefCounted             # systems/save/save_manager.gd
const DEFAULT_PATH: String = "user://save_slot0.json"
const MIGRATIONS: Dictionary = {}                      # from_version -> Callable(Dictionary) -> Dictionary
func setup(path: String = "") -> void                  # "" => DEFAULT_PATH
func snapshot_exists() -> bool
func save(snapshot: SaveSnapshot) -> SaveResult
func load_snapshot() -> SaveResult
```

### Content

```gdscript
class_name ContentManifest extends Resource           # systems/content/content_manifest.gd
@export var attacks: Array[AttackDefinition] = []
@export var enemies: Array[EnemyDefinition] = []
@export var items: Array[ItemDefinition] = []
@export var rewards: Array[RewardDefinition] = []
@export var worlds: Array[WorldDefinition] = []

class_name ContentRegistry extends RefCounted          # systems/content/content_registry.gd
static func build(manifest: ContentManifest) -> ContentRegistry    # never null
var errors: PackedStringArray = PackedStringArray()
func is_valid() -> bool
func find_attack(id: StringName) -> AttackDefinition
func find_enemy(id: StringName) -> EnemyDefinition
func find_item(id: StringName) -> ItemDefinition
func find_reward(id: StringName) -> RewardDefinition
func find_world(id: StringName) -> WorldDefinition
func all_worlds() -> Array[WorldDefinition]
```

### Interaction

```gdscript
class_name InteractionResult extends RefCounted       # systems/interaction/interaction_result.gd
const OK := &"ok"
var code: StringName = &""
var message: String = ""
static func ok(message: String = "") -> InteractionResult
static func rejected(code: StringName, message: String = "") -> InteractionResult
static func unavailable() -> InteractionResult
func succeeded() -> bool

class_name Interactable extends Area3D                # systems/interaction/interactable.gd
signal interaction_completed(interactor: Node3D, result: InteractionResult)
@export var prompt: String = "Interact"
@export var enabled: bool = true
@export var one_shot: bool = false
func can_interact() -> bool
func interact(interactor: Node3D) -> InteractionResult   # final: guards + one-shot + emits
func _perform_interact(_interactor: Node3D) -> InteractionResult   # virtual
func is_used() -> bool
func mark_used() -> void
# scene: collision_layer = INTERACTABLE, monitoring = false, one CollisionShape3D child

class_name InteractionController extends Node3D       # systems/interaction/interaction_controller.gd
signal focus_changed(interactable: Interactable)
signal prompt_changed(prompt: String, visible: bool)
signal interaction_resolved(result: InteractionResult)
const NODE_NAME: String = "InteractionController"
@export var view: Node3D
@export var interactor: Node3D
@export var reach: float = 2.5
static func find_on(actor: Node) -> InteractionController
func current_focus() -> Interactable
func try_interact() -> InteractionResult
# ray: view.global_position along -view.global_basis.z, mask WORLD|INTERACTABLE,
#      collide_with_bodies/areas = true; `interact` action handled in _unhandled_input;
#      a dead interactor (HealthComponent.find_on(interactor)) cannot interact

class_name PortalInteractable extends Interactable    # systems/interaction/portal_interactable.gd
@export var target_world_id: StringName = &""
@export var target_spawn_id: StringName = &""
var travel_provider: Callable
func _perform_interact(_interactor: Node3D) -> InteractionResult   # returns the router code

class_name PickupInteractable extends Interactable    # systems/interaction/pickup_interactable.gd
@export var reward: RewardDefinition = null
@export var loot_source_id: StringName = &""
var grant_key: StringName = &""
func configure(reward: RewardDefinition, grant_key: StringName, loot: LootService) -> void
func _perform_interact(_interactor: Node3D) -> InteractionResult   # consumed on granted/duplicate

class_name ChestInteractable extends Interactable     # systems/interaction/chest_interactable.gd
@export var reward: RewardDefinition = null
@export var loot_source_id: StringName = &""
func configure(reward: RewardDefinition, grant_key: StringName, loot: LootService) -> void
func _perform_interact(_interactor: Node3D) -> InteractionResult   # stays in world, opens once
```

### World orchestration and HUD

```gdscript
class_name SpawnMarker extends Node3D                 # world/spawn_marker.gd
@export var spawn_id: StringName = &""
static func choose(markers: Array, requested: StringName, default_id: StringName) -> SpawnMarker
# requested -> default -> first by name -> null

class_name WorldHost extends Node3D                   # world/world_host.gd
const PLAYER_NODE_NAME := &"Player"
@export var world_id: StringName = &""
@export var loot_pickup_scene: PackedScene = null
func configure(session: GameSession, registry: ContentRegistry, travel: Callable, save: Callable) -> void
func resolve_spawn(spawn_id: StringName) -> SpawnMarker
func spawn_markers() -> Array[SpawnMarker]
# _ready: bind portals (set travel provider), chests/pickups (configure with LootGrant.key_for),
#         shrine (set save provider), enemies (set_target(player)); on EnemyBrain.defeated spawn the
#         pickup unless the key is claimed. Missing context => push_warning, never push_error.

class_name WorldRouter extends Node                   # world/world_router.gd
signal world_loaded(world_id: StringName, spawn_id: StringName, used_fallback: bool)
signal world_load_failed(world_id: StringName, code: StringName)
signal player_spawned(player: PlayerController)
@export var world_slot: Node3D = null
@export var player_scene: PackedScene = null
@export var respawn_world_id: StringName = &"world.hub"
func configure(session: GameSession, registry: ContentRegistry) -> void
func bootstrap(world_id: StringName = &"", spawn_id: StringName = &"") -> StringName
func request_travel(world_id: StringName, spawn_id: StringName) -> StringName
func capture_session() -> bool
func is_travelling() -> bool
func current_world() -> WorldHost
func current_player() -> PlayerController
# codes: travel_started, busy, unknown_world, invalid_world, invalid_spawn

class_name Main extends Node                          # world/main.gd (new main scene root)
# _ready: ContentRegistry.build(load(manifest)) -> SaveManager -> GameSession.setup ->
#         save_result = load_or_new() -> router.configure(...) -> hud.bind(...) ->
#         router.bootstrap(state.world_id, state.spawn_id)
# the only file that knows concrete classes and construction order

class_name GameHud extends CanvasLayer                # presentation/hud/game_hud.gd
func bind(session: GameSession, router: WorldRouter, registry: ContentRegistry) -> void
# shows HP, gold, items, interaction prompt, last message, current world id (debug);
# owns no state; rebinds on player_spawned; is_instance_valid guards everywhere
```

### Sprint 01 seams (small, justified changes)

```gdscript
# systems/combat/health_component.gd  (ADD alongside reset(); apply_damage/signals unchanged)
func restore(value: float) -> void     # clamp to [0, max_health], set _death_reported accordingly,
                                       # emit health_changed; used for a fresh rig on world load

# actors/enemies/enemy_brain.gd  (ADD)
signal defeated(reward: RewardDefinition, loot_source_id: StringName, at: Vector3)
@export var loot_source_id: StringName = &""     # stable per-placement id, never a node name
# emits exactly once from _on_died when definition.reward != null and loot_source_id != ""

# content/definitions/enemy_grunt.tres  (ADD)
reward = ExtResource(<reward.grunt_drop>)

# actors/player/player.tscn  (ADD child only; existing nodes untouched)
InteractionController (Node3D, script interaction_controller.gd)
  view = NodePath("../../Head/Camera3D"), interactor = NodePath("../.."), reach = 2.5

# core/physics/physics_layers.gd (ADD)
const INTERACTABLE: int = 1 << 4      # layer 5; never part of movement_mask()
```

## Content for Sprint 02

| Id | Kind | Value |
|----|------|-------|
| `world.hub` | world | `world/hub/hub.tscn`, default spawn `spawn.hub.start` |
| `world.dungeon.proto01` | world | `world/dungeons/dungeon_proto01.tscn`, default spawn `spawn.dungeon.entry` |
| `spawn.hub.start`, `spawn.hub.dungeon_portal`, `spawn.hub.shrine` | spawn markers | hub scene |
| `spawn.dungeon.entry`, `spawn.dungeon.return_portal` | spawn markers | dungeon scene |
| `item.rusty_dagger` | item | stackable=false, max_stack=1, kind=WEAPON |
| `item.minor_salve` | item | stackable=true, max_stack=5, kind=CONSUMABLE |
| `reward.grunt_drop` | reward | 3 gold (gold-only path) |
| `reward.chest.proto01` | reward | 1 × `item.minor_salve` + 5 gold (item+gold path) |
| loot source ids | — | `enemy.a` (grunt), `chest.a` (chest) resolved to `world.dungeon.proto01/<source>` |

## Work items, ownership, order

| ID | Deliverable | Owner | Files (single writer) | Depends on | State |
|----|-------------|-------|-----------------------|-----------|-------|
| W0 | Contract freeze: ADR-005 addendum + ADR-007..011, layer 5, `interact`, lock tests, this doc | coordinator | `docs/**`, `core/physics/physics_layers.gd`, `tools/setup_input_map.gd`, `project.godot` (`[input]`/`[layer_names]`), `tests/unit/test_project_contract.gd`, `tests/integration/test_project_scripts.gd` | — | done (6f763eb) |
| W1a | Pure domain: definitions, inventory, session state, loot | `gameplay-engineer` | `core/content/{item_definition,reward_definition,world_definition}.gd`, `core/inventory/**`, `core/session/**`, `systems/loot/**`, `tests/unit/{inventory,session,loot}/**` | W0 | done (0a20168) |
| W1b | Save + content registry + `HealthComponent.restore()` | `gameplay-engineer` | `systems/content/**`, `systems/save/**`, `systems/combat/health_component.gd` (one added method), `tests/unit/{content,save}/**`, `tests/unit/combat/test_health_component_restore.gd` | W0 | done (00878bb) |
| W2 | Interaction system + ray integration test | `godot-specialist` | `systems/interaction/**`, `tests/unit/interaction/**`, `tests/integration/test_interaction_ray.gd` | W1a, W1b | done (74cb48a) |
| W3 | Actor seams: `defeated` signal + reward authoring; player rig interaction child | coordinator | `actors/enemies/enemy_brain.gd`, `content/definitions/enemy_grunt.tres`, `actors/player/player.tscn`, `tests/integration/test_enemy_defeat_signal.gd` | W1a, W2 | done (c261544, 1f34fc4) |
| W4 | Worlds, router, host, HUD, content data, bootstrap | coordinator | `world/**`, `presentation/hud/**`, `content/definitions/{item_*,reward_*,world_*,content_manifest}.tres`, `tests/integration/{test_main_boot,test_world_scenes,test_content_graph}.gd` | W1a, W1b, W2, W3 | done (c261544, 1f34fc4) |
| I1 | Integration: `main_scene` → `world/main.tscn`, move the stale main-scene assertion, full validation | coordinator | `project.godot` (one line), `tests/integration/test_arena_boot.gd` (main-scene test only) | W4 | done (1f34fc4) |
| W5 | QA: end-to-end loop, save round trip, respawn, manual checklist, runtime-error log, evidence | `qa-engineer` | `tests/integration/{test_sprint02_loop,test_save_round_trip,test_death_respawn}.gd`, `tests/manual/sprint02_checklist.md` | I1 | in progress (branch `feat/s02-qa`) |
| W6 | Independent review + fixes + re-validation | `reviewer` (read-only) + coordinator | fixes only in the owning files | W5 | planned |

### Defects found and fixed during integration (evidence trail)

| Defect | Found by | Fix |
|--------|----------|-----|
| The router resolved the spawn marker **before** injecting the world default spawn id, so an empty request fell through to the alphabetical fallback (the player spawned 17 m away at the portal marker) | `test_main_boot.gd` | inject services + `default_spawn_id` before `resolve_spawn()` (`world_router.gd`) |
| `main.tscn` declared the `player_scene` PackedScene export in `node_paths`, which silently left it null and aborted every boot with "player_scene is not assigned" | `test_main_boot.gd` | removed the bogus `node_paths` entry |
| `WorldHost.PLAYER_NODE_NAME` was a `StringName`, and Godot 4.7 rejects `StringName` in `get_node_or_null()` (compile error in the HUD's dependency chain) | suite | constant is a `String`, like `HealthComponent.NODE_NAME` |
| Deferred typing from W1a/W1b: `Object`/`Variant` contracts and duck-typed registry stubs | coordinator (contract review) | typed arrays, concrete kind checks, typed lookups, real registries in tests |

Sprint 01 files that must stay untouched: all of `systems/combat/*` except the one added method,
`systems/ai/**`, `actors/player/player_controller.gd`, `world/prototype/**`, and every Sprint 01 test
except the three lock files and the single moved main-scene assertion.

## Acceptance criteria

| AC | Criterion | Evidence |
|----|-----------|----------|
| AC-20 | Layer 5 + `interact` are in `project.godot`, `PhysicsLayers` and the closed-list lock tests | `test_project_contract`, `test_project_scripts`, `--editor --quit` |
| AC-21 | Inventory: add/remove/count, stack filling to `max_stack`, non-stackable items, invalid definition rejection | `tests/unit/inventory/test_inventory.gd` |
| AC-22 | Loot: one grant per key, duplicate → `duplicate` with no mutation, invalid → `invalid`, unknown item → `unknown_item`, key survives a snapshot round trip | `tests/unit/loot/test_loot_service.gd` |
| AC-23 | Session state: new-game defaults, claim(), location change, snapshot round trip, no Object values in the snapshot dict | `tests/unit/session/test_player_session_state.gd`, `test_save_snapshot.gd` |
| AC-24 | Content registry: duplicate/empty/null/invalid ids and broken cross-references are reported; lookups work; shipped manifest is valid | `tests/unit/content/test_content_registry.gd`, `tests/integration/test_content_graph.gd` |
| AC-25 | Save: round trip, atomic (no `.tmp`/`.bak` left), missing → `MISSING`, corrupt → quarantined + `CORRUPT`, future version → `UNSUPPORTED_VERSION` | `tests/unit/save/test_save_manager.gd` |
| AC-26 | `HealthComponent.restore()` sets HP without changing `apply_damage`/`reset` semantics | `tests/unit/combat/test_health_component_restore.gd` |
| AC-27 | Interaction: focus/prompt on an interactable, walls block, out of reach rejected, repeated `E` does not duplicate a one-shot action, portal returns the router code | `tests/unit/interaction/**`, `tests/integration/test_interaction_ray.gd` |
| AC-28 | Enemies emit `defeated` exactly once with a reward and never without one | `tests/integration/test_enemy_defeat_signal.gd` |
| AC-29 | Worlds: both scenes instantiate, host binds, markers resolve, dungeon has a pickup scene; manifest graph valid | `tests/integration/test_world_scenes.gd`, `test_content_graph.gd` |
| AC-30 | Boot: main scene == `world/main.tscn`, hub loads, exactly one player at `spawn.hub.start`, HUD bound | `tests/integration/test_main_boot.gd` |
| AC-31 | Loop: hub → travel → kill → pickup → interact (once) → return → HP/gold/items kept → save → fresh `Main` restores the same state once | `tests/integration/test_sprint02_loop.gd`, `test_save_round_trip.gd` |
| AC-32 | Death respawns in the hub with full HP, inventory kept, no duplicate actors | `tests/integration/test_death_respawn.gd` |
| AC-33 | Every Sprint 01 test still passes (except the intentionally moved main-scene assertion) | full suite |
| AC-34 | Runtime cleanliness: no `SCRIPT ERROR`, no ObjectDB leak warning, boot smoke exit 0 | suite output + `--quit-after 300` |

## Validation commands

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"
& $GODOT --headless --path . --editor --quit          # parse/import
& $GODOT --headless --path . -s res://tests/run_tests.gd   # full suite, exit 0 = PASS
& $GODOT --headless --path . --quit-after 300         # main scene boot smoke
python tools/validate_pack.py
```

## Known constraints (Sprint 02)

- A saved `health <= 0` is repaired to full health when the next player rig spawns
  (`GameSession.apply_to_player`), not while loading the snapshot: the rig's `max_health` is only
  known at spawn time.
- World state is not persisted: enemies and drops reset when a world is re-entered; claimed reward
  keys are persisted, so a claimed drop never reappears.
- Standing position is not persisted; the save stores world + spawn id only.
- One save slot, explicit save only (hub shrine), load only at boot.
- Interaction is synchronous: one interaction per physics tick, no async actions.
- Graphical checks (walking the loop, prompt readability, HUD legibility) must be reported NOT RUN
  when no graphical session is performed.
