extends "res://tests/test_case.gd"

## W5 — persistence edges around the shipped save pipeline (AC-25, AC-31, ADR-010).
##
## Every test uses a temporary `user://` slot and deletes the file plus its
## `.tmp`/`.bak`/`.corrupt` siblings in setup/teardown; the real slot
## (`user://save_slot0.json`) is never touched. The registry is the shipped manifest,
## so the id filtering runs against the real content graph.
##
## Covered here (the unit suite covers the pure DTO/manager mechanics):
## - a full round trip: `GameSession.to_snapshot()` -> `SaveManager.save()` ->
##   `load_snapshot()` -> `apply_snapshot()` for HP, gold, inventory, location, the
##   *story* reward keys and the dungeon progress; run-scoped reward keys must NOT
##   persist (ADR-013);
## - a first clear + unlock + story claim survive `save -> fresh Main -> load`;
## - garbage text -> `CORRUPT`, quarantined, boot degrades to a new game;
## - `version = 999` -> `UNSUPPORTED_VERSION`, the file is left byte-identical;
## - unknown item / reward key / world ids are dropped with warnings, the rest loads;
## - `health <= 0` in the save becomes full HP on the next real boot;
## - a successful save (including the overwrite path) leaves no `.tmp`/`.bak`.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const TEST_SAVE_PATH := "user://test_save_round_trip_slot.json"

const HUB_WORLD := &"world.hub"
const DUNGEON_WORLD := &"world.dungeon.proto01"
const SALVE := &"item.minor_salve"
const DAGGER := &"item.rusty_dagger"

var _main: Main = null


func setup() -> void:
	_main = null
	_delete_save_files()


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _registry() -> ContentRegistry:
	return ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)


func _new_manager() -> SaveManager:
	var manager := SaveManager.new()
	manager.setup(TEST_SAVE_PATH)
	return manager


func _new_session(registry: ContentRegistry, manager: SaveManager) -> GameSession:
	var session := GameSession.new()
	session.setup(registry, manager)
	return session


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("could not write %s" % path)
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _warnings_contain(warnings: PackedStringArray, needle: String) -> bool:
	for warning in warnings:
		if warning.contains(needle):
			return true
	return false


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


# --- round trip ---------------------------------------------------------------

func test_hp_inventory_gold_and_location_round_trip_through_the_save_file() -> void:
	var registry := _registry()
	assert_true(registry.is_valid(), "the shipped manifest builds a valid registry: %s" % registry.errors)
	var salve := registry.find_item(SALVE)
	var chest_reward := registry.find_reward(&"reward.chest.proto01")
	var story_reward := registry.find_reward(&"reward.story.dungeon01")
	assert_not_null(salve, "the shipped salve definition exists")
	assert_not_null(chest_reward, "the shipped chest reward exists")
	assert_not_null(story_reward, "the shipped first-clear reward exists")
	if salve == null or chest_reward == null or story_reward == null:
		return

	var manager := _new_manager()
	var session := _new_session(registry, manager)
	session.new_game()
	assert_eq(session.state.health, 100.0, "a new game starts at full HP")
	var run := session.dungeons.start_run(&"dungeon.01")
	assert_not_null(run, "entering dungeon 01 opens the transient loot ledger (ADR-014)")

	# Real loot path: one run-scoped chest grant (1 salve + 5 gold) ...
	var chest_key := LootGrant.key_for(DUNGEON_WORLD, &"chest.a")
	var chest_grant := LootGrant.from_reward(chest_key, chest_reward)
	assert_eq(chest_grant.scope, LootGrant.SCOPE_RUN, "a scene reward is run-scoped by default")
	assert_eq(session.loot.grant(chest_grant), LootService.CODE_GRANTED, "the chest grant applies")
	# ... one story-scoped first-clear grant (1 dagger + 10 gold), which must persist ...
	var story_key := LootGrant.key_for(&"dungeon.01", &"reward.story.dungeon01")
	var story_grant := LootGrant.from_reward(story_key, story_reward, LootGrant.SCOPE_STORY)
	assert_eq(session.loot.grant(story_grant), LootService.CODE_GRANTED, "the story grant applies")
	# ... plus a test-authored run-scoped grant so the bag holds more than one stack-worth.
	var extra := RewardDefinition.new()
	extra.id = &"reward.tests.extra"
	extra.item = salve
	extra.item_count = 2
	assert_true(extra.is_valid(), "the test reward is valid")
	var extra_key := LootGrant.key_for(HUB_WORLD, &"tests.extra")
	var extra_grant := LootGrant.from_reward(extra_key, extra)
	assert_eq(session.loot.grant(extra_grant), LootService.CODE_GRANTED, "the second run grant applies")

	session.add_gold(12)  # 5 (chest) + 10 (story) + 12 = 27
	session.state.health = 42.5
	session.note_location(DUNGEON_WORLD, &"spawn.dungeon.entry")

	var save_result := session.save_now()
	assert_eq(save_result.status, SaveResult.Status.OK, "save_now reports OK: %s" % save_result.message)
	assert_true(save_result.ok(), "and ok() agrees")
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "the save file exists")
	for suffix in [".tmp", ".bak"]:
		assert_false(
			FileAccess.file_exists(TEST_SAVE_PATH + suffix), "no %s is left by a successful save" % suffix
		)

	# The file is the documented JSON shape with version 2 and the progress section.
	var json := JSON.new()
	assert_eq(json.parse(_read_text(TEST_SAVE_PATH)), OK, "the save file is valid JSON")
	if json.data is Dictionary:
		var data: Dictionary = json.data
		assert_eq(
			data.get("version"), SaveSnapshot.CURRENT_VERSION, "the file declares the current schema version"
		)
		assert_eq(data.get("version"), 2, "Sprint 03 saves are version 2")
		assert_true(data.has("dungeon_progress"), "the file carries the dungeon progress section")

	# Load through the same public pipeline into a fresh session.
	var loaded_manager := _new_manager()
	var loaded := _new_session(registry, loaded_manager)
	var load_result := loaded.load_or_new()
	assert_eq(load_result.status, SaveResult.Status.OK, "load_or_new reports OK: %s" % load_result.message)
	assert_true(load_result.warnings.is_empty(), "a clean save loads without warnings: %s" % load_result.warnings)
	assert_almost_eq(loaded.state.health, 42.5, 0.0001, "HP round trips")
	assert_eq(loaded.state.gold, 27, "gold round trips (5 chest + 10 story + 12)")
	assert_eq(loaded.state.inventory.count_of(SALVE), 3, "the inventory round trips (3 salves)")
	assert_eq(
		loaded.state.inventory.stack_count(SALVE),
		1,
		"the three salves share one stack (max_stack 5)"
	)
	assert_eq(loaded.state.inventory.count_of(DAGGER), 1, "the story item round trips")
	assert_eq(loaded.state.world_id, DUNGEON_WORLD, "the world id round trips")
	assert_eq(loaded.state.spawn_id, &"spawn.dungeon.entry", "the spawn id round trips")

	# Only the story claim is persistent; run-scoped keys are gone with their run.
	assert_true(loaded.state.is_claimed(story_key), "the story reward key round trips")
	assert_false(loaded.state.is_claimed(chest_key), "the run-scoped chest key does not persist")
	assert_false(loaded.state.is_claimed(extra_key), "the run-scoped extra key does not persist")
	assert_eq(loaded.state.claimed_reward_keys.size(), 1, "exactly the story key is restored")

	# Re-earning: a run-scoped reward repeats in a new run, a story reward never does.
	assert_eq(
		loaded.loot.grant(chest_grant),
		LootService.CODE_INVALID,
		"a run-scoped grant without an active run is refused after loading"
	)
	assert_eq(loaded.state.gold, 27, "and changes nothing")
	var rerun := loaded.dungeons.start_run(&"dungeon.01")
	assert_not_null(rerun, "the loaded session can enter dungeon 01 again")
	assert_eq(
		loaded.loot.grant(chest_grant), LootService.CODE_GRANTED, "the chest reward is re-earned in the new run"
	)
	assert_eq(loaded.state.gold, 32, "and pays again")
	assert_eq(
		loaded.loot.grant(story_grant),
		LootService.CODE_DUPLICATE,
		"the story reward stays a duplicate after loading"
	)
	assert_eq(loaded.state.gold, 32, "and never pays twice")
	assert_eq(loaded.state.claimed_reward_keys.size(), 1, "the story ledger stays at one key")


func test_dungeon_progress_round_trips_through_a_fresh_main() -> void:
	## Sprint 03 acceptance (ADR-012/ADR-014): a first clear, the unlock it grants and
	## the one-time story claim survive `save -> fresh Main -> load`, while the transient
	## run state does not.
	var registry := _registry()
	var manager := _new_manager()
	var session := _new_session(registry, manager)
	session.new_game()
	assert_true(session.progress.is_unlocked(&"dungeon.01"), "a new game unlocks the start dungeon")
	assert_false(session.progress.is_unlocked(&"dungeon.02"), "dungeon 02 starts locked")

	var run := session.dungeons.start_run(&"dungeon.01")
	assert_not_null(run, "the run opens in dungeon 01")
	assert_true(
		session.dungeons.note_objective(&"objective.dungeon01.enemy_a"),
		"the objective enemy's death completes the dungeon"
	)
	assert_true(session.progress.is_completed(&"dungeon.01"), "the first completion is recorded")
	assert_true(session.progress.is_unlocked(&"dungeon.02"), "the first clear unlocks dungeon 02")
	assert_true(
		session.progress.was_first_clear_claimed(&"dungeon.01"), "the story reward claim is recorded"
	)
	session.note_location(HUB_WORLD, &"spawn.hub.start")
	var save_result := session.save_now()
	assert_eq(save_result.status, SaveResult.Status.OK, "the save succeeds: %s" % save_result.message)

	_main = _instantiate_main()
	if _main == null:
		return
	await wait_physics_frames(30)

	assert_eq(
		_main.boot_result.status,
		SaveResult.Status.OK,
		"the save loads on the next boot: %s" % _main.boot_result.message
	)
	assert_true(_main.session.progress.is_completed(&"dungeon.01"), "the completion survives the boot")
	assert_true(_main.session.progress.is_unlocked(&"dungeon.01"), "dungeon 01 stays available")
	assert_true(_main.session.progress.is_unlocked(&"dungeon.02"), "the unlock survives the boot")
	assert_true(
		_main.session.progress.was_first_clear_claimed(&"dungeon.01"),
		"the first-clear claim survives the boot"
	)
	assert_eq(
		_main.session.progress.completed_ids(),
		[&"dungeon.01"] as Array[StringName],
		"exactly one dungeon is completed"
	)
	# `DungeonProgress` returns StringName arrays; sort their string form so this test
	# checks the *set* of unlocks without depending on StringName pointer ordering.
	var unlocked: Array[String] = []
	for dungeon_id in _main.session.progress.unlocked_ids():
		unlocked.append(String(dungeon_id))
	unlocked.sort()
	assert_eq(
		unlocked,
		["dungeon.01", "dungeon.02"] as Array[String],
		"both dungeons are unlocked after the boot"
	)
	assert_eq(
		_main.session.dungeons.can_enter(&"dungeon.02"),
		DungeonService.CODE_OK,
		"the unlocked dungeon is enterable"
	)
	assert_null(_main.session.dungeons.active_run(), "no run state survives the restart")

	# The reward effects persist with the story claim, and nothing is granted again.
	assert_eq(_main.session.state.gold, 15, "the completion rewards persist (5 regular + 10 story)")
	assert_eq(_main.session.state.inventory.count_of(DAGGER), 1, "the story item persists")
	assert_true(
		_main.session.state.is_claimed(LootGrant.key_for(&"dungeon.01", &"reward.story.dungeon01")),
		"the story reward key persists"
	)
	assert_eq(
		_main.session.dungeons.claim_pending_first_clear_rewards(),
		0,
		"a completed, claimed dungeon has no pending reward to repair"
	)
	assert_eq(_main.session.state.gold, 15, "and the repair pass grants nothing")


# --- corrupt ------------------------------------------------------------------

func test_garbage_save_is_quarantined_and_the_boot_degrades_to_a_new_game() -> void:
	var garbage := "this is not JSON at all {{{ \"unterminated"
	_write_text(TEST_SAVE_PATH, garbage)

	var manager := _new_manager()
	var session := _new_session(_registry(), manager)
	var result := session.load_or_new()

	assert_eq(result.status, SaveResult.Status.CORRUPT, "garbage text is reported as CORRUPT")
	assert_false(FileAccess.file_exists(TEST_SAVE_PATH), "the unusable file is moved out of the way")
	assert_true(
		FileAccess.file_exists(TEST_SAVE_PATH + ".corrupt"), "the file is quarantined as .corrupt"
	)
	if FileAccess.file_exists(TEST_SAVE_PATH + ".corrupt"):
		assert_eq(
			_read_text(TEST_SAVE_PATH + ".corrupt"), garbage, "the quarantine keeps the original bytes"
		)

	assert_eq(session.state.world_id, HUB_WORLD, "the boot degraded to a new game in the hub")
	assert_eq(session.state.gold, 0, "with 0 gold")
	assert_almost_eq(session.state.health, 100.0, 0.0001, "with full HP")
	assert_true(session.state.inventory.is_empty(), "with an empty bag")
	assert_true(session.state.claimed_reward_keys.is_empty(), "and no claimed keys")

	var second := session.load_or_new()
	assert_eq(second.status, SaveResult.Status.MISSING, "the next boot finds no save at all")


# --- future version -----------------------------------------------------------

func test_a_future_version_is_refused_and_the_file_is_left_untouched() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.version = 999
	snapshot.health = 50.0
	snapshot.gold = 1
	snapshot.world_id = HUB_WORLD
	snapshot.spawn_id = &"spawn.hub.start"
	var text := JSON.stringify(snapshot.to_dict(), "\t")
	_write_text(TEST_SAVE_PATH, text)

	var manager := _new_manager()
	var session := _new_session(_registry(), manager)
	var result := session.load_or_new()

	assert_eq(
		result.status,
		SaveResult.Status.UNSUPPORTED_VERSION,
		"a version newer than the build is refused: %s" % result.message
	)
	assert_eq(session.state.gold, 0, "the refused save never reached the session")
	assert_almost_eq(session.state.health, 100.0, 0.0001, "the run started as a new game")
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "the future save file still exists")
	assert_eq(_read_text(TEST_SAVE_PATH), text, "and is byte-identical (never quarantined or rewritten)")
	assert_false(
		FileAccess.file_exists(TEST_SAVE_PATH + ".corrupt"), "no quarantine for a future version"
	)
	assert_eq(
		manager.load_snapshot().status,
		SaveResult.Status.UNSUPPORTED_VERSION,
		"a direct load reports the same refusal"
	)


# --- semantic filtering -------------------------------------------------------

func test_unknown_item_reward_and_world_ids_are_dropped_with_warnings() -> void:
	## A version 2 shape, so this exercises `GameSession.apply_snapshot`'s semantic
	## filtering rather than the v1 -> v2 migration (which drops all legacy keys).
	var data := {
		"version": SaveSnapshot.CURRENT_VERSION,
		"health": 55.0,
		"gold": 9,
		"items": [
			{"id": "item.minor_salve", "count": 2},
			{"id": "item.does_not_exist", "count": 4},
		],
		"world_id": "world.nowhere",
		"spawn_id": "spawn.hub.start",
		"claimed_reward_keys": [
			"world.dungeon.proto01/chest.a",
			"world.nowhere/chest.x",
		],
	}
	_write_text(TEST_SAVE_PATH, JSON.stringify(data, "\t"))

	var manager := _new_manager()
	var session := _new_session(_registry(), manager)
	var result := session.load_or_new()

	assert_eq(result.status, SaveResult.Status.OK, "the readable save loads as OK")
	assert_true(
		result.warnings.size() >= 3,
		"every dropped value produced a warning, got %d: %s" % [result.warnings.size(), result.warnings]
	)
	assert_true(
		_warnings_contain(result.warnings, "item.does_not_exist"),
		"the unknown item id is named in a warning: %s" % result.warnings
	)
	assert_true(
		_warnings_contain(result.warnings, "world.nowhere/chest.x"),
		"the unknown reward key is named in a warning: %s" % result.warnings
	)
	assert_true(
		_warnings_contain(result.warnings, "world.nowhere"),
		"the unknown world id is named in a warning: %s" % result.warnings
	)

	assert_almost_eq(session.state.health, 55.0, 0.0001, "the valid HP still loads")
	assert_eq(session.state.gold, 9, "the valid gold still loads")
	assert_eq(session.state.inventory.count_of(SALVE), 2, "the known item still loads")
	assert_eq(session.state.inventory.count_of(&"item.does_not_exist"), 0, "the unknown item is dropped")
	assert_eq(session.state.world_id, HUB_WORLD, "the unknown world falls back to the hub")
	assert_eq(session.state.spawn_id, &"spawn.hub.start", "the valid spawn id is kept")
	assert_true(
		session.state.is_claimed(LootGrant.key_for(DUNGEON_WORLD, &"chest.a")),
		"the known reward key is kept"
	)
	assert_false(
		session.state.is_claimed(&"world.nowhere/chest.x"), "the unknown reward key is dropped"
	)
	assert_eq(session.state.claimed_reward_keys.size(), 1, "exactly one claimed key survives")


# --- zero health --------------------------------------------------------------

func test_zero_health_in_the_save_becomes_full_hp_on_the_next_boot() -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.health = 0.0
	snapshot.gold = 3
	snapshot.world_id = HUB_WORLD
	snapshot.spawn_id = &"spawn.hub.start"
	_write_text(TEST_SAVE_PATH, JSON.stringify(snapshot.to_dict(), "\t"))

	_main = _instantiate_main()
	if _main == null:
		return
	await wait_physics_frames(30)

	assert_eq(_main.boot_result.status, SaveResult.Status.OK, "the zero-HP save is readable")
	assert_almost_eq(
		_main.session.state.health, 100.0, 0.0001, "0 HP in the save became full HP on the next boot"
	)
	var health := HealthComponent.find_on(_main.router.current_player())
	assert_not_null(health, "the booted rig has a HealthComponent")
	if health != null:
		assert_almost_eq(health.current_health, 100.0, 0.0001, "the live rig is playable at full HP")
	assert_eq(_main.session.state.gold, 3, "the rest of the save still applies")
	assert_not_null(_main.hud, "the booted HUD is wired")
	if _main.hud != null:
		assert_true(
			_main.hud.health_label.text.contains("100"),
			"the HUD reports the full HP: '%s'" % _main.hud.health_label.text
		)


# --- atomic overwrite ---------------------------------------------------------

func test_overwriting_a_save_leaves_no_tmp_or_bak_behind() -> void:
	var manager := _new_manager()
	var session := _new_session(_registry(), manager)
	session.new_game()
	session.add_gold(1)
	assert_eq(session.save_now().status, SaveResult.Status.OK, "the first save succeeds")

	# The second save has to move the existing file to `.bak` before promoting `.tmp`.
	session.add_gold(1)
	assert_eq(session.save_now().status, SaveResult.Status.OK, "the overwrite save succeeds")
	for suffix in [".tmp", ".bak"]:
		assert_false(
			FileAccess.file_exists(TEST_SAVE_PATH + suffix),
			"no %s survives the overwrite save" % suffix
		)

	var loaded := _new_session(_registry(), _new_manager())
	assert_eq(loaded.load_or_new().status, SaveResult.Status.OK, "the overwritten save loads")
	assert_eq(loaded.state.gold, 2, "the loaded file is the new save, not the backup")
