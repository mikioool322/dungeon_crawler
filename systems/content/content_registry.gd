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
## - Every entry is checked against its concrete definition class, so a resource of
##   the wrong kind is reported instead of being silently indexed.

const KIND_ATTACK: String = "attack"
const KIND_ENEMY: String = "enemy"
const KIND_ITEM: String = "item"
const KIND_REWARD: String = "reward"
const KIND_WORLD: String = "world"

## Members that distinguish a kind are no longer probed by name: every entry is
## checked against its concrete class in `_matches_kind()`.

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


## Returns the `ItemDefinition` for `id`, or null.
func find_item(id: StringName) -> ItemDefinition:
	return _items.get(id) as ItemDefinition


## Returns the `RewardDefinition` for `id`, or null.
func find_reward(id: StringName) -> RewardDefinition:
	return _rewards.get(id) as RewardDefinition


## Returns the `WorldDefinition` for `id`, or null.
func find_world(id: StringName) -> WorldDefinition:
	return _worlds.get(id) as WorldDefinition


## Every world that was indexed successfully, in manifest order.
func all_worlds() -> Array[WorldDefinition]:
	var worlds: Array[WorldDefinition] = []
	for value: Variant in _worlds.values():
		worlds.append(value as WorldDefinition)
	return worlds


func _to_string() -> String:
	return "ContentRegistry(attacks=%d, enemies=%d, items=%d, rewards=%d, worlds=%d, errors=%d)" % [
		_attacks.size(), _enemies.size(), _items.size(), _rewards.size(), _worlds.size(), errors.size()
	]


# --- indexing -----------------------------------------------------------------

func _collect(kind: String, definitions: Array, index: Dictionary) -> void:
	var bucket: String = BUCKET_NAMES[kind]
	for i in definitions.size():
		var label := "%s[%d]" % [bucket, i]
		var definition: Variant = definitions[i]
		if definition == null:
			errors.append("%s is null" % label)
			continue
		if not definition is Resource:
			errors.append("%s must be a Resource (got %s)" % [label, type_string(typeof(definition))])
			continue
		if not _matches_kind(kind, definition as Resource):
			errors.append("%s is not a valid %s definition (got %s)" % [
				label, kind, _class_name_of(definition as Resource)
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


## Concrete class check per bucket: a resource of the wrong kind is a content error.
static func _matches_kind(kind: String, definition: Resource) -> bool:
	match kind:
		KIND_ATTACK:
			return definition is AttackDefinition
		KIND_ENEMY:
			return definition is EnemyDefinition
		KIND_ITEM:
			return definition is ItemDefinition
		KIND_REWARD:
			return definition is RewardDefinition
		KIND_WORLD:
			return definition is WorldDefinition
	return false


static func _class_name_of(definition: Resource) -> String:
	var script := definition.get_script() as Script
	if script == null:
		return definition.get_class()
	var global_name := String(script.get_global_name())
	return global_name if global_name != "" else definition.get_class()


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
		var reward := _rewards[reward_id] as RewardDefinition
		if reward.item == null:
			continue
		if not _items.has(reward.item.id):
			errors.append("reward '%s': item '%s' is not listed in the manifest" % [
				reward_id, reward.item.id
			])

	for enemy_id: StringName in _enemies:
		var enemy := _enemies[enemy_id] as EnemyDefinition
		if enemy.attack_definition == null:
			errors.append("enemy '%s': attack_definition is null" % enemy_id)
		elif not _attacks.has(enemy.attack_definition.id):
			errors.append("enemy '%s': attack '%s' is not listed in the manifest" % [
				enemy_id, enemy.attack_definition.id
			])
		if enemy.reward != null and not _rewards.has(enemy.reward.id):
			errors.append("enemy '%s': reward '%s' is not listed in the manifest" % [
				enemy_id, enemy.reward.id
			])


# --- helpers ------------------------------------------------------------------

## The stable id of a definition, or "" when it has none.
static func _id_of(value: Variant) -> StringName:
	if value is Object and value.get("id") != null:
		var id: Variant = value.get("id")
		if id is StringName:
			return id
		if id is String:
			return StringName(id)
	return &""
