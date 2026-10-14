class_name WorldHost
extends Node3D

## Root script of every travel-managed world scene (ADR-007, ADR-008).
##
## Responsibilities and limits:
## - Binds the world's interactables to the services injected by the router
##   (travel callable, loot service, save callable) and hands enemies their target.
## - Resolves named spawn markers (coordinates live in the scene, ADR-007).
## - Spawns the loot pickup when an enemy is defeated, unless the reward key is
##   already claimed (ADR-009). It never decides damage, AI transitions or loot
##   rules, and combat never learns about inventory.

## Name of the router-managed player child of a world root (ADR-007).
## Kept as String because Node lookups require a NodePath-convertible value.
const PLAYER_NODE_NAME: String = "Player"

## Stable world id; the router cross-checks it against the WorldDefinition.
@export var world_id: StringName = &""

## Pickup scene spawned on a defeated enemy; required in worlds with loot.
@export var loot_pickup_scene: PackedScene = null

var _session: GameSession = null
var _registry: ContentRegistry = null
var _travel: Callable = Callable()
var _save: Callable = Callable()
var _default_spawn_id: StringName = &""


## Called by the router before the world enters the tree. Tolerates a null context
## (editor and unit tests instantiate worlds standalone).
func configure(
	session: GameSession,
	registry: ContentRegistry,
	travel: Callable,
	save: Callable,
	default_spawn_id: StringName = &""
) -> void:
	_session = session
	_registry = registry
	_travel = travel
	_save = save
	_default_spawn_id = default_spawn_id


func has_context() -> bool:
	return _session != null


func spawn_markers() -> Array[SpawnMarker]:
	var markers: Array[SpawnMarker] = []
	for node in find_children("*", "Node3D", true, false):
		if node is SpawnMarker:
			markers.append(node as SpawnMarker)
	return markers


## Resolves a spawn marker by id with the documented fallback chain.
func resolve_spawn(spawn_id: StringName) -> SpawnMarker:
	return SpawnMarker.choose(spawn_markers(), spawn_id, _default_spawn_id)


func current_player() -> Node3D:
	return get_node_or_null(PLAYER_NODE_NAME) as Node3D


func _ready() -> void:
	if _session == null:
		push_warning(
			"WorldHost %s: no context injected; interactables and enemies stay unbound" % name
		)
		return
	_bind_interactables()
	_bind_enemies()


## Injects the per-type service each interactable needs; the general interaction
## system never learns about loot, travel or save (ADR-008).
func _bind_interactables() -> void:
	for node in find_children("*", "Node3D", true, false):
		if node is PortalInteractable:
			(node as PortalInteractable).set_travel_provider(_travel)
		elif node is PickupInteractable:
			var pickup := node as PickupInteractable
			_bind_loot(pickup, pickup.reward, pickup.loot_source_id)
		elif node is ChestInteractable:
			var chest := node as ChestInteractable
			_bind_loot(chest, chest.reward, chest.loot_source_id)
		elif node is SaveShrineInteractable:
			(node as SaveShrineInteractable).set_save_provider(_save)


func _bind_loot(interactable: Interactable, reward: RewardDefinition, source: StringName) -> void:
	if source == &"":
		push_warning(
			"WorldHost %s: %s has no loot_source_id; it cannot grant a reward (ADR-009)"
			% [name, interactable.name]
		)
		return
	interactable.bind_loot(reward, LootGrant.key_for(world_id, source), _session.loot)


func _bind_enemies() -> void:
	var player := current_player()
	for node in find_children("*", "CharacterBody3D", true, false):
		if not (node is EnemyBrain):
			continue
		var enemy := node as EnemyBrain
		if player != null:
			enemy.set_target(player)
		enemy.defeated.connect(_on_enemy_defeated)


## Spawns the drop for a defeated enemy exactly once per reward key (ADR-009).
func _on_enemy_defeated(reward: RewardDefinition, loot_source_id: StringName, at: Vector3) -> void:
	if reward == null or loot_source_id == &"":
		return
	var key := LootGrant.key_for(world_id, loot_source_id)
	if _session.loot.is_claimed(key):
		return  # claimed in an earlier visit: the drop never reappears
	_spawn_pickup(reward, loot_source_id, key, at)


func _spawn_pickup(
	reward: RewardDefinition, loot_source_id: StringName, key: StringName, at: Vector3
) -> void:
	if loot_pickup_scene == null:
		push_warning(
			"WorldHost %s: enemy drop %s has no loot_pickup_scene to spawn" % [name, loot_source_id]
		)
		return
	var pickup := loot_pickup_scene.instantiate()
	if not (pickup is PickupInteractable):
		push_error("WorldHost %s: loot_pickup_scene root is not a PickupInteractable" % name)
		pickup.queue_free()
		return
	var node := pickup as PickupInteractable
	node.reward = reward
	node.loot_source_id = loot_source_id
	node.bind_loot(reward, key, _session.loot)
	add_child(node)
	node.global_position = at
