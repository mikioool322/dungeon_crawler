class_name TradingService
extends RefCounted

## Buying and selling with one merchant (ADR-017): the only trade writer and the only
## place with a price rule.
##
## Invariants:
## - Prices come from `ItemDefinition.base_value`: `buy = base_value`,
##   `sell = max(1, floor(base_value * SELL_RATE))`. The spread makes a buy/sell loop
##   unprofitable, so no gold exploit exists even without a stock limit.
## - Every operation re-validates internally (never trusting `can_buy`/`can_sell`) and is
##   atomic: full validation first, then the bag, then gold. A refusal mutates nothing, so
##   a duplicated UI event cannot grant or take anything twice.
## - Gold is a whole number and never goes below zero; the bag is never left short.
## - Sprint 04 stock is unlimited for the configured items (the owner's scope): the
##   service tracks nothing that would need saving.

signal trade_completed(kind: StringName, item_id: StringName, price: int, gold_total: int)

const CODE_OK := &"ok"
const CODE_INVALID := &"invalid"
const CODE_NO_MERCHANT := &"no_merchant"
const CODE_UNKNOWN_ITEM := &"unknown_item"
const CODE_NOT_STOCKED := &"not_stocked"
const CODE_NOT_TRADABLE := &"not_tradable"
const CODE_NOT_ENOUGH_GOLD := &"not_enough_gold"
const CODE_NOT_IN_BAG := &"not_in_bag"
const CODE_EQUIPPED := &"equipped"

const KIND_BUY := &"buy"
const KIND_SELL := &"sell"

## Sell price as a fraction of the buy price; the single pricing rule of the game.
const SELL_RATE: float = 0.5

var _state: PlayerSessionState = null
var _registry: ContentRegistry = null
var _equipment: EquipmentState = null
var _merchant: MerchantDefinition = null


func setup(state: PlayerSessionState, registry: ContentRegistry, equipment: EquipmentState) -> void:
	_state = state
	_registry = registry
	_equipment = equipment


## Opens a merchant; a null merchant closes the shop. Stock is unlimited in Sprint 04.
func bind_merchant(merchant: MerchantDefinition) -> void:
	_merchant = merchant


func current_merchant() -> MerchantDefinition:
	return _merchant


func is_ready() -> bool:
	return _state != null and _registry != null and _merchant != null


func is_stocked(item_id: StringName) -> bool:
	if _merchant == null:
		return false
	for item in _merchant.stock:
		if item != null and item.id == item_id:
			return true
	return false


## Whole-gold price the player pays, or 0 when the item cannot be bought.
func buy_price(item_id: StringName) -> int:
	var definition := _definition(item_id)
	if definition == null or not definition.is_tradable():
		return 0
	return definition.base_value


## Whole-gold price the player receives, or 0 when the item cannot be sold.
func sell_price(item_id: StringName) -> int:
	var definition := _definition(item_id)
	if definition == null or not definition.is_tradable():
		return 0
	return maxi(1, int(floor(float(definition.base_value) * SELL_RATE)))


func can_buy(item_id: StringName) -> StringName:
	if not is_ready():
		return CODE_NO_MERCHANT
	var definition := _definition(item_id)
	if definition == null:
		return CODE_UNKNOWN_ITEM
	if not is_stocked(item_id):
		return CODE_NOT_STOCKED
	if not definition.is_tradable():
		return CODE_NOT_TRADABLE
	if _state.gold < buy_price(item_id):
		return CODE_NOT_ENOUGH_GOLD
	return CODE_OK


## Buys one copy. Atomic: either the bag and gold both change, or nothing does.
func buy(item_id: StringName) -> StringName:
	var code := can_buy(item_id)
	if code != CODE_OK:
		return code
	var definition := _definition(item_id)
	var price := buy_price(item_id)
	var added: int = _state.inventory.add(definition, 1)
	if added != 1:
		# The bag refused the definition; gold is untouched.
		return CODE_INVALID
	_state.gold = maxi(0, _state.gold - price)
	trade_completed.emit(KIND_BUY, item_id, price, _state.gold)
	return CODE_OK


func can_sell(item_id: StringName) -> StringName:
	if not is_ready():
		return CODE_NO_MERCHANT
	var definition := _definition(item_id)
	if definition == null:
		return CODE_UNKNOWN_ITEM
	if not definition.is_tradable():
		return CODE_NOT_TRADABLE
	if _equipment != null and _equipment.is_equipped(item_id):
		# Impossible under ownership semantics A (an equipped item is not in the bag);
		# kept as a defensive check for a hand-edited state.
		return CODE_EQUIPPED
	if _state.inventory.count_of(item_id) < 1:
		return CODE_NOT_IN_BAG
	return CODE_OK


## Sells one copy. Atomic: either the bag and gold both change, or nothing does.
func sell(item_id: StringName) -> StringName:
	var code := can_sell(item_id)
	if code != CODE_OK:
		return code
	var price := sell_price(item_id)
	var removed: int = _state.inventory.remove(item_id, 1)
	if removed != 1:
		# The bag changed under us; no gold is granted.
		return CODE_NOT_IN_BAG
	_state.gold += price
	trade_completed.emit(KIND_SELL, item_id, price, _state.gold)
	return CODE_OK


func _definition(item_id: StringName) -> ItemDefinition:
	if _registry == null or item_id == &"":
		return null
	return _registry.find_item(item_id)


func _to_string() -> String:
	return "TradingService(merchant=%s, gold=%d)" % [
		_merchant.id if _merchant != null else &"none",
		_state.gold if _state != null else 0
	]
