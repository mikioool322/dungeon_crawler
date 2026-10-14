class_name WorldRouter
extends Node

## The only component that instantiates or frees a world or a player rig (ADR-007).
##
## Travel contract:
## - `request_travel()` is synchronous and single-flight: a request while another
##   travel is in progress returns `busy` and changes nothing.
## - The order is prepare-then-swap: validate the definition, instantiate the world
##   off-tree, resolve the spawn marker, build and add the player, add the world
##   (all `_ready`s run), restore HP, then remove and free the previous world in the
##   same call (no `await` in between).
## - Any failure before the swap frees the candidate instance, leaves the current
##   world untouched and emits `world_load_failed`.
## - A missing or invalid spawn id falls back to the world default (then to the
##   first marker by name) and reports `used_fallback = true`; an empty request that
##   resolves to the world default is normal, not a fallback.

signal world_loaded(world_id: StringName, spawn_id: StringName, used_fallback: bool)
signal world_load_failed(world_id: StringName, code: StringName)
signal player_spawned(player: PlayerController)

const CODE_TRAVEL_STARTED: StringName = &"travel_started"
const CODE_BUSY: StringName = &"busy"
const CODE_UNKNOWN_WORLD: StringName = &"unknown_world"
const CODE_INVALID_WORLD: StringName = &"invalid_world"
const CODE_INVALID_SPAWN: StringName = &"invalid_spawn"

## Node that hosts the current world; the world is its only child.
@export var world_slot: Node3D = null

## Player rig instantiated once per world load (ADR-007).
@export var player_scene: PackedScene = null

## World the player is sent to after dying.
@export var respawn_world_id: StringName = &"world.hub"

var _session: GameSession = null
var _registry: ContentRegistry = null
var _travelling: bool = false
var _world: WorldHost = null
var _player: PlayerController = null


func configure(session: GameSession, registry: ContentRegistry) -> void:
	_session = session
	_registry = registry


## First load; uses the session location when the arguments are empty.
func bootstrap(world_id: StringName = &"", spawn_id: StringName = &"") -> StringName:
	if _session == null:
		push_error("WorldRouter: configure() was not called")
		return CODE_INVALID_WORLD
	var target_world: StringName = world_id if world_id != &"" else _session.state.world_id
	var target_spawn: StringName = spawn_id if spawn_id != &"" else _session.state.spawn_id
	return request_travel(target_world, target_spawn)


func request_travel(world_id: StringName, spawn_id: StringName) -> StringName:
	return _travel(world_id, spawn_id, true)


func is_travelling() -> bool:
	return _travelling


func current_world() -> WorldHost:
	return _world


func current_player() -> PlayerController:
	return _player


func current_world_id() -> StringName:
	if _world != null and is_instance_valid(_world):
		return _world.world_id
	return &""


## Copies live player HP into the session (call before saving).
func capture_session() -> bool:
	if _session == null:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	return _session.capture_from_player(_player)


func _travel(world_id: StringName, spawn_id: StringName, capture_player_health: bool) -> StringName:
	if _travelling:
		return CODE_BUSY
	if _session == null or _registry == null:
		push_error("WorldRouter: configure() was not called")
		return CODE_INVALID_WORLD

	_travelling = true
	var outcome := _perform_travel(world_id, spawn_id, capture_player_health)
	_travelling = false

	var code: StringName = outcome.get("code", CODE_INVALID_WORLD)
	if code != CODE_TRAVEL_STARTED:
		world_load_failed.emit(world_id, code)
		return code
	world_loaded.emit(world_id, outcome.get("spawn_id", &""), outcome.get("used_fallback", false))
	var spawned: PlayerController = outcome.get("player", null)
	if spawned != null:
		player_spawned.emit(spawned)
	return CODE_TRAVEL_STARTED


## Prepare-then-swap. Returns {code, spawn_id, used_fallback, player}.
func _perform_travel(
	world_id: StringName, spawn_id: StringName, capture_player_health: bool
) -> Dictionary:
	var failure := {"code": CODE_INVALID_WORLD}
	var definition := _registry.find_world(world_id)
	if definition == null:
		push_warning("WorldRouter: unknown world id '%s'" % world_id)
		return {"code": CODE_UNKNOWN_WORLD}
	if definition.scene == null:
		push_warning("WorldRouter: world '%s' has no scene" % world_id)
		return failure
	if world_slot == null:
		push_error("WorldRouter: world_slot is not assigned")
		return failure

	var instance := definition.scene.instantiate()
	if not (instance is WorldHost):
		push_error("WorldRouter: world '%s' root is not a WorldHost" % world_id)
		_free_instance(instance)
		return failure
	var next_world := instance as WorldHost
	if next_world.world_id != &"" and next_world.world_id != world_id:
		push_error(
			"WorldRouter: world '%s' scene declares world_id '%s'" % [world_id, next_world.world_id]
		)
		_free_instance(instance)
		return failure

	var marker := next_world.resolve_spawn(spawn_id)
	if marker == null:
		push_warning("WorldRouter: world '%s' has no spawn markers" % world_id)
		_free_instance(instance)
		return {"code": CODE_INVALID_SPAWN}
	var resolved_spawn: StringName = marker.spawn_id
	var used_fallback: bool = spawn_id != &"" and resolved_spawn != spawn_id

	var player := _build_player(marker)
	if player == null:
		_free_instance(instance)
		return failure
	next_world.configure(
		_session,
		_registry,
		Callable(self, "request_travel"),
		_save_callable(),
		definition.default_spawn_id
	)
	next_world.add_child(player)

	if capture_player_health:
		capture_session()

	var previous_world := _world

	# Swap: after this point nothing may fail, so the run is never left half-moved.
	world_slot.add_child(next_world)
	_world = next_world
	_player = player
	_session.apply_to_player(player)
	_session.note_location(world_id, resolved_spawn)
	_connect_player_death(player)

	if previous_world != null and is_instance_valid(previous_world):
		world_slot.remove_child(previous_world)
		previous_world.queue_free()

	return {
		"code": CODE_TRAVEL_STARTED,
		"spawn_id": resolved_spawn,
		"used_fallback": used_fallback,
		"player": player,
	}


func _build_player(marker: SpawnMarker) -> PlayerController:
	if player_scene == null:
		push_error("WorldRouter: player_scene is not assigned")
		return null
	var instance := player_scene.instantiate()
	if not (instance is PlayerController):
		push_error("WorldRouter: player_scene root is not a PlayerController")
		_free_instance(instance)
		return null
	var player := instance as PlayerController
	player.position = marker.position
	player.rotation.y = marker.rotation.y
	return player


func _save_callable() -> Callable:
	return Callable(self, "_save_via_session")


## Save provider handed to save shrines: capture the live rig first, then persist.
func _save_via_session() -> SaveResult:
	if _session == null:
		var unavailable := SaveResult.new()
		unavailable.status = SaveResult.Status.IO_ERROR
		unavailable.message = "no active session"
		return unavailable
	capture_session()
	return _session.save_now()


func _connect_player_death(player: PlayerController) -> void:
	var health := HealthComponent.find_on(player)
	if health == null:
		return
	health.died.connect(_on_player_died.bind(player))


## Death outcome (ADR-007): respawn in the respawn world with full HP; inventory,
## gold and claimed rewards are preserved. HP is never captured from the dead rig.
func _on_player_died(_request: DamageRequest, player: PlayerController) -> void:
	if player == null or not is_instance_valid(player) or player != _player:
		return
	var health := HealthComponent.find_on(player)
	if health != null:
		_session.state.health = health.max_health
	_travel(respawn_world_id, &"", false)


func _free_instance(instance: Node) -> void:
	if instance != null and is_instance_valid(instance):
		instance.free()
