extends "res://tests/test_case.gd"

## W6 shipped-content validation (AC-09, AC-10, and the sprint's escape window).
##
## Locks the approved Sprint 01 numbers in the `.tres` files the scenes actually
## use, then re-derives the design arithmetic (escape margin, hits-to-kill) from
## those resources instead of restating it as a constant. The unit suite already
## validates the resources' own `validation_errors()`; this file is the content
## freeze: shipped file -> expected numbers -> the scenes that consume them.

const PLAYER_ATTACK_PATH := "res://content/definitions/attack_player_basic.tres"
const ENEMY_ATTACK_PATH := "res://content/definitions/attack_enemy_basic.tres"
const ENEMY_PATH := "res://content/definitions/enemy_grunt.tres"
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"
const ENEMY_SCENE_PATH := "res://actors/enemies/enemy.tscn"

## The enemy's range gate the backpedal has to beat, computed from the resource.
const EXPECTED_ENEMY_GATE := 1.95


func _load_attack(path: String) -> AttackDefinition:
	var definition := load(path) as AttackDefinition
	assert_not_null(definition, "%s loads as AttackDefinition" % path)
	if definition != null:
		assert_true(
			definition.is_valid(),
			"%s passes its own validation: %s" % [path, definition.validation_errors()]
		)
	return definition


func _load_enemy() -> EnemyDefinition:
	var definition := load(ENEMY_PATH) as EnemyDefinition
	assert_not_null(definition, "%s loads as EnemyDefinition" % ENEMY_PATH)
	if definition != null:
		assert_true(
			definition.is_valid(),
			"%s passes its own validation: %s" % [ENEMY_PATH, definition.validation_errors()]
		)
	return definition


## The player's walk speed as shipped in the scene (the evasion budget comes from
## the rig, not from a test constant).
func _player_move_speed() -> float:
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	assert_not_null(packed, "%s loads" % PLAYER_SCENE_PATH)
	if packed == null:
		return -1.0
	var player := packed.instantiate() as PlayerController
	assert_not_null(player, "%s instantiates as PlayerController" % PLAYER_SCENE_PATH)
	if player == null:
		return -1.0
	var speed: float = player.move_speed
	player.free()
	return speed


# --- approved numbers ---------------------------------------------------------

func test_shipped_player_attack_matches_the_approved_numbers() -> void:
	var attack := _load_attack(PLAYER_ATTACK_PATH)
	if attack == null:
		return
	assert_eq(attack.id, &"attack.player.basic", "stable content id")
	assert_almost_eq(attack.damage, 34.0, 0.0001, "damage")
	assert_almost_eq(attack.reach, 2.0, 0.0001, "reach")
	assert_almost_eq(attack.hit_radius, 0.3, 0.0001, "hit_radius")
	assert_almost_eq(attack.hit_arc_degrees, 60.0, 0.0001, "frontal arc")
	assert_almost_eq(attack.windup, 0.22, 0.0001, "windup")
	assert_almost_eq(attack.active_window, 0.1, 0.0001, "active window")
	assert_almost_eq(attack.recovery, 0.38, 0.0001, "recovery")
	assert_almost_eq(attack.cooldown, 0.6, 0.0001, "cooldown")


func test_shipped_enemy_attack_matches_the_approved_numbers() -> void:
	var attack := _load_attack(ENEMY_ATTACK_PATH)
	if attack == null:
		return
	assert_eq(attack.id, &"attack.enemy.basic", "stable content id")
	assert_almost_eq(attack.damage, 12.0, 0.0001, "damage")
	assert_almost_eq(attack.reach, 1.7, 0.0001, "reach")
	assert_almost_eq(attack.hit_radius, 0.25, 0.0001, "hit_radius")
	assert_almost_eq(attack.hit_arc_degrees, 60.0, 0.0001, "frontal arc")
	assert_almost_eq(attack.windup, 0.7, 0.0001, "windup (the escape window)")
	assert_almost_eq(attack.active_window, 0.15, 0.0001, "active window")
	assert_almost_eq(attack.recovery, 0.9, 0.0001, "recovery")
	assert_almost_eq(attack.cooldown, 1.9, 0.0001, "cooldown")


func test_shipped_enemy_definition_matches_the_approved_numbers() -> void:
	var definition := _load_enemy()
	if definition == null:
		return
	assert_eq(definition.id, &"enemy.grunt", "stable content id")
	assert_almost_eq(definition.max_health, 100.0, 0.0001, "max health")
	assert_almost_eq(definition.move_speed, 3.2, 0.0001, "move speed")
	assert_almost_eq(definition.detection_radius, 12.0, 0.0001, "detection radius")
	assert_almost_eq(definition.lose_radius, 16.0, 0.0001, "lose radius")
	assert_almost_eq(definition.attack_range, 1.8, 0.0001, "attack range")
	assert_almost_eq(definition.stop_distance, 1.5, 0.0001, "stop distance")
	var enemy_attack := _load_attack(ENEMY_ATTACK_PATH)
	assert_eq(
		definition.attack_definition, enemy_attack, "the grunt hunts with attack_enemy_basic.tres"
	)
	assert_true(
		definition.stop_distance <= definition.attack_range,
		"the grunt stops inside the range where it can swing"
	)
	assert_true(
		definition.lose_radius >= definition.detection_radius,
		"detection and loss keep the hysteresis band non-negative"
	)


func test_shipped_scenes_load_the_shipped_definitions() -> void:
	## A content freeze is worthless if the scenes point somewhere else.
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBrain
	assert_not_null(player, "player scene instantiates")
	assert_not_null(enemy, "enemy scene instantiates")
	if player == null or enemy == null:
		return
	var player_attack := player.get_node(^"AttackController") as AttackController
	var enemy_attack := enemy.get_node(^"AttackController") as AttackController
	assert_eq(
		player_attack.definition,
		load(PLAYER_ATTACK_PATH),
		"the player rig uses content/definitions/attack_player_basic.tres"
	)
	assert_eq(
		enemy_attack.definition,
		load(ENEMY_ATTACK_PATH),
		"the enemy rig uses content/definitions/attack_enemy_basic.tres"
	)
	assert_eq(
		enemy.definition, load(ENEMY_PATH), "the enemy rig uses content/definitions/enemy_grunt.tres"
	)
	assert_almost_eq(
		(player.get_node(^"HealthComponent") as HealthComponent).max_health,
		100.0,
		0.0001,
		"the player rig's HP budget"
	)
	player.free()
	enemy.free()


# --- derived design arithmetic -------------------------------------------------

func test_evasion_arithmetic_holds_for_the_shipped_numbers() -> void:
	## AC-03's window, computed: the enemy gate is `reach + hit_radius`, and the
	## player's walk must leave it inside the telegraph windup.
	var enemy_attack := _load_attack(ENEMY_ATTACK_PATH)
	var definition := _load_enemy()
	if enemy_attack == null or definition == null:
		return
	var walk_speed := _player_move_speed()
	assert_true(walk_speed > 0.0, "the player rig ships a positive walk speed (%.2f m/s)" % walk_speed)

	var gate := MeleeRules.range_limit(enemy_attack.reach, enemy_attack.hit_radius)
	assert_almost_eq(gate, EXPECTED_ENEMY_GATE, 0.0001, "enemy gate = reach + hit_radius")

	var travel := walk_speed * enemy_attack.windup
	var margin := travel - gate
	assert_true(
		travel > gate,
		"the walk covers %.2f m during the %.2f s windup, clearing the %.2f m gate by %.2f m" % [
			travel, enemy_attack.windup, gate, margin
		]
	)
	var time_to_escape: float = gate / walk_speed
	assert_true(
		time_to_escape < enemy_attack.windup,
		"leaving the gate needs %.3f s of the %.2f s telegraph (%.0f%% of the window)" % [
			time_to_escape, enemy_attack.windup, 100.0 * time_to_escape / enemy_attack.windup
		]
	)
	# Counterfactual: if the grunt walked after the player during ATTACK instead of
	# planting its feet, the net gain inside the windup would be %.2f m - below the
	# gate, so force_stop is load-bearing (behaviourally proven in test B).
	var net_gain_if_pursuing := (walk_speed - definition.move_speed) * enemy_attack.windup
	assert_true(
		net_gain_if_pursuing < gate,
		"a pursuing grunt would only lose %.2f m in the windup (< gate %.2f m)" % [
			net_gain_if_pursuing, gate
		]
	)
	assert_true(
		walk_speed > definition.move_speed,
		"the player outruns the grunt (%.2f > %.2f m/s)" % [walk_speed, definition.move_speed]
	)
	assert_true(
		enemy_attack.windup > enemy_attack.active_window,
		"the telegraph is longer than the active window, so the tell is readable before the hit"
	)


func test_hits_to_kill_arithmetic_matches_the_shipped_numbers() -> void:
	## Derived from the resources, not restated: what the rig-level scenario E and
	## the death rules have to produce.
	var player_attack := _load_attack(PLAYER_ATTACK_PATH)
	var enemy_attack := _load_attack(ENEMY_ATTACK_PATH)
	var definition := _load_enemy()
	if player_attack == null or enemy_attack == null or definition == null:
		return

	var swings_to_kill_the_grunt: int = ceili(definition.max_health / player_attack.damage)
	assert_eq(swings_to_kill_the_grunt, 3, "the grunt dies in %d player swings" % swings_to_kill_the_grunt)
	var left_over_hp := definition.max_health - player_attack.damage * (swings_to_kill_the_grunt - 1)
	assert_almost_eq(left_over_hp, 32.0, 0.0001, "the killing blow only has %.1f HP left to remove" % left_over_hp)

	var hits_to_kill_the_player: int = ceili(100.0 / enemy_attack.damage)
	assert_eq(
		hits_to_kill_the_player, 9, "the player survives %d grunt hits before dying" % (hits_to_kill_the_player - 1)
	)
	assert_true(
		hits_to_kill_the_player > swings_to_kill_the_grunt,
		"the player's damage race is the shorter one (%d < %d)" % [
			swings_to_kill_the_grunt, hits_to_kill_the_player
		]
	)
