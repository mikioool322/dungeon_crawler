extends "res://tests/test_case.gd"

## W2 unit contract for the portal interactable (AC-27, ADR-008).
##
## The portal owns exactly one decision - are my destination ids and my provider
## usable? - and otherwise reports the router's code verbatim. The spy below stands
## in for `WorldRouter.request_travel`; `systems/interaction/**` never imports it.

## Stand-in for the router's `request_travel(world_id, spawn_id) -> StringName`.
class _TravelSpy extends RefCounted:
	var calls: Array[Array] = []
	var code_to_return: StringName = &"travel_started"

	func request_travel(world_id: StringName, spawn_id: StringName) -> StringName:
		calls.append([world_id, spawn_id])
		return code_to_return


## A mis-wired provider: a `Callable` whose method reports no code at all.
class _SilentSpy extends RefCounted:
	func request_travel(_world_id: StringName, _spawn_id: StringName) -> void:
		pass


func _make_portal(world_id: StringName, spawn_id: StringName) -> PortalInteractable:
	var portal := PortalInteractable.new()
	portal.target_world_id = world_id
	portal.target_spawn_id = spawn_id
	add_to_tree(portal)
	return portal


# --- destination validation ---------------------------------------------------

func test_a_portal_without_a_provider_is_invalid_destination() -> void:
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	assert_false(portal.has_travel_provider(), "a fresh portal has no provider")
	var result := portal.interact(null)
	assert_false(result.succeeded(), "an unconnected portal cannot be used")
	assert_eq(result.code, &"invalid_destination", "the refusal is invalid_destination")
	assert_false(portal.is_used(), "a refused portal is not consumed")


func test_clearing_the_provider_makes_the_portal_invalid_again() -> void:
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	var spy := _TravelSpy.new()
	portal.set_travel_provider(Callable(spy, "request_travel"))
	assert_true(portal.has_travel_provider(), "the provider is bound")
	portal.set_travel_provider(Callable())
	assert_false(portal.has_travel_provider(), "an invalid Callable() clears the binding")
	assert_eq(portal.interact(null).code, &"invalid_destination", "and the portal refuses again")
	assert_eq(spy.calls.size(), 0, "the cleared provider never ran")


func test_empty_target_ids_are_refused_before_the_provider_runs() -> void:
	var spy := _TravelSpy.new()
	var portal := _make_portal(&"", &"")
	portal.set_travel_provider(Callable(spy, "request_travel"))

	assert_eq(portal.interact(null).code, &"invalid_destination", "no ids at all is invalid")
	portal.target_world_id = &"world.dungeon.proto01"
	assert_eq(portal.interact(null).code, &"invalid_destination", "a missing spawn id is invalid")
	portal.target_world_id = &""
	portal.target_spawn_id = &"spawn.dungeon.entry"
	assert_eq(portal.interact(null).code, &"invalid_destination", "a missing world id is invalid")
	assert_eq(spy.calls.size(), 0, "an incomplete destination never reaches the router")


# --- router code pass-through -------------------------------------------------

func test_travel_started_is_a_success_and_the_router_receives_the_ids() -> void:
	var spy := _TravelSpy.new()
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	portal.set_travel_provider(Callable(spy, "request_travel"))

	var result := portal.interact(null)
	assert_true(result.succeeded(), "travel_started is a success")
	assert_eq(result.code, InteractionResult.OK, "a success always uses the ok code")
	assert_eq(result.message, "travel_started", "the router code is preserved verbatim as display text")
	assert_eq(spy.calls.size(), 1, "the router was asked exactly once")
	assert_eq(spy.calls[0][0], &"world.dungeon.proto01", "the provider receives the configured world id")
	assert_eq(spy.calls[0][1], &"spawn.dungeon.entry", "and the configured spawn id")
	assert_false(portal.is_used(), "a portal is reusable (the router owns single-flight)")


func test_router_refusal_codes_reach_the_caller_verbatim() -> void:
	var spy := _TravelSpy.new()
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	portal.set_travel_provider(Callable(spy, "request_travel"))

	var codes: Array[StringName] = [&"busy", &"unknown_world", &"invalid_world", &"invalid_spawn"]
	for code in codes:
		spy.code_to_return = code
		var result := portal.interact(null)
		assert_false(result.succeeded(), "the router refused with %s" % code)
		assert_eq(result.code, code, "the router code %s is passed through verbatim" % code)
	assert_eq(spy.calls.size(), codes.size(), "every attempt reached the router")


func test_a_provider_that_reports_nothing_is_unavailable() -> void:
	var spy := _SilentSpy.new()
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")
	portal.set_travel_provider(Callable(spy, "request_travel"))
	var result := portal.interact(null)
	assert_false(result.succeeded(), "a provider without a decision cannot succeed")
	assert_eq(result.code, InteractionResult.UNAVAILABLE, "it degrades to unavailable")


func test_rebinding_replaces_the_provider() -> void:
	var first := _TravelSpy.new()
	var second := _TravelSpy.new()
	second.code_to_return = &"busy"
	var portal := _make_portal(&"world.dungeon.proto01", &"spawn.dungeon.entry")

	portal.set_travel_provider(Callable(first, "request_travel"))
	assert_true(portal.interact(null).succeeded(), "the first provider starts the travel")
	portal.set_travel_provider(Callable(second, "request_travel"))
	assert_eq(portal.interact(null).code, &"busy", "the rebind takes effect (world reload / host rebind)")
	assert_eq(first.calls.size(), 1, "the old provider is not called any more")
	assert_eq(second.calls.size(), 1, "the new provider is called")
