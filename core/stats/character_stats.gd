class_name CharacterStats
extends RefCounted

## Effective character stats: one base value per stat plus additive modifier buckets,
## one bucket per source (ADR-015).
##
## Invariants:
## - `base` never changes after `setup()`: equipment and every future source only
##   contribute through `set_modifiers()`. No source can mutate another's bucket.
## - `effective(stat) = clamp(base(stat) + sum(buckets[stat]))`; recomputation is
##   deterministic and idempotent. `set_modifiers()` *replaces* a bucket, so equipping
##   the same item twice cannot stack its bonus.
## - Non-finite or malformed modifier values are ignored with a warning; the clamps keep
##   HP/attack/defense at >= 0 and speed at > 0, so no consumer can observe NaN/Infinity.
## - `changed` is emitted only when an effective value actually differs, so a listener
##   may safely react by re-reading the values.
## - Holds no Node and no Resource reference after `setup()` copied the base values.

signal changed()

const MAX_HEALTH: StringName = &"max_health"
const ATTACK_DAMAGE: StringName = &"attack_damage"
const DEFENSE: StringName = &"defense"
const MOVEMENT_SPEED: StringName = &"movement_speed"

## Every stat this build knows, in panel order.
const STATS: Array[StringName] = [MAX_HEALTH, ATTACK_DAMAGE, DEFENSE, MOVEMENT_SPEED]

## Smallest allowed value per stat (speed may not be zero: a frozen player is a bug).
const MINIMUM: Dictionary = {
	MAX_HEALTH: 0.0,
	ATTACK_DAMAGE: 0.0,
	DEFENSE: 0.0,
	MOVEMENT_SPEED: 0.01,
}

var _base: Dictionary = {}
var _modifiers: Dictionary = {}
var _effective: Dictionary = {}
var _ready: bool = false


## Copies the base values out of a definition. False (and inert stats) when invalid.
func setup(definition: PlayerDefinition) -> bool:
	if definition == null or not definition.is_valid():
		push_warning("CharacterStats: refusing an invalid PlayerDefinition")
		return false
	_base = {
		MAX_HEALTH: definition.max_health,
		ATTACK_DAMAGE: definition.attack_damage,
		DEFENSE: definition.defense,
		MOVEMENT_SPEED: definition.movement_speed,
	}
	_modifiers.clear()
	_ready = true
	_recalculate()
	return true


func is_ready() -> bool:
	return _ready


func base(stat: StringName) -> float:
	return float(_base.get(stat, 0.0))


func effective(stat: StringName) -> float:
	return float(_effective.get(stat, 0.0))


## Sum of every bucket for one stat (what the equipment panel can show as "+X").
func modifier_total(stat: StringName) -> float:
	var total := 0.0
	for source: StringName in _modifiers:
		total += float((_modifiers[source] as Dictionary).get(stat, 0.0))
	return total


func sources() -> Array[StringName]:
	var ids: Array[StringName] = []
	for source: StringName in _modifiers.keys():
		ids.append(source)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Replaces the whole bucket of one source (idempotent). Returns true when the
## effective values changed. An empty dictionary removes the bucket.
func set_modifiers(source_id: StringName, modifiers: Dictionary) -> bool:
	if source_id == &"":
		push_warning("CharacterStats: a modifier source needs a stable id")
		return false
	if modifiers.is_empty():
		return clear_modifiers(source_id)
	var cleaned: Dictionary = {}
	for stat: Variant in modifiers:
		var key := StringName(stat)
		if not STATS.has(key):
			push_warning("CharacterStats: ignoring unknown stat '%s' from '%s'" % [key, source_id])
			continue
		var value: Variant = modifiers[stat]
		if not (value is int or value is float) or not is_finite(float(value)):
			push_warning(
				"CharacterStats: ignoring non-finite value for '%s' from '%s'" % [key, source_id]
			)
			continue
		cleaned[key] = float(value)
	_modifiers[source_id] = cleaned
	return _recalculate()


func clear_modifiers(source_id: StringName) -> bool:
	if not _modifiers.has(source_id):
		return false
	_modifiers.erase(source_id)
	return _recalculate()


func has_source(source_id: StringName) -> bool:
	return _modifiers.has(source_id)


## Recomputed effective values; emits `changed` when anything differs.
func _recalculate() -> bool:
	if not _ready:
		return false
	var next: Dictionary = {}
	for stat in STATS:
		var value: float = base(stat) + modifier_total(stat)
		next[stat] = maxf(float(MINIMUM[stat]), value)
	var differs := next != _effective
	_effective = next
	if differs:
		changed.emit()
	return differs


func _to_string() -> String:
	return "CharacterStats(hp=%.0f, atk=%.0f, def=%.0f, spd=%.2f)" % [
		effective(MAX_HEALTH), effective(ATTACK_DAMAGE), effective(DEFENSE),
		effective(MOVEMENT_SPEED)
	]
