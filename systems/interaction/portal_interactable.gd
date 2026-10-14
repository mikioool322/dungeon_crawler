class_name PortalInteractable
extends Interactable

## A walk-up-and-use world portal (ADR-008). It carries only *destination ids* and
## a travel `Callable`; coordinates, scene paths, the router and `world/**` stay
## outside this module. The world host injects
## `WorldRouter.request_travel` at `_ready`.
##
## Invariants:
## - The portal never decides travel: it validates its own destination ids, then
##   calls `travel_provider.call(target_world_id, target_spawn_id)` and reports the
##   router's code.
## - An incomplete destination (empty world or spawn id) or a missing provider is
##   refused as `invalid_destination` *before* the provider runs: a broken portal
##   must not start a travel that cannot resolve a spawn.
## - Result mapping (see `InteractionResult` for the vocabulary):
##   - `&"travel_started"` -> `ok("travel_started")`: a success whose display text
##     is the router code. A success code other than `InteractionResult.OK` would
##     make `succeeded()` report a failure, so the code travels as the message.
##   - every other router code (`busy`, `unknown_world`, `invalid_world`,
##     `invalid_spawn`, ...) -> `rejected(<code>)` with the code verbatim, so a
##     caller can branch on it without parsing text.
##   - a provider that returns nothing usable (not a `StringName`/`String`, e.g. a
##     `Callable` bound to a method whose signature lost its return value) ->
##     `unavailable()`, because no router decision can be reported.
## - The portal is reusable (`one_shot` stays false): travelling twice is legal,
##   the router's own single-flight guard (`busy`) is what refuses a re-entry.

## Stable content id of the destination world, e.g. `world.dungeon.proto01`.
@export var target_world_id: StringName = &""

## Stable spawn id inside the destination world, e.g. `spawn.dungeon.entry`.
## Never a coordinate and never an empty "default" - `WorldRouter` owns fallbacks.
@export var target_spawn_id: StringName = &""

## Injected destination router, normally `WorldRouter.request_travel`. Prefer
## `set_travel_provider()`; the field is public for scene/host compatibility.
var travel_provider: Callable = Callable()


## Binds the router. Passing an invalid `Callable()` clears the binding.
func set_travel_provider(travel: Callable) -> void:
	travel_provider = travel


## True when a router is bound (the destination ids are validated separately).
func has_travel_provider() -> bool:
	return travel_provider.is_valid()


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	if target_world_id == &"" or target_spawn_id == &"":
		return InteractionResult.rejected(
			&"invalid_destination",
			"This portal has no destination."
		)
	if not has_travel_provider():
		return InteractionResult.rejected(
			&"invalid_destination",
			"This portal is not connected to a world."
		)

	var code: Variant = travel_provider.call(target_world_id, target_spawn_id)
	if not (code is StringName or code is String):
		return InteractionResult.unavailable()
	var router_code := StringName(str(code))
	if router_code == &"travel_started":
		return InteractionResult.ok(String(router_code))
	return InteractionResult.rejected(router_code, String(router_code))


func _to_string() -> String:
	return "PortalInteractable(%s -> %s/%s, provider=%s)" % [
		name, target_world_id, target_spawn_id, has_travel_provider()
	]
