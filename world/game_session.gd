class_name GameSession
extends RefCounted

## Owns the durable run state of one playthrough and is the only writer of
## health, gold, location and (through `LootService`) inventory (ADR-001, ADR-007,
## ADR-009).
##
## Invariants:
## - Holds no Node reference, ever: only `PlayerSessionState`, `Inventory` values
##   and `StringName` ids survive a scene swap.
## - `state` is read-only by convention for everyone except this class and
##   `LootService`; readers must never mutate it.
## - Death is a routing concern (the router respawns the player); this class only
##   stores the resulting HP value.

signal gold_changed(gold: int)
signal inventory_changed()
signal location_changed(world_id: StringName, spawn_id: StringName)

## Default world for a new or unrecoverable run.
const DEFAULT_WORLD_ID: StringName = &"world.hub"

## Player HP budget used for a new game and as the clamp ceiling for restores.
const DEFAULT_MAX_HEALTH: float = 100.0

var state: PlayerSessionState = PlayerSessionState.new()
var loot: LootService = LootService.new()

## Durable dungeon story progress (ADR-012) and the policy service that owns the run
## lifecycle. Both are session-scoped: the run state never survives a restart.
var progress: DungeonProgress = DungeonProgress.new()
var dungeons: DungeonService = DungeonService.new()

var _registry: ContentRegistry = null
var _save_manager: SaveManager = null


## Wires the services this session needs. Safe to call again in tests.
func setup(registry: ContentRegistry, save_manager: SaveManager) -> void:
	_registry = registry
	_save_manager = save_manager
	loot.setup(state, registry)
	dungeons.setup(registry, progress, loot)
	if not state.inventory.changed.is_connected(_on_inventory_changed):
		state.inventory.changed.connect(_on_inventory_changed)
	if not loot.reward_granted.is_connected(_on_reward_granted):
		loot.reward_granted.connect(_on_reward_granted)


func registry() -> ContentRegistry:
	return _registry


func save_manager() -> SaveManager:
	return _save_manager


## Starts a fresh run in the default world, with only the start dungeons unlocked.
func new_game() -> void:
	state.reset_to_new_game(DEFAULT_MAX_HEALTH)
	state.world_id = DEFAULT_WORLD_ID
	state.spawn_id = &""
	progress.reset_to_new_game(_start_dungeon_ids())
	gold_changed.emit(state.gold)
	inventory_changed.emit()
	location_changed.emit(state.world_id, state.spawn_id)


## Loads the save when one exists and is usable; otherwise starts a new game.
## The returned result always describes what happened (including warnings).
func load_or_new() -> SaveResult:
	if _save_manager == null:
		push_error("GameSession: setup() was not called; starting a new game")
		var missing := SaveResult.new()
		missing.status = SaveResult.Status.IO_ERROR
		missing.message = "save system unavailable"
		new_game()
		return missing
	var result := _save_manager.load_snapshot()
	if result.ok() and result.snapshot != null:
		# Append, never replace: the load may carry its own warnings (a recovered backup).
		result.warnings.append_array(apply_snapshot(result.snapshot))
		gold_changed.emit(state.gold)
		inventory_changed.emit()
		location_changed.emit(state.world_id, state.spawn_id)
		return result
	new_game()
	return result


## Writes the current run state to the single save slot.
func save_now() -> SaveResult:
	if _save_manager == null:
		var unavailable := SaveResult.new()
		unavailable.status = SaveResult.Status.IO_ERROR
		unavailable.message = "save system unavailable"
		return unavailable
	return _save_manager.save(to_snapshot())


## Records where the run currently is; the router calls this after every travel.
func note_location(world_id: StringName, spawn_id: StringName) -> void:
	state.world_id = world_id
	state.spawn_id = spawn_id
	location_changed.emit(world_id, spawn_id)


## Reads live HP from a player rig into the session. Returns false when the rig
## has no HealthComponent (ADR-005 scene contract).
func capture_from_player(player: Node3D) -> bool:
	var health := HealthComponent.find_on(player)
	if health == null:
		push_warning("GameSession: player rig has no %s child; HP not captured" % HealthComponent.NODE_NAME)
		return false
	state.health = health.current_health
	return true


## Writes session HP into a freshly spawned player rig. Must be called after the
## rig entered the tree, because `HealthComponent._ready()` resets HP to full.
func apply_to_player(player: Node3D) -> bool:
	var health := HealthComponent.find_on(player)
	if health == null:
		push_warning("GameSession: player rig has no %s child; HP not applied" % HealthComponent.NODE_NAME)
		return false
	var value: float = state.health
	if not is_finite(value) or value <= 0.0:
		push_warning("GameSession: stored HP %f is not playable; using full health" % value)
		value = health.max_health
	health.restore(value)
	state.health = health.current_health
	return true


## Gold entry point for non-loot rewards. Loot must go through `LootService`.
func add_gold(amount: int) -> int:
	if amount <= 0:
		return state.gold
	state.gold += amount
	gold_changed.emit(state.gold)
	return state.gold


## Full health for the next life. Used by the router's death path (ADR-007) so the
## durable-state write stays in this class.
func restore_full_health() -> void:
	state.health = DEFAULT_MAX_HEALTH


func to_snapshot() -> SaveSnapshot:
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = state.health
	snapshot.gold = state.gold
	snapshot.items = state.inventory.entries()
	snapshot.world_id = state.world_id
	snapshot.spawn_id = state.spawn_id
	var keys: Array[String] = []
	for key: StringName in state.claimed_reward_keys.keys():
		keys.append(String(key))
	keys.sort()
	snapshot.claimed_reward_keys = PackedStringArray(keys)
	snapshot.dungeon_progress = progress.to_save_dict()
	return snapshot


## Rebuilds the run state from a snapshot, rebuilding a fresh inventory (never
## granting into a live bag) and dropping unknown ids with warnings (ADR-010).
## Always leaves the session in a bootable state.
func apply_snapshot(snapshot: SaveSnapshot) -> PackedStringArray:
	var warnings := PackedStringArray()
	if snapshot == null:
		warnings.append("empty save snapshot; started a new game")
		new_game()
		return warnings

	state.reset_to_new_game(DEFAULT_MAX_HEALTH)

	if is_finite(snapshot.health):
		state.health = clampf(snapshot.health, 0.0, DEFAULT_MAX_HEALTH)
	else:
		warnings.append("save health is not a finite number; using full health")
		state.health = DEFAULT_MAX_HEALTH

	state.gold = maxi(0, snapshot.gold)

	if _registry == null:
		warnings.append("no content registry; items and locations from the save were ignored")
		return warnings

	for entry: Variant in snapshot.items:
		if not (entry is Dictionary):
			warnings.append("ignored malformed inventory entry: %s" % [entry])
			continue
		var item_id := StringName(str((entry as Dictionary).get("id", "")))
		var count := int((entry as Dictionary).get("count", 0))
		if item_id == &"" or count <= 0:
			warnings.append("ignored malformed inventory entry: %s" % [entry])
			continue
		var definition := _registry.find_item(item_id)
		if definition == null:
			warnings.append("dropped unknown item id from save: %s" % item_id)
			continue
		state.inventory.add(definition, count)

	for key: Variant in snapshot.claimed_reward_keys:
		var reward_key := StringName(str(key))
		if reward_key == &"":
			continue
		if not _is_known_reward_key(reward_key):
			warnings.append("dropped unknown reward key from save: %s" % reward_key)
			continue
		state.claimed_reward_keys[reward_key] = true

	_apply_progress(snapshot, warnings)

	var world_id: StringName = snapshot.world_id
	if world_id == &"" or _registry.find_world(world_id) == null:
		if world_id != &"":
			warnings.append("unknown world id in save: %s; using %s" % [world_id, DEFAULT_WORLD_ID])
		world_id = DEFAULT_WORLD_ID
	else:
		var dungeon := _registry.find_dungeon_for_world(world_id)
		if dungeon != null and dungeons.can_enter(dungeon.dungeon_id) != DungeonService.CODE_OK:
			# A save that points into a dungeon the progress does not allow (a hand-edited
			# or mismatched file) must not brick the boot: start in the hub instead.
			warnings.append(
				"saved world %s is a dungeon that cannot be entered (%s); using %s" % [
					world_id, dungeons.can_enter(dungeon.dungeon_id), DEFAULT_WORLD_ID
				]
			)
			world_id = DEFAULT_WORLD_ID
	state.world_id = world_id
	state.spawn_id = snapshot.spawn_id
	return warnings


## Rebuilds durable dungeon progress (ADR-012): tolerant parse, unknown ids dropped,
## and the start dungeons are always available (a v1 migration carries no completions).
func _apply_progress(snapshot: SaveSnapshot, warnings: PackedStringArray) -> void:
	progress = DungeonProgress.from_save_dict(snapshot.dungeon_progress)
	if _registry == null:
		dungeons.setup(_registry, progress, loot)
		return
	var known := func(id: StringName) -> bool: return _registry.find_dungeon(id) != null
	for dropped in progress.drop_unknown(known):
		warnings.append("dropped unknown dungeon id from save: %s" % dropped)
	progress.unlock_all(_start_dungeon_ids())
	dungeons.setup(_registry, progress, loot)


## Dungeons a new game starts with (definitions without prerequisites).
func _start_dungeon_ids() -> Array[StringName]:
	if _registry == null:
		return []
	return _registry.start_dungeon_ids()


## A reward key is `<world_id>/<source>` for Sprint 01/02 drops and `<dungeon_id>/<reward_id>`
## for dungeon rewards (ADR-013); it is known when its prefix is a listed world or dungeon.
func _is_known_reward_key(key: StringName) -> bool:
	if _registry == null:
		return false
	var parts := String(key).split("/", false)
	if parts.is_empty():
		return false
	var prefix := StringName(parts[0])
	return _registry.find_world(prefix) != null or _registry.find_dungeon(prefix) != null


func _on_inventory_changed() -> void:
	inventory_changed.emit()


## `LootService` writes gold directly; re-emit so every listener (the HUD included)
## observes the "gold changed" contract instead of having to know about loot.
func _on_reward_granted(_grant: LootGrant, gold_total: int) -> void:
	gold_changed.emit(gold_total)
