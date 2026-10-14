extends "res://tests/test_case.gd"

## AC-30 — the game boots through `world/main.tscn`: the hub loads, exactly one player
## rig exists at the hub's start marker, the HUD is bound and the session is in the hub.
##
## The test injects a temporary save path so it never reads or writes a real slot.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_main_boot_slot.json"

var _main: Main = null


func setup() -> void:
	_delete_save_files()


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _instantiate_main() -> Main:
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	if scene == null:
		fail("main scene failed to load: %s" % MAIN_SCENE_PATH)
		return null
	_main = scene.instantiate() as Main
	if _main == null:
		fail("main scene root is not a Main")
		return null
	_main.save_path = TEST_SAVE_PATH
	add_to_tree(_main)
	return _main


func _count_players() -> int:
	var count := 0
	for node in _walk(_main):
		if node is PlayerController:
			count += 1
	return count


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func test_main_scene_is_the_bootstrap() -> void:
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, MAIN_SCENE_PATH, "the project boots into the composition root")


func test_boot_loads_the_hub_with_one_player_at_the_start_marker() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(30)

	assert_true(main.registry.is_valid(), "the shipped manifest is valid: %s" % main.registry.errors)
	assert_eq(main.boot_result.status, SaveResult.Status.MISSING, "a fresh slot starts a new game")
	assert_eq(main.session.state.world_id, &"world.hub", "the session starts in the hub")

	var router := main.router
	assert_not_null(router, "the router is wired")
	if router == null:
		return
	var world := router.current_world()
	assert_not_null(world, "a world is loaded")
	if world == null:
		return
	assert_eq(world.world_id, &"world.hub", "the hub is the first world")
	assert_eq(main.world_slot.get_child_count(), 1, "exactly one world is hosted")
	assert_eq(_count_players(), 1, "exactly one player rig exists")

	var player := router.current_player()
	assert_not_null(player, "the router owns the player")
	if player == null:
		return
	var marker := world.resolve_spawn(&"spawn.hub.start")
	assert_not_null(marker, "the hub has a start marker")
	if marker != null:
		var offset := MeleeRules.horizontal_distance(player.global_position, marker.global_position)
		assert_true(offset < 0.5, "the player spawned at the marker (%.2f m off)" % offset)
	assert_true(player.is_on_floor(), "and stands on the floor")
	assert_eq(main.session.state.spawn_id, &"spawn.hub.start", "the session recorded the spawn id")


func test_boot_binds_the_hud_to_the_live_rig() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(30)
	assert_not_null(main.hud, "the HUD is wired")
	if main.hud == null:
		return
	assert_true(main.hud.health_label.text.contains("100"), "HP shown: '%s'" % main.hud.health_label.text)
	assert_true(main.hud.gold_label.text.contains("0"), "gold shown: '%s'" % main.hud.gold_label.text)
	assert_true(
		main.hud.world_label.text.contains("world.hub"),
		"location shown: '%s'" % main.hud.world_label.text
	)
	assert_true(
		main.hud.status_label.text.contains("New game"),
		"the boot outcome is reported: '%s'" % main.hud.status_label.text
	)


func test_hud_survives_a_world_swap_without_duplicating_actors() -> void:
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(10)
	var code := main.router.request_travel(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	assert_eq(code, WorldRouter.CODE_TRAVEL_STARTED, "travel to the dungeon starts")
	await wait_physics_frames(10)

	assert_eq(main.router.current_world_id(), &"world.dungeon.proto01", "the dungeon is current")
	assert_eq(main.world_slot.get_child_count(), 1, "the old world is gone, not stacked")
	assert_eq(_count_players(), 1, "still exactly one player rig")
	assert_true(
		main.hud.world_label.text.contains("world.dungeon.proto01"),
		"the HUD followed the swap: '%s'" % main.hud.world_label.text
	)
	assert_true(main.hud.health_label.text.contains("100"), "HP survives the travel")
