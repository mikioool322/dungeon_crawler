extends "res://tests/test_case.gd"

## W5 — player death on the real composition root (AC-32, ADR-007).
##
## The live rig dies in the dungeon through the real `HealthComponent`; the router's
## own death handler must respawn in the hub at its default spawn with full HP while
## inventory, gold and *story* reward claims survive (a run-scoped claim is discarded
## with the aborted run, ADR-013/ADR-014). The dead rig must be freed by the ordinary
## world swap (no in-place revive, no leaked `PlayerController`).
##
## The lethal hit is applied directly with a test `DamageRequest` (the Sprint 01
## suite already proves the 9-hit natural route in the arena); the death signal,
## the router handler and the swap are the real ones. The save path is injected and
## never touches the real slot.

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_death_respawn_slot.json"

const HUB_WORLD := &"world.hub"
const DUNGEON_WORLD := &"world.dungeon.proto01"
const SALVE := &"item.minor_salve"

var _main: Main = null


func setup() -> void:
	_main = null
	_delete_save_files()


func teardown() -> void:
	_main = null
	_delete_save_files()


func _delete_save_files() -> void:
	for suffix in ["", ".tmp", ".bak", ".corrupt"]:
		var path := "%s%s" % [TEST_SAVE_PATH, suffix]
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _instantiate_main() -> Main:
	var scene := load(MAIN_SCENE_PATH) as PackedScene
	if scene == null:
		fail("main scene failed to load: %s" % MAIN_SCENE_PATH)
		return null
	_main = scene.instantiate() as Main
	if _main == null:
		fail("main scene root is not a Main")
		return null
	_main.save_path = TEST_SAVE_PATH
	add_to_tree(_main)
	return _main


func _walk(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		found.append(child)
		found.append_array(_walk(child))
	return found


func _count_players(root: Node) -> int:
	var count := 0
	for node in _walk(root):
		if node is PlayerController:
			count += 1
	return count


func _count_worlds(root: Node) -> int:
	var count := 0
	for node in _walk(root):
		if node is WorldHost:
			count += 1
	return count


func _count_enemies(root: Node) -> int:
	var count := 0
	for node in _walk(root):
		if node is EnemyBrain:
			count += 1
	return count


func test_lethal_damage_in_the_dungeon_respawns_in_the_hub_with_progress_kept() -> void:
	_main = _instantiate_main()
	if _main == null:
		return
	await wait_physics_frames(30)
	assert_eq(_main.router.current_world_id(), HUB_WORLD, "the run starts in the hub")

	var travel := _main.router.request_travel(DUNGEON_WORLD, &"spawn.dungeon.entry")
	assert_eq(travel, WorldRouter.CODE_TRAVEL_STARTED, "the router travels to the dungeon")
	await wait_physics_frames(5)
	assert_eq(_main.router.current_world_id(), DUNGEON_WORLD, "the dungeon is the current world")

	# --- progress that must survive the death ----------------------------------
	var salve := _main.registry.find_item(SALVE)
	assert_not_null(salve, "the shipped salve definition exists")
	if salve == null:
		return
	var story_reward := RewardDefinition.new()
	story_reward.id = &"reward.tests.death_story"
	story_reward.item = salve
	story_reward.item_count = 2
	story_reward.gold = 7
	assert_true(story_reward.is_valid(), "the story test reward is valid")
	var story_key := LootGrant.key_for(&"dungeon.01", &"tests.death_story")
	var story_grant := LootGrant.from_reward(story_key, story_reward, LootGrant.SCOPE_STORY)
	assert_eq(
		_main.session.loot.grant(story_grant),
		LootService.CODE_GRANTED,
		"the story reward is claimed for the save"
	)

	var run_reward := RewardDefinition.new()
	run_reward.id = &"reward.tests.death_run"
	run_reward.item = salve
	run_reward.item_count = 1
	run_reward.gold = 3
	assert_true(run_reward.is_valid(), "the run test reward is valid")
	var run_key := LootGrant.key_for(DUNGEON_WORLD, &"tests.death_run")
	var run_grant := LootGrant.from_reward(run_key, run_reward)
	assert_eq(
		_main.session.loot.grant(run_grant),
		LootService.CODE_GRANTED,
		"the active run earns an ordinary reward too"
	)
	assert_true(_main.session.loot.is_claimed_in_run(run_key), "the run ledger holds the ordinary key")
	assert_false(
		_main.session.state.is_claimed(run_key), "the ordinary key never reaches the save ledger"
	)
	assert_true(_main.session.state.is_claimed(story_key), "the story key is in the persistent ledger")

	var dead_player := _main.router.current_player()
	assert_not_null(dead_player, "the router owns the dungeon rig")
	if dead_player == null:
		return
	var health := HealthComponent.find_on(dead_player)
	assert_not_null(health, "the rig has a HealthComponent")
	if health == null:
		return
	assert_almost_eq(health.current_health, 100.0, 0.0001, "the rig starts at full HP")

	# --- lethal damage through the real component ------------------------------
	var lethal := health.apply_damage(
		DamageRequest.new(
			&"tests.w5.lethal",
			&"tests.w5",
			health.max_health + 1.0,
			dead_player.global_position,
			Vector3.UP
		)
	)
	assert_true(lethal.target_died, "the lethal request kills the player")

	# --- the router respawned in the hub in the same call ----------------------
	assert_eq(_main.router.current_world_id(), HUB_WORLD, "the router respawned in the hub")
	assert_eq(_main.world_slot.get_child_count(), 1, "exactly one world is hosted after the respawn")
	var respawned := _main.router.current_player()
	assert_not_null(respawned, "the router owns the respawned rig")
	if respawned == null:
		return
	assert_ne(respawned, dead_player, "the dead rig was replaced, not revived")
	assert_false(respawned.is_dead, "the respawned rig is alive")

	var respawned_health := HealthComponent.find_on(respawned)
	assert_not_null(respawned_health, "the respawned rig has a HealthComponent")
	if respawned_health != null:
		assert_almost_eq(
			respawned_health.current_health, 100.0, 0.0001, "the respawn is at full HP"
		)
	assert_almost_eq(_main.session.state.health, 100.0, 0.0001, "the session stores full HP")

	var hub := _main.router.current_world()
	assert_not_null(hub, "the hub world is loaded after the respawn")
	if hub == null:
		return
	var marker := hub.resolve_spawn(&"spawn.hub.start")
	assert_not_null(marker, "the hub default spawn resolves")
	if marker != null:
		var offset := MeleeRules.horizontal_distance(respawned.global_position, marker.global_position)
		assert_true(offset < 0.5, "the respawn is at spawn.hub.start (%.2f m off)" % offset)
	assert_eq(_main.session.state.world_id, HUB_WORLD, "the session records the hub")
	assert_eq(_main.session.state.spawn_id, &"spawn.hub.start", "and the hub default spawn id")

	assert_eq(_main.session.state.gold, 10, "gold survived the death (7 story + 3 run)")
	assert_eq(_main.session.state.inventory.count_of(SALVE), 3, "the inventory survived the death")
	assert_true(_main.session.state.is_claimed(story_key), "the story reward key survived the death")
	assert_false(
		_main.session.state.is_claimed(run_key), "the ordinary run key was never persistent"
	)
	assert_false(
		_main.session.loot.is_claimed_in_run(run_key), "the run-scoped claim was discarded with the run"
	)
	assert_eq(
		_main.session.state.claimed_reward_keys.size(), 1, "only the story claim remains persistent"
	)
	assert_eq(_main.session.loot.current_run_id(), 0, "no run ledger is open after the respawn")
	assert_null(_main.session.dungeons.active_run(), "the death aborted the run (ADR-014)")
	assert_eq(
		_main.session.loot.grant(story_grant),
		LootService.CODE_DUPLICATE,
		"the story reward can never be earned twice"
	)

	# --- no leaked actors ------------------------------------------------------
	await wait_process_frames(3)
	assert_false(is_instance_valid(dead_player), "the dead rig is freed (no leaked PlayerController)")
	assert_eq(_count_players(_main), 1, "exactly one player rig remains")
	assert_eq(_count_players(runner_root), 1, "the whole tree holds no duplicate rig")
	assert_eq(_count_worlds(runner_root), 1, "exactly one world remains")
	assert_eq(_count_enemies(runner_root), 0, "the dungeon enemy was freed with its world")

	assert_not_null(_main.hud, "the HUD is wired after the respawn")
	if _main.hud != null:
		assert_true(
			_main.hud.health_label.text.contains("100"),
			"the HUD shows full HP after the respawn: '%s'" % _main.hud.health_label.text
		)
		assert_true(
			_main.hud.world_label.text.contains("world.hub"),
			"the HUD shows the hub after the respawn: '%s'" % _main.hud.world_label.text
		)
