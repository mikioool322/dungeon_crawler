extends "res://tests/test_case.gd"

## AC-23 — durable run state: defaults, new-game reset, one-shot claim, save-style
## round trip and the node-free/JSON-safe guarantee (ADR-007, ADR-010).
## Pure domain logic: no SceneTree.

## JSON-compatible property types the state may consist of; `Inventory` is the one
## object reference it is allowed to hold.
const ALLOWED_TYPES: Array[int] = [
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_ARRAY, TYPE_DICTIONARY
]

const SAVE_KEY := &"world.dungeon.proto01/enemy.a"
const CHEST_KEY := &"world.dungeon.proto01/chest.a"
const ITEM_ID := &"item.minor_salve"

## The script's own fields, exactly; a new field must be a deliberate contract change.
const EXPECTED_FIELDS: Array[String] = [
	"claimed_reward_keys", "equipment", "gold", "health", "inventory", "spawn_id", "world_id"
]


func _item() -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = ITEM_ID
	definition.display_name = "Minor Salve"
	definition.stackable = true
	definition.max_stack = 5
	return definition


## The string list the save DTO is built from (the snapshot uses a PackedStringArray).
func _claimed_key_list(state: PlayerSessionState) -> Array:
	var keys: Array = []
	for key in state.claimed_reward_keys.keys():
		keys.append(String(key))
	keys.sort()
	return keys


# --- defaults and reset --------------------------------------------------------

func test_new_state_matches_the_documented_defaults() -> void:
	var state := PlayerSessionState.new()
	assert_almost_eq(state.health, 100.0, 0.0001, "health defaults to 100")
	assert_eq(state.gold, 0, "a new run has no gold")
	assert_not_null(state.inventory, "the bag exists")
	assert_true(state.inventory.is_empty(), "and starts empty")
	assert_eq(state.world_id, &"world.hub", "a new run starts in the hub")
	assert_eq(state.spawn_id, &"", "an empty spawn id means the world's default spawn")
	assert_eq(state.claimed_reward_keys.size(), 0, "nothing is claimed")
	assert_false(state.is_claimed(SAVE_KEY), "and is_claimed agrees")


func test_reset_to_new_game_clears_the_run() -> void:
	var state := PlayerSessionState.new()
	state.health = 7.5
	state.gold = 42
	state.inventory.add(_item(), 3)
	state.claim(SAVE_KEY)
	state.world_id = &"world.dungeon.proto01"
	state.spawn_id = &"spawn.dungeon.entry"

	state.reset_to_new_game(80.0)

	assert_almost_eq(state.health, 80.0, 0.0001, "health is the caller's rig maximum")
	assert_eq(state.gold, 0, "gold is reset")
	assert_true(state.inventory.is_empty(), "the bag is reset")
	assert_eq(state.claimed_reward_keys.size(), 0, "claimed keys are reset")
	assert_false(state.is_claimed(SAVE_KEY), "and is_claimed agrees")
	assert_eq(state.world_id, &"world.hub", "a new game does not inherit the previous world")
	assert_eq(state.spawn_id, &"", "nor its spawn")


func test_reset_clamps_a_broken_default_health() -> void:
	var state := PlayerSessionState.new()
	state.reset_to_new_game(-5.0)
	assert_almost_eq(state.health, 0.0, 0.0001, "negative health clamps to 0 (never a negative HP)")
	state.reset_to_new_game(NAN)
	assert_almost_eq(state.health, 0.0, 0.0001, "a non-finite default falls back to 0")
	state.reset_to_new_game(INF)
	assert_almost_eq(state.health, 0.0, 0.0001, "an infinite default falls back to 0")


# --- claimed keys --------------------------------------------------------------

func test_claim_is_one_shot() -> void:
	var state := PlayerSessionState.new()
	assert_true(state.claim(SAVE_KEY), "the first claim succeeds")
	assert_false(state.claim(SAVE_KEY), "the second claim reports false")
	assert_true(state.is_claimed(SAVE_KEY), "and is_claimed agrees")
	assert_eq(state.claimed_reward_keys.size(), 1, "the key is recorded once")
	assert_false(state.claim(&""), "an empty key is never recorded")
	assert_false(state.is_claimed(&""), "and is never reported as claimed")
	assert_eq(state.claimed_reward_keys.size(), 1, "still exactly one key")


func test_claimed_keys_survive_a_save_style_round_trip() -> void:
	var state := PlayerSessionState.new()
	state.claim(SAVE_KEY)
	state.claim(CHEST_KEY)

	var keys := _claimed_key_list(state)
	assert_eq(keys.size(), 2, "both keys are in the save list")

	var parsed: Variant = JSON.parse_string(JSON.stringify(keys))
	assert_true(parsed is Array, "the key list is JSON-safe")
	if parsed is not Array:
		return
	assert_eq(parsed.size(), 2, "both keys survive JSON")

	var restored := PlayerSessionState.new()
	for entry in parsed:
		restored.claim(StringName(entry))
	assert_eq(restored.claimed_reward_keys.size(), 2, "both keys are claimed after the round trip")
	assert_true(restored.is_claimed(SAVE_KEY), "the loot key survives")
	assert_true(restored.is_claimed(CHEST_KEY), "the chest key survives")


# --- serialisability -----------------------------------------------------------

func test_state_exposes_only_the_documented_node_free_fields() -> void:
	var state := PlayerSessionState.new()
	state.health = 42.5
	state.gold = 7
	state.inventory.add(_item(), 2)
	state.claim(SAVE_KEY)

	var names := PackedStringArray()
	for property in state.get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name := String(property["name"])
		names.append(name)
		var value: Variant = state.get(name)
		assert_false(value is Node, "%s must never hold a Node" % name)
		if typeof(value) == TYPE_OBJECT:
			assert_true(
				value is Inventory or value is EquipmentState,
				"%s may only hold a domain object (bag or equipment), not a scene object (got %s)"
				% [name, value]
			)
		else:
			assert_true(
				ALLOWED_TYPES.has(typeof(value)),
				"%s must be a JSON-compatible primitive (got %s)" % [name, type_string(typeof(value))]
			)
	names.sort()
	assert_eq(
		names,
		PackedStringArray(EXPECTED_FIELDS),
		"the state holds exactly the documented fields"
	)
	assert_eq(typeof(state.spawn_id), TYPE_STRING_NAME, "spawn_id stays a StringName")


func test_state_values_survive_a_json_round_trip() -> void:
	var state := PlayerSessionState.new()
	state.health = 55.5
	state.gold = 12
	state.inventory.add(_item(), 3)
	state.claim(SAVE_KEY)

	var payload := {
		"health": state.health,
		"gold": state.gold,
		"items": state.inventory.entries(),
		"world_id": String(state.world_id),
		"spawn_id": String(state.spawn_id),
		"claimed_reward_keys": _claimed_key_list(state),
	}
	var parsed: Variant = JSON.parse_string(JSON.stringify(payload))
	assert_true(parsed is Dictionary, "the state serialises to JSON and back")
	if parsed is not Dictionary:
		return
	assert_almost_eq(float(parsed["health"]), 55.5, 0.0001, "health survives")
	assert_eq(parsed["gold"], 12, "gold survives")
	assert_eq((parsed["items"] as Array).size(), 1, "the stack survives")
	assert_eq(parsed["world_id"], "world.hub", "the world id survives")
	assert_eq((parsed["claimed_reward_keys"] as Array).size(), 1, "the claimed key survives")
