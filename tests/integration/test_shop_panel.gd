extends "res://tests/test_case.gd"

## S04 UI — the shop panel and the dialogue's shop entry (ADR-017).
##
## The fixture is a hand-built session: one manifest with a player definition, a
## merchant selling one sword, a non-stock sellable axe and a non-tradable junk item,
## indexed through a real `ContentRegistry` and a real `GameSession`. Every price the
## tests assert comes from `TradingService`; the panel only displays it.

const SWORD_ID := &"item.test.sword"
const AXE_ID := &"item.test.axe"
const JUNK_ID := &"item.test.junk"
const UNKNOWN_ID := &"item.test.unknown"
const BASIC_ATTACK_ID := &"attack.test.basic"
const SWORD_ATTACK_ID := &"attack.test.sword"
const SWORD_NAME := "Test Sword"
const AXE_NAME := "Test Axe"
const SWORD_PRICE := 40
const AXE_PRICE := 10
const START_GOLD := 100
const MERCHANT_ID := &"merchant.test.smith"
const NPC_ID := &"npc.test.smith"
const HERMIT_ID := &"npc.test.hermit"
const HUD_SCENE_PATH := "res://presentation/hud/game_hud.tscn"
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _panel: ShopPanel = null
var _merchant: MerchantDefinition = null
var _npc: NpcDefinition = null
var _hermit: NpcDefinition = null


## Minimal router double for the HUD wiring test: `GameHud` only asks the router for the
## current world when a world load is announced.
class StubRouter extends WorldRouter:
	var world: WorldHost = null

	func current_world() -> WorldHost:
		return world


func teardown() -> void:
	Input.action_release(&"ui_cancel")
	_registry = null
	_session = null
	_panel = null
	_merchant = null
	_npc = null
	_hermit = null


# --- fixture ------------------------------------------------------------------

func _attack(id: StringName, damage: float) -> AttackDefinition:
	var attack := AttackDefinition.new()
	attack.id = id
	attack.damage = damage
	return attack


func _sword(weapon_profile: AttackDefinition) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = SWORD_ID
	item.display_name = SWORD_NAME
	item.kind = ItemDefinition.Kind.WEAPON
	item.stackable = false
	item.max_stack = 1
	item.slot = EquipmentSlot.Id.MAIN_HAND
	item.attack_bonus = 15
	item.attack_definition = weapon_profile
	item.base_value = SWORD_PRICE
	return item


func _axe() -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = AXE_ID
	item.display_name = AXE_NAME
	item.kind = ItemDefinition.Kind.WEAPON
	item.stackable = false
	item.max_stack = 1
	item.slot = EquipmentSlot.Id.MAIN_HAND
	item.base_value = AXE_PRICE
	return item


func _junk() -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = JUNK_ID
	item.display_name = "Test Junk"
	item.kind = ItemDefinition.Kind.MISC
	item.stackable = true
	item.max_stack = 5
	# base_value == 0: not tradable, so it must never be listed in the shop.
	return item


func _player_definition(basic_attack: AttackDefinition) -> PlayerDefinition:
	var definition := PlayerDefinition.new()
	definition.id = &"player.test"
	definition.display_name = "Tester"
	definition.attack_definition = basic_attack
	return definition


func _build_fixture() -> void:
	var basic := _attack(BASIC_ATTACK_ID, 10.0)
	var weapon_profile := _attack(SWORD_ATTACK_ID, 0.0)
	var sword := _sword(weapon_profile)

	_merchant = MerchantDefinition.new()
	_merchant.id = MERCHANT_ID
	_merchant.display_name = "Test Smith"
	_merchant.greeting = "Coin first."
	var stock: Array[ItemDefinition] = [sword]
	_merchant.stock = stock

	_npc = NpcDefinition.new()
	_npc.id = NPC_ID
	_npc.display_name = "Test Smith"
	_npc.greeting = "Steel for coin."
	_npc.merchant = _merchant

	_hermit = NpcDefinition.new()
	_hermit.id = HERMIT_ID
	_hermit.display_name = "Hermit"
	_hermit.greeting = "Leave me be."

	var manifest := ContentManifest.new()
	var attacks: Array[AttackDefinition] = [basic, weapon_profile]
	var items: Array[ItemDefinition] = [sword, _axe(), _junk()]
	var merchants: Array[MerchantDefinition] = [_merchant]
	var npcs: Array[NpcDefinition] = [_npc, _hermit]
	manifest.attacks = attacks
	manifest.items = items
	manifest.player = _player_definition(basic)
	manifest.merchants = merchants
	manifest.npcs = npcs

	_registry = ContentRegistry.build(manifest)
	if not _registry.is_valid():
		fail("fixture manifest is invalid: %s" % _registry.errors)
		return
	_session = GameSession.new()
	_session.setup(_registry, SaveManager.new())
	_session.new_game()
	# Same documented repair as test_inventory_panel.gd: `new_game()` leaves the
	# equipment unbound (see that file's fixture note); re-running the documented
	# `setup()` binds it again so the equip/sell interaction can be exercised.
	_session.setup(_registry, SaveManager.new())
	_session.add_gold(START_GOLD)

	_panel = ShopPanel.new()
	add_to_tree(_panel)
	_panel.bind(_session, _registry)


func _build_player() -> PlayerController:
	# The real rig keeps the scene contract (Head, HealthComponent, InteractionController)
	# intact, so the focus assertions run against the same node shape the game uses.
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	if packed == null:
		fail("%s failed to load" % PLAYER_SCENE_PATH)
		return null
	var player := packed.instantiate() as PlayerController
	if player == null:
		fail("the player scene root is not a PlayerController")
		return null
	add_to_tree(player)
	return player


# --- helpers ------------------------------------------------------------------

func _add_to_bag(item_id: StringName, count: int = 1) -> void:
	_session.state.inventory.add(_registry.find_item(item_id), count)


func _bag(item_id: StringName) -> int:
	return _session.state.inventory.count_of(item_id)


func _row_with(rows: Array, item_id: StringName) -> Dictionary:
	for row: Dictionary in rows:
		if row["item_id"] == item_id:
			return row
	return {}


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


# --- view model ---------------------------------------------------------------

func test_rows_report_service_prices_and_can_buy() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)

	var rows := _panel.rows()
	assert_eq(rows.size(), 1, "the empty bag leaves only the merchant's stock")
	if rows.size() != 1:
		return
	var row := rows[0]
	assert_eq(row["item_id"], SWORD_ID, "the stock row carries the item id")
	assert_eq(row["display_name"], SWORD_NAME, "and the definition's display name")
	assert_eq(row["buy_price"], SWORD_PRICE, "the buy price is the item's base value")
	assert_eq(
		row["buy_price"], _session.trading.buy_price(SWORD_ID), "the row reads the service, not a copy"
	)
	assert_eq(row["sell_price"], 20, "the sell price is the service's half-rate price")
	assert_eq(
		row["sell_price"],
		_session.trading.sell_price(SWORD_ID),
		"the row reads the service's sell price"
	)
	assert_eq(row["owned"], 0, "nothing is owned yet")
	assert_false(row["sellable"], "an item outside the bag cannot be sold")
	assert_true(row["can_buy"], "%d gold afford the %d-gold sword" % [START_GOLD, SWORD_PRICE])
	assert_not_null(
		_panel.find_child("Buy_item_test_sword", true, false), "a Buy button is built per stock row"
	)


func test_buy_grants_the_item_and_subtracts_exactly_the_price() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)

	assert_eq(_panel.buy(SWORD_ID), TradingService.CODE_OK, "the purchase succeeds")
	assert_eq(_bag(SWORD_ID), 1, "the item is in the bag")
	assert_eq(_session.state.gold, START_GOLD - SWORD_PRICE, "gold was subtracted exactly once")

	var row := _row_with(_panel.rows(), SWORD_ID)
	if row.is_empty():
		fail("the stock row is missing after the purchase")
		return
	assert_eq(row["owned"], 1, "the row follows the bag")
	assert_true(row["sellable"], "and the bought item can now be sold")
	assert_true(row["can_buy"], "and bought again while gold allows")


func test_a_second_click_cannot_duplicate_gold_or_items() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)

	# 100 gold buys two 40-gold swords; the third attempt must be refused untouched.
	assert_eq(_panel.buy(SWORD_ID), TradingService.CODE_OK, "the first buy succeeds")
	assert_eq(_panel.buy(SWORD_ID), TradingService.CODE_OK, "the second buy succeeds")
	var gold_after_two := _session.state.gold
	assert_eq(gold_after_two, START_GOLD - 2 * SWORD_PRICE, "each buy paid exactly once")
	assert_eq(_bag(SWORD_ID), 2, "exactly two copies were granted")

	assert_eq(
		_panel.buy(SWORD_ID), TradingService.CODE_NOT_ENOUGH_GOLD, "the third buy is refused"
	)
	assert_eq(_session.state.gold, gold_after_two, "a refused buy leaves gold untouched")
	assert_eq(_bag(SWORD_ID), 2, "and the bag untouched")

	var row := _row_with(_panel.rows(), SWORD_ID)
	if row.is_empty():
		fail("the stock row is missing")
		return
	assert_false(row["can_buy"], "the row reports that the sword is no longer affordable")
	assert_true(
		_panel.status_text().contains(String(TradingService.CODE_NOT_ENOUGH_GOLD)),
		"the refusal code is shown: '%s'" % _panel.status_text()
	)


func test_sell_grants_the_sell_price_and_removes_the_item() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)
	_add_to_bag(SWORD_ID, 1)
	var price := _session.trading.sell_price(SWORD_ID)
	var gold_before := _session.state.gold

	assert_eq(_panel.sell(SWORD_ID), TradingService.CODE_OK, "selling a bagged item succeeds")
	assert_eq(_bag(SWORD_ID), 0, "the item left the bag")
	assert_eq(_session.state.gold, gold_before + price, "gold rose by the service's sell price")


func test_selling_an_unowned_item_is_refused() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)

	assert_eq(
		_panel.sell(AXE_ID), TradingService.CODE_NOT_IN_BAG, "an item outside the bag cannot be sold"
	)
	assert_eq(_session.state.gold, START_GOLD, "gold is untouched")
	assert_eq(
		_panel.sell(UNKNOWN_ID), TradingService.CODE_UNKNOWN_ITEM, "an unknown id is refused"
	)
	assert_eq(_session.state.gold, START_GOLD, "and gold stays untouched")


func test_a_sellable_bag_entry_is_listed_even_when_not_stocked() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)
	_add_to_bag(AXE_ID, 1)

	var rows := _panel.rows()
	assert_eq(rows.size(), 2, "the merchant's stock plus the sellable bag entry")
	var axe := _row_with(rows, AXE_ID)
	if axe.is_empty():
		fail("the bagged axe is not listed")
		return
	assert_eq(axe["display_name"], AXE_NAME, "the bag row carries its own display name")
	assert_false(axe["can_buy"], "a non-stocked item cannot be bought")
	assert_true(axe["sellable"], "but it can be sold")
	assert_eq(axe["sell_price"], int(floor(AXE_PRICE * TradingService.SELL_RATE)), "at the service price")

	var gold_before := _session.state.gold
	assert_eq(_panel.sell(AXE_ID), TradingService.CODE_OK, "the bag row sells")
	assert_eq(_session.state.gold, gold_before + 5, "gold rose by the axe's sell price")
	assert_eq(_panel.rows().size(), 1, "the sold entry is gone from the list")


func test_a_non_tradable_bag_entry_is_not_listed() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)
	_add_to_bag(JUNK_ID, 1)

	assert_eq(_panel.rows().size(), 1, "a base_value 0 item is neither stocked nor sellable")


func test_an_equipped_item_cannot_be_sold() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)
	_add_to_bag(SWORD_ID, 1)
	assert_eq(
		_session.equip_item(SWORD_ID), EquipmentState.CODE_OK, "the fixture equips the sword through the session"
	)
	assert_eq(_bag(SWORD_ID), 0, "ownership A: the equipped item is not in the bag")

	assert_eq(
		_panel.sell(SWORD_ID), TradingService.CODE_EQUIPPED, "the service refuses the equipped item"
	)
	assert_eq(_session.state.gold, START_GOLD, "gold is untouched")


# --- open / close and input focus ---------------------------------------------

func test_open_and_close_toggle_the_panel_and_restore_input() -> void:
	_build_fixture()
	if _panel == null:
		return
	var player := _build_player()
	if player == null:
		return
	_panel.bind_player(player)
	player.mouse_captured = true

	_panel.open(_merchant)
	assert_true(_panel.is_open(), "open() reports the shop open")
	assert_true(_panel.visible, "open() makes the shop visible")
	assert_eq(
		_session.trading.current_merchant(), _merchant, "open() binds the merchant on the service"
	)
	assert_false(player.mouse_captured, "open() releases the cursor through the player flag")
	var controller := InteractionController.find_on(player)
	assert_not_null(controller, "the rig has an InteractionController")
	if controller != null:
		assert_false(controller.is_enabled(), "the open shop suspends the interaction ray")

	_panel.close()
	assert_false(_panel.is_open(), "close() reports the shop closed")
	assert_false(_panel.visible, "close() hides the shop")
	assert_true(player.mouse_captured, "close() restores the cursor")
	if controller != null:
		assert_true(controller.is_enabled(), "closing the shop resumes interaction")
	assert_null(_session.trading.current_merchant(), "closing unbinds the merchant")
	assert_true(_panel.rows().is_empty(), "a closed shop exposes no rows")


func test_ui_cancel_closes_the_shop() -> void:
	_build_fixture()
	if _panel == null:
		return
	_panel.open(_merchant)
	assert_true(_panel.is_open(), "the shop is open before the key press")

	Input.parse_input_event(_action_event(&"ui_cancel", true))
	Input.flush_buffered_events()
	await wait_physics_frames(2)
	Input.action_release(&"ui_cancel")

	assert_false(_panel.is_open(), "ui_cancel closes the shop")
	assert_false(_panel.visible, "and hides it")


# --- dialogue -> shop ----------------------------------------------------------

func test_the_dialogue_offers_the_shop_and_emits_the_merchants_request() -> void:
	_build_fixture()
	if _panel == null or _npc == null or _hermit == null:
		return
	var dialogue := DialoguePanel.new()
	add_to_tree(dialogue)
	var received: Array[MerchantDefinition] = []
	dialogue.shop_requested.connect(
		func(merchant: MerchantDefinition) -> void: received.append(merchant)
	)

	dialogue.open(_npc)
	assert_true(dialogue.is_open(), "open() reports the dialogue open")
	assert_eq(dialogue.npc(), _npc, "the dialogue remembers the NPC")
	assert_true(dialogue.has_shop_button(), "an NPC with a merchant shows the Shop button")
	var name_label := dialogue.find_child("NpcName", true, false) as Label
	assert_not_null(name_label, "the NPC name is rendered")
	if name_label != null:
		assert_eq(name_label.text, _npc.display_name, "with the definition's display name")
	var greeting := dialogue.find_child("Greeting", true, false) as Label
	assert_not_null(greeting, "the greeting is rendered")
	if greeting != null:
		assert_eq(greeting.text, _npc.greeting, "with the definition's greeting line")

	var shop_button := dialogue.find_child("ShopButton", true, false) as Button
	assert_not_null(shop_button, "the Shop button exists")
	if shop_button != null:
		shop_button.pressed.emit()
	assert_eq(received.size(), 1, "pressing Shop emits exactly one request")
	if received.size() == 1:
		assert_eq(received[0], _merchant, "carrying the NPC's merchant")

	dialogue.close()
	assert_false(dialogue.is_open(), "close() reports the dialogue closed")

	dialogue.open(_hermit)
	assert_false(dialogue.has_shop_button(), "an NPC without a merchant hides the Shop button")
	if name_label != null:
		assert_eq(name_label.text, _hermit.display_name, "and the panel shows the new NPC")


# --- GameHud wiring ------------------------------------------------------------

func test_the_hud_wires_the_dialogue_the_shop_and_the_inventory_toggle() -> void:
	_build_fixture()
	if _panel == null or _npc == null:
		return
	var hud_scene := load(HUD_SCENE_PATH) as PackedScene
	assert_not_null(hud_scene, "the HUD scene loads")
	if hud_scene == null:
		return
	var hud := hud_scene.instantiate() as GameHud
	assert_not_null(hud, "the HUD scene root is a GameHud")
	if hud == null:
		return
	add_to_tree(hud)

	# A context-free world host is enough: the HUD only needs the request signals.
	var world := WorldHost.new()
	world.name = "TestWorld"
	world.configure(_session, _registry, Callable(), Callable(), &"spawn.test")
	add_to_tree(world)

	var router := StubRouter.new()
	router.world = world
	add_to_tree(router)

	var player := _build_player()
	if player == null:
		return
	hud.bind(_session, router, _registry)
	hud.bind_player(player)
	player.mouse_captured = true

	# A world load is what makes the HUD connect the world's request signals.
	router.world_loaded.emit(&"world.test", &"spawn.test", false)
	world.dialogue_requested.emit(_npc)
	assert_true(hud.dialogue_panel.is_open(), "an NPC request opens the dialogue")
	assert_eq(hud.dialogue_panel.npc(), _npc, "the dialogue shows the requesting NPC")
	assert_false(player.mouse_captured, "the open dialogue releases the cursor")
	assert_false(hud.inventory_panel.is_open(), "and no other panel opened")

	var shop_button := hud.dialogue_panel.find_child("ShopButton", true, false) as Button
	assert_not_null(shop_button, "the dialogue offers the Shop button")
	if shop_button == null:
		return
	shop_button.pressed.emit()
	assert_true(hud.shop_panel.is_open(), "the shop request opens the shop")
	assert_false(hud.dialogue_panel.is_open(), "the dialogue hands the screen over")
	assert_eq(_session.trading.current_merchant(), _merchant, "with the NPC's merchant bound")

	Input.parse_input_event(_action_event(&"inventory", true))
	Input.flush_buffered_events()
	await wait_physics_frames(2)
	Input.action_release(&"inventory")
	assert_true(hud.inventory_panel.is_open(), "the inventory action opens the character panel")
	assert_false(hud.shop_panel.is_open(), "one screen owner: the shop closed")
	assert_false(player.mouse_captured, "and the character panel keeps the input suspended")

	Input.parse_input_event(_action_event(&"inventory", true))
	Input.flush_buffered_events()
	await wait_physics_frames(2)
	Input.action_release(&"inventory")
	assert_false(hud.inventory_panel.is_open(), "pressing inventory again closes it")
	assert_true(player.mouse_captured, "and the cursor returns to the game")
	var controller := InteractionController.find_on(player)
	if controller != null:
		assert_true(controller.is_enabled(), "and interaction resumes")
