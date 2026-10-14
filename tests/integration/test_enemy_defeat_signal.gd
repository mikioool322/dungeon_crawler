extends "res://tests/test_case.gd"

## W3 seam: an enemy reports its drop exactly once per life, and only when the
## archetype carries a reward and the placement carries a loot source id (ADR-009).

const ENEMY_SCENE_PATH := "res://actors/enemies/enemy.tscn"

var _world: Node3D = null
var _enemy: EnemyBrain = null
var _events: Array = []


func teardown() -> void:
	_world = null
	_enemy = null
	_events.clear()


func _spawn_enemy(loot_source_id: StringName) -> void:
	_world = Node3D.new()
	_world.name = &"DefeatWorld"
	add_to_tree(_world)
	var scene := load(ENEMY_SCENE_PATH) as PackedScene
	assert_not_null(scene, "the enemy scene loads")
	if scene == null:
		return
	_enemy = scene.instantiate() as EnemyBrain
	_enemy.loot_source_id = loot_source_id
	_world.add_child(_enemy)
	_enemy.defeated.connect(
		func(reward: RewardDefinition, source: StringName, at: Vector3) -> void:
			_events.append({"reward": reward, "source": source, "at": at})
	)
	await wait_physics_frames(2)


func _kill() -> void:
	var health := HealthComponent.find_on(_enemy)
	assert_not_null(health, "the enemy owns a HealthComponent")
	if health == null:
		return
	health.apply_damage(
		DamageRequest.new(&"test.lethal", &"test.runner", health.max_health, Vector3.ZERO, Vector3.UP)
	)


func test_shipped_enemy_reports_its_drop_once() -> void:
	await _spawn_enemy(&"enemy.a")
	assert_true(_enemy.definition.is_valid(), "the shipped grunt definition (with its reward) is valid")
	_kill()
	assert_eq(_events.size(), 1, "exactly one defeat report per life")
	if _events.size() == 1:
		var event: Dictionary = _events[0]
		var reward: RewardDefinition = event["reward"]
		assert_not_null(reward, "the report carries a reward definition")
		if reward != null:
			assert_eq(reward.id, &"reward.grunt_drop", "the shipped reward is used")
			assert_eq(reward.gold, 3, "the drop is the authored payload")
		assert_eq(event["source"], &"enemy.a", "the placement's loot source id is reported")
		assert_eq(event["at"], _enemy.global_position, "the drop position is the corpse position")


func test_a_second_lethal_hit_does_not_report_again() -> void:
	await _spawn_enemy(&"enemy.a")
	_kill()
	_kill()
	await wait_physics_frames(2)
	assert_eq(_events.size(), 1, "a corpse never reports a second drop")


func test_placement_without_a_loot_source_id_reports_nothing() -> void:
	await _spawn_enemy(&"")
	_kill()
	assert_eq(_events.size(), 0, "a placement without a loot source id cannot be claimed (ADR-009)")


func test_archetype_without_a_reward_reports_nothing() -> void:
	await _spawn_enemy(&"enemy.a")
	var bare := EnemyDefinition.new()
	bare.id = &"enemy.test_bare"
	bare.max_health = 10.0
	bare.attack_definition = _enemy.definition.attack_definition
	_enemy.definition = bare
	_kill()
	assert_eq(_events.size(), 0, "an archetype without a reward drops nothing")


func test_death_still_stops_the_enemy_when_a_drop_is_reported() -> void:
	await _spawn_enemy(&"enemy.a")
	_kill()
	await wait_physics_frames(30)
	assert_eq(_enemy.fsm_state, EnemyFsm.State.DEAD, "the enemy is dead")
	assert_true(_enemy.velocity.length() < 0.05, "and stopped: the drop does not change death behaviour")
