class_name EnemyBrain
extends CharacterBody3D

## Runtime adapter between the pure `EnemyFsm` and the scene (ADR-001, ADR-006).
##
## Ownership: this node owns the FSM state and `velocity`. `HealthComponent` owns
## HP and `AttackController` owns attack phase and cooldown. No transition rule,
## attack timing, reach or damage rule is repeated here: `_physics_process` reads
## live state into `EnemyFsm.Inputs`, asks `EnemyFsm.step()` and applies the
## returned `Decision`.
##
## Damage leaves this actor only through its own `AttackController`/`HitDetector`
## chain; the brain never resolves or touches another actor's health.
##
## Death consequences belong to the owning actor (ADR-001): abort the in-flight
## swing, stop dead, turn the placeholder body grey and never attack again.
##
## The material changes below are presentation only: disabling them changes
## nothing about the FSM, the attack timing or the damage outcome.
##
## Missing or freed targets are handled every tick without errors: the FSM
## receives `has_target = false` and returns to IDLE.

## Emitted on every FSM state change; values are `EnemyFsm.State`.
signal state_changed(previous: int, next: int)

## Emitted exactly once per life when this placement carries a reward (ADR-009).
## The world host turns it into a drop; combat never touches inventory.
signal defeated(reward: RewardDefinition, loot_source_id: StringName, at: Vector3)

## Downward acceleration for the placeholder body (flat greybox arenas).
const GRAVITY: float = 9.8

## Yaw alignment speed while a target exists, in radians per second.
const TURN_SPEED: float = 12.0

## Height above the target's origin at which line of sight is tested (metres).
const LINE_OF_SIGHT_PROBE_HEIGHT: float = 1.0

## Duration of the damage flash in seconds.
const DAMAGE_FLASH_TIME: float = 0.12

## Warm windup telegraph; ACTIVE is brighter, death desaturated grey.
const TELEGRAPH_WINDUP_COLOR: Color = Color(0.95, 0.45, 0.12)
const TELEGRAPH_ACTIVE_COLOR: Color = Color(1.0, 0.85, 0.25)
const TELEGRAPH_DAMAGED_COLOR: Color = Color(1.0, 0.35, 0.35)
const TELEGRAPH_DEAD_COLOR: Color = Color(0.35, 0.35, 0.36)

## Static data for this enemy; drives HP, movement, ranges and the attack.
@export var definition: EnemyDefinition

## Optional scene path to the hunted actor; `set_target()` overrides it.
@export var target_path: NodePath

## Stable per-placement loot source id (e.g. `enemy.a`). Together with the world id
## it forms the reward key, so a drop is claimable exactly once (ADR-009). Never a
## node name or display name.
@export var loot_source_id: StringName = &""

## Optional completion objective this placement satisfies when it dies (ADR-012).
## Empty means "ordinary enemy": its death never completes a dungeon. The world host
## reads this from `HealthComponent.died`, so an objective enemy without a loot reward
## still reports (the `defeated` signal is reward-gated).
@export var objective_id: StringName = &""

## Current FSM state, exposed for tests and the future HUD.
var fsm_state: EnemyFsm.State = EnemyFsm.State.IDLE

var _params: EnemyFsm.Params = EnemyFsm.Params.new()
var _target: Node3D = null
var _alive: bool = true
var _defeat_reported: bool = false

var _material: StandardMaterial3D = null
var _base_albedo: Color = Color(0.35, 0.30, 0.32)
var _flash_remaining: float = 0.0

@onready var _health: HealthComponent = get_node_or_null(^"HealthComponent") as HealthComponent
@onready var _attack: AttackController = get_node_or_null(^"AttackController") as AttackController
@onready var _body: MeshInstance3D = get_node_or_null(^"Body") as MeshInstance3D
@onready var _muzzle: Node3D = get_node_or_null(^"Muzzle") as Node3D


func _ready() -> void:
	_params = EnemyFsm.Params.from_definition(definition)
	# Death consequences are wired unconditionally: an enemy must never end up
	# damageable but unable to die just because its definition is missing/invalid.
	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	if definition != null and definition.is_valid():
		if _health != null:
			_health.max_health = definition.max_health
			_health.actor_id = definition.id
			_health.reset()
	else:
		push_warning("EnemyBrain %s: missing or invalid EnemyDefinition; the enemy stays inert" % name)
	if _attack != null:
		_attack.phase_changed.connect(_on_attack_phase_changed)
	_configure_telegraph_material()
	_resolve_target()
	_refresh_telegraph()


## Wires the actor this brain hunts; the arena calls this after spawning.
func set_target(node: Node3D) -> void:
	_target = node


func _physics_process(delta: float) -> void:
	_tick_damage_flash(delta)
	if not _alive:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if definition == null or not definition.is_valid():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var target := _resolve_target()
	var inputs := _build_inputs(target)
	var decision := EnemyFsm.step(fsm_state, inputs, _params)
	_set_state(decision.next)
	if decision.want_attack and _attack != null:
		_attack.request_attack()
	_apply_movement(delta, target, inputs.distance, decision)


# --- FSM adapter -------------------------------------------------------------

func _build_inputs(target: Node3D) -> EnemyFsm.Inputs:
	var inputs := EnemyFsm.Inputs.new()
	inputs.is_alive = _alive
	inputs.has_target = target != null
	if target == null:
		return inputs
	inputs.distance = MeleeRules.horizontal_distance(global_position, target.global_position)
	inputs.has_line_of_sight = _has_line_of_sight(target)
	inputs.attack_ready = _attack != null and _attack.can_attack()
	inputs.attack_in_progress = _attack != null and _attack.is_busy()
	return inputs


func _set_state(next: EnemyFsm.State) -> void:
	if next == fsm_state:
		return
	var previous: EnemyFsm.State = fsm_state
	fsm_state = next
	state_changed.emit(previous, next)


func _apply_movement(
	delta: float, target: Node3D, distance: float, decision: EnemyFsm.Decision
) -> void:
	var horizontal := Vector3.ZERO
	if target != null:
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			var direction := to_target.normalized()
			_face_direction(direction, delta)
			if not decision.force_stop and distance > definition.stop_distance:
				horizontal = direction * definition.move_speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


## Yaws towards a normalised horizontal direction at `TURN_SPEED`.
func _face_direction(direction: Vector3, delta: float) -> void:
	var desired_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))


func _resolve_target() -> Node3D:
	if is_instance_valid(_target):
		return _usable_target(_target)
	_target = null
	if target_path != NodePath() and is_inside_tree():
		var node := get_node_or_null(target_path)
		if node is Node3D:
			_target = node as Node3D
			return _usable_target(_target)
	return null


## A target counts only while it is in the tree and alive (if it owns HP).
func _usable_target(target: Node3D) -> Node3D:
	if target == null or not target.is_inside_tree():
		return null
	var health := HealthComponent.find_on(target)
	if health != null and not health.is_alive():
		return null
	return target


func _has_line_of_sight(target: Node3D) -> bool:
	if _muzzle == null or not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from: Vector3 = _muzzle.global_position
	var to: Vector3 = target.global_position + Vector3.UP * LINE_OF_SIGHT_PROBE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(
		from, to, PhysicsLayers.WORLD, [get_rid()]
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.hit_from_inside = false
	return space.intersect_ray(query).is_empty()


# --- presentation (telegraph) ------------------------------------------------

func _configure_telegraph_material() -> void:
	if _body == null:
		return
	var base: StandardMaterial3D = null
	if definition != null:
		base = definition.body_material
	if base == null:
		var surface := _body.get_active_material(0)
		if surface is StandardMaterial3D:
			base = surface as StandardMaterial3D
	if base == null:
		base = StandardMaterial3D.new()
	# Never mutate a shared resource: each instance owns its own copy.
	_material = base.duplicate() as StandardMaterial3D
	_base_albedo = _material.albedo_color
	_body.material_override = _material


func _tick_damage_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	_refresh_telegraph()


func _refresh_telegraph() -> void:
	if _material == null:
		return
	var colour: Color = _base_albedo
	var emission: Color = Color.BLACK
	if not _alive:
		colour = TELEGRAPH_DEAD_COLOR
	elif _flash_remaining > 0.0:
		colour = TELEGRAPH_DAMAGED_COLOR
		emission = TELEGRAPH_DAMAGED_COLOR * 0.6
	elif _attack != null:
		match _attack.phase:
			AttackController.Phase.WINDUP:
				colour = TELEGRAPH_WINDUP_COLOR
				emission = TELEGRAPH_WINDUP_COLOR * 0.6
			AttackController.Phase.ACTIVE:
				colour = TELEGRAPH_ACTIVE_COLOR
				emission = TELEGRAPH_ACTIVE_COLOR
	_material.albedo_color = colour
	_material.emission_enabled = emission != Color.BLACK
	_material.emission = emission


# --- combat signals ----------------------------------------------------------

func _on_attack_phase_changed(_phase: int) -> void:
	if not _alive:
		return
	_refresh_telegraph()


func _on_damaged(_request: DamageRequest, _result: DamageResult) -> void:
	if not _alive:
		return
	_flash_remaining = DAMAGE_FLASH_TIME
	_refresh_telegraph()


func _on_died(_request: DamageRequest) -> void:
	_alive = false
	_flash_remaining = 0.0
	if _attack != null:
		_attack.abort(&"dead")
	velocity = Vector3.ZERO
	_set_state(EnemyFsm.State.DEAD)
	_refresh_telegraph()
	_report_defeat()


## Reports this placement's drop exactly once per life (ADR-009). Silent when the
## archetype has no reward or the placement carries no loot source id.
func _report_defeat() -> void:
	if _defeat_reported:
		return
	if definition == null or definition.reward == null or loot_source_id == &"":
		return
	_defeat_reported = true
	defeated.emit(definition.reward, loot_source_id, global_position)
