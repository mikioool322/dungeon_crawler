class_name ArenaDebugHud
extends CanvasLayer

## Minimal Sprint 01 debug overlay (presentation only).
##
## Purpose: make the sprint's manual acceptance checks observable — enemy HP,
## enemy FSM state and attack phase (telegraph readability) and player HP (whether
## a hit landed). It only reads state; removing this node changes no game rule.
##
## Values are polled every frame: the HUD must never be the source of truth for
## gameplay state, so it keeps no copy of it.

@export var player_hp_label: Label
@export var enemy_status_label: Label
@export var hint_label: Label

const HINT_TEXT := "WASD move | mouse look | left click attack | backpedal to dodge | Esc release mouse | R restart"

var _player: Node = null
var _enemy: Node = null


## Called by the arena after spawning; both arguments may be null in tests.
func bind(player: Node, enemy: Node) -> void:
	_player = player
	_enemy = enemy
	if hint_label != null:
		hint_label.text = HINT_TEXT


func _process(_delta: float) -> void:
	if player_hp_label != null:
		player_hp_label.text = _player_status()
	if enemy_status_label != null:
		enemy_status_label.text = _enemy_status()


func _player_status() -> String:
	if not is_instance_valid(_player):
		return "Player: n/a"
	var health := _health_of(_player)
	if health == null:
		return "Player: n/a"
	if not health.is_alive():
		return "Player: DEAD  (press R to restart)"
	return "Player HP: %d / %d" % [roundi(health.current_health), roundi(health.max_health)]


func _enemy_status() -> String:
	if not is_instance_valid(_enemy):
		return "Enemy: n/a"
	var health := _health_of(_enemy)
	var attack := _enemy.get_node_or_null("AttackController") as AttackController
	var parts := PackedStringArray()
	if health != null:
		parts.append("HP %d / %d" % [roundi(health.current_health), roundi(health.max_health)])
	else:
		parts.append("HP n/a")
	if "fsm_state" in _enemy:
		parts.append("state %s" % EnemyFsm.state_name(_enemy.fsm_state))
	if attack != null:
		parts.append("attack %s" % attack.phase_name())
	return "Enemy: %s" % " | ".join(parts)


func _health_of(node: Node) -> HealthComponent:
	return HealthComponent.find_on(node)
