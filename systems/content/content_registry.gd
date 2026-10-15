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
const KIND_DUNGEON: String = "dungeon"

## Members that distinguish a kind are no longer probed by name: every entry is
## checked against its concrete class in `_matches_kind()`.

## Manifest field name per kind, used in diagnostics.
const BUCKET_NAMES: Dictionary = {
	KIND_ATTACK: "attacks",
	KIND_ENEMY: "enemies",
	KIND_ITEM: "items",
	KIND_REWARD: "rewards",
	KIND_WORLD: "worlds",
	KIND_DUNGEON: "dungeons",
}

## Property that carries the stable id per kind. Dungeons use `dungeon_id` (ADR-012),
## every other bucket uses `id`.
const ID_PROPERTIES: Dictionary = {
	KIND_ATTACK: "id",
	KIND_ENEMY: "id",
	KIND_ITEM: "id",
	KIND_REWARD: "id",
	KIND_WORLD: "id",
	KIND_DUNGEON: "dungeon_id",
}

## Every authoring problem found while building, in manifest order.
var errors: PackedStringArray = PackedStringArray()

var _attacks: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _rewards: Dictionary = {}
var _worlds: Dictionary = {}
var _dungeons: Dictionary = {}


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
	registry._collect(KIND_DUNGEON, manifest.dungeons, registry._dungeons)
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


## Returns the `DungeonDefinition` for `id`, or null.
func find_dungeon(id: StringName) -> DungeonDefinition:
	return _dungeons.get(id) as DungeonDefinition


## Every dungeon that was indexed successfully, in manifest order.
func all_dungeons() -> Array[DungeonDefinition]:
	var dungeons: Array[DungeonDefinition] = []
	for value: Variant in _dungeons.values():
		dungeons.append(value as DungeonDefinition)
	return dungeons


## Dungeons available at the start of a new game (no prerequisites).
func start_dungeons() -> Array[DungeonDefinition]:
	var starts: Array[DungeonDefinition] = []
	for dungeon in all_dungeons():
		if dungeon.is_start_dungeon():
			starts.append(dungeon)
	return starts


## Start dungeon ids, used to seed `DungeonProgress` for a new game.
func start_dungeon_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for dungeon in start_dungeons():
		ids.append(dungeon.dungeon_id)
	return ids


## The dungeon that owns a world, or null when the world is not a dungeon.
func find_dungeon_for_world(world_id: StringName) -> DungeonDefinition:
	if world_id == &"":
		return null
	for value: Variant in _dungeons.values():
		var dungeon := value as DungeonDefinition
		if dungeon != null and dungeon.world_id == world_id:
			return dungeon
	return null


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
		var id: StringName = _id_of(definition, ID_PROPERTIES[kind])
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
		KIND_DUNGEON:
			return definition is DungeonDefinition
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

	_check_dungeon_references()


## Dungeon cross-references plus the progression graph: a dungeon that can never be
## unlocked (no start, no path through `first_clear_unlocks`) is a content error.
func _check_dungeon_references() -> void:
	for dungeon_id: StringName in _dungeons:
		var dungeon := _dungeons[dungeon_id] as DungeonDefinition
		if not _worlds.has(dungeon.world_id):
			errors.append("dungeon '%s': world '%s' is not listed in the manifest" % [
				dungeon_id, dungeon.world_id
			])
		for prerequisite in dungeon.prerequisites:
			if not _dungeons.has(prerequisite):
				errors.append("dungeon '%s': prerequisite '%s' is not listed in the manifest" % [
					dungeon_id, prerequisite
				])
		for unlock in dungeon.first_clear_unlocks:
			if not _dungeons.has(unlock):
				errors.append("dungeon '%s': first-clear unlock '%s' is not listed in the manifest" % [
					dungeon_id, unlock
				])
		_check_reward_reference(dungeon_id, "regular_reward_id", dungeon.regular_reward_id)
		_check_reward_reference(dungeon_id, "first_clear_reward_id", dungeon.first_clear_reward_id)

	if _dungeons.is_empty():
		return

	# Reachability from the start dungeons through the unlock graph.
	var reachable: Dictionary = {}
	var frontier: Array[StringName] = []
	for dungeon in start_dungeons():
		reachable[dungeon.dungeon_id] = true
		frontier.append(dungeon.dungeon_id)
	while not frontier.is_empty():
		var current: StringName = frontier.pop_back()
		var definition := _dungeons.get(current) as DungeonDefinition
		if definition == null:
			continue
		for unlock in definition.first_clear_unlocks:
			if unlock != &"" and not reachable.has(unlock):
				reachable[unlock] = true
				frontier.append(unlock)
	if reachable.is_empty():
		errors.append("dungeons: no start dungeon is listed; nothing can ever be unlocked")
	for dungeon_id: StringName in _dungeons:
		if not reachable.has(dungeon_id):
			errors.append(
				"dungeon '%s': cannot be unlocked - no start dungeon reaches it" % dungeon_id
			)


func _check_reward_reference(dungeon_id: StringName, field: String, reward_id: StringName) -> void:
	if reward_id == &"":
		return
	if not _rewards.has(reward_id):
		errors.append("dungeon '%s': %s '%s' is not listed in the manifest" % [
			dungeon_id, field, reward_id
		])


# --- helpers ------------------------------------------------------------------

## The stable id of a definition read from `property_name`, or "" when it has none.
static func _id_of(value: Variant, property_name: String = "id") -> StringName:
	if value is Object and value.get(property_name) != null:
		var id: Variant = value.get(property_name)
		if id is StringName:
			return id
		if id is String:
			return StringName(id)
	return &""
