class_name LootService
extends RefCounted

## The single loot entry point and the only writer of `PlayerSessionState.inventory`,
## `PlayerSessionState.gold` and `PlayerSessionState.claimed_reward_keys` (ADR-009).
##
## Invariants:
## - `grant()` is idempotent per `grant_key` and ledger (ADR-013): a key already claimed in
##   the current run returns `duplicate` and changes nothing; a story key already claimed in
##   the save does the same. Run-scoped keys are never persisted, so a new run can earn them
##   again.
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

## The grant belongs to a run that is no longer current (ADR-012 rule 10).
const CODE_STALE_RUN := &"stale_run"

var _state: PlayerSessionState = null
var _registry: ContentRegistry = null

## Transient ledger of run-scoped claims: `grant_key -> true`. Cleared on every
## `begin_run()`/`end_run()`, so ordinary rewards repeat per run and never grow the
## save file (ADR-013).
var _run_claims: Dictionary = {}
var _run_id: int = 0


## Binds the run state and the content registry. The state may be null; the service
## then reports `invalid` (never crashes) until `setup()` is called with a state.
func setup(state: PlayerSessionState, registry: ContentRegistry) -> void:
	_state = state
	_registry = registry


## True when `grant_key` is recorded in the persistent (story) ledger.
func is_claimed(grant_key: StringName) -> bool:
	if _state == null:
		return false
	return _state.is_claimed(grant_key)


## True when `grant_key` was already claimed during the current dungeon run.
func is_claimed_in_run(grant_key: StringName) -> bool:
	return _run_claims.has(grant_key)


func current_run_id() -> int:
	return _run_id


## Opens the transient ledger of a new dungeon run (ADR-012: ordinary rewards reset
## per run). Called by the run owner, never by an interactable.
func begin_run(run_id: int) -> void:
	_run_claims.clear()
	_run_id = maxi(0, run_id)


## Closes the transient ledger when the player leaves the dungeon.
func end_run() -> void:
	_run_claims.clear()
	_run_id = 0


## Applies one grant atomically and returns a documented code.
##
## Codes: `granted`, `duplicate` (key already claimed in the grant's ledger),
## `invalid` (malformed grant or service without a state/bag), `unknown_item`
## (item id not resolvable), `stale_run` (run-scoped grant from an older run).
func grant(grant: LootGrant) -> StringName:
	if grant == null or not grant.is_valid():
		return CODE_INVALID
	if _state == null:
		return CODE_INVALID
	if grant.run_id > 0 and grant.run_id != _run_id:
		return CODE_STALE_RUN
	if grant.is_story_scope():
		if _state.is_claimed(grant.grant_key):
			return CODE_DUPLICATE
	else:
		if _run_id <= 0:
			# A repeatable reward belongs to a dungeon run (ADR-012 rule 6): granting one
			# without an active run would create a claim that no run owns.
			push_warning("LootService: run-scoped grant '%s' without an active run" % grant.grant_key)
			return CODE_INVALID
		if _run_claims.has(grant.grant_key):
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
	if grant.is_story_scope():
		_state.claim(grant.grant_key)
	else:
		_run_claims[grant.grant_key] = true
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
