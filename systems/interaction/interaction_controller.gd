class_name InteractionController
extends Node3D

## Turns "walk up and press E" into exactly one resolved interaction per physics
## tick (ADR-008).
##
## Responsibilities:
## - Cast one ray per physics tick from `view` along the view direction, over the
##   `world | interactable` layers. Walls therefore occlude by construction: the
##   first hit decides, and only an `Interactable` that `can_interact()` becomes
##   the focus - a disabled, used or blocked interactable yields *no* focus rather
##   than being looked through.
## - Publish the focus and the prompt as signals (`focus_changed`,
##   `prompt_changed`); it owns no UI, no text drawing and no state beyond the
##   cached focus/prompt.
## - Handle the `interact` action in `_unhandled_input`: every event of a frame
##   collapses into one pending request, which the next physics tick resolves
##   against that tick's ray. Two presses in one frame are one action, a key echo
##   is none, and a signal handler re-entering `try_interact()` in the same physics
##   frame is refused.
##
## Invariants:
## - Synchronous: no `await` anywhere; `try_interact()` returns the interactable's
##   own result unchanged (`null` is normalised to `unavailable`).
## - An interaction always resolves against the ray of one single tick
##   (`current_focus()` is that tick's hit), never against a stale focus.
## - A dead interactor (`HealthComponent.find_on(interactor)` reports not alive)
##   has no focus and cannot interact. An interactor without a `HealthComponent` is
##   treated as alive: the missing component is not evidence of death.
## - `interaction_resolved` fires once per attempt that reached an interactable,
##   including the interactable's own refusals; it stays silent when there was
##   nothing to act on. `interaction_completed` (on the interactable) is the
##   success-only channel.
## - `systems/interaction/**` never imports `world/**`: world services arrive as
##   `Callable`s or through the subclasses' binding hooks.
##
## Node contract: a direct child of the actor named "InteractionController"
## (`NODE_NAME`), exactly like `HealthComponent` (ADR-005), so the lookup lives in
## one place (`find_on`). `view` is the eye (the player camera), `interactor` the
## actor that performs the action.

## The focus changed (a new interactable, or null when nothing is in reach).
signal focus_changed(interactable: Interactable)

## The prompt to show, or that it must be hidden. Emitted only when the text or
## the visibility actually changes.
signal prompt_changed(prompt: String, visible: bool)

## One attempt reached an interactable and produced a result.
signal interaction_resolved(result: InteractionResult)

## Required child node name for an actor that can interact (ADR-008).
const NODE_NAME: String = "InteractionController"

## Ray origin and orientation; the player camera. Its `-Z` is "forward".
@export var view: Node3D = null

## The actor that performs the interaction (the rig whose `HealthComponent`
## decides whether it may act at all).
@export var interactor: Node3D = null

## Ray length in metres.
@export var reach: float = 2.5

var _focus: Interactable = null
var _prompt_text: String = ""
var _prompt_visible: bool = false
var _pending_interact: bool = false
var _last_interaction_frame: int = -1

## UI focus lock (ADR-008): while false, focus is cleared and `interact` is ignored.
## The selection panel owns it; gameplay code never needs to.
var _enabled: bool = true


## Suspends or resumes interaction (a UI panel owns the screen). Clears the focus when
## suspended so a stale prompt cannot stay visible behind the panel.
func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	_pending_interact = false
	if not enabled:
		_clear_focus()


func is_enabled() -> bool:
	return _enabled


## Drops the current focus and republishes the (hidden) prompt.
func _clear_focus() -> void:
	if _focus == null:
		return
	_focus = null
	focus_changed.emit(null)
	_sync_prompt()


## Finds the interaction controller of an actor, or null when the scene breaks the
## node contract. Mirrors `HealthComponent.find_on()`: direct child, by name.
static func find_on(actor: Node) -> InteractionController:
	if actor == null:
		return null
	var node := actor.get_node_or_null(NODE_NAME)
	if node is InteractionController:
		return node as InteractionController
	return null


## The interactable the last physics tick's ray hit, or null. Never returns a
## freed instance (a consumed pickup drops out of the focus on the next tick).
func current_focus() -> Interactable:
	if _focus != null and not is_instance_valid(_focus):
		return null
	return _focus


## Resolves the pending action against the current focus and publishes the result.
##
## Returns `unavailable` (without emitting anything) when there is no focus, when
## the interactor cannot act, or when an interaction was already resolved in this
## physics frame. Safe to call from a signal handler.
func try_interact() -> InteractionResult:
	if not _enabled:
		return InteractionResult.unavailable()
	if not _can_act():
		return InteractionResult.unavailable()
	var focus := current_focus()
	if focus == null:
		return InteractionResult.unavailable()

	var frame := Engine.get_physics_frames()
	if frame == _last_interaction_frame:
		# At most one interaction per physics frame (ADR-008): a repeated event, a
		# second handler or a direct call cannot double-fire.
		return InteractionResult.unavailable()
	_last_interaction_frame = frame

	var result: InteractionResult = focus.interact(interactor)
	if result == null:
		result = InteractionResult.unavailable()
	interaction_resolved.emit(result)
	return result


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if not event.is_action_pressed(&"interact"):
		return
	# Coalesce every `interact` event of this frame into one request; the physics
	# tick below consumes it exactly once.
	_pending_interact = true
	if is_inside_tree():
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _physics_process(_delta: float) -> void:
	_update_focus()
	if _pending_interact:
		_pending_interact = false
		try_interact()


## Casts the tick's ray, publishes focus/prompt changes. Called once per physics
## tick (never from `try_interact`, so an action cannot see a second ray).
func _update_focus() -> void:
	var found: Interactable = _probe()
	if found != _focus:
		_focus = found
		focus_changed.emit(found)
	_sync_prompt()


func _probe() -> Interactable:
	if not _enabled:
		return null
	if not _can_act():
		return null
	if view == null or not is_instance_valid(view) or not view.is_inside_tree():
		return null
	var world := view.get_world_3d()
	if world == null:
		return null
	var space := world.direct_space_state
	if space == null:
		return null

	var length := maxf(reach, 0.0)
	if length <= 0.0:
		return null
	var origin := view.global_position
	var forward := -view.global_basis.z
	if forward.length_squared() <= 0.0:
		return null

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward.normalized() * length,
		PhysicsLayers.WORLD | PhysicsLayers.INTERACTABLE
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_from_inside = false

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Variant = hit.get("collider", null)
	if collider is Interactable:
		var interactable := collider as Interactable
		if interactable.can_interact():
			return interactable
	return null


func _sync_prompt() -> void:
	var text := ""
	var visible := false
	var focus := current_focus()
	if focus != null:
		text = focus.prompt
		visible = true
	if text == _prompt_text and visible == _prompt_visible:
		return
	_prompt_text = text
	_prompt_visible = visible
	prompt_changed.emit(text, visible)


## True when the interactor is bound and alive. Missing `HealthComponent` means
## "not proven dead", not "dead".
func _can_act() -> bool:
	if interactor == null or not is_instance_valid(interactor):
		return false
	var health := HealthComponent.find_on(interactor)
	if health == null:
		return true
	return health.is_alive()


func _to_string() -> String:
	return "InteractionController(focus=%s, reach=%.2f)" % [_focus, reach]
