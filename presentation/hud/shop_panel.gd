class_name ShopPanel
extends Control

## Merchant shop panel (Sprint 04 UI, ADR-017): the merchant's stock plus every sellable
## bag entry, with buy and sell buttons.
##
## Presentation only: every price and every eligibility flag is read from
## `TradingService` on every `rows()` call, and `buy()` / `sell()` only delegate to it.
## The panel computes no price, mutates no gold and no bag and caches no trade state.
## `open()` binds the merchant on the service; `close()` unbinds it, so the service is
## never left ready after the shop is gone.
##
## While it is open the panel owns the screen (ADR-008 UI focus): the cursor is released
## through `PlayerController.mouse_captured` and look/move/attack/interact input is
## suspended. `ui_cancel` closes the panel; `GameHud` enforces the one-screen-owner rule.

var _session: GameSession = null
var _registry: ContentRegistry = null
var _player: PlayerController = null
var _open: bool = false
var _layout_built: bool = false
var _title: Label = null
var _gold: Label = null
var _list: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	_ensure_layout()


## Stores the services the shop reads. Builds nothing: the view model and the buttons
## are produced by `rows()`, `refresh()` and `open()`.
func bind(session: GameSession, registry: ContentRegistry) -> void:
	_session = session
	_registry = registry
	if _session != null:
		_connect_once(_session.inventory_changed, _on_models_changed)
		_connect_once(_session.gold_changed, _on_gold_changed)


## Binds the rig whose input the panel suspends while it is open.
func bind_player(player: PlayerController) -> void:
	_player = player
	if _open:
		_set_player_input(false)


## View model of the shop, built live from the service on every call: one row per stock
## item plus one per sellable bag entry:
##   [{"item_id", "display_name", "buy_price", "sell_price", "owned", "sellable",
##     "can_buy"}]
## Prices come from `TradingService` (`0` when the item is not tradable); `sellable` and
## `can_buy` are the service's own `can_sell()` / `can_buy()` verdicts.
func rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _session == null or _registry == null:
		return result
	var merchant := _session.trading.current_merchant()
	if merchant == null:
		return result
	var listed: Dictionary = {}
	for item: ItemDefinition in merchant.stock:
		if item == null or listed.has(item.id):
			continue
		listed[item.id] = true
		result.append(_row_for(item.id))
	for entry: Dictionary in _session.state.inventory.entries():
		var item_id := StringName(str(entry.get("id", "")))
		if listed.has(item_id):
			continue
		listed[item_id] = true
		if _session.trading.can_sell(item_id) == TradingService.CODE_OK:
			result.append(_row_for(item_id))
	return result


## Shows the shop for `merchant`, binds it on the trade service and suspends player input.
func open(merchant: MerchantDefinition) -> void:
	_ensure_layout()
	if _session != null:
		_session.trading.bind_merchant(merchant)
	_open = true
	visible = true
	_update_title()
	refresh()
	_set_player_input(false)
	_focus_first_enabled()


## Hides the shop, unbinds the merchant and restores the cursor and player input.
## A no-op when closed, so a stray close() never captures a cursor the player had released.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	if _session != null:
		_session.trading.bind_merchant(null)
	_set_player_input(true)


func is_open() -> bool:
	return _open


## Rebuilds the shop rows from the live service. Safe to call while closed; an open panel
## also refreshes itself on every gold/bag change (which is how a trade reports back).
func refresh() -> void:
	_ensure_layout()
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for row: Dictionary in rows():
		_list.add_child(_build_row(row))
	_update_title()


## Button action and test entry point. Delegates to the trade service (the only trade
## writer) and shows the returned code in the panel's own status label.
func buy(item_id: StringName) -> StringName:
	if _session == null:
		_set_status("Cannot buy %s (%s)" % [_display_name(item_id), TradingService.CODE_INVALID])
		return TradingService.CODE_INVALID
	var code := _session.trading.buy(item_id)
	if code == TradingService.CODE_OK:
		_set_status("Bought %s for %d gold" % [
			_display_name(item_id), _session.trading.buy_price(item_id)
		])
	else:
		_set_status("Cannot buy %s (%s)" % [_display_name(item_id), code])
	refresh()
	return code


## Sells one bagged copy through the trade service.
func sell(item_id: StringName) -> StringName:
	if _session == null:
		_set_status("Cannot sell %s (%s)" % [_display_name(item_id), TradingService.CODE_INVALID])
		return TradingService.CODE_INVALID
	var code := _session.trading.sell(item_id)
	if code == TradingService.CODE_OK:
		_set_status("Sold %s for %d gold" % [
			_display_name(item_id), _session.trading.sell_price(item_id)
		])
	else:
		_set_status("Cannot sell %s (%s)" % [_display_name(item_id), code])
	refresh()
	return code


## Last message the panel showed (a refusal code, or the result of the last trade).
func status_text() -> String:
	return _status.text if _status != null else ""


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		if is_inside_tree():
			accept_event()


# --- view model ---------------------------------------------------------------

func _row_for(item_id: StringName) -> Dictionary:
	return {
		"item_id": item_id,
		"display_name": _display_name(item_id),
		"buy_price": _session.trading.buy_price(item_id),
		"sell_price": _session.trading.sell_price(item_id),
		"owned": _session.state.inventory.count_of(item_id),
		"sellable": _session.trading.can_sell(item_id) == TradingService.CODE_OK,
		"can_buy": _session.trading.can_buy(item_id) == TradingService.CODE_OK,
	}


func _display_name(item_id: StringName) -> String:
	if _registry != null:
		var definition := _registry.find_item(item_id)
		if definition != null and definition.display_name != "":
			return definition.display_name
	return String(item_id)


# --- input focus --------------------------------------------------------------

func _set_player_input(enabled: bool) -> void:
	var player := _player
	if player == null or not is_instance_valid(player):
		return
	player.set_input_enabled(enabled)
	player.mouse_captured = enabled
	# The panel owns the screen: the interaction ray is suspended too, so `interact`
	# cannot reach an NPC, board or portal behind the open panel (ADR-008 UI focus).
	var controller := InteractionController.find_on(player)
	if controller != null:
		controller.set_enabled(enabled)


func _focus_first_enabled() -> void:
	if not is_inside_tree() or _list == null:
		return
	for child in _list.get_children():
		for node in child.find_children("*", "Button", true, false):
			var button := node as Button
			if button != null and not button.disabled:
				button.grab_focus()
				return


# --- script-built chrome ------------------------------------------------------

## Builds the panel chrome once; the scene stays a bare full-rect Control.
func _ensure_layout() -> void:
	if _layout_built:
		return
	_layout_built = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	column.add_child(_title)

	var gold := Label.new()
	gold.name = "Gold"
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold.add_theme_font_size_override("font_size", 14)
	_gold = gold
	column.add_child(gold)

	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.add_theme_constant_override("separation", 6)
	column.add_child(_list)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	column.add_child(_status)

	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close [Esc]"
	close_button.pressed.connect(close)
	column.add_child(close_button)


func _build_row(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "Row_%s" % _node_suffix(row["item_id"])
	var label := Label.new()
	label.text = "%s (owned %d) - buy %d / sell %d" % [
		row["display_name"], row["owned"], row["buy_price"], row["sell_price"]
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)

	var buy_button := Button.new()
	buy_button.name = "Buy_%s" % _node_suffix(row["item_id"])
	buy_button.text = "Buy"
	buy_button.disabled = not row["can_buy"]
	buy_button.pressed.connect(buy.bind(row["item_id"]))
	line.add_child(buy_button)

	var sell_button := Button.new()
	sell_button.name = "Sell_%s" % _node_suffix(row["item_id"])
	sell_button.text = "Sell"
	sell_button.disabled = not row["sellable"]
	sell_button.pressed.connect(sell.bind(row["item_id"]))
	line.add_child(sell_button)

	return line


func _update_title() -> void:
	if _title != null:
		var merchant := _session.trading.current_merchant() if _session != null else null
		_title.text = "%s - Shop" % merchant.display_name if merchant != null else "Shop"
	if _gold != null:
		_gold.text = "Gold: %d" % (_session.state.gold if _session != null else 0)


func _node_suffix(item_id: Variant) -> String:
	return String(item_id).replace(".", "_")


func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message


func _on_models_changed() -> void:
	if _open:
		refresh()


func _on_gold_changed(_gold: int) -> void:
	if _open:
		refresh()


func _connect_once(signal_ref: Signal, target: Callable) -> void:
	if not signal_ref.is_connected(target):
		signal_ref.connect(target)
