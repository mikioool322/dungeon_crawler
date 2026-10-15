extends "res://tests/test_case.gd"

## AC-43 — the shipped Sprint 04 content: one player definition, two swords, one armour
## piece, a tradable junk item, a merchant and a hub NPC, all cross-referenced and valid.

const MANIFEST_PATH := "res://content/definitions/content_manifest.tres"
const HUB_SCENE_PATH := "res://world/hub/hub.tscn"

const SWORD := &"item.iron_sword"
const VEST := &"item.leather_vest"
const DAGGER := &"item.rusty_dagger"
const SALVE := &"item.minor_salve"
const SMITH := &"npc.hub.smith"
const MERCHANT := &"merchant.hub.smith"


func _registry() -> ContentRegistry:
	var manifest := load(MANIFEST_PATH) as ContentManifest
	if manifest == null:
		fail("the shipped manifest failed to load")
		return ContentRegistry.build(null)
	return ContentRegistry.build(manifest)


# --- the player definition ----------------------------------------------------

func test_the_manifest_ships_exactly_one_player_definition() -> void:
	var registry := _registry()
	var player := registry.player_definition()
	assert_not_null(player, "the shipped manifest has a player definition")
	if player == null:
		return
	assert_eq(player.id, &"player.default", "stable id")
	assert_true(player.is_valid(), "and it is valid: %s" % player.validation_errors())
	assert_almost_eq(player.max_health, 100.0, 0.0001, "base HP matches the rig's scene value")
	assert_almost_eq(player.movement_speed, 4.0, 0.0001, "base speed matches the rig's scene value")
	assert_almost_eq(player.defense, 0.0, 0.0001, "an unarmoured player has no defense")


func test_the_base_attack_matches_the_unarmed_profile() -> void:
	# Two numbers describe the same swing: the stat is the source of truth (ADR-016), and
	# they must not drift apart, or the shipped damage would silently change.
	var registry := _registry()
	var player := registry.player_definition()
	if player == null or player.attack_definition == null:
		fail("the player definition needs an attack profile")
		return
	assert_almost_eq(
		player.attack_damage,
		player.attack_definition.damage,
		0.0001,
		"the base attack equals the unarmed profile's damage"
	)
	assert_almost_eq(player.attack_damage, 34.0, 0.0001, "and keeps the Sprint 01/02 swing damage")


func test_the_player_profile_is_listed_in_the_manifest() -> void:
	var registry := _registry()
	var player := registry.player_definition()
	if player == null or player.attack_definition == null:
		return
	assert_not_null(
		registry.find_attack(player.attack_definition.id),
		"the player's attack profile is a listed attack definition"
	)


# --- items --------------------------------------------------------------------

func test_the_sword_is_a_main_hand_weapon_with_its_own_profile() -> void:
	var registry := _registry()
	var sword := registry.find_item(SWORD)
	assert_not_null(sword, "the iron sword ships")
	if sword == null:
		return
	assert_eq(sword.slot, EquipmentSlot.Id.MAIN_HAND, "it goes into the main hand")
	assert_true(sword.attack_bonus > 0, "and it adds attack damage")
	assert_true(sword.is_tradable(), "and it can be bought")
	assert_not_null(sword.attack_definition, "it carries its own attack profile")
	if sword.attack_definition == null:
		return
	assert_almost_eq(
		sword.attack_definition.damage, 0.0, 0.0001,
		"a weapon profile owns reach/timings only (ADR-016): the stats own the damage"
	)
	assert_true(sword.attack_definition.is_valid(), "the profile is valid")
	assert_not_null(
		registry.find_attack(sword.attack_definition.id),
		"and it is listed in the manifest"
	)


func test_the_armour_is_a_chest_slot_with_defense() -> void:
	var registry := _registry()
	var vest := registry.find_item(VEST)
	assert_not_null(vest, "the leather vest ships")
	if vest == null:
		return
	assert_eq(vest.slot, EquipmentSlot.Id.CHEST_ARMOR, "it goes onto the chest")
	assert_true(vest.defense_bonus > 0, "and it adds defense")
	assert_true(vest.is_tradable(), "and it can be bought")


func test_the_story_dagger_is_a_usable_weak_weapon() -> void:
	var registry := _registry()
	var dagger := registry.find_item(DAGGER)
	assert_not_null(dagger, "the story reward ships")
	if dagger == null:
		return
	assert_eq(dagger.slot, EquipmentSlot.Id.MAIN_HAND, "the first-clear reward is usable")
	assert_true(dagger.attack_bonus > 0, "with a small bonus")
	assert_true(dagger.attack_bonus < 15, "weaker than the bought sword")
	assert_true(dagger.is_tradable(), "and it can be sold if the player chooses")


func test_the_loot_item_is_sellable() -> void:
	var registry := _registry()
	var salve := registry.find_item(SALVE)
	assert_not_null(salve, "the salve ships")
	if salve == null:
		return
	assert_true(salve.is_tradable(), "it has a base value, so the loot -> sell loop works")
	assert_false(salve.is_equippable(), "and it is not equipment")


func test_every_shipped_item_still_validates() -> void:
	var manifest := load(MANIFEST_PATH) as ContentManifest
	if manifest == null:
		fail("the shipped manifest failed to load")
		return
	assert_true(manifest.items.size() >= 4, "at least the four documented items ship")
	for item in manifest.items:
		assert_true(
			item.is_valid(),
			"item %s is valid: %s" % [item.id, item.validation_errors()]
		)


# --- merchant and npc ---------------------------------------------------------

func test_the_merchant_stocks_only_listed_tradable_items() -> void:
	var registry := _registry()
	var merchant := registry.find_merchant(MERCHANT)
	assert_not_null(merchant, "the smith's merchant definition ships")
	if merchant == null:
		return
	assert_true(merchant.is_valid(), "and it is valid: %s" % merchant.validation_errors())
	assert_true(merchant.stock.size() >= 2, "it sells a weapon and armour")
	for item in merchant.stock:
		assert_not_null(registry.find_item(item.id), "stock item %s is in the manifest" % item.id)
		assert_true(item.is_tradable(), "and it has a price")


func test_the_hub_npc_offers_that_merchant() -> void:
	var registry := _registry()
	var npc := registry.find_npc(SMITH)
	assert_not_null(npc, "the smith NPC ships")
	if npc == null:
		return
	assert_true(npc.is_valid(), "and it is valid: %s" % npc.validation_errors())
	assert_true(npc.has_shop(), "the first NPC is a merchant")
	if npc.merchant == null:
		return
	assert_eq(npc.merchant.id, MERCHANT, "and it points at the shipped merchant")
	assert_not_null(registry.find_merchant(npc.merchant.id), "which is listed in the manifest")


func test_every_sell_price_stays_below_its_buy_price() -> void:
	var registry := _registry()
	var merchant := registry.find_merchant(MERCHANT)
	if merchant == null:
		return
	var state := PlayerSessionState.new()
	var equipment := EquipmentState.new()
	equipment.setup(registry, state.inventory)
	var trading := TradingService.new()
	trading.setup(state, registry, equipment)
	trading.bind_merchant(merchant)
	for item in merchant.stock:
		assert_true(
			trading.sell_price(item.id) < trading.buy_price(item.id),
			"%s cannot be bought and sold for a profit" % item.id
		)


# --- the hub scene ------------------------------------------------------------

func test_the_hub_scene_holds_the_merchant_and_its_spawn_marker() -> void:
	var scene := load(HUB_SCENE_PATH) as PackedScene
	assert_not_null(scene, "the hub scene loads")
	if scene == null:
		return
	var hub := scene.instantiate()
	add_to_tree(hub)

	var npcs: Array[NpcInteractable] = []
	var markers: Array[SpawnMarker] = []
	for node in _walk(hub):
		if node is NpcInteractable:
			npcs.append(node as NpcInteractable)
		elif node is SpawnMarker:
			markers.append(node as SpawnMarker)

	assert_eq(npcs.size(), 1, "exactly one merchant NPC is placed")
	if npcs.size() == 1:
		assert_not_null(npcs[0].npc, "and it carries a definition")
		if npcs[0].npc != null:
			assert_eq(npcs[0].npc.id, SMITH, "the shipped smith")
		assert_eq(npcs[0].collision_layer, PhysicsLayers.INTERACTABLE, "on the interactable layer")

	var ids := PackedStringArray()
	for marker in markers:
		ids.append(String(marker.spawn_id))
	assert_true(ids.has("spawn.hub.merchant"), "the merchant spawn marker exists")

	hub.queue_free()


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found
