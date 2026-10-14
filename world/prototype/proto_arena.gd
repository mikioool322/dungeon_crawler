class_name ProtoArena
extends Node3D

## Sprint 01 greybox arena controller (world orchestration layer, ADR-003).
##
## Responsibilities and limits:
## - Wires the encounter: connects the enemy brain to the player actor.
## - Binds the debug HUD to both actors.
## - Offers a manual restart so the fight can be repeated (there is no save system
##   in Sprint 01 and player death freezes input by design).
## - It never decides damage, attack phase or AI transitions: those belong to
##   `AttackController`, `HealthComponent` and `EnemyBrain`.

## Physical key used to restart the encounter (debug affordance, intentionally not
## part of the closed InputMap contract in ADR-005).
const RESTART_KEY: Key = KEY_R

@export var player_path: NodePath
@export var enemy_path: NodePath
@export var hud_path: NodePath

var _player: Node3D = null
var _enemy: Node = null


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_enemy = get_node_or_null(enemy_path)
	var hud := get_node_or_null(hud_path) as ArenaDebugHud
	if _enemy != null and _player != null and _enemy.has_method("set_target"):
		_enemy.call("set_target", _player)
	if hud != null:
		hud.bind(_player, _enemy)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == RESTART_KEY:
			_restart()


## Reloads the arena: the only "reset" in Sprint 01 (ADR-003).
func _restart() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.reload_current_scene()
