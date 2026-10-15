class_name PlayerController
extends CharacterBody3D

## First-person player rig: mouse look, WASD walking and backpedal evasion (W3).
##
## Invariants:
## - Owns its own transform and camera pitch only (ADR-001). Attack phase,
##   cooldown, range and damage belong to `AttackController`; HP belongs to
##   `HealthComponent`.
## - Attacks never lock movement. Walking backwards out of an enemy's reach is
##   the sprint's only evasion mechanic (ADR-003), so it has to stay available
##   while a swing is in progress.
## - No jump, dash, block, parry or magic.
## - Death freezes input and aborts the swing; restarting is the arena's job.
##
## Scene contract (ADR-005): a direct child named "HealthComponent" is required,
## with `AttackController` and `HitDetector` as siblings.

## Horizontal walk speed in metres per second.
@export var move_speed: float = 4.0

## Mouse look sensitivity in radians per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0025

## Maximum camera pitch in degrees away from the horizon (both directions).
@export var pitch_limit_degrees: float = 89.0

## Downward acceleration in metres per second squared.
@export var gravity: float = 9.8

## True once `HealthComponent.died` fired: all input is ignored from then on.
var is_dead: bool = false

## True while mouse motion drives the look and a click attacks. Only this flag
## changes in a headless run: `Input.mouse_mode` is never touched without a real
## display server, so tests can exercise look input directly.
var mouse_captured: bool = false:
	set(value):
		mouse_captured = value
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

@onready var head: Node3D = $Head
@onready var health_component: HealthComponent = $HealthComponent
@onready var attack_controller: AttackController = $AttackController

var _pitch: float = 0.0

## False while a UI panel owns the screen; look, move and attack input are ignored
## until `set_input_enabled(true)` restores them.
var _input_enabled: bool = true


func _ready() -> void:
	if health_component != null:
		health_component.died.connect(_on_health_died)
	# Capture the cursor only in a real session (ADR-006 keeps tests headless).
	if DisplayServer.get_name() != "headless":
		mouse_captured = true


## Blocks look/move/attack input while a UI panel owns the screen (ADR-008 UI focus).
## Gravity, the mouse-capture flag and the `is_dead` lockout stay untouched.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventMouseMotion:
		if mouse_captured and _input_enabled:
			_look((event as InputEventMouseMotion).relative)
		return
	if event.is_action_pressed(&"ui_cancel"):
		mouse_captured = false
		return
	if not _input_enabled:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		# A click after `ui_cancel` brings the cursor back to the game instead of
		# attacking. Headless runs have no cursor to re-capture, so the click
		# stays an attack there.
		if not mouse_captured and DisplayServer.get_name() != "headless":
			mouse_captured = true
			return
	if event.is_action_pressed(&"attack_primary"):
		if attack_controller != null:
			attack_controller.request_attack()


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	# Movement input is never gated on the attack phase: backpedalling out of an
	# enemy's reach must work mid-swing; death and an open UI panel are the only
	# input lockouts.
	var direction: Vector3 = Vector3.ZERO if is_dead or not _input_enabled else _movement_direction()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()


## Yaw on the body, pitch on the head, both in radians (ADR-001).
func _look(relative_pixels: Vector2) -> void:
	rotate_y(-relative_pixels.x * mouse_sensitivity)
	var limit: float = deg_to_rad(pitch_limit_degrees)
	_pitch = clampf(_pitch - relative_pixels.y * mouse_sensitivity, -limit, limit)
	if head != null:
		head.rotation.x = _pitch


## Horizontal movement direction in world space, built from the body's yaw basis.
func _movement_direction() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var yaw_basis := global_transform.basis
	var direction: Vector3 = yaw_basis.x * input.x + yaw_basis.z * input.y
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction


func _on_health_died(_request: DamageRequest) -> void:
	is_dead = true
	velocity = Vector3.ZERO
	if attack_controller != null:
		attack_controller.abort(&"dead")
	print(
		"[PlayerController] %s died; input frozen, swing aborted (the arena owns the restart)."
		% _actor_label()
	)


func _actor_label() -> String:
	if health_component != null:
		return String(health_component.target_id())
	return name
