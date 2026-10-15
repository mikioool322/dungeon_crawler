extends "res://tests/test_case.gd"

## S04-QA — independent verification of the ADR-017 anti-exploit rules.
##
## Gaps this file closes:
## - a long buy/sell alternation proves the spread makes gold strictly decrease; no
##   sequence can create gold and gold never goes negative.
## - `buy`/`sell` re-validate after `can_buy`/`can_sell`: an unbound merchant, a drained
##   bag, a drained purse and an equipped item are all caught inside the operation.
## - invalid prices (`base_value <= 0`) are refused in both directions, including a
##   stocked-but-worthless item.
## - every *shipped* item (not only the merchant's stock) keeps sell < buy.

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const MERCHANT := &"merchant.hub.smith"
const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const SALVE := &"item.minor_salve"
const DAGGER := &"item.rusty_dagger"

const SWORD_PRICE := 40
const SALVE_PRICE := 3

var _registry: ContentRegistry = null
var _state: PlayerSessionState = null
var _equipment: EquipmentState = null
var _trading: TradingService = null
var _trades: Array[Dictionary] = []


func setup() -> void:
	_registry = ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)
	_state = PlayerSessionState.new()
	_equipment = EquipmentState.new()
	_equipment.setup(_registry, _state.inventory)
	_trading = TradingService.new()
	_trading.setup(_state, _registry, _equipment)
	_trading.bind_merchant(_registry.find_merchant(MERCHANT))
	_trades = []
	_trading.trade_completed.connect(
		func(kind: StringName, item_id: StringName, price: int, gold_total: int) -> void:
			_trades.append({"kind": kind, "item": item_id, "price": price, "gold": gold_total})
	)


func teardown() -> void:
	# The signal connection above points back at this test object: dropping the
	# references breaks the cycle, so nothing leaks.
	_trading = null
	_equipment = null
	_state = null
	_registry = null
	_trades = []


# --- loops ---------------------------------------------------------------------

func test_a_buy_sell_loop_cannot_create_gold() -> void:
	_state.gold = 1000
	var previous := _state.gold
	for cycle in 40:
		assert_eq(_trading.buy(SWORD), TradingService.CODE_OK, "cycle %d: buy" % cycle)
		assert_eq(_state.gold, previous - SWORD_PRICE, "cycle %d: gold fell by the buy price" % cycle)
		assert_eq(_state.inventory.count_of(SWORD), 1, "cycle %d: one copy is held" % cycle)
		assert_eq(_trading.sell(SWORD), TradingService.CODE_OK, "cycle %d: sell" % cycle)
		assert_eq(_state.gold, previous - SWORD_PRICE + 20, "cycle %d: the sell paid half" % cycle)
		assert_eq(_state.inventory.count_of(SWORD), 0, "cycle %d: the copy left the bag" % cycle)
		assert_true(_state.gold < previous, "cycle %d: the alternation lost gold" % cycle)
		previous = _state.gold
	assert_eq(_state.gold, 1000 - 40 * (SWORD_PRICE - 20), "40 alternations lost 20 each")
	assert_eq(_state.inventory.count_of(SWORD), 0, "no item was left behind")
	assert_eq(_trades.size(), 80, "every accepted operation reported exactly one trade")
	for trade: Dictionary in _trades:
		var price: int = trade["price"]
		if trade["kind"] == TradingService.KIND_BUY:
			assert_eq(price, SWORD_PRICE, "the buy price is the base value")
		else:
			assert_eq(price, 20, "the sell price is half the base value")


func test_gold_never_goes_negative_across_a_long_mixed_sequence() -> void:
	_state.gold = 25
	_state.inventory.add(_registry.find_item(SALVE), 20)
	var sells := 0
	var buys := 0
	for step in 60:
		var sell_code := _trading.sell(SALVE)
		if sell_code == TradingService.CODE_OK:
			sells += 1
		else:
			assert_eq(sell_code, TradingService.CODE_NOT_IN_BAG, "step %d: only sold-out refusals" % step)
		assert_true(_state.gold >= 0, "step %d: gold never negative after a sell" % step)
		var buy_code := _trading.buy(SWORD)
		if buy_code == TradingService.CODE_OK:
			buys += 1
		else:
			assert_eq(
				buy_code, TradingService.CODE_NOT_ENOUGH_GOLD,
				"step %d: the only buy refusal is insufficient gold" % step
			)
		assert_true(_state.gold >= 0, "step %d: gold never negative after a buy" % step)
	assert_eq(sells, 20, "all 20 salves were sold exactly once")
	assert_true(buys >= 1, "at least one sword was bought")
	assert_eq(
		_state.gold, 25 + sells * SALVE_PRICE - buys * SWORD_PRICE,
		"the final purse is exactly the arithmetic sum of the trades"
	)
	assert_eq(_state.inventory.count_of(SWORD), buys, "exactly one sword per accepted buy")
	assert_eq(_state.inventory.count_of(SALVE), 0, "no salve was duplicated or lost")


# --- re-validation -------------------------------------------------------------

func test_buy_and_sell_revalidate_after_the_merchant_was_unbound() -> void:
	_state.gold = 100
	assert_eq(_trading.can_buy(SWORD), TradingService.CODE_OK, "the shop is ready")
	_trading.bind_merchant(null)
	var bag_before := _state.inventory.total_item_count()
	assert_eq(_trading.buy(SWORD), TradingService.CODE_NO_MERCHANT, "buy refuses without a merchant")
	assert_eq(_trading.sell(SALVE), TradingService.CODE_NO_MERCHANT, "sell refuses without a merchant")
	assert_eq(_state.gold, 100, "gold is untouched")
	assert_eq(_state.inventory.total_item_count(), bag_before, "the bag is untouched")
	assert_eq(_trades.size(), 0, "no trade event was emitted")


func test_buy_revalidates_when_the_purse_changed_after_can_buy() -> void:
	_state.gold = 100
	assert_eq(_trading.can_buy(SWORD), TradingService.CODE_OK, "affordable at the check")
	_state.gold = 0  # the UI read can_buy, then another system spent the gold
	assert_eq(
		_trading.buy(SWORD), TradingService.CODE_NOT_ENOUGH_GOLD,
		"the operation itself catches the drained purse"
	)
	assert_eq(_state.gold, 0, "gold stays at zero, never negative")
	assert_eq(_state.inventory.count_of(SWORD), 0, "nothing was granted")
	assert_eq(_trades.size(), 0, "no trade event was emitted")


func test_sell_revalidates_when_the_bag_changed_after_can_sell() -> void:
	_state.inventory.add(_registry.find_item(SALVE), 1)
	assert_eq(_trading.can_sell(SALVE), TradingService.CODE_OK, "sellable at the check")
	_state.inventory.remove(SALVE, 1)  # the bag changed between the check and the click
	assert_eq(
		_trading.sell(SALVE), TradingService.CODE_NOT_IN_BAG,
		"the operation itself catches the emptied stack"
	)
	assert_eq(_state.gold, 0, "no gold was granted")
	assert_eq(_trades.size(), 0, "no trade event was emitted")


func test_sell_revalidates_when_the_item_became_equipped_after_can_sell() -> void:
	_state.inventory.add(_registry.find_item(SWORD), 1)
	assert_eq(_trading.can_sell(SWORD), TradingService.CODE_OK, "sellable at the check")
	assert_eq(
		_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND), EquipmentState.CODE_OK,
		"the item moves into the slot"
	)
	assert_eq(
		_trading.sell(SWORD), TradingService.CODE_EQUIPPED,
		"the operation itself refuses the equipped item"
	)
	assert_eq(_state.gold, 0, "no gold was granted")
	assert_eq(_trades.size(), 0, "no trade event was emitted")


# --- invalid prices ------------------------------------------------------------

func _invalid_price_registry() -> ContentRegistry:
	var manifest := ContentManifest.new()

	var worthless := ItemDefinition.new()
	worthless.id = &"item.qa.worthless"
	worthless.display_name = "Worthless"
	worthless.kind = ItemDefinition.Kind.MISC
	worthless.stackable = true
	worthless.max_stack = 5
	worthless.base_value = 0

	var cursed := ItemDefinition.new()
	cursed.id = &"item.qa.cursed"
	cursed.display_name = "Cursed"
	cursed.kind = ItemDefinition.Kind.MISC
	cursed.stackable = true
	cursed.max_stack = 5
	cursed.base_value = -5

	var items: Array[ItemDefinition] = [worthless, cursed]
	manifest.items = items

	var merchant := MerchantDefinition.new()
	merchant.id = &"merchant.qa"
	merchant.display_name = "QA Merchant"
	merchant.greeting = "Nothing is free."
	var stock: Array[ItemDefinition] = [worthless, cursed]
	merchant.stock = stock
	var merchants: Array[MerchantDefinition] = [merchant]
	manifest.merchants = merchants

	# The manifest is intentionally invalid; the lookups must still degrade safely.
	return ContentRegistry.build(manifest)


func test_invalid_prices_are_refused_in_both_directions() -> void:
	var registry := _invalid_price_registry()
	var state := PlayerSessionState.new()
	var equipment := EquipmentState.new()
	equipment.setup(registry, state.inventory)
	var trading := TradingService.new()
	trading.setup(state, registry, equipment)
	trading.bind_merchant(registry.find_merchant(&"merchant.qa"))
	state.gold = 100

	assert_eq(trading.buy_price(&"item.qa.worthless"), 0, "a 0-value item has no buy price")
	assert_eq(trading.sell_price(&"item.qa.worthless"), 0, "and no sell price")
	assert_eq(
		trading.can_buy(&"item.qa.worthless"), TradingService.CODE_NOT_TRADABLE,
		"stocked but worthless: not tradable"
	)
	assert_eq(trading.buy(&"item.qa.worthless"), TradingService.CODE_NOT_TRADABLE, "buy refused")
	assert_eq(trading.sell(&"item.qa.worthless"), TradingService.CODE_NOT_TRADABLE, "sell refused")
	assert_eq(trading.buy_price(&"item.qa.cursed"), 0, "a negative value is not a price")
	assert_eq(trading.sell_price(&"item.qa.cursed"), 0, "in either direction")
	assert_eq(trading.buy(&"item.qa.cursed"), TradingService.CODE_NOT_TRADABLE, "buy refused")
	assert_eq(trading.sell(&"item.qa.cursed"), TradingService.CODE_NOT_TRADABLE, "sell refused")
	assert_eq(trading.buy(&"item.ghost"), TradingService.CODE_UNKNOWN_ITEM, "an unknown id is refused")
	assert_eq(trading.sell(&"item.ghost"), TradingService.CODE_UNKNOWN_ITEM, "in both directions")
	assert_eq(trading.buy(&""), TradingService.CODE_UNKNOWN_ITEM, "an empty id is refused")
	assert_eq(trading.buy_price(&""), 0, "and has no price")
	assert_eq(state.gold, 100, "no refusal touched the gold")
	assert_eq(state.inventory.total_item_count(), 0, "no refusal granted an item")


func test_every_shipped_item_sell_price_stays_strictly_below_its_buy_price() -> void:
	var manifest := load(MANIFEST_PATH) as ContentManifest
	if manifest == null:
		fail("the shipped manifest failed to load")
		return
	var state := PlayerSessionState.new()
	var equipment := EquipmentState.new()
	equipment.setup(_registry, state.inventory)
	var trading := TradingService.new()
	trading.setup(state, _registry, equipment)
	trading.bind_merchant(_registry.find_merchant(MERCHANT))

	var checked := 0
	for item: ItemDefinition in manifest.items:
		if not item.is_tradable():
			assert_eq(trading.sell_price(item.id), 0, "%s is not tradable" % item.id)
			continue
		checked += 1
		var buy: int = trading.buy_price(item.id)
		var sell: int = trading.sell_price(item.id)
		assert_true(sell >= 1, "%s sells for at least one gold" % item.id)
		assert_true(sell < buy, "%s cannot be bought and sold for a profit (%d -> %d)" % [item.id, buy, sell])
	assert_true(checked >= 4, "all four shipped tradable items were checked (got %d)" % checked)
	# The same rule must hold for the shipped story weapon, which is not stocked.
	assert_true(
		trading.sell_price(DAGGER) < trading.buy_price(DAGGER),
		"the story dagger keeps the spread"
	)
	assert_true(trading.sell_price(VEST) < trading.buy_price(VEST), "the vest keeps the spread")
