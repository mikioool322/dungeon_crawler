extends "res://tests/test_case.gd"

## S04-QA — independent verification of the save v3 contract at *session* level
## (ADR-010/ADR-015): the file round trip restores equipment and recomputes the exact
## effective stats, v1/v2 migrate without inventing gear, a damaged equipment section
## cannot crash the boot, corruption quarantines, a backup is recovered and a future
## version is refused without touching the file.

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"

## Sibling files the save path may produce; typed so path concatenation stays typed.
const SIBLING_SUFFIXES: Array[String] = ["", ".tmp", ".bak", ".corrupt"]

const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const SALVE := &"item.minor_salve"

var _path: String = ""
var _case_index: int = 0
var _registry: ContentRegistry = null


func setup() -> void:
	_case_index += 1
	_path = "user://test_s04_qa_persistence_%d.json" % _case_index
	_remove_files()
	_registry = ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)


func teardown() -> void:
	_registry = null
	_remove_files()


func _remove_files() -> void:
	for suffix: String in SIBLING_SUFFIXES:
		var candidate: String = _path + suffix
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _session() -> GameSession:
	var manager := SaveManager.new()
	manager.setup(_path)
	var session := GameSession.new()
	session.setup(_registry, manager)
	return session


func _write_raw(data: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	assert_not_null(file, "the fixture file opens for writing")
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()


func _read_text() -> String:
	return FileAccess.get_file_as_string(_path)


func _v2_data() -> Dictionary:
	return {
		"version": 2,
		"health": 55.0,
		"gold": 12,
		"items": [{"id": String(SWORD), "count": 1}, {"id": String(SALVE), "count": 2}],
		"world_id": "world.hub",
		"spawn_id": "spawn.hub.shrine",
		"claimed_reward_keys": [],
		"dungeon_progress": {
			"completed": ["dungeon.01"],
			"unlocked": ["dungeon.01", "dungeon.02"],
			"first_clear_claimed": ["dungeon.01"],
			"story_flags": [],
		},
	}


# --- v3 round trip -------------------------------------------------------------

func test_equipment_and_effective_stats_round_trip_through_the_session() -> void:
	var first := _session()
	first.new_game()
	first.state.inventory.add(_registry.find_item(SWORD), 1)
	first.state.inventory.add(_registry.find_item(VEST), 1)
	first.state.inventory.add(_registry.find_item(SALVE), 2)
	assert_eq(first.equip_item(SWORD), EquipmentState.CODE_OK, "the sword equips")
	assert_eq(first.equip_item(VEST), EquipmentState.CODE_OK, "the vest equips")
	first.state.gold = 77
	first.state.health = 61.5

	var expected_attack := first.stats.effective(CharacterStats.ATTACK_DAMAGE)
	var expected_defense := first.stats.effective(CharacterStats.DEFENSE)
	var expected_health := first.stats.effective(CharacterStats.MAX_HEALTH)
	var expected_speed := first.stats.effective(CharacterStats.MOVEMENT_SPEED)
	var save_result := first.save_now()
	assert_true(save_result.ok(), "the session saves: %s" % save_result.message)

	# Effective stats are derived, never stored.
	var raw := JSON.parse_string(_read_text()) as Dictionary
	assert_false(raw.has("stats"), "no stats section is written")
	assert_false(raw.has("effective_stats"), "and no effective-stats section")
	assert_eq(raw.get("version"), 3, "the file is v3")
	var raw_equipment: Dictionary = raw.get("equipment", {})
	assert_eq(raw_equipment.get("main_hand"), String(SWORD), "the hand is written by stable name")
	assert_eq(raw_equipment.get("chest_armor"), String(VEST), "the chest is written by stable name")

	var second := _session()
	var result := second.load_or_new()
	assert_true(result.ok(), "the session loads the file: %s" % result.message)
	assert_eq(
		second.state.equipment.get_equipped(EquipmentSlot.Id.MAIN_HAND), SWORD,
		"the sword is still equipped"
	)
	assert_eq(
		second.state.equipment.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), VEST,
		"the vest is still equipped"
	)
	assert_eq(second.state.inventory.count_of(SWORD), 0, "the equipped sword is not duplicated in the bag")
	assert_eq(second.state.inventory.count_of(VEST), 0, "the equipped vest is not duplicated in the bag")
	assert_eq(second.state.inventory.count_of(SALVE), 2, "the bag items survive")
	assert_eq(second.state.gold, 77, "gold survives")
	assert_almost_eq(second.state.health, 61.5, 0.0001, "health survives")
	assert_almost_eq(
		second.stats.effective(CharacterStats.ATTACK_DAMAGE), expected_attack, 0.0001,
		"the attack is recomputed identically"
	)
	assert_almost_eq(
		second.stats.effective(CharacterStats.DEFENSE), expected_defense, 0.0001,
		"the defense is recomputed identically"
	)
	assert_almost_eq(
		second.stats.effective(CharacterStats.MAX_HEALTH), expected_health, 0.0001,
		"the max HP is recomputed identically"
	)
	assert_almost_eq(
		second.stats.effective(CharacterStats.MOVEMENT_SPEED), expected_speed, 0.0001,
		"the speed is recomputed identically"
	)
	assert_almost_eq(expected_attack, 49.0, 0.0001, "and the value is the sword's 34 + 15")
	assert_almost_eq(expected_defense, 5.0, 0.0001, "and the vest's 5")

	# The restored session pushes the same values into a fresh rig.
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("the player scene failed to load")
		return
	var player := packed.instantiate() as PlayerController
	add_to_tree(player)
	assert_true(second.apply_to_player(player), "the stored HP applies to a fresh rig")
	assert_true(second.apply_stats_to_player(player), "the restored stats apply to a fresh rig")
	var health := HealthComponent.find_on(player)
	if health != null:
		assert_almost_eq(health.current_health, 61.5, 0.0001, "the rig got the stored HP")
		assert_almost_eq(health.max_health, expected_health, 0.0001, "and the restored maximum")
		assert_not_null(health.defense_provider(), "and the defense provider")
	assert_almost_eq(player.move_speed, expected_speed, 0.0001, "the rig got the restored speed")
	var attack := player.get_node_or_null("AttackController") as AttackController
	if attack != null and attack.attack_profile() != null:
		assert_eq(
			attack.attack_profile().id, &"attack.player.iron_sword",
			"the rig swings with the restored weapon profile"
		)


# --- migrations ----------------------------------------------------------------

func test_a_v2_file_loads_through_the_session_without_inventing_equipment() -> void:
	_write_raw(_v2_data())
	var session := _session()
	var result := session.load_or_new()
	assert_true(result.ok(), "the v2 file loads: %s" % result.message)
	assert_eq(result.snapshot.version, 3, "the snapshot is migrated to v3")
	assert_eq(session.state.equipment.equipped_slots().size(), 0, "an old player starts unarmoured")
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), 34.0, 0.0001,
		"the effective attack is the base value, not an invented weapon bonus"
	)
	assert_almost_eq(session.stats.effective(CharacterStats.DEFENSE), 0.0, 0.0001, "no invented armor")
	assert_eq(session.state.inventory.count_of(SWORD), 1, "the bagged sword survives")
	assert_eq(session.state.gold, 12, "gold survives")
	assert_almost_eq(session.state.health, 55.0, 0.0001, "health survives")
	assert_true(session.progress.is_completed(&"dungeon.01"), "the completion survives")
	assert_true(session.progress.is_unlocked(&"dungeon.02"), "the unlock survives")
	assert_true(session.progress.was_first_clear_claimed(&"dungeon.01"), "the first-clear claim survives")


func test_a_v1_file_runs_the_chain_to_v3_without_equipment() -> void:
	_write_raw({
		"version": 1,
		"health": 44.0,
		"gold": 9,
		"items": [{"id": String(SALVE), "count": 1}],
		"world_id": "world.hub",
		"spawn_id": "spawn.hub.shrine",
		"claimed_rewards": ["world.dungeon.proto01/enemy.a"],
	})
	var session := _session()
	var result := session.load_or_new()
	assert_true(result.ok(), "the v1 file loads: %s" % result.message)
	assert_eq(result.snapshot.version, 3, "v1 reached v3")
	assert_eq(session.state.equipment.equipped_slots().size(), 0, "no equipment is invented")
	assert_eq(session.state.gold, 9, "gold survives the chain")
	assert_almost_eq(session.state.health, 44.0, 0.0001, "health survives the chain")
	assert_eq(session.state.inventory.count_of(SALVE), 1, "the item survives the chain")
	assert_true(session.progress.is_unlocked(&"dungeon.01"), "the start dungeon is seeded")


# --- damaged equipment records -------------------------------------------------

func test_a_v3_save_with_damaged_equipment_cannot_crash_the_boot() -> void:
	var data := _v2_data()
	data["version"] = 3
	data["equipment"] = {
		"main_hand": "item.does_not_exist",
		"hat": String(SWORD),
		"chest_armor": String(SWORD),
	}
	_write_raw(data)
	var session := _session()
	var result := session.load_or_new()
	assert_true(result.ok(), "the damaged file still boots: %s" % result.message)
	assert_eq(session.state.equipment.equipped_slots().size(), 0, "every damaged entry is dropped")
	assert_eq(session.state.inventory.count_of(SWORD), 1, "the sword stays in the bag")
	# Note (reported S04-QA finding): the drops are announced through `push_warning`
	# inside `EquipmentState.from_save_dict` only; `GameSession._apply_equipment()`
	# does not append them to the returned warnings, unlike item/world/reward filtering.
	# The session stays fully usable after the damaged load.
	assert_eq(session.equip_item(SWORD), EquipmentState.CODE_OK, "the sword can be equipped afterwards")
	assert_almost_eq(
		session.stats.effective(CharacterStats.ATTACK_DAMAGE), 49.0, 0.0001,
		"and the stats follow the new equipment"
	)


# --- corruption, backup and version gate ---------------------------------------

func test_a_corrupt_save_is_quarantined() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		fail("the fixture file could not be created")
		return
	file.store_string("{ this is not json")
	file.close()

	var session := _session()
	var result := session.load_or_new()
	assert_eq(result.status, SaveResult.Status.CORRUPT, "the corrupt file is reported")
	assert_false(FileAccess.file_exists(_path), "the bad file is moved out of the way")
	assert_true(FileAccess.file_exists(_path + ".corrupt"), "and quarantined")
	assert_eq(session.state.gold, 0, "the session started a new game")
	assert_eq(session.state.world_id, GameSession.DEFAULT_WORLD_ID, "in the hub")


func test_a_leftover_backup_is_recovered_through_the_session() -> void:
	var first := _session()
	first.new_game()
	first.state.gold = 33
	first.state.health = 71.0
	assert_true(first.save_now().ok(), "the first save succeeds")
	assert_eq(DirAccess.rename_absolute(_path, _path + ".bak"), OK, "the crash window is simulated")
	assert_false(FileAccess.file_exists(_path), "no main file remains")

	var second := _session()
	var result := second.load_or_new()
	assert_true(result.ok(), "the backup is recovered: %s" % result.message)
	assert_true(result.warnings.size() >= 1, "and the recovery is reported: %s" % result.warnings)
	assert_eq(second.state.gold, 33, "the recovered gold is restored")
	assert_almost_eq(second.state.health, 71.0, 0.0001, "and the recovered health")
	assert_true(FileAccess.file_exists(_path), "the promoted file is the main save")


func test_a_future_version_is_refused_without_touching_the_file() -> void:
	var data := _v2_data()
	data["version"] = 99
	_write_raw(data)
	var before := _read_text()
	var session := _session()
	var result := session.load_or_new()
	assert_eq(result.status, SaveResult.Status.UNSUPPORTED_VERSION, "a future version is refused")
	assert_eq(_read_text(), before, "the file on disk is byte-identical")
	assert_eq(session.state.gold, 0, "the session fell back to a new game")
