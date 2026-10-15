extends "res://tests/test_case.gd"

## AC-25 — `SaveManager` atomic write, corruption quarantine and version gate (ADR-010).
##
## Every test uses its own temp path under `user://` and removes the save plus every
## sibling file it may have produced (`.tmp`, `.bak`, `.corrupt`) in `teardown()`.

const TEMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const QUARANTINE_SUFFIX: String = ".corrupt"
const SIBLING_SUFFIXES: Array[String] = ["", TEMP_SUFFIX, BACKUP_SUFFIX, QUARANTINE_SUFFIX]

var _path: String = ""
var _manager: SaveManager = null
var _case_index: int = 0


func setup() -> void:
	_case_index += 1
	_path = "user://w1b_test_save_%d.json" % _case_index
	_remove_files()
	_manager = SaveManager.new()
	_manager.setup(_path)


func teardown() -> void:
	_remove_files()


func _remove_files() -> void:
	for suffix in SIBLING_SUFFIXES:
		var candidate := _path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


func _snapshot(health: float, gold: int) -> SaveSnapshot:
	var snapshot := SaveSnapshot.new()
	snapshot.health = health
	snapshot.gold = gold
	snapshot.items = [{"id": "item.minor_salve", "count": 2}]
	snapshot.world_id = &"world.dungeon.proto01"
	snapshot.spawn_id = &"spawn.dungeon.entry"
	snapshot.claimed_reward_keys = PackedStringArray(["world.dungeon.proto01/enemy.a"])
	return snapshot


func _write_raw_to(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "the test can write %s" % path)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _write_raw(text: String) -> void:
	_write_raw_to(_path, text)


func test_a_leftover_backup_is_recovered_when_the_main_file_is_gone() -> void:
	## A crash between the two renames of `save()` leaves the previous save in `.bak`
	## and no main file. The next boot must recover it instead of starting a new game.
	var first := _manager.save(_snapshot(55.0, 12))
	assert_true(first.ok(), "the first save succeeds")
	var backup_error := DirAccess.rename_absolute(_path, _path + BACKUP_SUFFIX)
	assert_eq(backup_error, OK, "the test simulates the crash window")
	assert_false(FileAccess.file_exists(_path), "no main file remains")

	var recovered := _manager.load_snapshot()
	assert_true(recovered.ok(), "the backup is recovered: %s" % recovered.message)
	assert_true(
		recovered.warnings.size() >= 1,
		"and the recovery is reported as a warning: %s" % recovered.warnings
	)
	if recovered.snapshot != null:
		assert_eq(recovered.snapshot.gold, 12, "the recovered snapshot carries the old gold")
		assert_eq(recovered.snapshot.health, 55.0, "and the old health")
	assert_true(FileAccess.file_exists(_path), "the promoted file is the new main save")
	assert_false(FileAccess.file_exists(_path + BACKUP_SUFFIX), "and the backup is gone")


func test_save_then_load_returns_an_equal_snapshot() -> void:
	var saved := _snapshot(63.5, 9)
	var save_result := _manager.save(saved)
	assert_true(save_result.ok(), "save reported OK: %s" % save_result.message)
	assert_eq(save_result.status, SaveResult.Status.OK, "explicit OK status")
	assert_true(_manager.snapshot_exists(), "the save file exists after a save")

	var load_result := _manager.load_snapshot()
	assert_true(load_result.ok(), "load reported OK: %s" % load_result.message)
	assert_not_null(load_result.snapshot, "a successful load carries a snapshot")
	if load_result.snapshot == null:
		return
	assert_eq(load_result.snapshot.health, saved.health, "health survives the file round trip")
	assert_eq(load_result.snapshot.gold, saved.gold, "gold survives the file round trip")
	assert_eq(load_result.snapshot.items, saved.items, "items survive the file round trip")
	assert_eq(load_result.snapshot.world_id, saved.world_id, "world id survives the file round trip")
	assert_eq(load_result.snapshot.spawn_id, saved.spawn_id, "spawn id survives the file round trip")
	assert_eq(
		load_result.snapshot.claimed_reward_keys,
		saved.claimed_reward_keys,
		"claimed loot keys survive the file round trip"
	)


func test_the_save_is_a_readable_json_file() -> void:
	_manager.save(_snapshot(100.0, 3))
	var text := FileAccess.get_file_as_string(_path)
	assert_ne(text, "", "the save file is not empty")
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "the save file is a JSON object")
	if not parsed is Dictionary:
		return
	assert_eq(parsed.get("version"), SaveSnapshot.CURRENT_VERSION, "the file declares the schema version")
	assert_false(text.contains("Object"), "no serialised object reference leaks into the text")


func test_snapshot_exists_follows_the_file() -> void:
	assert_false(_manager.snapshot_exists(), "no file before the first save")
	_manager.save(_snapshot(50.0, 1))
	assert_true(_manager.snapshot_exists(), "the file exists after the save")
	DirAccess.remove_absolute(_path)
	assert_false(_manager.snapshot_exists(), "a deleted save stops existing")


func test_a_fresh_manager_reads_the_same_slot() -> void:
	_manager.save(_snapshot(12.0, 4))
	var other := SaveManager.new()
	other.setup(_path)
	var result := other.load_snapshot()
	assert_true(result.ok(), "a new manager instance loads the slot")
	assert_not_null(result.snapshot, "a snapshot came back")
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.gold, 4, "the loaded data is the file's")


func test_missing_file_is_reported_as_missing() -> void:
	var result := _manager.load_snapshot()
	assert_eq(result.status, SaveResult.Status.MISSING, "a missing file is a normal boot case")
	assert_false(result.ok(), "MISSING is not OK")
	assert_ne(result.message, "", "the result carries a diagnostic")
	assert_null(result.snapshot, "no snapshot for a missing file")
	for suffix in SIBLING_SUFFIXES:
		assert_false(FileAccess.file_exists(_path + suffix), "loading created no '%s' file" % suffix)


func test_garbage_text_is_corrupt_and_quarantined() -> void:
	_write_raw("this is not JSON {{{")
	var result := _manager.load_snapshot()
	assert_eq(result.status, SaveResult.Status.CORRUPT, "garbage is CORRUPT")
	assert_null(result.snapshot, "no snapshot for a corrupt file")
	assert_true(
		FileAccess.file_exists(_path + QUARANTINE_SUFFIX),
		"the corrupt file is quarantined: %s" % result.message
	)
	assert_eq(
		FileAccess.get_file_as_string(_path + QUARANTINE_SUFFIX),
		"this is not JSON {{{",
		"the quarantined bytes are preserved"
	)
	assert_false(FileAccess.file_exists(_path), "the slot is free for a new game")


func test_json_that_is_not_an_object_is_corrupt() -> void:
	_write_raw("[1, 2, 3]")
	var result := _manager.load_snapshot()
	assert_eq(result.status, SaveResult.Status.CORRUPT, "a JSON array root is not a save")
	assert_true(FileAccess.file_exists(_path + QUARANTINE_SUFFIX), "and it is quarantined too")


func test_an_unusable_shape_is_corrupt() -> void:
	var cases: Array[Dictionary] = [
		{},
		{"version": 1},
		{"version": 1, "health": "high", "gold": 0, "items": [], "world_id": "", "spawn_id": "", "claimed_reward_keys": []},
		{"health": 50.0, "gold": 0, "items": [], "world_id": "", "spawn_id": "", "claimed_reward_keys": []},
	]
	for data: Dictionary in cases:
		_write_raw(JSON.stringify(data))
		var result := _manager.load_snapshot()
		assert_eq(result.status, SaveResult.Status.CORRUPT, "unusable shape %s is CORRUPT" % [data])
		assert_null(result.snapshot, "no snapshot for an unusable shape")
		assert_false(FileAccess.file_exists(_path), "the unusable file was moved away")
		assert_true(
			FileAccess.file_exists(_path + QUARANTINE_SUFFIX),
			"quarantine file exists for %s" % [data]
		)


func test_an_old_version_without_a_migration_is_reported() -> void:
	# Version 0 has no migration path; version 1 does (v1 -> v2, ADR-010/ADR-012).
	var data := _snapshot(70.0, 2).to_dict()
	data["version"] = 0
	_write_raw(JSON.stringify(data))
	var result := _manager.load_snapshot()
	assert_eq(result.status, SaveResult.Status.CORRUPT, "an unmigratable version is unusable data")
	assert_false(result.ok(), "an unmigratable version does not load")
	assert_null(result.snapshot, "no snapshot is produced")
	assert_ne(result.message, "", "a clear diagnostic is reported")
	assert_true(
		result.message.contains("version"),
		"the diagnostic mentions the version: %s" % result.message
	)
	assert_true(
		result.message.contains("no migration path"),
		"and says there is no path: %s" % result.message
	)
	assert_false(FileAccess.file_exists(_path), "the unusable file is moved out of the way")
	assert_true(
		FileAccess.file_exists(_path + QUARANTINE_SUFFIX), "and quarantined like any corrupt save"
	)


func test_a_v1_file_migrates_to_v2_and_drops_the_legacy_reward_keys() -> void:
	## Sprint 03 (ADR-012/ADR-013): version 1 had a single persistent loot ledger whose
	## keys were all regular-reward keys with no story meaning. The migration adds an
	## empty `dungeon_progress` section, drops those legacy keys, and never invents a
	## completion; the session then seeds the start dungeons.
	var data := {
		"version": 1,
		"health": 42.0,
		"gold": 9,
		"items": [{"id": "item.minor_salve", "count": 2}],
		"world_id": "world.dungeon.proto01",
		"spawn_id": "spawn.dungeon.entry",
		"claimed_reward_keys": [
			"world.dungeon.proto01/enemy.a",
			"world.dungeon.proto01/chest.a",
		],
	}
	_write_raw(JSON.stringify(data, "\t"))

	var result := _manager.load_snapshot()
	assert_true(result.ok(), "a v1 file migrates and loads: %s" % result.message)
	assert_not_null(result.snapshot, "the migration produces a snapshot")
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.version, SaveSnapshot.CURRENT_VERSION, "the snapshot reports the current version")
	assert_eq(result.snapshot.version, 3, "the migration chain reaches version 3")
	assert_true(
		result.snapshot.dungeon_progress.is_empty(),
		"the migration adds an empty dungeon_progress section: %s" % result.snapshot.dungeon_progress
	)
	assert_true(
		result.snapshot.claimed_reward_keys.is_empty(),
		"the legacy v1 reward keys are dropped: %s" % result.snapshot.claimed_reward_keys
	)
	assert_almost_eq(result.snapshot.health, 42.0, 0.0001, "v1 health survives the migration")
	assert_eq(result.snapshot.gold, 9, "v1 gold survives the migration")
	assert_eq(result.snapshot.world_id, &"world.dungeon.proto01", "the v1 world id survives")
	assert_eq(result.snapshot.spawn_id, &"spawn.dungeon.entry", "the v1 spawn id survives")
	assert_eq(result.snapshot.items.size(), 1, "the v1 inventory survives")
	assert_true(FileAccess.file_exists(_path), "a valid v1 save keeps its slot")
	assert_false(
		FileAccess.file_exists(_path + QUARANTINE_SUFFIX), "and is never quarantined"
	)


func test_a_newer_version_is_refused_and_the_file_is_untouched() -> void:
	var data := _snapshot(80.0, 5).to_dict()
	data["version"] = SaveSnapshot.CURRENT_VERSION + 1
	_write_raw(JSON.stringify(data))
	var before := FileAccess.get_file_as_string(_path)

	var result := _manager.load_snapshot()
	assert_eq(result.status, SaveResult.Status.UNSUPPORTED_VERSION, "a future version is refused")
	assert_false(result.ok(), "UNSUPPORTED_VERSION is not OK")
	assert_null(result.snapshot, "never a snapshot from a newer schema")
	assert_ne(result.message, "", "the refusal carries a diagnostic")
	assert_eq(FileAccess.get_file_as_string(_path), before, "the future save is not modified")
	assert_false(
		FileAccess.file_exists(_path + QUARANTINE_SUFFIX),
		"a future version is never quarantined"
	)
	assert_true(FileAccess.file_exists(_path), "the file keeps its place")


func test_a_successful_save_leaves_no_temp_or_backup_files() -> void:
	var result := _manager.save(_snapshot(100.0, 0))
	assert_true(result.ok(), "first save: %s" % result.message)
	assert_false(FileAccess.file_exists(_path + TEMP_SUFFIX), "no .tmp after the first save")
	assert_false(FileAccess.file_exists(_path + BACKUP_SUFFIX), "no .bak after the first save")

	# The second save goes through the rename-the-previous-file path.
	var second := _manager.save(_snapshot(55.0, 8))
	assert_true(second.ok(), "second save: %s" % second.message)
	assert_false(FileAccess.file_exists(_path + TEMP_SUFFIX), "no .tmp after the second save")
	assert_false(FileAccess.file_exists(_path + BACKUP_SUFFIX), "no .bak after the second save")
	assert_true(FileAccess.file_exists(_path), "the save file is in place")


func test_saving_twice_replaces_the_previous_save() -> void:
	_manager.save(_snapshot(90.0, 1))
	var replacement := _snapshot(20.5, 42)
	_manager.save(replacement)

	var result := _manager.load_snapshot()
	assert_true(result.ok(), "the replacement loads: %s" % result.message)
	assert_not_null(result.snapshot, "a snapshot came back")
	if result.snapshot == null:
		return
	assert_eq(result.snapshot.gold, 42, "the second save wins")
	assert_eq(result.snapshot.health, 20.5, "the second health value wins")
	assert_eq(result.snapshot.to_dict(), replacement.to_dict(), "the file matches the last save exactly")


func test_a_stale_temp_or_backup_from_a_crash_does_not_survive_the_next_save() -> void:
	# Simulate a crash between the two renames of an earlier save: no save file, but
	# leftovers from it.
	_write_raw_to(_path + BACKUP_SUFFIX, "{\"version\": 1}")
	_write_raw_to(_path + TEMP_SUFFIX, "half written")
	var result := _manager.save(_snapshot(44.0, 6))
	assert_true(result.ok(), "the save succeeds despite the leftovers: %s" % result.message)
	assert_false(FileAccess.file_exists(_path + TEMP_SUFFIX), "the stale .tmp is gone")
	assert_false(FileAccess.file_exists(_path + BACKUP_SUFFIX), "the stale .bak is gone")
	var loaded := _manager.load_snapshot()
	assert_true(loaded.ok(), "and the new save is readable")
	assert_not_null(loaded.snapshot, "a snapshot came back")
	if loaded.snapshot == null:
		return
	assert_eq(loaded.snapshot.gold, 6, "with the new data")


func test_saving_a_null_snapshot_is_an_io_error_without_touching_the_slot() -> void:
	_manager.save(_snapshot(100.0, 7))
	var failure := _manager.save(null)
	assert_eq(failure.status, SaveResult.Status.IO_ERROR, "a null snapshot is an IO_ERROR")
	assert_ne(failure.message, "", "the failure carries a diagnostic")
	assert_false(FileAccess.file_exists(_path + TEMP_SUFFIX), "no .tmp is left behind")
	var reloaded := _manager.load_snapshot()
	assert_true(reloaded.ok(), "the previous save is still readable")
	assert_not_null(reloaded.snapshot, "a snapshot came back")
	if reloaded.snapshot == null:
		return
	assert_eq(reloaded.snapshot.gold, 7, "and unchanged")
