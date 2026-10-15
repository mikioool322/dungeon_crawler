extends "res://tests/test_case.gd"

## AC-42 — trading: one price rule, atomic operations, refusals that mutate nothing and
## no way to duplicate gold or items.

const SWORD := &"item.test.sword"
const VEST := &"item.test.vest"
const ROCK := &"item.test.rock"
const WORTHLESS := &"item.test.junk"

var _registry: ContentRegistry = null
var _state: PlayerSessionState = null
var _equipment: EquipmentState = null
var _trading: TradingService = null
var _trades: Array[Dictionary] = []


func setup() -> void:
	_registry = _build_registry()
	_state = PlayerSessionState.new()
	_equipment = EquipmentState.new()
	_equipment.setup(_registry, _state.inventory)
	_trading = TradingService.new()
	_trading.setup(_state, _registry, _equipment)
	_trading.bind_merchant(_registry.find_merchant(&"merchant.test"))
	_trades = []
	_trading.trade_completed.connect(
		func(kind: StringName, item_id: StringName, price: int, gold_total: int) -> void:
			_trades.append({"kind": kind, "item": item_id, "price": price, "gold": gold_total})
	)


func teardown() -> void:
	# The signal connection above points back at this test object: dropping the references
	# breaks the cycle, so neither the service nor the test leaks.
	_trading = null
	_equipment = null
	_state = null
	_registry = null
	_trades = []


func _build_registry() -> ContentRegistry:
	var manifest := ContentManifest.new()

	var sword := ItemDefinition.new()
	sword.id = SWORD
	sword.display_name = "Test Sword"
	sword.kind = ItemDefinition.Kind.WEAPON
	sword.stackable = false
	sword.max_stack = 1
	sword.slot = EquipmentSlot.Id.MAIN_HAND
	sword.attack_bonus = 15
	sword.base_value = 40

	var vest := ItemDefinition.new()
	vest.id = VEST
	vest.display_name = "Test Vest"
	vest.kind = ItemDefinition.Kind.MISC
	vest.stackable = false
	vest.max_stack = 1
	vest.slot = EquipmentSlot.Id.CHEST_ARMOR
	vest.defense_bonus = 5
	vest.base_value = 30

	var rock := ItemDefinition.new()
	rock.id = ROCK
	rock.display_name = "Test Rock"
	rock.kind = ItemDefinition.Kind.MISC
	rock.stackable = true
	rock.max_stack = 5
	rock.base_value = 8

	var worthless := ItemDefinition.new()
	worthless.id = WORTHLESS
	worthless.display_name = "Priceless Trinket"
	worthless.kind = ItemDefinition.Kind.MISC
	worthless.stackable = false
	worthless.max_stack = 1
	worthless.base_value = 0

	var items: Array[ItemDefinition] = [sword, vest, rock, worthless]
	manifest.items = items

	var merchant := MerchantDefinition.new()
	merchant.id = &"merchant.test"
	merchant.display_name = "Test Merchant"
	merchant.greeting = "Coin for steel."
	var stock: Array[ItemDefinition] = [sword, vest]
	merchant.stock = stock
	var merchants: Array[MerchantDefinition] = [merchant]
	manifest.merchants = merchants

	return ContentRegistry.build(manifest)


func _definition(item_id: StringName) -> ItemDefinition:
	return _registry.find_item(item_id)


# --- prices -------------------------------------------------------------------

func test_prices_follow_the_single_documented_rule() -> void:
	assert_eq(_trading.buy_price(SWORD), 40, "buy price is the base value")
	assert_eq(_trading.sell_price(SWORD), 20, "sell price is half, rounded down")
	assert_eq(_trading.buy_price(ROCK), 8, "the price is the item's own value, stocked or not")
	assert_eq(_trading.sell_price(WORTHLESS), 0, "an item without a base value is not tradable")


func test_the_sell_price_is_always_below_the_buy_price() -> void:
	for item_id in [SWORD, VEST]:
		assert_true(
			_trading.sell_price(item_id) < _trading.buy_price(item_id),
			"no buy/sell loop is profitable for %s" % item_id
		)


# --- buying -------------------------------------------------------------------

func test_buying_subtracts_gold_and_grants_the_item() -> void:
	_state.gold = 100
	assert_eq(_trading.can_buy(SWORD), TradingService.CODE_OK, "affordable and stocked")
	assert_eq(_trading.buy(SWORD), TradingService.CODE_OK, "bought")
	assert_eq(_state.gold, 60, "gold decreased by exactly the price")
	assert_eq(_state.inventory.count_of(SWORD), 1, "the item is in the bag")
	assert_eq(_trades.size(), 1, "one trade event")
	assert_eq(_trades[0]["kind"], TradingService.KIND_BUY, "reported as a buy")
	assert_eq(_trades[0]["gold"], 60, "the event carries the new total")


func test_buying_without_enough_gold_is_refused_and_changes_nothing() -> void:
	_state.gold = 10
	assert_eq(_trading.buy(SWORD), TradingService.CODE_NOT_ENOUGH_GOLD, "refused")
	assert_eq(_state.gold, 10, "gold untouched")
	assert_eq(_state.inventory.count_of(SWORD), 0, "nothing granted")
	assert_eq(_trades.size(), 0, "no event")


func test_buying_an_unstocked_or_unknown_item_is_refused() -> void:
	_state.gold = 500
	assert_eq(_trading.buy(ROCK), TradingService.CODE_NOT_STOCKED, "not in stock")
	assert_eq(_trading.buy(&"item.ghost"), TradingService.CODE_UNKNOWN_ITEM, "unknown id")
	assert_eq(_trading.buy(WORTHLESS), TradingService.CODE_NOT_STOCKED, "not stocked either")
	assert_eq(_state.gold, 500, "gold untouched")
	assert_eq(_state.inventory.total_item_count(), 0, "nothing granted")


func test_a_duplicate_buy_event_cannot_double_charge_or_double_grant() -> void:
	_state.gold = 80
	assert_eq(_trading.buy(SWORD), TradingService.CODE_OK, "first click buys")
	assert_eq(_state.gold, 40, "charged once")
	assert_eq(_state.inventory.count_of(SWORD), 1, "one item")
	# A second identical event: affordable again (40 gold), so it must be a normal second
	# purchase, not a duplicate grant.
	assert_eq(_trading.buy(SWORD), TradingService.CODE_OK, "a second, deliberate purchase")
	assert_eq(_state.gold, 0, "charged exactly twice")
	assert_eq(_state.inventory.count_of(SWORD), 2, "two items, no duplication")
	assert_eq(_trades.size(), 2, "two events")


# --- selling ------------------------------------------------------------------

func test_selling_removes_the_item_and_grants_gold() -> void:
	_state.inventory.add(_definition(ROCK), 2)
	_state.gold = 0
	assert_eq(_trading.can_sell(ROCK), TradingService.CODE_OK, "sellable")
	assert_eq(_trading.sell(ROCK), TradingService.CODE_OK, "sold")
	assert_eq(_state.gold, 4, "half of 8, rounded down")
	assert_eq(_state.inventory.count_of(ROCK), 1, "one copy left")


func test_selling_an_unowned_item_is_refused() -> void:
	_state.gold = 5
	assert_eq(_trading.sell(ROCK), TradingService.CODE_NOT_IN_BAG, "not owned")
	assert_eq(_state.gold, 5, "gold untouched")
	assert_eq(_trades.size(), 0, "no event")


func test_selling_an_equipped_item_is_refused() -> void:
	_state.inventory.add(_definition(SWORD), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	assert_eq(_state.inventory.count_of(SWORD), 0, "the worn copy left the bag")
	assert_eq(_trading.sell(SWORD), TradingService.CODE_EQUIPPED, "the defensive equipped check fires first")


func test_a_spare_copy_of_an_equipped_item_is_sellable() -> void:
	# Ownership A is per copy, not per id: the worn sword is untouchable, a second one in the
	# bag is ordinary goods.
	_state.inventory.add(_definition(SWORD), 1)
	_state.inventory.add(_definition(SWORD), 1)
	_equipment.equip(SWORD, EquipmentSlot.Id.MAIN_HAND)
	assert_eq(_state.inventory.count_of(SWORD), 1, "one copy stayed in the bag")
	assert_eq(_trading.can_sell(SWORD), TradingService.CODE_OK, "the spare is sellable")
	assert_eq(_trading.sell(SWORD), TradingService.CODE_OK, "sold the spare")
	assert_eq(_state.inventory.count_of(SWORD), 0, "the bag is empty of swords")
	assert_true(_equipment.is_equipped(SWORD), "the worn copy is untouched")
	assert_eq(
		_trading.sell(SWORD), TradingService.CODE_EQUIPPED,
		"only the worn copy is left, and it is not for sale"
	)


func test_an_item_worth_one_gold_is_not_tradable() -> void:
	var cheap := ItemDefinition.new()
	cheap.id = &"item.test.cheap"
	cheap.display_name = "Copper Trinket"
	cheap.kind = ItemDefinition.Kind.MISC
	cheap.stackable = false
	cheap.max_stack = 1
	cheap.base_value = 1
	assert_false(cheap.is_tradable(), "base_value 1 would make sell == buy")
	assert_true(cheap.is_valid(), "but it is still a valid item definition")


func test_selling_a_non_tradable_item_is_refused() -> void:
	_state.inventory.add(_definition(WORTHLESS), 1)
	assert_eq(_trading.sell(WORTHLESS), TradingService.CODE_NOT_TRADABLE, "base_value 0")
	assert_eq(_state.inventory.count_of(WORTHLESS), 1, "the item stays")


func test_selling_everything_keeps_gold_and_bag_consistent() -> void:
	_state.inventory.add(_definition(ROCK), 3)
	for _i in 3:
		assert_eq(_trading.sell(ROCK), TradingService.CODE_OK, "sold a copy")
	assert_eq(_state.inventory.count_of(ROCK), 0, "the bag is empty of rocks")
	assert_eq(_state.gold, 12, "3 x 4 gold")
	assert_eq(_trading.sell(ROCK), TradingService.CODE_NOT_IN_BAG, "a fourth sell is refused")
	assert_eq(_state.gold, 12, "gold unchanged by the refusal")


func test_gold_never_goes_negative_across_many_transactions() -> void:
	_state.gold = 45
	for _i in 3:
		_trading.buy(SWORD)
	assert_eq(_state.gold, 5, "45 buys exactly one 40-gold sword")
	assert_eq(_trading.buy(SWORD), TradingService.CODE_NOT_ENOUGH_GOLD, "the next buy is refused")
	assert_true(_state.gold >= 0, "gold never negative")
	assert_eq(_state.inventory.count_of(SWORD), 1, "exactly one sword")


func test_a_shop_without_a_merchant_is_refused() -> void:
	var trading := TradingService.new()
	trading.setup(_state, _registry, _equipment)
	assert_eq(trading.buy(SWORD), TradingService.CODE_NO_MERCHANT, "no merchant bound")
	assert_eq(trading.sell(SWORD), TradingService.CODE_NO_MERCHANT, "no merchant bound")
	assert_eq(trading.buy_price(SWORD), 40, "prices still readable")
