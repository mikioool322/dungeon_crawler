class_name PlayerViewModel
extends Node3D

## Presentation-only placeholder weapon rig for the first-person camera (W3).
##
## Invariant: this node is decoration. It never calls `request_attack()`, never
## reads an `AttackDefinition`, and never writes gameplay state. Deleting it (or
## its whole camera branch) must leave combat behaviour identical: phase, timing,
## cooldown, range and damage stay owned by `AttackController`.
##
## Reaction only: it listens to `AttackController.phase_changed` and lerps a
## small local offset (plus a small rotation) in `_process`. There is no
## animation pipeline in Sprint 01 (ADR-004), so the pose must never become a
## source of attack timing.

## Attack source whose phases drive the pose. Assigned in `player.tscn`.
@export var attack_controller: AttackController

## Local offset in camera space while the attack winds up (pull back).
@export var windup_offset: Vector3 = Vector3(-0.04, 0.06, 0.14)

## Local offset in camera space on the active hit window (thrust forward).
@export var active_offset: Vector3 = Vector3(0.02, -0.06, -0.26)

## Local offset in camera space while recovering (ease back to the rest pose).
@export var recovery_offset: Vector3 = Vector3(-0.01, 0.0, -0.06)

## Pose smoothing rate in e-folds per second. A constant on purpose: the pose can
## never feed back into attack timing.
const POSE_LERP_RATE: float = 12.0

## Extra rotation per phase, in degrees. Placeholder feedback only.
const WINDUP_ROTATION_DEGREES: Vector3 = Vector3(-10.0, 5.0, 0.0)
const ACTIVE_ROTATION_DEGREES: Vector3 = Vector3(9.0, -5.0, 0.0)
const RECOVERY_ROTATION_DEGREES: Vector3 = Vector3(3.0, 0.0, 0.0)

var _rest_position: Vector3 = Vector3.ZERO
var _rest_rotation: Vector3 = Vector3.ZERO
var _target_offset: Vector3 = Vector3.ZERO
var _target_rotation: Vector3 = Vector3.ZERO


func _ready() -> void:
	_rest_position = position
	_rest_rotation = rotation
	if attack_controller != null:
		attack_controller.phase_changed.connect(_on_phase_changed)
		_apply_phase(attack_controller.phase)


func _process(delta: float) -> void:
	# Frame-rate independent smoothing; never an authoritative timer.
	var weight: float = 1.0 - exp(-POSE_LERP_RATE * delta)
	position = position.lerp(_rest_position + _target_offset, weight)
	rotation = rotation.lerp(_rest_rotation + _target_rotation, weight)


func _on_phase_changed(phase: AttackController.Phase) -> void:
	_apply_phase(phase)


func _apply_phase(phase: AttackController.Phase) -> void:
	match phase:
		AttackController.Phase.WINDUP:
			_target_offset = windup_offset
			_target_rotation = _degrees_to_radians(WINDUP_ROTATION_DEGREES)
		AttackController.Phase.ACTIVE:
			_target_offset = active_offset
			_target_rotation = _degrees_to_radians(ACTIVE_ROTATION_DEGREES)
		AttackController.Phase.RECOVERY:
			_target_offset = recovery_offset
			_target_rotation = _degrees_to_radians(RECOVERY_ROTATION_DEGREES)
		_:
			_target_offset = Vector3.ZERO
			_target_rotation = Vector3.ZERO


static func _degrees_to_radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
