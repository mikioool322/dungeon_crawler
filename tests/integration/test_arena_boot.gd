extends "res://tests/test_case.gd"

## AC-11 — the greybox arena is the project's main scene, boots headless and wires
## its actors, obstacles and HUD. Encounter-level scenarios (attack exchange,
## evasion, death) live in the QA suite, not here.

const ARENA_SCENE_PATH := "res://world/prototype/proto_arena.tscn"

var _arena: Node3D


func teardown() -> void:
	_arena = null


func _instantiate_arena() -> Node3D:
	var scene := load(ARENA_SCENE_PATH) as PackedScene
	if scene == null:
		fail("arena scene failed to load: %s" % ARENA_SCENE_PATH)
		return null
	_arena = scene.instantiate() as Node3D
	if _arena == null:
		fail("arena scene did not instantiate as Node3D")
		return null
	add_to_tree(_arena)
	return _arena


func _player() -> CharacterBody3D:
	return _arena.get_node_or_null("Player") as CharacterBody3D


func _enemy() -> EnemyBrain:
	return _arena.get_node_or_null("Enemy") as EnemyBrain


func test_main_scene_is_the_arena() -> void:
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, ARENA_SCENE_PATH, "the project must boot into the greybox arena")


func test_arena_loads_without_errors_and_has_the_expected_root() -> void:
	var arena := _instantiate_arena()
	assert_not_null(arena, "arena instantiated")
	assert_true(arena is ProtoArena, "arena root carries the ProtoArena controller script")
	await wait_physics_frames(2)
	assert_true(arena.is_inside_tree(), "arena is running in the tree")


func test_arena_has_ground_walls_and_occlusion_obstacles_on_the_world_layer() -> void:
	_instantiate_arena()
	await wait_physics_frames(2)
	for node_name in ["Floor", "WallNorth", "WallSouth", "WallEast", "WallWest", "PillarWest", "PillarEast"]:
		var body := _arena.get_node_or_null(node_name) as StaticBody3D
		assert_not_null(body, "%s exists as static world geometry" % node_name)
		if body != null:
			assert_eq(body.collision_layer, PhysicsLayers.WORLD, "%s is on the world layer" % node_name)
	# The pillars are the attack-blocking obstacles required by the sprint scope.
	var pillar := _arena.get_node_or_null("PillarWest") as StaticBody3D
	assert_not_null(pillar, "at least one pillar is present for occlusion")


func test_arena_spawns_a_player_with_full_health() -> void:
	_instantiate_arena()
	await wait_physics_frames(2)
	var player := _player()
	assert_not_null(player, "player exists")
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	assert_not_null(health, "player owns a HealthComponent (scene contract, ADR-005)")
	assert_eq(health.max_health, 100.0, "player HP budget")
	assert_true(health.is_alive(), "player starts alive")


func test_arena_spawns_the_enemy_with_a_definition() -> void:
	_instantiate_arena()
	await wait_physics_frames(2)
	var enemy := _enemy()
	assert_not_null(enemy, "enemy exists")
	assert_not_null(enemy.definition, "enemy has an EnemyDefinition assigned")
	assert_true(enemy.definition.is_valid(), "enemy definition is valid data")
	assert_eq(enemy.definition.id, &"enemy.grunt", "the shipped grunt definition is used")


func test_enemy_detects_the_player_and_closes_distance() -> void:
	## The sprint's encounter must start on its own: the spawn distance is inside the
	## detection radius, line of sight is clear and the enemy walks towards the player.
	var arena := _instantiate_arena()
	await wait_physics_frames(4)
	var player := _player()
	var enemy := _enemy()
	var start_distance := MeleeRules.horizontal_distance(
		enemy.global_position, player.global_position
	)
	await wait_physics_frames(60)
	var end_distance := MeleeRules.horizontal_distance(
		enemy.global_position, player.global_position
	)
	assert_eq(enemy.fsm_state, EnemyFsm.State.CHASE, "enemy spotted the player and chases")
	assert_true(end_distance < start_distance - 0.5, "enemy closed the gap (%.2f -> %.2f m)" % [
		start_distance, end_distance
	])
	assert_true(arena.is_inside_tree(), "arena still running")


func test_hud_is_bound_and_reports_player_health() -> void:
	_instantiate_arena()
	await wait_physics_frames(30)
	var hud := _arena.get_node_or_null("Hud") as ArenaDebugHud
	assert_not_null(hud, "HUD exists")
	assert_not_null(hud.player_hp_label, "player HP label wired")
	assert_not_null(hud.enemy_status_label, "enemy status label wired")
	assert_not_null(hud.hint_label, "controls hint wired")
	assert_true(
		hud.player_hp_label.text.contains("100"),
		"HUD shows the player's current HP, got '%s'" % hud.player_hp_label.text
	)
	assert_true(
		hud.enemy_status_label.text.contains("100"),
		"HUD shows the enemy's current HP, got '%s'" % hud.enemy_status_label.text
	)


func test_player_settles_on_the_floor_at_spawn() -> void:
	_instantiate_arena()
	await wait_physics_frames(30)
	var player := _player()
	assert_true(player.is_on_floor(), "player stands on the arena floor")
	assert_almost_eq(player.global_position.y, 0.0, 0.1, "player origin sits at floor level")


func test_hud_controls_never_swallow_mouse_input() -> void:
	## Controls default to MOUSE_FILTER_STOP, which would eat the click that
	## re-captures the mouse (and could later eat gameplay clicks).
	_instantiate_arena()
	await wait_physics_frames(2)
	var hud := _arena.get_node_or_null("Hud") as CanvasLayer
	assert_not_null(hud, "HUD exists")
	if hud == null:
		return
	var checked: int = 0
	for node in _all_controls(hud):
		checked += 1
		assert_eq(
			node.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"HUD control '%s' must ignore mouse input" % node.name
		)
	assert_true(checked >= 4, "the HUD has the expected controls (found %d)" % checked)


func test_hud_survives_a_freed_actor() -> void:
	## Corpse cleanup / in-place encounter resets are the next likely feature; the HUD
	## must degrade to "n/a" instead of dereferencing a freed node every frame.
	_instantiate_arena()
	await wait_physics_frames(2)
	var hud := _arena.get_node_or_null("Hud") as ArenaDebugHud
	var enemy := _enemy()
	assert_not_null(hud, "HUD exists")
	assert_not_null(enemy, "enemy exists")
	enemy.queue_free()
	await wait_process_frames(3)
	assert_false(is_instance_valid(enemy), "the enemy is really freed")
	assert_true(
		hud.enemy_status_label.text.contains("n/a"),
		"HUD reports the missing actor instead of a stale line, got '%s'" % hud.enemy_status_label.text
	)


func _all_controls(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in root.get_children():
		if child is Control:
			found.append(child as Control)
		found.append_array(_all_controls(child))
	return found
