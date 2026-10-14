class_name EnemyFsm
extends RefCounted

## Pure, deterministic finite state machine for one enemy (ADR-006).
##
## `step()` is a pure function of (current state, world inputs, parameters): no
## SceneTree, no timers, no physics queries, no randomness. The owning
## `EnemyBrain` builds live `Inputs` every physics tick and applies the returned
## `Decision`. `AttackController` owns all attack timing, so this class never
## counts a windup down, never resolves a hit and never touches HP.
##
## Required transition table (first matching row wins):
##
## | From   | To     | Condition |
## |--------|--------|-----------|
## | any    | DEAD   | `not is_alive` (terminal, `force_stop = true`, never leaves DEAD) |
## | IDLE   | CHASE  | `has_target and distance <= detection_radius and has_line_of_sight` |
## | IDLE   | IDLE   | otherwise (`force_stop = true`) |
## | CHASE  | ATTACK | `distance <= attack_range and attack_ready and has_line_of_sight and has_target` |
## | CHASE  | IDLE   | `not has_target or distance > lose_radius` (`force_stop = true`) |
## | ATTACK | ATTACK | `attack_in_progress` |
## | ATTACK | CHASE  | attack finished and `has_target and distance <= lose_radius` |
## | ATTACK | IDLE   | `not has_target or distance > lose_radius` (`force_stop = true`) |
##
## Movement policy on the ATTACK rows: those rows also set `force_stop = true`,
## so a swinging enemy plants its feet for the whole windup. Without that, an
## enemy closing at `move_speed` would follow a backpedalling target and the
## escape window declared in `attack_enemy_basic.tres` would not exist.
##
## No cancellation: a target that retreats during the windup does not abort the
## swing. `attack_in_progress` stays true, so the FSM keeps reporting ATTACK and
## `AttackController` resolves the swing against live physics state at the hit
## frame; the retreating (or freed) target simply takes a miss.
##
## Preconditions (enforced by `EnemyDefinition`, not re-validated here):
## `lose_radius >= detection_radius` (the hysteresis band) and radii >= 0.
##
## `want_attack` is true only on the tick that enters ATTACK, so an adapter
## issues exactly one `request_attack()` per swing.

enum State { IDLE, CHASE, ATTACK, DEAD }


## Tuning read from `EnemyDefinition`; never mutated by the FSM.
class Params extends RefCounted:
	## Distance at which an idle enemy notices a target (metres).
	var detection_radius: float = 0.0

	## Distance beyond which a chasing enemy gives up; >= detection_radius (metres).
	var lose_radius: float = 0.0

	## Distance at which the enemy may start a swing (metres).
	var attack_range: float = 0.0

	## Builds params from static enemy data; the single mapping point for callers.
	static func from_definition(definition: EnemyDefinition) -> Params:
		var params := Params.new()
		if definition == null:
			return params
		params.detection_radius = definition.detection_radius
		params.lose_radius = definition.lose_radius
		params.attack_range = definition.attack_range
		return params


## What the world looks like this tick; written by the adapter, read-only here.
class Inputs extends RefCounted:
	## False when the target is missing, freed or dead.
	var has_target: bool = false

	## Horizontal distance to the target, centre to centre (metres).
	var distance: float = INF

	## True when a world-only ray from the enemy to the target's chest is clear.
	var has_line_of_sight: bool = false

	## `AttackController.can_attack()`.
	var attack_ready: bool = false

	## `AttackController.is_busy()`.
	var attack_in_progress: bool = false

	## The enemy's own life state (`HealthComponent.is_alive()`).
	var is_alive: bool = true


## What the adapter must do this tick.
class Decision extends RefCounted:
	## State to be in after this tick.
	var next: State = State.IDLE

	## True only on the tick that enters ATTACK.
	var want_attack: bool = false

	## True when the enemy must not move this tick.
	var force_stop: bool = false


## Returns the decision for one tick. Never mutates `current`, `inputs` or `params`.
static func step(current: State, inputs: Inputs, params: Params) -> Decision:
	var decision := Decision.new()
	decision.next = current
	if inputs == null or params == null:
		decision.force_stop = true
		return decision

	# any -> DEAD: health is the authority and DEAD is terminal.
	if not inputs.is_alive:
		decision.next = State.DEAD
		decision.force_stop = true
		return decision
	if current == State.DEAD:
		decision.next = State.DEAD
		decision.force_stop = true
		return decision

	match current:
		State.IDLE:
			if (
				inputs.has_target
				and inputs.has_line_of_sight
				and inputs.distance <= params.detection_radius
			):
				decision.next = State.CHASE
				return decision
			decision.next = State.IDLE
			decision.force_stop = true
			return decision

		State.CHASE:
			if (
				inputs.has_target
				and inputs.has_line_of_sight
				and inputs.attack_ready
				and inputs.distance <= params.attack_range
			):
				decision.next = State.ATTACK
				decision.want_attack = true
				decision.force_stop = true
				return decision
			if not inputs.has_target or inputs.distance > params.lose_radius:
				decision.next = State.IDLE
				decision.force_stop = true
				return decision
			decision.next = State.CHASE
			return decision

		State.ATTACK:
			if not inputs.has_target or inputs.distance > params.lose_radius:
				# Target lost: stop, but never cancel the in-flight swing.
				decision.next = State.IDLE
				decision.force_stop = true
				return decision
			if inputs.attack_in_progress:
				decision.next = State.ATTACK
				decision.force_stop = true
				return decision
			decision.next = State.CHASE
			return decision

	return decision


## Human-readable state name for logs, the future HUD and test messages.
static func state_name(state: State) -> StringName:
	match state:
		State.IDLE:
			return &"idle"
		State.CHASE:
			return &"chase"
		State.ATTACK:
			return &"attack"
		State.DEAD:
			return &"dead"
	return &"unknown"
