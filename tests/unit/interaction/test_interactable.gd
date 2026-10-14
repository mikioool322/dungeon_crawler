extends "res://tests/test_case.gd"

## W2 unit contract for the interaction base (AC-27, ADR-008).
##
## The base owns the guards, the one-shot bookkeeping and the single
## `interaction_completed` emission; subclasses only implement `_perform_interact()`.
## The local subclasses below count their calls and return a configurable result, so
## these tests prove what the *base* does rather than what a scene happens to do.
##
## No physics and no controller here: that is `tests/integration/test_interaction_ray.gd`.

## Records calls and returns whatever the test configured.
class _Probe extends Interactable:
	var perform_count: int = 0
	var last_interactor: Node3D = null
	var result_to_return: InteractionResult = null

	func _perform_interact(interactor: Node3D) -> InteractionResult:
		perform_count += 1
		last_interactor = interactor
		if result_to_return == null:
			return InteractionResult.ok("probe")
		return result_to_return


## A subclass that calls `interact()` from inside `_perform_interact()`: the base's
## re-entrancy guard is the only thing that can stop a second action.
class _Reentrant extends Interactable:
	var nested_results: Array[InteractionResult] = []

	func _perform_interact(_interactor: Node3D) -> InteractionResult:
		nested_results.append(interact(null))
		return InteractionResult.ok("outer")


## `interaction_completed` payloads of the current test.
var _completed: Array[Dictionary] = []


func setup() -> void:
	_completed = []


func _on_interaction_completed(interactor: Node3D, result: InteractionResult) -> void:
	_completed.append({"interactor": interactor, "result": result})


## Puts the interactable in the tree (so `_ready()` runs the layer contract) and
## records its completions. The runner frees it after the test.
func _watch(interactable: Interactable) -> void:
	interactable.interaction_completed.connect(_on_interaction_completed)
	add_to_tree(interactable)


# --- defaults and guards ------------------------------------------------------

func test_defaults_match_the_contract() -> void:
	var probe := _Probe.new()
	_watch(probe)
	assert_eq(probe.prompt, "Interact", "default prompt text")
	assert_true(probe.enabled, "an interactable starts enabled")
	assert_false(probe.one_shot, "the base is reusable by default")
	assert_false(probe.is_used(), "nothing is used before the first action")
	assert_true(probe.can_interact(), "a fresh interactable can be used")


func test_disabled_interactable_refuses_without_performing() -> void:
	var probe := _Probe.new()
	_watch(probe)
	probe.enabled = false
	assert_false(probe.can_interact(), "a disabled interactable cannot be used")
	var result := probe.interact(null)
	assert_not_null(result, "a refusal is still a result")
	assert_false(result.succeeded(), "a disabled interactable does not succeed")
	assert_eq(result.code, InteractionResult.UNAVAILABLE, "the refusal code is unavailable")
	assert_eq(probe.perform_count, 0, "the subclass never ran")
	assert_eq(_completed.size(), 0, "no completion is emitted for a refused action")
	assert_false(probe.is_used(), "a refused action does not mark the interactable used")


func test_the_base_virtual_reports_unavailable_and_emits_nothing() -> void:
	var base := Interactable.new()
	_watch(base)
	base.one_shot = true
	assert_true(base.can_interact(), "an untouched base interactable is available")
	var result := base.interact(null)
	assert_false(result.succeeded(), "the default _perform_interact() refuses")
	assert_eq(result.code, InteractionResult.UNAVAILABLE, "with the unavailable code")
	assert_eq(_completed.size(), 0, "an unavailable action emits nothing")
	assert_false(base.is_used(), "and does not consume a one-shot")


func test_a_used_one_shot_performs_once_and_is_then_refused() -> void:
	var probe := _Probe.new()
	_watch(probe)
	probe.one_shot = true

	var first := probe.interact(null)
	assert_true(first.succeeded(), "the first action succeeds")
	assert_eq(probe.perform_count, 1, "the subclass performed once")
	assert_true(probe.is_used(), "a successful one-shot is marked used")
	assert_false(probe.can_interact(), "a used one-shot cannot be used again")

	var second := probe.interact(null)
	assert_false(second.succeeded(), "the second action is refused")
	assert_eq(second.code, InteractionResult.UNAVAILABLE, "with the unavailable code")
	assert_eq(probe.perform_count, 1, "the second action does not perform again")
	assert_eq(_completed.size(), 1, "interaction_completed fired exactly once")


func test_a_reusable_interactable_keeps_working_after_mark_used() -> void:
	var probe := _Probe.new()
	_watch(probe)
	assert_false(probe.is_used(), "a fresh interactable is unused")
	probe.mark_used()
	assert_true(probe.is_used(), "mark_used()/is_used() round trip")
	assert_true(probe.can_interact(), "`used` only gates a one-shot interactable")
	assert_true(probe.interact(null).succeeded(), "and a reusable interactable still performs")
	assert_eq(probe.perform_count, 1, "once per call")


# --- result plumbing ----------------------------------------------------------

func test_completion_carries_the_interactor_and_the_returned_result() -> void:
	var interactor := Node3D.new()
	add_to_tree(interactor)
	var probe := _Probe.new()
	_watch(probe)

	var result := probe.interact(interactor)
	assert_true(result.succeeded(), "the probe succeeds")
	assert_eq(probe.last_interactor, interactor, "the subclass received the interactor")
	assert_eq(_completed.size(), 1, "interaction_completed fired once")
	assert_eq(_completed[0]["interactor"], interactor, "the signal carries the interactor")
	assert_eq(_completed[0]["result"], result, "the signal carries the exact returned result")
	assert_eq(result.code, InteractionResult.OK, "a success uses the ok code")


func test_a_subclass_result_code_reaches_the_caller_unchanged() -> void:
	var probe := _Probe.new()
	_watch(probe)
	probe.result_to_return = InteractionResult.rejected(&"portal_busy", "The way is blocked.")

	var result := probe.interact(null)
	assert_eq(result.code, &"portal_busy", "a custom refusal code is passed through verbatim")
	assert_eq(result.message, "The way is blocked.", "the display message is preserved")
	assert_false(result.succeeded(), "a custom refusal is not a success")
	assert_eq(probe.perform_count, 1, "the subclass still ran (it is the one refusing)")
	assert_eq(_completed.size(), 0, "a refusal never emits interaction_completed")


func test_reentrant_interact_is_refused() -> void:
	var probe := _Reentrant.new()
	_watch(probe)
	var result := probe.interact(null)
	assert_true(result.succeeded(), "the outer action succeeds")
	assert_eq(probe.nested_results.size(), 1, "the nested call returned a result")
	assert_false(probe.nested_results[0].succeeded(), "the nested call is refused")
	assert_eq(
		probe.nested_results[0].code,
		InteractionResult.UNAVAILABLE,
		"the re-entrant call reports unavailable"
	)
	assert_eq(_completed.size(), 1, "one action, one completion - even from inside the action")


func test_rejected_with_an_empty_code_degrades_to_unavailable() -> void:
	var result := InteractionResult.rejected(&"")
	assert_eq(result.code, InteractionResult.UNAVAILABLE, "an empty refusal code carries no information")
	assert_false(result.succeeded(), "and is still a refusal")
	assert_eq(InteractionResult.ok().code, InteractionResult.OK, "ok() uses the ok code")


# --- scene / ADR-005 layer contract ------------------------------------------

func test_interactable_is_a_query_only_area_on_layer_five() -> void:
	var probe := _Probe.new()
	_watch(probe)
	assert_eq(probe.collision_layer, PhysicsLayers.INTERACTABLE, "layer 5 only (ADR-005 addendum)")
	assert_eq(probe.collision_mask, 0, "an interactable detects nothing")
	assert_false(probe.monitoring, "an interactable never monitors (ADR-008)")
	assert_eq(
		PhysicsLayers.movement_mask(PhysicsLayers.PLAYER_BODY) & probe.collision_layer,
		0,
		"interactables are never part of a movement mask"
	)
	assert_eq(
		PhysicsLayers.movement_mask(PhysicsLayers.ENEMY_BODY) & probe.collision_layer,
		0,
		"not even for enemies"
	)


func test_the_base_loot_hook_is_inert() -> void:
	## ADR-008: the hook exists so the world host can inject loot without the base
	## knowing about it. On the base it must change nothing at all.
	var probe := _Probe.new()
	_watch(probe)
	probe.bind_loot(null, &"world.test/source.a", null)
	assert_true(probe.can_interact(), "the base stays usable after bind_loot()")
	assert_false(probe.is_used(), "and unused")
	assert_true(probe.interact(null).succeeded(), "the base behaviour is unchanged")
