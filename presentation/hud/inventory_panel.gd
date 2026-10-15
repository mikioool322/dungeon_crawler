class_name InventoryPanel
extends Control

## Character panel (Sprint 04 UI, ADR-015): bag, worn equipment and effective stats.
##
## Presentation only: `rows()` reads the live session models on every call and caches
## nothing, and every mutation goes through `GameSession.equip_item()` /
## `GameSession.unequip_slot()`. The panel never touches `Inventory`, `EquipmentState`
## or `CharacterStats` directly and never derives a bonus or a price of its own.
##
## While it is open the panel owns the screen (ADR-008 UI focus): the cursor is released
## through `PlayerController.mouse_captured` and look/move/attack/interact input is
## suspended. `ui_cancel` closes the panel; the `inventory` action is owned by `GameHud`,
## which enforces the one-screen-owner rule.

## Rendered for a supported equipment slot with nothing in it.
const LABEL_EMPTY_SLOT: String = "(empty)"

var _session: GameSession = null
var _registry: ContentRegistry = null
var _player: PlayerController = null
var _open: bool = false
var _layout_built: bool = false
var _items_list: VBoxContainer = null
var _equipment_list: VBoxContainer = null
var _stats_list: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	_ensure_layout()


## Stores the services the panel reads. Builds nothing: the view model and the buttons
## are produced by `rows()`, `refresh()` and `open()`.
func bind(session: GameSession, registry: ContentRegistry) -> void:
	_session = session
	_registry = registry
	if _session != null:
		_connect_once(_session.equipment_changed, _on_models_changed)
		_connect_once(_session.stats_changed, _on_models_changed)
		_connect_once(_session.inventory_changed, _on_models_changed)
		_connect_once(_session.gold_changed, _on_gold_changed)


## Binds the rig whose input the panel suspends while it is open.
func bind_player(player: PlayerController) -> void:
	_player = player
	if _open:
		_set_player_input(false)


## View model of the character sheet, built live from the session on every call:
##   {
##     "items": [{"item_id", "display_name", "kind", "count", "equippable", "slot_name",
##                "bonuses"}],
##     "equipment": [{"slot", "slot_name", "item_id", "display_name"}],
##     "stats": [{"stat", "base", "bonus", "effective"}],
##   }
## `bonuses` is the item definition's own `equipment_modifiers()`; an empty slot carries
## `item_id == &""` and an empty `display_name`.
func rows() -> Dictionary:
	var model: Dictionary = {"items": [], "equipment": [], "stats": []}
	if _session == null:
		return model
	for entry: Dictionary in _session.state.inventory.entries():
		var item_id := StringName(str(entry.get("id", "")))
		(model["items"] as Array).append(_item_row(item_id, int(entry.get("count", 0))))
	for slot in EquipmentSlot.SUPPORTED:
		(model["equipment"] as Array).append(_equipment_row(slot))
	for stat in CharacterStats.STATS:
		(model["stats"] as Array).append({
			"stat": stat,
			"base": _session.stats.base(stat),
			"bonus": _session.stats.modifier_total(stat),
			"effective": _session.stats.effective(stat),
		})
	return model


## Shows the panel, rebuilds it from the live models and suspends player input.
func open() -> void:
	_open = true
	visible = true
	refresh()
	_set_player_input(false)
	_focus_first_enabled()


## Hides the panel and restores the cursor and player input. A no-op when closed, so a
## stray close() never captures a cursor the player had released.
func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_set_player_input(true)


func is_open() -> bool:
	return _open


## Rebuilds the item, equipment and stat rows from the live session. Safe to call while
## closed; an open panel also refreshes itself on every model signal.
func refresh() -> void:
	_ensure_layout()
	if _items_list == null:
		return
	var model := rows()
	_clear_list(_items_list)
	_clear_list(_equipment_list)
	_clear_list(_stats_list)
	for row: Dictionary in model["items"]:
		_items_list.add_child(_build_item_row(row))
	for row: Dictionary in model["equipment"]:
		_equipment_list.add_child(_build_equipment_row(row))
	for row: Dictionary in model["stats"]:
		_stats_list.add_child(_build_stat_label(row))


## Button action and test entry point. Delegates to the session (the only equipment
## writer) and shows the returned code in the panel's own status label.
func equip(item_id: StringName) -> StringName:
	if _session == null:
		_set_status("Cannot equip %s (%s)" % [_display_name(item_id), EquipmentState.CODE_NOT_READY])
		return EquipmentState.CODE_NOT_READY
	var code := _session.equip_item(item_id)
	if code == EquipmentState.CODE_OK:
		_set_status("Equipped %s" % _display_name(item_id))
	else:
		_set_status("Cannot equip %s (%s)" % [_display_name(item_id), code])
	refresh()
	return code


## Unequips one slot through the session and returns the item to the bag.
func unequip(slot: int) -> StringName:
	if _session == null:
		_set_status("Cannot unequip %s (%s)" % [EquipmentSlot.name_of(slot), EquipmentState.CODE_NOT_READY])
		return EquipmentState.CODE_NOT_READY
	var item_id := _session.state.equipment.get_equipped(slot)
	var code := _session.unequip_slot(slot)
	if code == EquipmentState.CODE_OK:
		_set_status("Unequipped %s" % _display_name(item_id))
	else:
		_set_status("Cannot unequip %s (%s)" % [EquipmentSlot.name_of(slot), code])
	refresh()
	return code


## Last message the panel showed (a refusal code, or the result of the last action).
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

func _item_row(item_id: StringName, count: int) -> Dictionary:
	var definition := _find_item(item_id)
	var row: Dictionary = {
		"item_id": item_id,
		"display_name": String(item_id),
		"kind": ItemDefinition.Kind.MISC,
		"count": count,
		"equippable": false,
		"slot_name": EquipmentSlot.name_of(EquipmentSlot.Id.NONE),
		"bonuses": {},
	}
	if definition == null:
		return row
	if definition.display_name != "":
		row["display_name"] = definition.display_name
	row["kind"] = definition.kind
	row["equippable"] = definition.is_equippable()
	row["slot_name"] = EquipmentSlot.name_of(definition.slot)
	row["bonuses"] = definition.equipment_modifiers()
	return row


func _equipment_row(slot: int) -> Dictionary:
	var item_id := _session.state.equipment.get_equipped(slot)
	var display_name := ""
	if item_id != &"":
		display_name = _display_name(item_id)
	return {
		"slot": slot,
		"slot_name": EquipmentSlot.name_of(slot),
		"item_id": item_id,
		"display_name": display_name,
	}


func _find_item(item_id: StringName) -> ItemDefinition:
	if _registry == null:
		return null
	return _registry.find_item(item_id)


func _display_name(item_id: StringName) -> String:
	var definition := _find_item(item_id)
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
	if not is_inside_tree():
		return
	for list in [_equipment_list, _items_list]:
		if list == null:
			continue
		for child in list.get_children():
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
	frame.custom_minimum_size = Vector2(520.0, 0.0)
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

	var title := Label.new()
	title.name = "Title"
	title.text = "Character"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	column.add_child(_build_section_title("EquipmentTitle", "Equipment"))
	_equipment_list = VBoxContainer.new()
	_equipment_list.name = "Equipment"
	_equipment_list.add_theme_constant_override("separation", 4)
	column.add_child(_equipment_list)

	column.add_child(_build_section_title("StatsTitle", "Stats"))
	_stats_list = VBoxContainer.new()
	_stats_list.name = "Stats"
	_stats_list.add_theme_constant_override("separation", 4)
	column.add_child(_stats_list)

	column.add_child(_build_section_title("InventoryTitle", "Inventory"))
	_items_list = VBoxContainer.new()
	_items_list.name = "Items"
	_items_list.add_theme_constant_override("separation", 4)
	column.add_child(_items_list)

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


func _build_section_title(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	return label


func _build_item_row(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "Item_%s" % _node_suffix(row["item_id"])
	var label := Label.new()
	label.text = "%s x%d%s" % [row["display_name"], row["count"], _bonus_text(row["bonuses"])]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	if row["equippable"]:
		var button := Button.new()
		button.name = "Equip_%s" % _node_suffix(row["item_id"])
		button.text = "Equip"
		button.pressed.connect(equip.bind(row["item_id"]))
		line.add_child(button)
	return line


func _build_equipment_row(row: Dictionary) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "Slot_%s" % String(row["slot_name"])
	var label := Label.new()
	label.name = "SlotLabel_%s" % String(row["slot_name"])
	var shown: String = row["display_name"] if row["item_id"] != &"" else LABEL_EMPTY_SLOT
	label.text = "%s: %s" % [_slot_label(row["slot_name"]), shown]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	if row["item_id"] != &"":
		var button := Button.new()
		button.name = "Unequip_%s" % String(row["slot_name"])
		button.text = "Unequip"
		button.pressed.connect(unequip.bind(row["slot"]))
		line.add_child(button)
	return line


func _build_stat_label(row: Dictionary) -> Label:
	var label := Label.new()
	label.name = "Stat_%s" % String(row["stat"])
	var base := _format_number(float(row["base"]))
	var effective := _format_number(float(row["effective"]))
	var bonus := float(row["bonus"])
	if is_zero_approx(bonus):
		label.text = "%s: %s" % [_stat_label(row["stat"]), effective]
	else:
		label.text = "%s: %s + %s = %s" % [
			_stat_label(row["stat"]), base, _format_number(bonus), effective
		]
	return label


func _bonus_text(bonuses: Dictionary) -> String:
	if bonuses.is_empty():
		return ""
	var parts := PackedStringArray()
	for stat in CharacterStats.STATS:
		if not bonuses.has(stat):
			continue
		parts.append("%+d %s" % [roundi(float(bonuses[stat])), _stat_label(stat)])
	return " (%s)" % ", ".join(parts)


func _stat_label(stat: StringName) -> String:
	match stat:
		CharacterStats.MAX_HEALTH:
			return "Max Health"
		CharacterStats.ATTACK_DAMAGE:
			return "Attack Damage"
		CharacterStats.DEFENSE:
			return "Defense"
		CharacterStats.MOVEMENT_SPEED:
			return "Move Speed"
	return String(stat)


func _slot_label(slot_name: StringName) -> String:
	match slot_name:
		&"main_hand":
			return "Main Hand"
		&"chest_armor":
			return "Chest Armor"
	return String(slot_name)


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return "%.2f" % value


func _node_suffix(item_id: Variant) -> String:
	return String(item_id).replace(".", "_")


func _clear_list(list: VBoxContainer) -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


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
