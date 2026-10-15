class_name GameHud
extends CanvasLayer

## Sprint 02 debug HUD (presentation only, ADR-007).
##
## It reads models and listens to signals; it owns no gameplay state, never writes
## to the session and never decides gameplay. Every actor reference is guarded with
## `is_instance_valid`, because the player rig is recreated on each world load.

@export var health_label: Label
@export var gold_label: Label
@export var inventory_label: Label
@export var prompt_label: Label
@export var status_label: Label
@export var world_label: Label

## Hub dungeon-selection panel (ADR-012); opens from the hub board, never on load.
@export var dungeon_panel: DungeonPanel = null

## Character panel (ADR-015): bag, equipment and stats; toggled by the `inventory` action.
@export var inventory_panel: InventoryPanel = null

## NPC dialogue (ADR-017); opens from a world's `dialogue_requested`.
@export var dialogue_panel: DialoguePanel = null

## Merchant shop (ADR-017); opens from the dialogue's `shop_requested`.
@export var shop_panel: ShopPanel = null

var _session: GameSession = null
var _router: WorldRouter = null
var _registry: ContentRegistry = null
var _player: PlayerController = null
var _health: HealthComponent = null
var _interaction: InteractionController = null
var _status: String = ""


## Connects the HUD to the session and the router; safe to call again in tests.
func bind(session: GameSession, router: WorldRouter, registry: ContentRegistry) -> void:
	_session = session
	_router = router
	_registry = registry
	if _session != null:
		_connect_once(_session.gold_changed, _on_gold_changed)
		_connect_once(_session.inventory_changed, _on_inventory_changed)
		_connect_once(_session.location_changed, _on_location_changed)
		_connect_once(_session.loot.reward_granted, _on_reward_granted)
	if _router != null:
		_connect_once(_router.player_spawned, _on_player_spawned)
		_connect_once(_router.world_loaded, _on_world_loaded)
		_connect_once(_router.world_load_failed, _on_world_load_failed)
	if dungeon_panel != null:
		dungeon_panel.bind(session, router, registry)
		_connect_once(dungeon_panel.travel_requested, _on_travel_requested)
		dungeon_panel.bind_player(_player)
	if inventory_panel != null:
		inventory_panel.bind(session, registry)
		inventory_panel.bind_player(_player)
	if shop_panel != null:
		shop_panel.bind(session, registry)
		shop_panel.bind_player(_player)
	if dialogue_panel != null:
		dialogue_panel.bind_player(_player)
		_connect_once(dialogue_panel.shop_requested, _on_shop_requested)
	_refresh_all()


func set_status(message: String) -> void:
	_status = message
	_update_status_label()


## Binds the live rig: HP changes and interaction feedback come from the actor.
func bind_player(player: PlayerController) -> void:
	_unbind_player()
	_player = player
	if dungeon_panel != null:
		dungeon_panel.bind_player(_player)
	if inventory_panel != null:
		inventory_panel.bind_player(_player)
	if shop_panel != null:
		shop_panel.bind_player(_player)
	if dialogue_panel != null:
		dialogue_panel.bind_player(_player)
	if _player == null or not is_instance_valid(_player):
		return
	_health = HealthComponent.find_on(_player)
	if _health != null:
		_connect_once(_health.health_changed, _on_health_changed)
	_interaction = InteractionController.find_on(_player)
	if _interaction != null:
		_connect_once(_interaction.prompt_changed, _on_prompt_changed)
		_connect_once(_interaction.interaction_resolved, _on_interaction_resolved)
	_refresh_health()


func _unbind_player() -> void:
	if _health != null and is_instance_valid(_health):
		if _health.health_changed.is_connected(_on_health_changed):
			_health.health_changed.disconnect(_on_health_changed)
	if _interaction != null and is_instance_valid(_interaction):
		if _interaction.prompt_changed.is_connected(_on_prompt_changed):
			_interaction.prompt_changed.disconnect(_on_prompt_changed)
		if _interaction.interaction_resolved.is_connected(_on_interaction_resolved):
			_interaction.interaction_resolved.disconnect(_on_interaction_resolved)
	_health = null
	_interaction = null
	_player = null
	if dungeon_panel != null:
		dungeon_panel.bind_player(null)
	if inventory_panel != null:
		inventory_panel.bind_player(null)
	if shop_panel != null:
		shop_panel.bind_player(null)
	if dialogue_panel != null:
		dialogue_panel.bind_player(null)


func _connect_once(signal_ref: Signal, target: Callable) -> void:
	if not signal_ref.is_connected(target):
		signal_ref.connect(target)


# --- refresh -----------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_health()
	_refresh_gold()
	_refresh_inventory()
	_refresh_world()
	_update_status_label()


func _refresh_health() -> void:
	if health_label == null:
		return
	if _health == null or not is_instance_valid(_health):
		health_label.text = "HP: --"
		return
	health_label.text = "HP: %d / %d" % [roundi(_health.current_health), roundi(_health.max_health)]


func _refresh_gold() -> void:
	if gold_label == null:
		return
	gold_label.text = "Gold: %d" % (_session.state.gold if _session != null else 0)


func _refresh_inventory() -> void:
	if inventory_label == null:
		return
	if _session == null or _session.state.inventory.is_empty():
		inventory_label.text = "Items: (empty)"
		return
	var parts := PackedStringArray()
	for entry: Dictionary in _session.state.inventory.entries():
		var item_id := StringName(str(entry.get("id", "")))
		var count := int(entry.get("count", 0))
		parts.append("%s x%d" % [_display_name(item_id), count])
	inventory_label.text = "Items: %s" % ", ".join(parts)


func _refresh_world() -> void:
	if world_label == null:
		return
	if _session == null:
		world_label.text = "Location: --"
		return
	world_label.text = "Location: %s @ %s" % [_session.state.world_id, _session.state.spawn_id]


func _update_status_label() -> void:
	if status_label != null:
		status_label.text = _status


func _display_name(item_id: StringName) -> String:
	if _registry != null:
		var definition := _registry.find_item(item_id)
		if definition != null and definition.display_name != "":
			return definition.display_name
	return String(item_id)


# --- signals -----------------------------------------------------------------

func _on_health_changed(_current: float, _maximum: float) -> void:
	_refresh_health()


func _on_gold_changed(_gold: int) -> void:
	_refresh_gold()


func _on_inventory_changed() -> void:
	_refresh_inventory()


func _on_location_changed(_world_id: StringName, _spawn_id: StringName) -> void:
	_refresh_world()


func _on_reward_granted(grant: LootGrant, gold_total: int) -> void:
	var parts := PackedStringArray()
	if grant.gold > 0:
		parts.append("%d gold" % grant.gold)
	if grant.item_id != &"" and grant.item_count > 0:
		parts.append("%s x%d" % [_display_name(grant.item_id), grant.item_count])
	var summary := "reward granted" if parts.is_empty() else ", ".join(parts)
	set_status("Collected: %s (gold %d)" % [summary, gold_total])


func _on_player_spawned(player: PlayerController) -> void:
	bind_player(player)


func _on_world_loaded(world_id: StringName, spawn_id: StringName, used_fallback: bool) -> void:
	_refresh_world()
	_refresh_gold()
	_refresh_inventory()
	_connect_world_requests()
	if used_fallback:
		set_status("Requested spawn was missing; used '%s' in %s" % [spawn_id, world_id])
	else:
		set_status("Entered %s at %s" % [world_id, spawn_id])


## World furniture that speaks to presentation: the hub board opens the dungeon panel
## and an NPC opens the dialogue. Both panels are never auto-opened on load.
func _connect_world_requests() -> void:
	if _router == null:
		return
	var world := _router.current_world()
	if not (world is WorldHost):
		return
	if dungeon_panel != null and world.has_signal(&"board_requested"):
		var open_board := Callable(dungeon_panel, "open")
		if not world.board_requested.is_connected(open_board):
			world.board_requested.connect(open_board)
	if dialogue_panel != null and world.has_signal(&"dialogue_requested"):
		var open_dialogue := Callable(self, "_on_dialogue_requested")
		if not world.dialogue_requested.is_connected(open_dialogue):
			world.dialogue_requested.connect(open_dialogue)


## The panel only announces intent; the router owns the gate. A refusal is surfaced in
## the status line, and the panel closes either way so the line is readable again.
func _on_travel_requested(world_id: StringName, spawn_id: StringName) -> void:
	var code: StringName = WorldRouter.CODE_UNKNOWN_WORLD
	if _router != null:
		code = _router.request_travel(world_id, spawn_id)
	if dungeon_panel != null and dungeon_panel.is_open():
		dungeon_panel.close()
	if code != WorldRouter.CODE_TRAVEL_STARTED:
		set_status("Travel to %s refused (%s)" % [world_id, code])


func _on_world_load_failed(world_id: StringName, code: StringName) -> void:
	set_status("Travel to %s failed (%s)" % [world_id, code])


func _on_prompt_changed(prompt: String, visible: bool) -> void:
	if prompt_label == null:
		return
	prompt_label.text = "[E] %s" % prompt if visible else ""


func _on_interaction_resolved(result: InteractionResult) -> void:
	if result == null:
		return
	if result.message != "":
		set_status(result.message)
	elif not result.succeeded():
		set_status("Interaction failed (%s)" % result.code)


# --- panels: one screen owner (ADR-008 UI focus) -------------------------------

## `inventory` toggles the character panel; `ui_cancel` closes whichever panel is open.
## Each panel also consumes `ui_cancel` itself, so this is the fallback for a panel whose
## event was not consumed.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		_toggle_inventory()
		# CanvasLayer has no `accept_event()`; mark it handled through the viewport.
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_close_all_panels()


## One screen owner: opening one panel closes every other, and pressing `inventory`
## while the character panel is open closes it again.
func _toggle_inventory() -> void:
	if inventory_panel == null:
		return
	if inventory_panel.is_open():
		inventory_panel.close()
		return
	_close_all_panels()
	inventory_panel.open()


func _close_all_panels() -> void:
	if dungeon_panel != null and dungeon_panel.is_open():
		dungeon_panel.close()
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	if shop_panel != null and shop_panel.is_open():
		shop_panel.close()
	if dialogue_panel != null and dialogue_panel.is_open():
		dialogue_panel.close()


## An NPC asked to talk: the dialogue owns the screen. Its `shop_requested` is the only
## way into the shop, so the NPC never learns about trading.
func _on_dialogue_requested(npc: NpcDefinition) -> void:
	if dialogue_panel == null:
		return
	_close_all_panels()
	dialogue_panel.open(npc)


## The dialogue asked for the shop: the shop replaces it as the one open panel.
func _on_shop_requested(merchant: MerchantDefinition) -> void:
	if shop_panel == null:
		return
	_close_all_panels()
	shop_panel.open(merchant)
