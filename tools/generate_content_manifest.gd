extends SceneTree

## Sprint 02/03 content generator (maintenance tool, like tools/setup_input_map.gd).
##
## Run:  <godot> --headless --path . -s res://tools/generate_content_manifest.gd
##
## It writes the world definitions, dungeon definitions and the content manifest so the
## typed arrays serialize exactly as Godot expects, then prints the registry validation
## result. The script is the source of truth for those .tres files: add content here and
## re-run it instead of hand-editing the manifest. Re-running is idempotent (the manifest
## references the loose world/dungeon .tres files instead of embedding copies).

const WORLD_HUB := "res://content/definitions/world_hub.tres"
const WORLD_DUNGEON := "res://content/definitions/world_dungeon_proto01.tres"
const WORLD_DUNGEON_02 := "res://content/definitions/world_dungeon_proto02.tres"
const DUNGEON_01 := "res://content/definitions/dungeon_01.tres"
const DUNGEON_02 := "res://content/definitions/dungeon_02.tres"
const MANIFEST := "res://content/definitions/content_manifest.tres"

const REWARD_STORY_01 := "res://content/definitions/reward_story_dungeon01.tres"
const REWARD_REGULAR_01 := "res://content/definitions/reward_regular_dungeon01.tres"
const REWARD_STORY_02 := "res://content/definitions/reward_story_dungeon02.tres"
const REWARD_REGULAR_02 := "res://content/definitions/reward_regular_dungeon02.tres"
const REWARD_CHEST_02 := "res://content/definitions/reward_chest_proto02.tres"
const ATTACK_SWORD := "res://content/definitions/attack_player_iron_sword.tres"
const ITEM_SWORD := "res://content/definitions/item_iron_sword.tres"
const ITEM_VEST := "res://content/definitions/item_leather_vest.tres"
const MERCHANT := "res://content/definitions/merchant_hub_smith.tres"
const NPC := "res://content/definitions/npc_hub_smith.tres"
const PLAYER := "res://content/definitions/player_default.tres"


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	var failed := 0

	# --- worlds -----------------------------------------------------------------
	var hub := WorldDefinition.new()
	hub.id = &"world.hub"
	hub.display_name = "Hub"
	hub.scene = load("res://world/hub/hub.tscn") as PackedScene
	hub.default_spawn_id = &"spawn.hub.start"
	failed += _save(hub, WORLD_HUB)

	var dungeon01_world := WorldDefinition.new()
	dungeon01_world.id = &"world.dungeon.proto01"
	dungeon01_world.display_name = "Proto Dungeon"
	dungeon01_world.scene = load("res://world/dungeons/dungeon_proto01.tscn") as PackedScene
	dungeon01_world.default_spawn_id = &"spawn.dungeon.entry"
	failed += _save(dungeon01_world, WORLD_DUNGEON)

	var dungeon02_world := WorldDefinition.new()
	dungeon02_world.id = &"world.dungeon.proto02"
	dungeon02_world.display_name = "Sunken Vault"
	dungeon02_world.scene = load("res://world/dungeons/dungeon_proto02.tscn") as PackedScene
	dungeon02_world.default_spawn_id = &"spawn.dungeon.entry"
	failed += _save(dungeon02_world, WORLD_DUNGEON_02)

	# --- rewards -----------------------------------------------------------------
	var dagger := load("res://content/definitions/item_rusty_dagger.tres") as ItemDefinition
	var salve := load("res://content/definitions/item_minor_salve.tres") as ItemDefinition

	failed += _save(
		_reward(&"reward.story.dungeon01", dagger, 1, 10), REWARD_STORY_01
	)
	failed += _save(_reward(&"reward.regular.dungeon01", null, 0, 5), REWARD_REGULAR_01)
	failed += _save(_reward(&"reward.story.dungeon02", null, 0, 25), REWARD_STORY_02)
	failed += _save(_reward(&"reward.regular.dungeon02", null, 0, 8), REWARD_REGULAR_02)
	failed += _save(_reward(&"reward.chest.proto02", salve, 1, 6), REWARD_CHEST_02)

	# --- dungeons ----------------------------------------------------------------
	var dungeon01 := DungeonDefinition.new()
	dungeon01.dungeon_id = &"dungeon.01"
	dungeon01.display_name = "Dungeon 01 - Collapsed Hall"
	dungeon01.world_id = &"world.dungeon.proto01"
	dungeon01.entry_spawn_id = &"spawn.dungeon.entry"
	dungeon01.prerequisites = [] as Array[StringName]
	dungeon01.first_clear_unlocks = [&"dungeon.02"] as Array[StringName]
	dungeon01.repeatable = true
	dungeon01.completion_objective = &"objective.dungeon01.enemy_a"
	dungeon01.regular_reward_id = &"reward.regular.dungeon01"
	dungeon01.first_clear_reward_id = &"reward.story.dungeon01"
	failed += _save(dungeon01, DUNGEON_01)

	var dungeon02 := DungeonDefinition.new()
	dungeon02.dungeon_id = &"dungeon.02"
	dungeon02.display_name = "Dungeon 02 - Sunken Vault"
	dungeon02.world_id = &"world.dungeon.proto02"
	dungeon02.entry_spawn_id = &"spawn.dungeon.entry"
	dungeon02.prerequisites = [&"dungeon.01"] as Array[StringName]
	dungeon02.first_clear_unlocks = [] as Array[StringName]
	dungeon02.repeatable = true
	dungeon02.completion_objective = &"objective.dungeon02.enemy_b"
	dungeon02.regular_reward_id = &"reward.regular.dungeon02"
	dungeon02.first_clear_reward_id = &"reward.story.dungeon02"
	failed += _save(dungeon02, DUNGEON_02)

	# --- sprint 04: player, weapons, armour, merchant, npc -----------------------
	var sword_profile := AttackDefinition.new()
	sword_profile.id = &"attack.player.iron_sword"
	sword_profile.damage = 0.0  # the stats own the damage (ADR-016)
	sword_profile.reach = 2.2
	sword_profile.hit_radius = 0.3
	sword_profile.hit_arc_degrees = 60.0
	sword_profile.windup = 0.28
	sword_profile.active_window = 0.12
	sword_profile.recovery = 0.42
	sword_profile.cooldown = 0.7
	failed += _save(sword_profile, ATTACK_SWORD)

	var vest := ItemDefinition.new()
	vest.id = &"item.leather_vest"
	vest.display_name = "Leather Vest"
	vest.description = "Cracked hide over a layer of rags. Better than nothing."
	vest.kind = ItemDefinition.Kind.MISC
	vest.stackable = false
	vest.max_stack = 1
	vest.slot = EquipmentSlot.Id.CHEST_ARMOR
	vest.defense_bonus = 5
	vest.base_value = 30
	failed += _save(vest, ITEM_VEST)

	var sword := ItemDefinition.new()
	sword.id = &"item.iron_sword"
	sword.display_name = "Iron Sword"
	sword.description = "Plain, heavy, and honest about what it is for."
	sword.kind = ItemDefinition.Kind.WEAPON
	sword.stackable = false
	sword.max_stack = 1
	sword.slot = EquipmentSlot.Id.MAIN_HAND
	sword.attack_bonus = 15
	sword.attack_definition = sword_profile
	sword.base_value = 40
	failed += _save(sword, ITEM_SWORD)

	# The story dagger becomes a usable (and sellable) weak weapon.
	dagger.slot = EquipmentSlot.Id.MAIN_HAND
	dagger.attack_bonus = 6
	dagger.base_value = 12
	failed += _save(dagger, "res://content/definitions/item_rusty_dagger.tres")

	salve.base_value = 6
	failed += _save(salve, "res://content/definitions/item_minor_salve.tres")

	var merchant := MerchantDefinition.new()
	merchant.id = &"merchant.hub.smith"
	merchant.display_name = "Orla the Smith"
	merchant.greeting = "Steel for coin. Nothing else worth saying."
	var stock: Array[ItemDefinition] = [sword, vest]
	merchant.stock = stock
	failed += _save(merchant, MERCHANT)

	var npc := NpcDefinition.new()
	npc.id = &"npc.hub.smith"
	npc.display_name = "Orla the Smith"
	npc.greeting = "Back again? The forge does not run on goodwill."
	npc.merchant = merchant
	failed += _save(npc, NPC)

	var player := PlayerDefinition.new()
	player.id = &"player.default"
	player.display_name = "Wanderer"
	player.max_health = 100.0
	player.attack_damage = 34.0  # matches attack_player_basic.damage: no unarmed regression
	player.defense = 0.0
	player.movement_speed = 4.0
	player.attack_definition = load("res://content/definitions/attack_player_basic.tres")
	failed += _save(player, PLAYER)

	# --- manifest ----------------------------------------------------------------
	var manifest := ContentManifest.new()

	var attacks: Array[AttackDefinition] = []
	attacks.append(load("res://content/definitions/attack_player_basic.tres"))
	attacks.append(load("res://content/definitions/attack_enemy_basic.tres"))
	attacks.append(load(ATTACK_SWORD))
	manifest.attacks = attacks

	var enemies: Array[EnemyDefinition] = []
	enemies.append(load("res://content/definitions/enemy_grunt.tres"))
	manifest.enemies = enemies

	var items: Array[ItemDefinition] = []
	items.append(dagger)
	items.append(salve)
	items.append(sword)
	items.append(vest)
	manifest.items = items

	var rewards: Array[RewardDefinition] = []
	rewards.append(load("res://content/definitions/reward_grunt_drop.tres"))
	rewards.append(load("res://content/definitions/reward_chest_proto01.tres"))
	rewards.append(load(REWARD_STORY_01))
	rewards.append(load(REWARD_REGULAR_01))
	rewards.append(load(REWARD_STORY_02))
	rewards.append(load(REWARD_REGULAR_02))
	rewards.append(load(REWARD_CHEST_02))
	manifest.rewards = rewards

	var worlds: Array[WorldDefinition] = []
	worlds.append(load(WORLD_HUB))
	worlds.append(load(WORLD_DUNGEON))
	worlds.append(load(WORLD_DUNGEON_02))
	manifest.worlds = worlds

	var dungeons: Array[DungeonDefinition] = []
	dungeons.append(load(DUNGEON_01))
	dungeons.append(load(DUNGEON_02))
	manifest.dungeons = dungeons

	manifest.player = load(PLAYER)

	var merchants: Array[MerchantDefinition] = []
	merchants.append(load(MERCHANT))
	manifest.merchants = merchants

	var npcs: Array[NpcDefinition] = []
	npcs.append(load(NPC))
	manifest.npcs = npcs

	failed += _save(manifest, MANIFEST)

	var registry := ContentRegistry.build(manifest)
	print("generated worlds=%d dungeons=%d items=%d rewards=%d attacks=%d enemies=%d" % [
		worlds.size(), dungeons.size(), items.size(), rewards.size(), attacks.size(), enemies.size()
	])
	if registry.is_valid():
		print("registry: VALID")
		print("start dungeons: %s" % [registry.start_dungeon_ids()])
	else:
		print("registry: INVALID")
		for problem in registry.errors:
			print("  %s" % problem)
		failed += 1
	quit(1 if failed > 0 else 0)


func _reward(
	id: StringName, item: ItemDefinition, item_count: int, gold: int
) -> RewardDefinition:
	var reward := RewardDefinition.new()
	reward.id = id
	reward.item = item
	reward.item_count = item_count
	reward.gold = gold
	return reward


func _save(resource: Resource, path: String) -> int:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		print("failed to save %s (error %d)" % [path, err])
		return 1
	print("saved %s" % path)
	return 0
