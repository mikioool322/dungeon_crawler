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
const KIND_MERCHANT: String = "merchant"
const KIND_NPC: String = "npc"

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
	KIND_MERCHANT: "merchants",
	KIND_NPC: "npcs",
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
	KIND_MERCHANT: "id",
	KIND_NPC: "id",
}

## Every authoring problem found while building, in manifest order.
var errors: PackedStringArray = PackedStringArray()

var _attacks: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _rewards: Dictionary = {}
var _worlds: Dictionary = {}
var _dungeons: Dictionary = {}
var _merchants: Dictionary = {}
var _npcs: Dictionary = {}
var _player: PlayerDefinition = null


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
	registry._collect(KIND_MERCHANT, manifest.merchants, registry._merchants)
	registry._collect(KIND_NPC, manifest.npcs, registry._npcs)
	registry._read_player(manifest.player)
	registry._check_cross_references()
	return registry


## The player definition is a single field: exactly one player character ships in Sprint 04.
## Optional at the registry level so hand-built test manifests stay valid; the shipped
## content test asserts it is present, and a session without one degrades to the rig's
## scene values with a warning instead of crashing.
func _read_player(definition: PlayerDefinition) -> void:
	if definition == null:
		return
	for problem in definition.validation_errors():
		errors.append("player: %s" % problem)
	_player = definition


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


## The shipped player definition, or null when the manifest has none.
func player_definition() -> PlayerDefinition:
	return _player


func find_merchant(id: StringName) -> MerchantDefinition:
	return _merchants.get(id) as MerchantDefinition


func all_merchants() -> Array[MerchantDefinition]:
	var merchants: Array[MerchantDefinition] = []
	for value: Variant in _merchants.values():
		merchants.append(value as MerchantDefinition)
	return merchants


func find_npc(id: StringName) -> NpcDefinition:
	return _npcs.get(id) as NpcDefinition


func all_npcs() -> Array[NpcDefinition]:
	var npcs: Array[NpcDefinition] = []
	for value: Variant in _npcs.values():
		npcs.append(value as NpcDefinition)
	return npcs


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
		KIND_MERCHANT:
			return definition is MerchantDefinition
		KIND_NPC:
			return definition is NpcDefinition
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
	_check_player_references()
	_check_merchant_references()
	_check_npc_references()


## Every weapon profile an item references must be a listed attack definition.
func _check_player_references() -> void:
	for item_id: StringName in _items:
		var item := _items[item_id] as ItemDefinition
		if item.attack_definition != null and not _attacks.has(item.attack_definition.id):
			errors.append("item '%s': attack_definition '%s' is not listed in the manifest" % [
				item_id, item.attack_definition.id
			])
	if _player != null and _player.attack_definition != null:
		if not _attacks.has(_player.attack_definition.id):
			errors.append("player: attack_definition '%s' is not listed in the manifest" % [
				_player.attack_definition.id
			])


func _check_merchant_references() -> void:
	for merchant_id: StringName in _merchants:
		var merchant := _merchants[merchant_id] as MerchantDefinition
		for item: ItemDefinition in merchant.stock:
			if item == null:
				errors.append("merchant '%s': stock contains a null item" % merchant_id)
			elif not _items.has(item.id):
				errors.append("merchant '%s': stock item '%s' is not listed in the manifest" % [
					merchant_id, item.id
				])


func _check_npc_references() -> void:
	for npc_id: StringName in _npcs:
		var npc := _npcs[npc_id] as NpcDefinition
		if npc.merchant != null and not _merchants.has(npc.merchant.id):
			errors.append("npc '%s': merchant '%s' is not listed in the manifest" % [
				npc_id, npc.merchant.id
			])


## Dungeon cross-references plus the progression graph: a dungeon that can never be
## unlocked (no start, no path through `first_clear_unlocks`) is a content error.
func _check_dungeon_references() -> void:
	var world_owners: Dictionary = {}
	for dungeon_id: StringName in _dungeons:
		var dungeon := _dungeons[dungeon_id] as DungeonDefinition
		if not _worlds.has(dungeon.world_id):
			errors.append("dungeon '%s': world '%s' is not listed in the manifest" % [
				dungeon_id, dungeon.world_id
			])
		elif world_owners.has(dungeon.world_id):
			# The travel gate resolves a world to exactly one dungeon, so a shared world
			# would silently disable the other dungeon's gate.
			errors.append("dungeon '%s': world '%s' is already owned by dungeon '%s'" % [
				dungeon_id, dungeon.world_id, world_owners[dungeon.world_id]
			])
		else:
			world_owners[dungeon.world_id] = dungeon_id
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
