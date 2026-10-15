extends "res://tests/test_case.gd"

## S03 — boot resilience for hand-written save files (ADR-010 + ADR-012/014):
##
## - a v2 save whose `world_id` is a dungeon the progress does not unlock boots into the
##   hub with a warning, no crash, exactly one world and exactly one rig;
## - a v2 save with an unknown world id does the same;
## - a v1 file loads, migrates to version 2, keeps HP/gold/items/world/spawn, leaves no
##   legacy reward key behind, keeps dungeon 01 available and invents no completion.
##
## The files are written by hand into a temporary `user://` slot; the real slot is never
## read or written. `Main.save_path` is injected before the tree entry, and the router
## signals are recorded from before the boot travel so the *boot* outcome is observable.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_boot_locked_world_slot.json"

const WORLD_HUB := &"world.hub"
const DUNGEON_01 := &"dungeon.01"
const DUNGEON_02 := &"dungeon.02"
const SPAWN_HUB_START := &"spawn.hub.start"

var _main: Main = null

## {world_id, spawn_id, used_fallback} per successful travel, boot travel included.
var _loaded: Array[Dictionary] = []

## {world_id, code} per refused travel.
var _failed: Array[Dictionary] = []


func setup() -> void:
	_delete_save_files()
	_loaded = []
	_failed = []


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- fixture ------------------------------------------------------------------

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
	_main.router.world_loaded.connect(_on_world_loaded)
	_main.router.world_load_failed.connect(_on_world_load_failed)
	add_to_tree(_main)
	return _main


func _on_world_loaded(world_id: StringName, spawn_id: StringName, used_fallback: bool) -> void:
	_loaded.append({"world_id": world_id, "spawn_id": spawn_id, "used_fallback": used_fallback})


func _on_world_load_failed(world_id: StringName, code: StringName) -> void:
	_failed.append({"world_id": world_id, "code": code})


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _count_nodes(root: Node, type_check: Callable) -> int:
	var count := 0
	for node in _walk(root):
		if type_check.call(node):
			count += 1
	return count


func _players() -> int:
	return _count_nodes(_main, func(node: Node) -> bool: return node is PlayerController)


func _worlds() -> int:
	return _count_nodes(_main, func(node: Node) -> bool: return node is WorldHost)


# --- hand-written saves -------------------------------------------------------

func _write_save(data: Dictionary) -> bool:
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		fail("could not write %s (error %d)" % [TEST_SAVE_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	return true


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(TEST_SAVE_PATH):
		fail("no save file at %s" % TEST_SAVE_PATH)
		return {}
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	if file == null:
		fail("could not read %s" % TEST_SAVE_PATH)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		fail("the save file is not a JSON object")
		return {}
	return parsed


func _has_warning(result: SaveResult, needle: String) -> bool:
	if result == null:
		return false
	for warning in result.warnings:
		if String(warning).contains(needle):
			return true
	return false


func _warnings_text(result: SaveResult) -> String:
	return "; ".join(result.warnings) if result != null else "<no result>"


# --- a dungeon world the progress does not unlock -----------------------------

func test_a_v2_save_pointing_into_a_locked_dungeon_boots_into_the_hub() -> void:
	assert_true(
		_write_save({
			"version": 2,
			"health": 42.5,
			"gold": 17,
			"items": [{"id": "item.minor_salve", "count": 2}],
			"world_id": "world.dungeon.proto02",
			"spawn_id": "spawn.dungeon.entry",
			"claimed_reward_keys": [],
			"dungeon_progress": {},
		}),
		"the hand-written save is on disk"
	)
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session

	assert_true(main.boot_result.ok(), "the file is a usable v2 save: %s" % main.boot_result.message)
	assert_true(
		_has_warning(main.boot_result, "cannot be entered"),
		"the boot warned about the locked destination: %s" % _warnings_text(main.boot_result)
	)
	assert_eq(_failed.size(), 0, "the boot itself did not fail to load a world")

	# The session repaired the location before the router ran, so the hub is loaded.
	assert_eq(session.state.world_id, WORLD_HUB, "the session fell back to the hub")
	assert_eq(main.router.current_world_id(), WORLD_HUB, "and the hub is the loaded world")
	assert_eq(main.world_slot.get_child_count(), 1, "exactly one world is hosted")
	assert_eq(_worlds(), 1, "exactly one world node exists")
	assert_eq(_players(), 1, "exactly one player rig exists")
	assert_eq(_loaded.size(), 1, "one world was loaded")
	if _loaded.size() == 1:
		assert_eq(_loaded[0]["world_id"], WORLD_HUB, "the loaded world is the hub")
		assert_eq(_loaded[0]["spawn_id"], SPAWN_HUB_START, "at the hub start marker")
		assert_true(
			_loaded[0]["used_fallback"],
			"the dungeon entry spawn id does not exist in the hub; the default was used"
		)
	assert_eq(session.state.spawn_id, SPAWN_HUB_START, "and the session records that spawn")

	# The dungeon stays locked and the fallback did not start a run.
	assert_eq(
		session.dungeons.can_enter(DUNGEON_02),
		DungeonService.CODE_LOCKED,
		"the dungeon in the save is still locked"
	)
	assert_false(session.dungeons.is_run_active(), "no run was started by the fallback")

	# Everything else from the save survives the repair.
	assert_eq(session.state.health, 42.5, "the saved HP is kept")
	assert_eq(session.state.gold, 17, "the saved gold is kept")
	assert_eq(session.state.inventory.count_of(&"item.minor_salve"), 2, "the saved items are kept")
	var health := HealthComponent.find_on(main.router.current_player())
	assert_not_null(health, "the live rig has HP")
	if health != null:
		assert_eq(health.current_health, 42.5, "and the live rig carries the saved HP")


# --- an unknown world id ------------------------------------------------------

func test_a_v2_save_with_an_unknown_world_boots_into_the_hub() -> void:
	assert_true(
		_write_save({
			"version": 2,
			"health": 100.0,
			"gold": 0,
			"items": [],
			"world_id": "world.does.not.exist",
			"spawn_id": "spawn.hub.start",
			"claimed_reward_keys": [],
			"dungeon_progress": {},
		}),
		"the hand-written save is on disk"
	)
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session

	assert_true(main.boot_result.ok(), "the file is a usable v2 save: %s" % main.boot_result.message)
	assert_true(
		_has_warning(main.boot_result, "unknown world id in save"),
		"the boot warned about the unknown world: %s" % _warnings_text(main.boot_result)
	)
	assert_eq(_failed.size(), 0, "the boot itself did not fail to load a world")
	assert_eq(session.state.world_id, WORLD_HUB, "the session fell back to the hub")
	assert_eq(main.router.current_world_id(), WORLD_HUB, "and the hub is the loaded world")
	assert_eq(main.world_slot.get_child_count(), 1, "exactly one world is hosted")
	assert_eq(_worlds(), 1, "exactly one world node exists")
	assert_eq(_players(), 1, "exactly one player rig exists")
	assert_eq(_loaded.size(), 1, "one world was loaded")
	if _loaded.size() == 1:
		assert_eq(_loaded[0]["world_id"], WORLD_HUB, "the loaded world is the hub")
		assert_eq(_loaded[0]["spawn_id"], SPAWN_HUB_START, "at the requested spawn")
		assert_false(_loaded[0]["used_fallback"], "the spawn id itself was valid, so no fallback")
	assert_false(session.dungeons.is_run_active(), "no run was started by the fallback")
	assert_true(session.progress.is_unlocked(DUNGEON_01), "dungeon 01 is available after the repair")
	assert_eq(
		session.dungeons.can_enter(DUNGEON_01), DungeonService.CODE_OK, "and enterable"
	)


# --- a version 1 file --------------------------------------------------------

func test_a_v1_save_migrates_and_keeps_the_run_state() -> void:
	assert_true(
		_write_save({
			"version": 1,
			"health": 55.0,
			"gold": 9,
			"items": [{"id": "item.rusty_dagger", "count": 1}],
			"world_id": "world.hub",
			"spawn_id": "spawn.hub.start",
			"claimed_reward_keys": [
				"world.dungeon.proto01/chest.a",
				"world.dungeon.proto01/enemy.a",
			],
		}),
		"the hand-written v1 save is on disk"
	)
	var main := _instantiate_main()
	if main == null:
		return
	await wait_physics_frames(20)
	var session := main.session

	assert_true(main.boot_result.ok(), "the v1 file loads and migrates: %s" % main.boot_result.message)
	assert_eq(SaveSnapshot.CURRENT_VERSION, 2, "the current schema version is 2")
	if main.boot_result.snapshot != null:
		assert_eq(main.boot_result.snapshot.version, 2, "the migrated snapshot is version 2")
	else:
		fail("an OK load must carry a snapshot")

	# --- HP / gold / items / world / spawn are preserved ----------------------
	assert_eq(session.state.health, 55.0, "HP is preserved")
	assert_eq(session.state.gold, 9, "gold is preserved")
	assert_eq(session.state.inventory.count_of(&"item.rusty_dagger"), 1, "items are preserved")
	assert_eq(session.state.world_id, WORLD_HUB, "the world is preserved")
	assert_eq(session.state.spawn_id, SPAWN_HUB_START, "the spawn is preserved")
	assert_eq(main.router.current_world_id(), WORLD_HUB, "and the hub is loaded")
	assert_eq(_worlds(), 1, "exactly one world node exists")
	assert_eq(_players(), 1, "exactly one player rig exists")

	# --- the legacy keys are gone --------------------------------------------
	assert_eq(session.state.claimed_reward_keys.size(), 0, "no legacy v1 reward key survives")
	assert_false(
		session.loot.is_claimed(&"world.dungeon.proto01/chest.a"),
		"the legacy key is not claimed in the story ledger"
	)
	assert_false(
		session.loot.is_claimed(&"world.dungeon.proto01/enemy.a"),
		"neither is the legacy drop key"
	)

	# --- the migration invents nothing ---------------------------------------
	assert_true(session.progress.is_unlocked(DUNGEON_01), "dungeon 01 is available after the migration")
	assert_eq(session.dungeons.can_enter(DUNGEON_01), DungeonService.CODE_OK, "and enterable")
	assert_false(session.progress.is_unlocked(DUNGEON_02), "dungeon 02 is still locked")
	assert_eq(session.progress.completed_ids(), [] as Array[StringName], "no completion was invented")
	assert_eq(
		session.progress.first_clear_claimed_ids(),
		[] as Array[StringName],
		"no story claim was invented"
	)
	var panel := main.hud.dungeon_panel
	assert_not_null(panel, "the HUD owns the dungeon panel")
	if panel != null:
		var rows := panel.rows()
		assert_eq(rows.size(), 2, "both dungeons are listed")
		if rows.size() == 2:
			assert_eq(rows[0]["state"], DungeonPanel.STATE_UNLOCKED, "the board shows dungeon 01 enterable")
			assert_eq(rows[1]["state"], DungeonPanel.STATE_LOCKED, "and dungeon 02 locked")

	# --- the migrated state is what the next save writes ----------------------
	assert_true(session.save_now().ok(), "the migrated state saves")
	var written := _read_save()
	assert_eq(int(written.get("version", 0)), 2, "the rewritten file is version 2")
	assert_eq((written.get("claimed_reward_keys", []) as Array).size(), 0, "with no legacy keys")
	assert_true(written.has("dungeon_progress"), "and a dungeon_progress section")
	var progress_dict: Dictionary = written.get("dungeon_progress", {})
	assert_eq(
		(progress_dict.get("completed", []) as Array).size(), 0, "which records no completion"
	)
	assert_true(
		(progress_dict.get("unlocked", []) as Array).has("dungeon.01"),
		"and keeps dungeon 01 unlocked"
	)
	assert_eq(session.state.gold, 9, "the save did not disturb the run state")
