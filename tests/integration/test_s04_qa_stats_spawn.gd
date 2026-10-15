extends "res://tests/test_case.gd"

## S04-QA — the spawn path must respect an unready `CharacterStats` source (ADR-015):
## an invalid `PlayerDefinition` leaves the stats not ready and `apply_stats_to_player()`
## then refuses to touch the freshly spawned rig, which therefore keeps its scene values.
##
## The control case proves the assertions are not vacuous: a valid definition does
## overwrite the same rig fields.

const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"
const TEST_SAVE_PATH := "user://test_s04_qa_stats_spawn.json"

var _session: GameSession = null


func setup() -> void:
	_delete_save_files()


func teardown() -> void:
	_session = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _profile(id: StringName) -> AttackDefinition:
	var profile := AttackDefinition.new()
	profile.id = id
	profile.damage = 34.0
	profile.reach = 2.0
	profile.windup = 0.35
	profile.active_window = 0.15
	profile.recovery = 0.45
	profile.cooldown = 0.6
	return profile


func _invalid_player() -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &""  # an empty id is a validation error
	definition.display_name = "Broken"
	definition.max_health = 250.0  # values that must never reach the rig
	definition.attack_damage = 99.0
	definition.defense = 50.0
	definition.movement_speed = 9.0
	definition.attack_definition = null
	return definition


func _valid_player() -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &"player.qa"
	definition.display_name = "QA Tester"
	definition.max_health = 120.0
	definition.attack_damage = 40.0
	definition.defense = 7.0
	definition.movement_speed = 5.0
	definition.attack_definition = _profile(&"attack.qa")
	return definition


func _registry_with(player: PlayerDefinition, list_profile: bool) -> ContentRegistry:
	var manifest := ContentManifest.new()
	manifest.player = player
	if list_profile and player.attack_definition != null:
		var attacks: Array[AttackDefinition] = [player.attack_definition]
		manifest.attacks = attacks
	return ContentRegistry.build(manifest)


func _session_with(player: PlayerDefinition, list_profile: bool) -> GameSession:
	var manager := SaveManager.new()
	manager.setup(TEST_SAVE_PATH)
	var session := GameSession.new()
	session.setup(_registry_with(player, list_profile), manager)
	return session


func _rig() -> PlayerController:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("%s failed to load" % PLAYER_SCENE_PATH)
		return null
	var player := packed.instantiate() as PlayerController
	if player == null:
		fail("the player scene root is not a PlayerController")
		return null
	add_to_tree(player)
	return player


func test_an_invalid_player_definition_never_overwrites_the_rig() -> void:
	_session = _session_with(_invalid_player(), false)
	assert_false(_session.stats.is_ready(), "the invalid definition leaves the stats unready")

	var player := _rig()
	if player == null:
		return
	var health := HealthComponent.find_on(player)
	assert_not_null(health, "the rig has its HealthComponent")
	if health == null:
		return

	assert_false(
		_session.apply_stats_to_player(player),
		"the spawn path refuses to apply unready stats"
	)
	assert_almost_eq(player.move_speed, 4.0, 0.0001, "the rig keeps its scene speed, not 9.0")
	assert_almost_eq(health.max_health, 100.0, 0.0001, "the rig keeps its scene max HP, not 250")
	assert_almost_eq(health.current_health, 100.0, 0.0001, "and its full scene life")
	assert_null(health.defense_provider(), "no defense provider was bound")
	var attack := player.get_node_or_null("AttackController") as AttackController
	assert_not_null(attack, "the rig has its AttackController")
	if attack != null:
		assert_not_null(attack.attack_profile(), "the base attack profile is still set")
		if attack.attack_profile() != null:
			assert_eq(
				attack.attack_profile().id, &"attack.player.basic",
				"and it is the scene's own profile"
			)

	# Control: a valid definition does overwrite the same fields, so the assertions
	# above prove a refusal rather than an inert code path.
	var valid := _session_with(_valid_player(), true)
	assert_true(valid.stats.is_ready(), "the valid definition readies the stats")
	var other := _rig()
	if other == null:
		return
	assert_true(valid.apply_stats_to_player(other), "the valid session applies its stats")
	assert_almost_eq(other.move_speed, 5.0, 0.0001, "the valid speed reached the rig")
	var other_health := HealthComponent.find_on(other)
	if other_health != null:
		assert_almost_eq(other_health.max_health, 120.0, 0.0001, "the valid max HP reached the rig")
		assert_not_null(other_health.defense_provider(), "and the defense provider is bound")
