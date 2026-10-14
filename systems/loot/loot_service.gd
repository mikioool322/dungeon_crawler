class_name LootService
extends RefCounted

## The single loot entry point and the only writer of `PlayerSessionState.inventory`,
## `PlayerSessionState.gold` and `PlayerSessionState.claimed_reward_keys` (ADR-009).
##
## Invariants:
## - `grant()` is idempotent per `grant_key`: a key that is already claimed (in this
##   run or restored from a save) returns `duplicate` and changes nothing.
## - All validation (grant shape, service readiness, registry lookup) completes before
##   the first mutation. A rejected grant therefore neither changes gold/bag nor
##   consumes the key, so the same key can still be granted later.
## - `reward_granted` is emitted exactly once per successful grant, after the session
##   is consistent, and carries the new gold total.
## - The service never decides *when* loot exists: enemy death and pickups create the
##   grant, the world host supplies the key, this service only applies it.
##
## Registry injection:
## - `setup()` takes the typed `ContentRegistry`; the service resolves items only
##   through its frozen `find_item(id) -> ItemDefinition` lookup.
## - A missing registry (null) degrades to `unknown_item` for item rewards;
##   gold-only grants never need the registry.
## - A definition returned by the registry must itself pass `ItemDefinition.is_valid()`,
##   otherwise it is treated as `unknown_item` (a bag cannot represent it).

signal reward_granted(grant: LootGrant, gold_total: int)

const CODE_GRANTED := &"granted"
const CODE_DUPLICATE := &"duplicate"
const CODE_INVALID := &"invalid"
const CODE_UNKNOWN_ITEM := &"unknown_item"

var _state: PlayerSessionState = null
var _registry: ContentRegistry = null


## Binds the run state and the content registry. The state may be null; the service
## then reports `invalid` (never crashes) until `setup()` is called with a state.
func setup(state: PlayerSessionState, registry: ContentRegistry) -> void:
	_state = state
	_registry = registry


## True when `grant_key` is recorded in the session (or restored from a save).
func is_claimed(grant_key: StringName) -> bool:
	if _state == null:
		return false
	return _state.is_claimed(grant_key)


## Applies one grant atomically and returns one of the four documented codes.
##
## Codes: `granted`, `duplicate` (key already claimed), `invalid` (malformed grant or
## service without a state/bag), `unknown_item` (item id not resolvable).
func grant(grant: LootGrant) -> StringName:
	if grant == null or not grant.is_valid():
		return CODE_INVALID
	if _state == null:
		return CODE_INVALID
	if _state.is_claimed(grant.grant_key):
		return CODE_DUPLICATE

	# --- validation ends here: resolve everything the grant needs -----------------
	var item: ItemDefinition = null
	if grant.item_id != &"":
		item = _find_item(grant.item_id)
		if item == null:
			return CODE_UNKNOWN_ITEM
		if _state.inventory == null:
			return CODE_INVALID

	# --- first mutation ------------------------------------------------------------
	if item != null:
		var added: int = _state.inventory.add(item, grant.item_count)
		if added != grant.item_count:
			# Defensive: `Inventory.add()` is all-or-nothing, so a short add means the
			# bag refused the definition. Nothing has been mutating yet, so the key is
			# not consumed and the grant can be retried with fixed content.
			return CODE_UNKNOWN_ITEM
	if grant.gold > 0:
		_state.gold += grant.gold
	_state.claim(grant.grant_key)
	reward_granted.emit(grant, _state.gold)
	return CODE_GRANTED


## Resolves an item through the registry's lookup API, or null.
func _find_item(item_id: StringName) -> ItemDefinition:
	if _registry == null:
		return null
	var found := _registry.find_item(item_id)
	if found != null and found.is_valid():
		return found
	return null


func _to_string() -> String:
	return "LootService(state=%s, registry=%s)" % [_state, _registry]
