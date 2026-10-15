extends "res://tests/test_case.gd"

## W2 integration contract for the first-person interaction ray (AC-27, ADR-008).
##
## Real physics: a minimal rig (a body with a `HealthComponent`, an eye-height view
## node and a controller), world geometry on layer `world`, interactables on layer
## `interactable`. The travel provider is a local `Callable` and loot is a real
## `LootService` backed by a real `ContentRegistry`, because
## `systems/interaction/**` must never import `world/**`.
##
## Covered here (the unit files cover the base and the portal in isolation):
## focus + prompt, wall occlusion, walking out of reach, `enabled = false`, the
## `interact` action route through `Input.parse_input_event`, one action per frame,
## one grant per loot key *per run* (scene loot is run-scoped, ADR-013), a chest that
## stays in the world, a dead interactor and the explicit "a ray still hits a
## `monitoring = false` area" verification.

## Ray length used by the fixture (the default).
const REACH: float = 2.5

## Eye height of the fixture view node.
const VIEW_HEIGHT: float = 1.6

## Centre of the fixture interactable: 1.5 m in front of the view, at eye height.
const INTERACTABLE_POSITION := Vector3(0.0, 1.4, -1.5)

## Half-metre box: the ray from the view enters it 1.2 m away, well inside reach.
const AREA_SIZE := Vector3(0.6, 0.6, 0.6)

## Interactable that counts its performances. The base virtual returns
## `unavailable`, which cannot prove that the ray *acted*.
class _CountingInteractable extends Interactable:
	var performed: int = 0

	func _perform_interact(_interactor: Node3D) -> InteractionResult:
		performed += 1
		return InteractionResult.ok("probe")


## Builds a real `ContentRegistry` from a hand-written manifest, so the loot path is
## exercised exactly as shipped (no duck-typed stand-in).
func _registry_with(items: Array[ItemDefinition]) -> ContentRegistry:
	var manifest := ContentManifest.new()
	manifest.items = items
	return ContentRegistry.build(manifest)


var _world: Node3D
var _rig: CharacterBody3D
var _view: Node3D
var _health: HealthComponent
var _controller: InteractionController
var _state: PlayerSessionState
var _loot: LootService
var _foci: Array[Interactable] = []
var _prompts: Array[Dictionary] = []
var _completions: Array[InteractionResult] = []
var _resolved: Array[InteractionResult] = []


func setup() -> void:
	_world = null
	_rig = null
	_view = null
	_health = null
	_controller = null
	_state = null
	_loot = null
	_foci = []
	_prompts = []
	_completions = []
	_resolved = []


func teardown() -> void:
	Input.action_release(&"interact")
	_world = null
	_rig = null
	_view = null
	_health = null
	_controller = null


# --- signal recorders ---------------------------------------------------------

func _on_focus_changed(interactable: Interactable) -> void:
	_foci.append(interactable)


func _on_prompt_changed(prompt: String, visible: bool) -> void:
	_prompts.append({"prompt": prompt, "visible": visible})


func _on_interaction_completed(_interactor: Node3D, result: InteractionResult) -> void:
	_completions.append(result)


func _on_interaction_resolved(result: InteractionResult) -> void:
	_resolved.append(result)


func _last_prompt() -> Dictionary:
	if _prompts.is_empty():
		return {}
	return _prompts.back()


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


# --- fixture ------------------------------------------------------------------

func _add_static_box(box_position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = box_position
	_world.add_child(body)
	return body


## Floor + a rig (body with a `HealthComponent`, a view node and a controller).
## The rig body carries a real shape on `player_body`: it must never occlude the
## interaction ray, because that layer is not in the ray mask.
func _build_fixture() -> void:
	_world = Node3D.new()
	_world.name = "InteractionFixture"
	add_to_tree(_world)

	_add_static_box(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))

	_rig = CharacterBody3D.new()
	_rig.name = "Rig"
	_rig.collision_layer = PhysicsLayers.PLAYER_BODY
	_rig.collision_mask = 0
	var rig_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	rig_shape.shape = capsule
	_rig.add_child(rig_shape)
	_world.add_child(_rig)

	_health = HealthComponent.new()
	_health.name = HealthComponent.NODE_NAME
	_health.max_health = 100.0
	_health.actor_id = &"player.test"
	_rig.add_child(_health)

	_view = Node3D.new()
	_view.name = "View"
	_view.position = Vector3(0.0, VIEW_HEIGHT, 0.0)
	_rig.add_child(_view)

	_controller = InteractionController.new()
	_controller.name = InteractionController.NODE_NAME
	_controller.view = _view
	_controller.interactor = _rig
	_controller.reach = REACH
	_controller.focus_changed.connect(_on_focus_changed)
	_controller.prompt_changed.connect(_on_prompt_changed)
	_controller.interaction_resolved.connect(_on_interaction_resolved)
	_rig.add_child(_controller)


## Adds a box-shaped interactable in the world, records its completions and
## returns it.
func _spawn_interactable(
	interactable: Interactable,
	at: Vector3 = INTERACTABLE_POSITION
) -> Interactable:
	interactable.interaction_completed.connect(_on_interaction_completed)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = AREA_SIZE
	shape.shape = box
	interactable.add_child(shape)
	interactable.position = at
	_world.add_child(interactable)
	return interactable


## Builds a real session state + loot service and opens a run ledger: chest and pickup
## grants are run-scoped since Sprint 03 (ADR-013), so a grant without a run would be
## `invalid`.
func _setup_loot(registry: ContentRegistry = null) -> void:
	_state = PlayerSessionState.new()
	_loot = LootService.new()
	_loot.setup(_state, registry)
	_loot.begin_run(1)


# --- focus, occlusion, reach --------------------------------------------------

func test_interactable_within_reach_becomes_focus_and_publishes_its_prompt() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	probe.prompt = "Open the sealed chest"
	_spawn_interactable(probe)
	await wait_physics_frames(3)

	assert_eq(_controller.current_focus(), probe, "the interactable in front is the focus")
	assert_eq(_foci.size(), 1, "focus_changed fired once")
	assert_eq(_foci.back(), probe, "and carried the interactable")
	assert_eq(_prompts.size(), 1, "prompt_changed fired once, not once per tick")
	assert_true(_last_prompt().get("visible", false), "the prompt is visible")
	assert_eq(
		_last_prompt().get("prompt", ""),
		"Open the sealed chest",
		"the prompt text comes from the interactable"
	)
	assert_true(_controller.try_interact().succeeded(), "and the action resolves")
	assert_eq(probe.performed, 1, "the interactable performed once")


func test_a_wall_between_view_and_interactable_clears_the_focus() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), probe, "control: the focus exists before the wall")

	_add_static_box(Vector3(0.0, 1.4, -0.8), Vector3(2.0, 2.8, 0.2))
	await wait_physics_frames(3)

	assert_null(_controller.current_focus(), "world geometry occludes the interactable")
	assert_false(_last_prompt().get("visible", true), "the prompt is hidden")
	assert_false(_controller.try_interact().succeeded(), "and the action is refused")
	assert_eq(probe.performed, 0, "the interactable never ran")
	assert_eq(_resolved.size(), 0, "nothing was resolved through an occluded ray")


func test_walking_beyond_reach_clears_the_focus() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), probe, "control: 1.5 m is inside reach %.1f" % REACH)
	var prompts_before := _prompts.size()

	_rig.position = Vector3(0.0, 0.0, 2.0)  # 3.5 m away: past the 2.5 m reach
	await wait_physics_frames(3)

	assert_null(_controller.current_focus(), "walking backwards out of reach loses the focus")
	assert_true(_prompts.size() > prompts_before, "prompt_changed fired again")
	assert_false(_last_prompt().get("visible", true), "the prompt is hidden")


func test_the_nearest_interactable_wins_and_is_never_looked_through() -> void:
	_build_fixture()
	var near := _CountingInteractable.new()
	_spawn_interactable(near, Vector3(0.0, 1.4, -1.2))
	var far := _CountingInteractable.new()
	_spawn_interactable(far, Vector3(0.0, 1.4, -2.4))
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), near, "the first hit of the ray is the focus")

	near.enabled = false
	await wait_physics_frames(3)
	assert_null(
		_controller.current_focus(),
		"a disabled interactable in the way yields no focus - the ray is never looked through"
	)
	assert_false(_controller.try_interact().succeeded(), "and the action is refused")


func test_a_disabled_interactable_is_never_focused() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	probe.enabled = false
	_spawn_interactable(probe)
	await wait_physics_frames(3)

	assert_null(_controller.current_focus(), "a disabled interactable is not a focus")
	assert_eq(_prompts.size(), 0, "and publishes no prompt")
	assert_false(_controller.try_interact().succeeded(), "the action is refused")
	assert_eq(probe.performed, 0, "the interactable never ran")

	probe.enabled = true
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), probe, "re-enabling it restores the focus")
	assert_true(_last_prompt().get("visible", false), "and the prompt appears")


func test_prompt_changed_only_fires_when_the_prompt_or_visibility_changes() -> void:
	_build_fixture()
	var first := _CountingInteractable.new()
	_spawn_interactable(first, Vector3(0.0, 1.4, -1.5))
	var second := _CountingInteractable.new()
	_spawn_interactable(second, Vector3(0.0, 1.4, -3.0))
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), first, "the first interactable is focused")
	assert_eq(_prompts.size(), 1, "its prompt was published once")

	# Looking at a different interactable with the same prompt: the focus changes,
	# the prompt does not, so the HUD must not be told again.
	_rig.position = Vector3(0.0, 0.0, -2.0)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), second, "the second interactable is now focused")
	assert_eq(_foci.size(), 2, "focus_changed fired for the new focus")
	assert_eq(_prompts.size(), 1, "prompt_changed stayed silent: text and visibility are unchanged")


# --- the `interact` action ----------------------------------------------------

func test_the_interact_action_reaches_the_controller_and_fires_once_per_frame() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), probe, "precondition: the interactable is focused")

	Input.parse_input_event(_action_event(&"interact", true))
	await wait_physics_frames(2)
	assert_eq(
		probe.performed,
		1,
		"Input.parse_input_event(&\"interact\") reached InteractionController._unhandled_input"
	)
	assert_eq(_completions.size(), 1, "one action, one completion")

	# Two presses inside one frame must still resolve to a single action.
	Input.parse_input_event(_action_event(&"interact", true))
	Input.parse_input_event(_action_event(&"interact", true))
	await wait_physics_frames(3)
	assert_eq(probe.performed, 2, "a double press in one frame adds exactly one action")
	assert_eq(_completions.size(), 2, "and one completion")
	assert_eq(_resolved.size(), 2, "the controller published exactly one result per action")


func test_a_direct_try_interact_cannot_fire_twice_in_one_physics_frame() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	await wait_physics_frames(3)

	var first := _controller.try_interact()
	var second := _controller.try_interact()
	assert_true(first.succeeded(), "the first call acts")
	assert_false(second.succeeded(), "the second call in the same physics frame is refused")
	assert_eq(second.code, InteractionResult.UNAVAILABLE, "with the unavailable code")
	assert_eq(probe.performed, 1, "and the interactable performed once")


# --- loot through the interaction system --------------------------------------

## Wires the loot path of a pickup or chest exactly like the world host does.
func _bind_loot(interactable: Interactable, reward: RewardDefinition, key: StringName) -> void:
	interactable.bind_loot(reward, key, _loot)


func test_a_double_press_grants_a_one_shot_pickup_exactly_once() -> void:
	_build_fixture()
	var salve := ItemDefinition.new()
	salve.id = &"item.minor_salve"
	salve.display_name = "Minor Salve"
	salve.kind = ItemDefinition.Kind.CONSUMABLE
	salve.stackable = true
	salve.max_stack = 5
	assert_true(salve.is_valid(), "the fixture item is valid")
	var registry_items: Array[ItemDefinition] = [salve]
	var registry := _registry_with(registry_items)
	_setup_loot(registry)

	var reward := RewardDefinition.new()
	reward.id = &"reward.test.pickup"
	reward.item = salve
	reward.item_count = 2
	reward.gold = 5
	assert_true(reward.is_valid(), "the fixture reward is valid")

	var key := LootGrant.key_for(&"world.test", &"enemy.a")
	var pickup := PickupInteractable.new()
	pickup.one_shot = true
	_bind_loot(pickup, reward, key)
	assert_true(pickup.is_bound(), "the pickup is bound to the loot service")
	assert_eq(pickup.grant_key, key, "and keeps the stable idempotency key")
	_spawn_interactable(pickup)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), pickup, "the pickup is focused")

	Input.parse_input_event(_action_event(&"interact", true))
	Input.parse_input_event(_action_event(&"interact", true))
	await wait_physics_frames(4)

	assert_eq(_completions.size(), 1, "exactly one interaction_completed for a double press")
	assert_eq(_resolved.size(), 1, "exactly one resolved interaction")
	assert_true(_resolved[0].succeeded(), "the interaction succeeded")
	assert_eq(_resolved[0].code, InteractionResult.OK, "with the ok code")
	assert_eq(_resolved[0].message, "granted", "and the loot code as display text")
	assert_eq(_state.gold, 5, "the grant was applied exactly once (gold)")
	assert_eq(_state.inventory.count_of(&"item.minor_salve"), 2, "the item was granted exactly once")
	assert_true(_state.claimed_reward_keys.is_empty(), "a run-scoped grant writes no persistent key")
	assert_true(_loot.is_claimed_in_run(key), "the key is claimed in the run ledger")
	assert_false(_loot.is_claimed(key), "and not in the persistent (story) ledger")

	await wait_process_frames(2)
	assert_false(is_instance_valid(pickup), "the pickup is consumed after the grant")
	await wait_physics_frames(2)
	assert_null(_controller.current_focus(), "a consumed interactable leaves the focus")
	assert_false(_last_prompt().get("visible", true), "and the prompt is hidden again")


func test_an_unbound_pickup_refuses_and_stays_in_the_world() -> void:
	_build_fixture()
	_setup_loot()
	var pickup := PickupInteractable.new()
	_spawn_interactable(pickup)
	await wait_physics_frames(3)
	assert_false(pickup.is_bound(), "a fresh pickup has no loot binding")

	var result := _controller.try_interact()
	assert_false(result.succeeded(), "an unbound pickup cannot be used")
	assert_eq(result.code, &"not_configured", "the refusal is not_configured")
	assert_eq(_resolved.size(), 1, "the refusal is still published to the HUD")
	assert_eq(_completions.size(), 0, "but no completion is emitted")
	assert_true(is_instance_valid(pickup), "and the pickup stays in the world")


func test_an_invalid_reward_is_refused_with_invalid() -> void:
	_build_fixture()
	_setup_loot()
	var reward := RewardDefinition.new()  # empty id, no item, no gold
	assert_false(reward.is_valid(), "the fixture reward is invalid by construction")
	var pickup := PickupInteractable.new()
	_bind_loot(pickup, reward, &"world.test/enemy.a")
	_spawn_interactable(pickup)
	await wait_physics_frames(3)
	assert_true(pickup.is_bound(), "the reward object is wired")

	var result := _controller.try_interact()
	assert_false(result.succeeded(), "an invalid reward cannot be granted")
	assert_eq(result.code, &"invalid", "LootService's own code is passed through verbatim")
	assert_eq(_completions.size(), 0, "no completion")
	assert_true(is_instance_valid(pickup), "and the pickup stays for a retry once content is fixed")


func test_a_chest_stays_in_the_world_and_a_claimed_key_never_grants_twice() -> void:
	_build_fixture()
	_setup_loot()
	var reward := RewardDefinition.new()
	reward.id = &"reward.test.chest"
	reward.gold = 7
	assert_true(reward.is_valid(), "a gold-only reward needs no registry")
	var key := LootGrant.key_for(&"world.dungeon.proto01", &"chest.a")

	var chest := ChestInteractable.new()
	assert_true(chest.one_shot, "a chest is one-shot by default")
	_bind_loot(chest, reward, key)
	_spawn_interactable(chest)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), chest, "the chest is focused")

	var first := _controller.try_interact()
	assert_true(first.succeeded(), "the first open succeeds")
	assert_eq(first.message, "granted", "and reports the grant")
	assert_eq(_state.gold, 7, "the gold was granted once")
	assert_true(_loot.is_claimed_in_run(key), "the chest key is claimed in the run ledger")
	assert_true(_state.claimed_reward_keys.is_empty(), "and never in the persistent ledger")
	assert_true(chest.is_used(), "the chest records the open")
	assert_true(is_instance_valid(chest), "the chest stays in the world")
	assert_false(chest.can_interact(), "a used chest cannot be opened again")

	# A fresh chest for the same key: the shape of a world re-entered after the drop
	# was already collected (or of a restored save).
	chest.queue_free()
	await wait_process_frames(2)
	var reloaded := ChestInteractable.new()
	_bind_loot(reloaded, reward, key)
	_spawn_interactable(reloaded)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), reloaded, "the fresh chest is focused")

	var second := _controller.try_interact()
	assert_true(second.succeeded(), "re-opening a claimed chest is a harmless success")
	assert_eq(second.message, "already_collected", "and says why nothing was granted")
	assert_eq(_state.gold, 7, "a duplicate grant never awards again")
	assert_true(_loot.is_claimed_in_run(key), "still exactly one claim in the run ledger")
	assert_true(_state.claimed_reward_keys.is_empty(), "and still no persistent key")
	assert_true(reloaded.is_used(), "the second chest records its open too")


# --- dead interactor and the layer-5 setup ------------------------------------

func test_a_dead_interactor_cannot_interact() -> void:
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	await wait_physics_frames(3)
	assert_eq(_controller.current_focus(), probe, "control: a living rig has a focus")

	var lethal := DamageRequest.new(&"tests.w2.lethal", &"tests.w2", 1000.0, Vector3.ZERO, Vector3.UP)
	_health.apply_damage(lethal)
	assert_false(_health.is_alive(), "the fixture rig is dead")
	await wait_physics_frames(3)

	assert_null(_controller.current_focus(), "a dead interactor has no focus")
	assert_false(_last_prompt().get("visible", true), "so no prompt is offered")
	assert_false(_controller.try_interact().succeeded(), "a dead interactor cannot interact")
	assert_eq(probe.performed, 0, "the interactable never ran")
	assert_eq(_completions.size(), 0, "and nothing was completed")

	Input.parse_input_event(_action_event(&"interact", true))
	await wait_physics_frames(3)
	assert_eq(probe.performed, 0, "a parsed E press cannot act through a dead interactor")


func test_the_ray_hits_an_area_with_monitoring_disabled() -> void:
	## Explicit verification of the ADR-005 layer-5 setup: the interaction ray must
	## find a query-only `Area3D`. If an engine change ever stopped reporting
	## `monitoring = false` areas to `intersect_ray`, the whole interaction system
	## would silently stop working - this test fails instead.
	_build_fixture()
	var probe := _CountingInteractable.new()
	_spawn_interactable(probe)
	assert_false(probe.monitoring, "the interactable does not monitor")
	assert_eq(probe.collision_layer, PhysicsLayers.INTERACTABLE, "it is on layer 5 only")
	assert_eq(probe.collision_mask, 0, "with an empty mask")
	await wait_physics_frames(3)

	assert_eq(
		_controller.current_focus(),
		probe,
		"a ray with collide_with_areas = true still hits a monitoring = false area"
	)
	assert_true(_controller.try_interact().succeeded(), "and the interaction resolves against it")
	assert_eq(probe.performed, 1, "exactly once")


func test_find_on_mirrors_the_health_component_lookup() -> void:
	_build_fixture()
	await wait_physics_frames(1)
	assert_eq(
		InteractionController.find_on(_rig),
		_controller,
		"find_on() finds the direct child named InteractionController"
	)
	assert_null(InteractionController.find_on(null), "null in, null out")
	assert_null(InteractionController.find_on(_world), "an actor without the node reports null")
