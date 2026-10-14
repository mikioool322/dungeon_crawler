class_name SaveSnapshot
extends RefCounted

## Versioned, persistence-only DTO of the durable run state (ADR-010).
##
## Invariants:
## - JSON-compatible values only: `StringName`, `String`, `int`, `float`, `bool`,
##   `Array[Dictionary]`, `PackedStringArray`. Never a Node, a Resource or a scene
##   path: a snapshot outlives the scene tree it was captured from.
## - `to_dict()` / `from_dict()` is the only (de)serialisation point; `SaveManager`
##   adds the file, atomicity and version policy on top of it.
## - `from_dict()` is shape-strict (missing keys and wrong value types are rejected)
##   but version-agnostic: an unknown/newer `version` is preserved, never clamped, so
##   the loader can refuse it before the data is used.
## - Content is referenced by stable ids only, never by display name or asset path.

const CURRENT_VERSION: int = 1

## Every key a usable snapshot dictionary must carry.
const REQUIRED_KEYS: Array = [
	"version",
	"health",
	"gold",
	"items",
	"world_id",
	"spawn_id",
	"claimed_reward_keys",
]

var version: int = CURRENT_VERSION
var health: float = 0.0
var gold: int = 0

## `[{"id": String, "count": int}]`, one entry per inventory stack, in inventory order.
var items: Array = []

var world_id: StringName = &""
var spawn_id: StringName = &""

## Claimed loot keys, `"<world_id>/<loot_source_id>"` (ADR-009).
var claimed_reward_keys: PackedStringArray = PackedStringArray()


## Serialises to a plain JSON-compatible dictionary. Item entries that are not
## `{"id": ..., "count": ...}` are dropped instead of being written as junk.
func to_dict() -> Dictionary:
	return {
		"version": version,
		"health": health,
		"gold": gold,
		"items": _items_to_json(items),
		"world_id": world_id,
		"spawn_id": spawn_id,
		"claimed_reward_keys": claimed_reward_keys,
	}


## Parses one dictionary back into a snapshot, or returns null when the shape is
## unusable (missing key, wrong type, non-integral version). The version value itself
## is not restricted to `CURRENT_VERSION`: the caller owns the version policy.
static func from_dict(data: Dictionary) -> SaveSnapshot:
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return null

	var version_value: Variant = _as_int(data["version"])
	var health_value: Variant = _as_float(data["health"])
	var gold_value: Variant = _as_int(data["gold"])
	var items_value: Variant = _read_items(data["items"])
	var world_value: Variant = _read_id(data["world_id"])
	var spawn_value: Variant = _read_id(data["spawn_id"])
	var keys_value: Variant = _read_keys(data["claimed_reward_keys"])

	if version_value == null or version_value < 0:
		return null
	if health_value == null or gold_value == null or items_value == null:
		return null
	if world_value == null or spawn_value == null or keys_value == null:
		return null

	var snapshot := SaveSnapshot.new()
	snapshot.version = version_value
	snapshot.health = health_value
	snapshot.gold = gold_value
	snapshot.items = items_value
	snapshot.world_id = world_value
	snapshot.spawn_id = spawn_value
	snapshot.claimed_reward_keys = keys_value
	return snapshot


## Probes the schema version of a raw dictionary without validating the rest of the
## shape. `SaveManager` uses it to refuse a *newer* save before anything else touches
## it (ADR-010: a future version must be refused, never quarantined or loaded).
## Returns null when the value is missing or is not an integer number.
static func version_of(data: Dictionary) -> Variant:
	return _as_int(data.get("version"))


# --- value coercion (shape checks only, never gameplay semantics) -------------

## Returns the value as an int when it is an integer number, null otherwise.
static func _as_int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floorf(value):
		return int(value)
	return null


## Returns the value as a float when it is a finite number, null otherwise.
static func _as_float(value: Variant) -> Variant:
	if value is int:
		return float(value)
	if value is float and is_finite(value):
		return value
	return null


## Returns a StringName for a JSON string, null for anything else.
static func _read_id(value: Variant) -> Variant:
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return null


## Returns a normalised `Array[Dictionary]` of `{"id": String, "count": int}`,
## or null when any entry is not shaped like that.
static func _read_items(value: Variant) -> Variant:
	if not value is Array:
		return null
	var parsed: Array[Dictionary] = []
	for entry: Variant in value:
		if not entry is Dictionary:
			return null
		var item_id: Variant = _read_id(entry.get("id"))
		var count: Variant = _as_int(entry.get("count"))
		if item_id == null or count == null:
			return null
		parsed.append({"id": String(item_id), "count": count})
	return parsed


## Returns a PackedStringArray of String/StringName entries, or null otherwise.
static func _read_keys(value: Variant) -> Variant:
	if value is PackedStringArray:
		return value
	if not value is Array:
		return null
	var keys := PackedStringArray()
	for entry: Variant in value:
		if not entry is String and not entry is StringName:
			return null
		keys.append(String(entry))
	return keys


## Normalises the stored item list for JSON; malformed entries are skipped.
static func _items_to_json(items: Array) -> Array[Dictionary]:
	var json_items: Array[Dictionary] = []
	for entry: Variant in items:
		if not entry is Dictionary:
			continue
		var item_id: Variant = _read_id(entry.get("id"))
		var count: Variant = _as_int(entry.get("count"))
		if item_id == null or count == null:
			continue
		json_items.append({"id": String(item_id), "count": count})
	return json_items


func _to_string() -> String:
	return "SaveSnapshot(v%d, hp=%.1f, gold=%d, items=%d, '%s/%s')" % [
		version, health, gold, items.size(), world_id, spawn_id
	]
