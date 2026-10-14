class_name ContentRegistry
extends RefCounted

## Read-only id -> definition lookup built from one `ContentManifest` (ADR-011).
##
## Invariants:
## - `build()` never returns null and never crashes on a bad manifest: null entries,
##   empty or duplicated ids, resources of the wrong kind and unresolved cross
##   references are collected into `errors` as data. A broken entry degrades to a
##   missing lookup plus a diagnostic, never to a boot failure.
## - `is_valid() == errors.is_empty()`; there is no other validity state.
## - No folder scanning: what the manifest lists is what exists.
##
## Sprint 02 dependency note (W1b): `ItemDefinition`, `RewardDefinition` and
## `WorldDefinition` are W1a deliverables that are not part of this branch yet, so
## item/reward/world entries are recognised by their member surface (plus each
## definition's own `validation_errors()`) instead of an `is` check, and
## `find_item` / `find_reward` / `find_world` return an untyped value. When W1a is
## merged, add the concrete `is` checks and the typed return annotations.

const KIND_ATTACK: String = "attack"
const KIND_ENEMY: String = "enemy"
const KIND_ITEM: String = "item"
const KIND_REWARD: String = "reward"
const KIND_WORLD: String = "world"

## Members that distinguish a kind, on top of the shared `id` and `validation_errors()`.
const REQUIRED_MEMBERS: Dictionary = {
	KIND_ATTACK: ["reach", "windup"],
	KIND_ENEMY: ["move_speed", "attack_definition"],
	KIND_ITEM: ["display_name", "max_stack"],
	KIND_REWARD: ["item", "gold"],
	KIND_WORLD: ["scene", "default_spawn_id"],
}

## Manifest field name per kind, used in diagnostics.
const BUCKET_NAMES: Dictionary = {
	KIND_ATTACK: "attacks",
	KIND_ENEMY: "enemies",
	KIND_ITEM: "items",
	KIND_REWARD: "rewards",
	KIND_WORLD: "worlds",
}

## Every authoring problem found while building, in manifest order.
var errors: PackedStringArray = PackedStringArray()

var _attacks: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _rewards: Dictionary = {}
var _worlds: Dictionary = {}


## Indexes a manifest. Never null: a null manifest builds an empty, invalid registry.
static func build(manifest: ContentManifest) -> ContentRegistry:
	var registry := ContentRegistry.new()
	if manifest == null:
		registry.errors.append("manifest is null")
		return registry
	registry._collect(KIND_ATTACK, manifest.attacks, registry._attacks)
	registry._collect(KIND_ENEMY, manifest.enemies, registry._enemies)
	registry._collect(KIND_ITEM, manifest.items, registry._items)
	registry._collect(KIND_REWARD, manifest.rewards, registry._rewards)
	registry._collect(KIND_WORLD, manifest.worlds, registry._worlds)
	registry._check_cross_references()
	return registry


func is_valid() -> bool:
	return errors.is_empty()


func find_attack(id: StringName) -> AttackDefinition:
	var found: AttackDefinition = _attacks.get(id)
	return found


func find_enemy(id: StringName) -> EnemyDefinition:
	var found: EnemyDefinition = _enemies.get(id)
	return found


## Returns the `ItemDefinition` for `id` once W1a is merged (see the class note).
func find_item(id: StringName) -> Variant:
	return _items.get(id)


## Returns the `RewardDefinition` for `id` once W1a is merged (see the class note).
func find_reward(id: StringName) -> Variant:
	return _rewards.get(id)


## Returns the `WorldDefinition` for `id` once W1a is merged (see the class note).
func find_world(id: StringName) -> Variant:
	return _worlds.get(id)


## Every world that was indexed successfully, in manifest order.
func all_worlds() -> Array:
	return _worlds.values()


func _to_string() -> String:
	return "ContentRegistry(attacks=%d, enemies=%d, items=%d, rewards=%d, worlds=%d, errors=%d)" % [
		_attacks.size(), _enemies.size(), _items.size(), _rewards.size(), _worlds.size(), errors.size()
	]


# --- indexing -----------------------------------------------------------------

func _collect(kind: String, definitions: Variant, index: Dictionary) -> void:
	var bucket: String = BUCKET_NAMES[kind]
	if not definitions is Array:
		errors.append("%s: the manifest entry is not an array" % bucket)
		return
	var required: Array = REQUIRED_MEMBERS[kind]
	for i in definitions.size():
		var label := "%s[%d]" % [bucket, i]
		var definition: Variant = definitions[i]
		if definition == null:
			errors.append("%s is null" % label)
			continue
		if not definition is Resource:
			errors.append("%s must be a Resource (got %s)" % [label, type_string(typeof(definition))])
			continue
		var missing := _missing_members(definition, required)
		if not missing.is_empty():
			errors.append("%s is not a valid %s definition (missing: %s)" % [
				label, kind, ", ".join(missing)
			])
			continue
		var id: StringName = _id_of(definition)
		if id == &"":
			errors.append("%s has an empty id" % label)
			continue
		if index.has(id):
			errors.append("%s duplicates the id '%s'; the first definition stays" % [label, id])
			continue
		index[id] = definition
		_append_definition_errors(kind, id, definition)


## Prefixes the definition's own validation messages, so `errors` points at the
## manifest entry. A non-array return value is a shape problem of its own.
func _append_definition_errors(kind: String, id: StringName, definition: Object) -> void:
	var problems: Variant = definition.call("validation_errors")
	if not problems is Array and not problems is PackedStringArray:
		errors.append("%s '%s': validation_errors() did not return a string array" % [kind, id])
		return
	for problem in problems:
		errors.append("%s '%s': %s" % [kind, id, problem])


func _check_cross_references() -> void:
	for reward_id: StringName in _rewards:
		var reward: Object = _rewards[reward_id]
		var item: Variant = reward.get("item")
		if item == null:
			continue
		var item_id: StringName = _id_of(item)
		if not _items.has(item_id):
			errors.append("reward '%s': item '%s' is not listed in the manifest" % [reward_id, item_id])

	for enemy_id: StringName in _enemies:
		var enemy: Object = _enemies[enemy_id]
		var attack: Variant = enemy.get("attack_definition")
		if attack == null:
			errors.append("enemy '%s': attack_definition is null" % enemy_id)
		elif not _attacks.has(_id_of(attack)):
			errors.append("enemy '%s': attack '%s' is not listed in the manifest" % [
				enemy_id, _id_of(attack)
			])
		if not _has_property(enemy, "reward"):
			continue
		var reward: Variant = enemy.get("reward")
		if reward != null and not _rewards.has(_id_of(reward)):
			errors.append("enemy '%s': reward '%s' is not listed in the manifest" % [
				enemy_id, _id_of(reward)
			])


# --- reflection helpers -------------------------------------------------------

static func _missing_members(definition: Object, required: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for member: String in required:
		if not _has_property(definition, member):
			missing.append(member)
	if not _has_property(definition, "id"):
		missing.append("id")
	if not definition.has_method("validation_errors"):
		missing.append("validation_errors()")
	return missing


static func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false


## The stable id of a referenced resource, or "" when it has none.
static func _id_of(value: Variant) -> StringName:
	if value is Object and _has_property(value, "id"):
		var id: Variant = value.get("id")
		if id is StringName:
			return id
		if id is String:
			return StringName(id)
	return &""
