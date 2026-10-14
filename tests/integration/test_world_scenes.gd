extends "res://tests/test_case.gd"

## AC-29 — the two shipped worlds are structurally sound: WorldHost roots with the
## right ids, resolvable spawn markers, authored interactables and enemy placements.
##
## Structural only: the encounter behaviour lives in the Sprint 01 suites and the
## end-to-end loop is QA's.

const HUB_SCENE := "res://world/hub/hub.tscn"
const DUNGEON_SCENE := "res://world/dungeons/dungeon_proto01.tscn"

var _world: WorldHost = null


func teardown() -> void:
	_world = null


func _instantiate(path: String) -> WorldHost:
	var scene := load(path) as PackedScene
	if scene == null:
		fail("scene failed to load: %s" % path)
		return null
	var instance := scene.instantiate()
	if not (instance is WorldHost):
		fail("%s root is not a WorldHost" % path)
		if instance != null:
			instance.free()
		return null
	_world = instance as WorldHost
	add_to_tree(_world)
	return _world


func test_hub_scene_contract() -> void:
	var hub := _instantiate(HUB_SCENE)
	if hub == null:
		return
	await wait_physics_frames(2)
	assert_eq(hub.world_id, &"world.hub", "the hub declares its world id")
	var ids := _spawn_ids(hub)
	assert_true(ids.has(&"spawn.hub.start"), "the start marker exists")
	assert_true(ids.has(&"spawn.hub.dungeon_portal"), "the portal arrival marker exists")
	assert_not_null(hub.resolve_spawn(&"spawn.hub.start"), "the default spawn resolves")
	assert_not_null(hub.get_node_or_null("PortalToDungeon") as PortalInteractable, "the hub portal exists")
	assert_not_null(
		hub.get_node_or_null("Shrine") as SaveShrineInteractable, "the save shrine exists"
	)
	assert_true(hub.get_node_or_null("Floor") is StaticBody3D, "the hub has ground")
	for node_name in ["StallWest", "StallEast"]:
		assert_true(
			hub.get_node_or_null(node_name) is StaticBody3D,
			"%s reserves space for future NPCs/trade" % node_name
		)


func test_dungeon_scene_contract() -> void:
	var dungeon := _instantiate(DUNGEON_SCENE)
	if dungeon == null:
		return
	await wait_physics_frames(2)
	assert_eq(dungeon.world_id, &"world.dungeon.proto01", "the dungeon declares its world id")
	var ids := _spawn_ids(dungeon)
	assert_true(ids.has(&"spawn.dungeon.entry"), "the entry marker exists")
	assert_true(ids.has(&"spawn.dungeon.return_portal"), "the return marker exists")
	assert_not_null(dungeon.resolve_spawn(&"spawn.dungeon.entry"), "the default spawn resolves")
	assert_not_null(dungeon.loot_pickup_scene, "the dungeon can spawn drops")
	assert_not_null(
		dungeon.get_node_or_null("PortalToHub") as PortalInteractable, "the return portal exists"
	)

	var enemy := dungeon.get_node_or_null("Enemy") as EnemyBrain
	assert_not_null(enemy, "the dungeon holds one enemy")
	if enemy != null:
		assert_eq(enemy.loot_source_id, &"enemy.a", "the enemy placement carries a stable loot source id")
		assert_not_null(enemy.definition, "and an archetype")

	var chest := dungeon.get_node_or_null("Chest") as ChestInteractable
	assert_not_null(chest, "the dungeon holds a chest")
	if chest != null:
		assert_not_null(chest.reward, "the chest has a reward")
		assert_eq(chest.loot_source_id, &"chest.a", "and a stable loot source id")

	for node_name in ["PillarWest", "PillarEast"]:
		assert_true(
			dungeon.get_node_or_null(node_name) is StaticBody3D,
			"%s provides attack-blocking cover" % node_name
		)


func test_worlds_stand_alone_without_injected_services() -> void:
	## Editor and unit-test instantiation must not error: a world without a context
	## binds nothing and warns.
	var hub := _instantiate(HUB_SCENE)
	if hub == null:
		return
	await wait_physics_frames(2)
	assert_false(hub.has_context(), "no services were injected")
	assert_true(hub.is_inside_tree(), "the world still runs")
	assert_null(hub.current_player(), "and hosts no player of its own")


func test_portals_point_at_real_destinations() -> void:
	var hub := _instantiate(HUB_SCENE)
	if hub == null:
		return
	var portal := hub.get_node_or_null("PortalToDungeon") as PortalInteractable
	assert_not_null(portal, "the hub portal exists")
	if portal != null:
		assert_eq(portal.target_world_id, &"world.dungeon.proto01", "it targets the dungeon")
		assert_eq(portal.target_spawn_id, &"spawn.dungeon.entry", "at the entry marker")


func _spawn_ids(world: WorldHost) -> Array[StringName]:
	var ids: Array[StringName] = []
	for marker in world.spawn_markers():
		ids.append(marker.spawn_id)
	return ids
