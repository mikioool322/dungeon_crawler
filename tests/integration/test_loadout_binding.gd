extends "res://tests/test_case.gd"

## Independent-review follow-ups (M2/M3/L11): the equipment record's change signal survives the
## rebuild that `new_game()` and a load perform, a spawn applies the effective maximum before it
## restores HP, the load clamp uses the effective ceiling, and the player's walking speed follows
## the effective movement stat.

const SWORD := &"item.test.sword"
const VITALITY_VEST := &"item.test.vitality_vest"
const PLAYER_SCENE_PATH := "res://actors/player/player.tscn"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _player: PlayerController = null


func teardown() -> void:
	_session = null
	_registry = null
	_player = null


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
	var sword_profile := AttackDefinition.new()
	sword_profile.id = &"attack.test.sword"
	sword_profile.damage = 0.0  # the stats own the damage (ADR-016)
	sword_profile.reach = 2.2
	sword_profile.hit_radius = 0.3
	sword_profile.hit_arc_degrees = 60.0
	sword_profile.windup = 0.28
	sword_profile.active_window = 0.12
	sword_profile.recovery = 0.42
	sword_profile.cooldown = 0.7
	sword.attack_definition = sword_profile

	var vest := ItemDefinition.new()
	vest.id = VITALITY_VEST
	vest.display_name = "Vitality Vest"
	vest.kind = ItemDefinition.Kind.MISC
	vest.stackable = false
	vest.max_stack = 1
	vest.slot = EquipmentSlot.Id.CHEST_ARMOR
	vest.defense_bonus = 5
	vest.max_health_bonus = 25
	vest.base_value = 30

	var items: Array[ItemDefinition] = [sword, vest]
	manifest.items = items

	var player := PlayerDefinition.new()
	player.id = &"player.test"
	player.display_name = "Tester"
	player.max_health = 100.0
	player.attack_damage = 34.0
	player.defense = 0.0
	player.movement_speed = 4.0
	var profile := AttackDefinition.new()
	profile.id = &"attack.test"
	profile.damage = 34.0
	player.attack_definition = profile
	var attacks: Array[AttackDefinition] = [profile, sword_profile]
	manifest.attacks = attacks
	manifest.player = player

	return ContentRegistry.build(manifest)


## The production boot shape: `Main` calls `setup()` once and then `load_or_new()`.
func _boot_session() -> GameSession:
	_registry = _build_registry()
	_session = GameSession.new()
	_session.setup(_registry, SaveManager.new())
	_session.new_game()
	return _session


func _spawn_player() -> PlayerController:
	var scene := load(PLAYER_SCENE_PATH) as PackedScene
	if scene == null:
		fail("the player scene failed to load")
		return null
	_player = scene.instantiate() as PlayerController
	add_to_tree(_player)
	return _player


# --- M2: the change signal survives a rebuild ---------------------------------

func test_equipment_changed_fires_after_the_production_boot_shape() -> void:
	var session := _boot_session()
	session.state.inventory.add(_registry.find_item(SWORD), 1)
	var emissions: Array[int] = []
	session.equipment_changed.connect(func() -> void: emissions.append(1))
	assert_eq(session.equip_item(SWORD), EquipmentState.CODE_OK, "equipped")
	assert_eq(emissions.size(), 1, "the session re-emitted the equipment change")
	session.unequip_slot(EquipmentSlot.Id.MAIN_HAND)
	assert_eq(emissions.size(), 2, "and again on unequip")
	emissions = []


func test_the_stats_reach_the_live_rig_after_a_production_boot() -> void:
	var session := _boot_session()
	var player := _spawn_player()
	if player == null:
		return
	session.apply_stats_to_player(player)
	session.state.inventory.add(_registry.find_item(SWORD), 1)
	session.equip_item(SWORD)
	await wait_process_frames(2)
	var controller := player.get_node_or_null("AttackController") as AttackController
	assert_not_null(controller, "the rig has an attack controller")
	if controller == null:
		return
	assert_not_null(controller.attack_profile(), "a profile is bound")
	if controller.attack_profile() == null:
		return
	assert_eq(
		controller.attack_profile().id, &"attack.test",
		"the player's default profile is in use while nothing is equipped"
	)
	assert_true(controller.attack_profile().reach > 0.0, "with a usable reach")
	session.state.inventory.add(_registry.find_item(SWORD), 1)
	session.equip_item(SWORD)
	# No router in this fixture, so the loadout is re-applied by hand; the automatic path
	# (equipment change -> live rig) is asserted by the end-to-end loop on the real scene.
	session.apply_stats_to_player(player)
	assert_eq(
		controller.attack_profile().id, &"attack.test.sword",
		"the equipped weapon's profile is applied to the live rig"
	)
	assert_almost_eq(controller.attack_profile().reach, 2.2, 0.0001, "and its reach follows")


# --- M3: the effective maximum across a spawn and a load -----------------------

func test_a_spawn_keeps_hp_above_the_base_maximum() -> void:
	var session := _boot_session()
	var player := _spawn_player()
	if player == null:
		return
	session.state.inventory.add(_registry.find_item(VITALITY_VEST), 1)
	assert_eq(session.equip_item(VITALITY_VEST), EquipmentState.CODE_OK, "wearing the vest")
	assert_almost_eq(
		session.stats.effective(CharacterStats.MAX_HEALTH), 125.0, 0.0001, "100 + 25"
	)
	session.state.health = 120.0
	# The router's order: stats (which raise the ceiling) before the saved HP is restored.
	session.apply_stats_to_player(player)
	session.apply_to_player(player)
	var health := HealthComponent.find_on(player)
	assert_not_null(health, "the rig has health")
	if health == null:
		return
	assert_almost_eq(health.max_health, 125.0, 0.0001, "the rig's ceiling moved")
	assert_almost_eq(health.current_health, 120.0, 0.0001, "and 120 HP survived the spawn")


func test_a_load_keeps_hp_above_the_base_maximum() -> void:
	var session := _boot_session()
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = 120.0
	snapshot.gold = 0
	snapshot.items = []
	snapshot.equipment = {"chest_armor": String(VITALITY_VEST)}
	var warnings := session.apply_snapshot(snapshot)
	assert_eq(warnings.size(), 0, "a clean load reports no warnings")
	assert_almost_eq(
		session.stats.effective(CharacterStats.MAX_HEALTH), 125.0, 0.0001, "the vest is worn"
	)
	assert_almost_eq(session.state.health, 120.0, 0.0001, "HP above the base maximum survived")


func test_a_load_without_the_bonus_clamps_to_the_base_maximum() -> void:
	var session := _boot_session()
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = 120.0
	snapshot.items = []
	snapshot.equipment = {}
	session.apply_snapshot(snapshot)
	assert_almost_eq(
		session.state.health, 100.0, 0.0001,
		"without the bonus the ceiling is the base maximum again"
	)


func test_a_dropped_equipment_record_is_reported_to_the_load_result() -> void:
	var session := _boot_session()
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = 50.0
	snapshot.items = []
	snapshot.equipment = {"main_hand": "item.ghost", "hat": "item.test.sword"}
	var warnings := session.apply_snapshot(snapshot)
	assert_eq(warnings.size(), 2, "both dropped records are reported: %s" % warnings)
	assert_eq(session.state.equipment.equipped_slots().size(), 0, "nothing is equipped")


func test_a_slot_mismatch_returns_the_item_instead_of_losing_it() -> void:
	var session := _boot_session()
	var snapshot := SaveSnapshot.new()
	snapshot.version = SaveSnapshot.CURRENT_VERSION
	snapshot.health = 100.0
	snapshot.items = []
	snapshot.equipment = {"chest_armor": String(SWORD)}  # a sword in the armour slot
	session.apply_snapshot(snapshot)
	assert_eq(session.state.equipment.get_equipped(EquipmentSlot.Id.CHEST_ARMOR), &"", "refused")
	assert_eq(session.state.inventory.count_of(SWORD), 1, "and the copy is in the bag, not lost")


# --- L11: movement speed follows the effective stat ---------------------------

func test_movement_speed_follows_the_effective_stat() -> void:
	var session := _boot_session()
	var player := _spawn_player()
	if player == null:
		return
	assert_almost_eq(player.move_speed, 4.0, 0.0001, "the scene default before any binding")
	session.apply_stats_to_player(player)
	assert_almost_eq(player.move_speed, 4.0, 0.0001, "the base stat matches the scene value")
	assert_true(session.stats.set_modifiers(&"boots", {CharacterStats.MOVEMENT_SPEED: 1.5}), "buffed")
	assert_almost_eq(player.move_speed, 5.5, 0.0001, "the rig followed the change")
	assert_true(session.stats.clear_modifiers(&"boots"), "buff removed")
	assert_almost_eq(player.move_speed, 4.0, 0.0001, "and back to the base")
