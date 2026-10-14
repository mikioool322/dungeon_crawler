extends SceneTree

## Sprint 02 content generator (maintenance tool, like tools/setup_input_map.gd).
##
## Run:  <godot> --headless --path . -s res://tools/generate_content_manifest.gd
##
## It writes the world definitions and the content manifest so the typed arrays
## serialize exactly as Godot expects, then prints the registry validation result.
## The script is the source of truth for those .tres files: add content here and
## re-run it instead of hand-editing the manifest.

const WORLD_HUB := "res://content/definitions/world_hub.tres"
const WORLD_DUNGEON := "res://content/definitions/world_dungeon_proto01.tres"
const MANIFEST := "res://content/definitions/content_manifest.tres"


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	var hub := WorldDefinition.new()
	hub.id = &"world.hub"
	hub.display_name = "Hub"
	hub.scene = load("res://world/hub/hub.tscn") as PackedScene
	hub.default_spawn_id = &"spawn.hub.start"

	var dungeon := WorldDefinition.new()
	dungeon.id = &"world.dungeon.proto01"
	dungeon.display_name = "Proto Dungeon"
	dungeon.scene = load("res://world/dungeons/dungeon_proto01.tscn") as PackedScene
	dungeon.default_spawn_id = &"spawn.dungeon.entry"

	var failed := 0
	failed += _save(hub, WORLD_HUB)
	failed += _save(dungeon, WORLD_DUNGEON)

	var manifest := ContentManifest.new()

	var attacks: Array[AttackDefinition] = []
	attacks.append(load("res://content/definitions/attack_player_basic.tres"))
	attacks.append(load("res://content/definitions/attack_enemy_basic.tres"))
	manifest.attacks = attacks

	var enemies: Array[EnemyDefinition] = []
	enemies.append(load("res://content/definitions/enemy_grunt.tres"))
	manifest.enemies = enemies

	var items: Array[ItemDefinition] = []
	items.append(load("res://content/definitions/item_rusty_dagger.tres"))
	items.append(load("res://content/definitions/item_minor_salve.tres"))
	manifest.items = items

	var rewards: Array[RewardDefinition] = []
	rewards.append(load("res://content/definitions/reward_grunt_drop.tres"))
	rewards.append(load("res://content/definitions/reward_chest_proto01.tres"))
	manifest.rewards = rewards

	var worlds: Array[WorldDefinition] = []
	# Load the saved world definitions back so the manifest references the loose .tres
	# files (ExtResource) instead of embedding a second inline copy: re-running this
	# tool must be idempotent.
	worlds.append(load(WORLD_HUB) as WorldDefinition)
	worlds.append(load(WORLD_DUNGEON) as WorldDefinition)
	manifest.worlds = worlds

	failed += _save(manifest, MANIFEST)

	var registry := ContentRegistry.build(manifest)
	print("generated worlds=%d items=%d rewards=%d attacks=%d enemies=%d" % [
		worlds.size(), items.size(), rewards.size(), attacks.size(), enemies.size()
	])
	if registry.is_valid():
		print("registry: VALID")
	else:
		print("registry: INVALID")
		for problem in registry.errors:
			print("  %s" % problem)
		failed += 1
	quit(1 if failed > 0 else 0)


func _save(resource: Resource, path: String) -> int:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		print("failed to save %s (error %d)" % [path, err])
		return 1
	print("saved %s" % path)
	return 0
