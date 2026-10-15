extends "res://tests/test_case.gd"

## W5 — the Sprint 02 end-to-end loop on the real composition root (AC-31).
##
## Everything runs on the shipped scenes: `res://world/main.tscn` (the real `Main`,
## `WorldRouter`, `WorldHost`, `GameSession`, `ContentRegistry`, `SaveManager`,
## `GameHud`), the real `player.tscn`, `enemy.tscn`, portals, chest, shrine and the
## shipped content manifest. The save path is injected per test, so the real slot
## (`user://save_slot0.json`) is never read or written; every temporary file is
## removed in setup/teardown.
##
## Seams used (documented, not invented):
## - travel: the real `PortalInteractable` focused by the real `InteractionController`
##   ray and resolved through `InteractionController.try_interact()` (the same call
##   the `interact` action route ends in; the raw `Input.parse_input_event` route is
##   covered by `test_interaction_ray.gd`).
## - combat: `player._unhandled_input(InputEventAction("attack_primary", true))`, the
##   seam used by `test_encounter.gd`, with the shipped 34-damage player swing.
## - the pre-fight damage: applied directly through the real `HealthComponent` with a
##   test `DamageRequest` (34.0). The grunt's own hits depend on windup timing, so a
##   direct hit keeps the "HP is provably not full" precondition deterministic; the
##   kill itself still runs the full real combat path.
## - pickup: `Input.parse_input_event(&"interact")`, the real E route.
##
## Determinism: no real-time sleeps; every wait is counted in physics frames. Before
## every ray interaction the player is placed at geometry computed against the shipped
## box shapes, and each focus is asserted before it is used.
##
## Geometry (player at floor height, camera 1.6 m above the body origin, forward -Z at
## yaw 0):
## - hub portal  (0, 0, -11.5), box y[0, 2.4] z[-11.7, -11.3] -> player 2.0 m away, pitch 0
## - grunt drop  (enemy death spot), sphere y[0, 1.0]        -> player 1.2 m away, pitch -0.65
## - chest       (-6, 0, -6),    box y[0, 0.8] z[-6.35, -5.65] -> player 1.5 m away, pitch -0.6
## - return portal (0, 0, 9.5),  box y[0, 2.4] z[9.3, 9.7]  -> player 2.0 m away, pitch 0
## - shrine      (5, 0, -9),     box y[0, 1.4] z[-9.6, -8.4]  -> player 1.5 m away, pitch -0.5

const MAIN_SCENE_PATH := "res://world/main.tscn"
const TEST_SAVE_PATH := "user://test_sprint02_loop_slot.json"

const HUB_WORLD := &"world.hub"
const DUNGEON_WORLD := &"world.dungeon.proto01"
const GRUNT_KEY := &"world.dungeon.proto01/enemy.a"
const CHEST_KEY := &"world.dungeon.proto01/chest.a"
const SALVE := &"item.minor_salve"

const GRUNT_GOLD := 3
const CHEST_GOLD := 5
const CHEST_ITEM_COUNT := 1
const PLAYER_SWING_DAMAGE := 34.0

## Dungeon 01 completion rewards (ADR-012/ADR-013): the grunt is the objective boss, so
## killing it completes the dungeon and grants the regular (5) and first-clear (10) gold.
const COMPLETION_REGULAR_GOLD := 5
const COMPLETION_STORY_GOLD := 10
const COMPLETION_GOLD := COMPLETION_REGULAR_GOLD + COMPLETION_STORY_GOLD
const STORY_KEY := &"dungeon.01/reward.story.dungeon01"

var _main: Main = null

## `reward_granted` emissions per grant key, recorded from the real loot service.
var _grants: Dictionary = {}


func setup() -> void:
	_main = null
	_grants = {}
	_delete_save_files()


func teardown() -> void:
	Input.action_release(&"interact")
	Input.action_release(&"attack_primary")
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


# --- tree helpers -------------------------------------------------------------

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


func _find_pickups(root: Node) -> Array[PickupInteractable]:
	var found: Array[PickupInteractable] = []
	for node in _walk(root):
		if node is PickupInteractable:
			found.append(node as PickupInteractable)
	return found


# --- actor / input helpers ----------------------------------------------------

func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if condition.call():
			return true
		await wait_physics_frames(1)
	return condition.call()


## Places the rig `distance` metres in front of `target` (horizontal), facing it, and
## sets the head pitch. The body height is preserved.
func _place_player(player: PlayerController, target: Vector3, distance: float, pitch: float) -> void:
	var to_target := target - player.global_position
	to_target.y = 0.0
	var direction := Vector3.FORWARD
	if to_target.length_squared() > 0.000001:
		direction = to_target.normalized()
	var position := target - direction * distance
	position.y = player.global_position.y
	player.global_position = position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = pitch


## One real player swing through the documented input seam; waits for the hit frame.
func _swing(player: PlayerController) -> DamageResult:
	var attack := player.get_node_or_null(^"AttackController") as AttackController
	if attack == null:
		fail("the player rig has no AttackController")
		return null
	var ready := await _wait_until(func() -> bool: return attack.can_attack(), 180)
	if not ready:
		fail("the player never became able to swing again (cooldown/phase)")
		return null
	player._unhandled_input(_action_event(&"attack_primary", true))
	if not attack.is_busy():
		fail("attack_primary did not start a swing on the real rig")
		return null
	var resolved := await _wait_until(func() -> bool: return attack.last_result() != null, 180)
	if not resolved:
		fail("the player's swing never resolved")
		return null
	return attack.last_result()


func _on_reward_granted(grant: LootGrant, _gold_total: int) -> void:
	if grant == null:
		return
	_grants[grant.grant_key] = int(_grants.get(grant.grant_key, 0)) + 1


# --- fresh boot ---------------------------------------------------------------

func test_fresh_boot_starts_in_the_hub_with_one_rig_and_the_hub_hud() -> void:
	_main = _instantiate_main()
	if _main == null:
		return
	await wait_physics_frames(30)

	assert_eq(_main.boot_result.status, SaveResult.Status.MISSING, "a fresh slot starts a new game")
	assert_eq(_main.session.state.world_id, HUB_WORLD, "the session starts in the hub")
	assert_eq(_main.session.state.spawn_id, &"spawn.hub.start", "at the hub's default spawn")
	assert_eq(_main.router.current_world_id(), HUB_WORLD, "the router loaded the hub")
	assert_eq(_main.world_slot.get_child_count(), 1, "exactly one world is hosted")
	assert_eq(_count_players(_main), 1, "exactly one player rig exists")

	var player := _main.router.current_player()
	assert_not_null(player, "the router owns the player")
	if player == null:
		return
	var marker := _main.router.current_world().resolve_spawn(&"spawn.hub.start")
	assert_not_null(marker, "the hub start marker resolves")
	if marker != null:
		var offset := MeleeRules.horizontal_distance(player.global_position, marker.global_position)
		assert_true(offset < 0.5, "the player spawned at spawn.hub.start (%.2f m off)" % offset)
	assert_true(player.is_on_floor(), "the rig stands on the hub floor")

	assert_not_null(_main.hud, "the HUD is wired")
	if _main.hud != null:
		assert_true(
			_main.hud.world_label.text.contains("world.hub"),
			"the HUD shows the hub: '%s'" % _main.hud.world_label.text
		)
		assert_true(
			_main.hud.health_label.text.contains("100"),
			"the HUD shows full HP: '%s'" % _main.hud.health_label.text
		)
		assert_true(
			_main.hud.gold_label.text.contains("0"),
			"the HUD shows 0 gold: '%s'" % _main.hud.gold_label.text
		)


# --- the whole loop -----------------------------------------------------------

func test_full_loop_hub_to_dungeon_loot_return_save_and_reload() -> void:
	_main = _instantiate_main()
	if _main == null:
		return
	_main.session.loot.reward_granted.connect(_on_reward_granted)
	await wait_physics_frames(30)

	# --- 1. hub -> dungeon through the real hub portal -------------------------
	var player := _main.router.current_player()
	if player == null:
		fail("no player after boot")
		return
	var controller := InteractionController.find_on(player)
	if controller == null:
		fail("the player rig has no InteractionController")
		return
	var hub := _main.router.current_world()
	var hub_portal := hub.get_node_or_null("PortalToDungeon") as PortalInteractable
	assert_not_null(hub_portal, "the hub portal exists")
	if hub_portal == null:
		return

	_place_player(player, hub_portal.global_position, 2.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), hub_portal, "the hub portal is focused through the real ray")
	var travel := controller.try_interact()
	assert_true(travel.succeeded(), "the hub portal starts the travel: %s" % travel)
	assert_eq(travel.message, "travel_started", "the portal reports the router's travel_started code")
	await wait_physics_frames(3)

	# --- 2. landed in the dungeon at spawn.dungeon.entry ------------------------
	var dungeon := _main.router.current_world()
	assert_eq(_main.router.current_world_id(), DUNGEON_WORLD, "travel landed in the dungeon")
	assert_eq(_main.world_slot.get_child_count(), 1, "the hub was swapped out, not stacked")
	assert_eq(_count_players(_main), 1, "still exactly one player rig")
	player = _main.router.current_player()
	if player == null:
		fail("no player after the travel")
		return
	controller = InteractionController.find_on(player)
	var entry_marker := dungeon.resolve_spawn(&"spawn.dungeon.entry")
	assert_not_null(entry_marker, "the dungeon entry marker resolves")
	if entry_marker != null:
		var entry_offset := MeleeRules.horizontal_distance(player.global_position, entry_marker.global_position)
		assert_true(entry_offset < 0.5, "the player spawned at spawn.dungeon.entry (%.2f m off)" % entry_offset)
	assert_eq(
		_main.session.state.spawn_id,
		&"spawn.dungeon.entry",
		"the session recorded the dungeon spawn"
	)
	assert_eq(_find_pickups(dungeon).size(), 0, "no drop exists before the grunt is defeated")

	# --- 3. damage the player first (direct, documented) ------------------------
	var health := HealthComponent.find_on(player)
	var enemy := dungeon.get_node_or_null("Enemy") as EnemyBrain
	var enemy_health := HealthComponent.find_on(enemy) if enemy != null else null
	assert_not_null(health, "the player rig has a HealthComponent")
	assert_not_null(enemy, "the dungeon holds the grunt")
	assert_not_null(enemy_health, "the grunt has a HealthComponent")
	if health == null or enemy == null or enemy_health == null:
		return
	var setup_hit := health.apply_damage(
		DamageRequest.new(&"tests.w5.setup", &"tests.w5", PLAYER_SWING_DAMAGE, player.global_position, Vector3.UP)
	)
	assert_true(setup_hit.applied, "the documented setup hit lands on the live rig")
	assert_almost_eq(health.current_health, 66.0, 0.0001, "HP is provably below full before the fight")

	# --- 4. kill the grunt with the real 34-damage swings -----------------------
	_place_player(player, enemy.global_position, 1.9, 0.0)
	await wait_physics_frames(2)
	assert_true(
		MeleeRules.horizontal_distance(player.global_position, enemy.global_position) <= 2.3,
		"the grunt stands inside the player's reach (%.2f m)" % MeleeRules.horizontal_distance(
			player.global_position, enemy.global_position
		)
	)
	for swing in 3:
		var result := await _swing(player)
		assert_not_null(result, "player swing %d resolved" % (swing + 1))
		if result == null:
			return
		assert_true(result.applied, "player swing %d landed on the grunt (%s)" % [swing + 1, result])
		assert_eq(result.target_id, &"enemy.grunt", "swing %d hit the grunt's HealthComponent" % (swing + 1))
	assert_false(enemy_health.is_alive(), "three 34-damage swings kill the 100 HP grunt")
	assert_eq(enemy.fsm_state, EnemyFsm.State.DEAD, "the grunt's FSM reports DEAD")
	assert_true(
		health.current_health > 0.0 and health.current_health <= 66.0,
		"the player survived the exchange and never healed (HP %.1f)" % health.current_health
	)

	# --- 5. exactly one drop, reward.grunt_drop (3 gold, no item) ---------------
	var pickups := _find_pickups(dungeon)
	assert_eq(pickups.size(), 1, "the defeated grunt spawned exactly one loot pickup")
	if pickups.size() != 1:
		return
	var pickup := pickups[0]
	assert_eq(pickup.grant_key, GRUNT_KEY, "the drop's idempotency key is world.dungeon.proto01/enemy.a")
	assert_true(pickup.is_bound(), "the world host bound the drop to the loot service")
	assert_not_null(pickup.reward, "the drop carries a reward")
	if pickup.reward != null:
		assert_eq(pickup.reward.id, &"reward.grunt_drop", "the reward is reward.grunt_drop")
		assert_eq(pickup.reward.gold, GRUNT_GOLD, "worth exactly 3 gold")
		assert_null(pickup.reward.item, "and no item")
	# The grunt is dungeon 01's objective boss, so its death completed the run and
	# granted the completion rewards before the drop is even touched (ADR-012/013).
	assert_eq(
		_main.session.state.gold, COMPLETION_GOLD, "the completion rewards landed on the kill"
	)
	assert_true(_main.session.progress.is_completed(&"dungeon.01"), "the dungeon is completed")

	# --- 6. pick it up with the real interact action ----------------------------
	_place_player(player, pickup.global_position, 1.2, -0.65)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), pickup, "the drop is focused through the real ray")
	Input.parse_input_event(_action_event(&"interact", true))
	await wait_physics_frames(2)
	Input.parse_input_event(_action_event(&"interact", false))
	await wait_process_frames(2)

	assert_eq(
		_main.session.state.gold, COMPLETION_GOLD + GRUNT_GOLD, "the pickup granted exactly 3 gold"
	)
	assert_eq(_grants.get(GRUNT_KEY, 0), 1, "reward_granted fired exactly once for the drop key")
	assert_true(
		_main.session.loot.is_claimed_in_run(GRUNT_KEY),
		"the drop key is claimed in the RUN ledger (ADR-013)"
	)
	assert_false(
		_main.session.state.is_claimed(GRUNT_KEY),
		"and NOT in the persistent ledger: ordinary loot repeats next run"
	)
	assert_false(is_instance_valid(pickup), "the pickup is consumed after the grant")
	assert_true(
		_main.hud.gold_label.text.contains(str(COMPLETION_GOLD + GRUNT_GOLD)),
		"the HUD gold label follows a loot grant, got '%s'" % _main.hud.gold_label.text
	)

	var second := controller.try_interact()
	assert_false(second.succeeded(), "a second interact on the gone drop is refused")
	assert_eq(
		_main.session.state.gold, COMPLETION_GOLD + GRUNT_GOLD, "and the gold never changes twice"
	)
	assert_eq(_grants.get(GRUNT_KEY, 0), 1, "and reward_granted stays at exactly one")

	# --- 7. open the chest: +1 item.minor_salve and +5 gold, exactly once -------
	var chest := dungeon.get_node_or_null("Chest") as ChestInteractable
	assert_not_null(chest, "the dungeon holds the chest")
	if chest == null:
		return
	_place_player(player, chest.global_position, 1.5, -0.6)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), chest, "the chest is focused through the real ray")
	var open := controller.try_interact()
	assert_true(open.succeeded(), "opening the chest succeeds: %s" % open)
	assert_eq(open.message, "granted", "the chest granted its reward")
	assert_eq(
		_main.session.state.inventory.count_of(SALVE),
		CHEST_ITEM_COUNT,
		"exactly one item.minor_salve was added"
	)
	assert_eq(
		_main.session.state.gold,
		COMPLETION_GOLD + GRUNT_GOLD + CHEST_GOLD,
		"gold is completion (15) + drop (3) + chest (5)"
	)
	assert_eq(_grants.get(CHEST_KEY, 0), 1, "reward_granted fired once for the chest key")
	assert_true(chest.is_used(), "the chest records the open")
	assert_true(is_instance_valid(chest), "the chest stays in the world")
	var reopen := chest.interact(player)
	assert_false(reopen.succeeded(), "the opened chest refuses a second open")
	assert_eq(
		_main.session.state.gold,
		COMPLETION_GOLD + GRUNT_GOLD + CHEST_GOLD,
		"a second open never pays twice"
	)
	assert_eq(
		_main.session.state.inventory.count_of(SALVE),
		CHEST_ITEM_COUNT,
		"and never adds a second salve"
	)

	# --- 8. return through the dungeon portal -----------------------------------
	var hp_before_travel := health.current_health
	var gold_before_travel := _main.session.state.gold
	var salve_before_travel := _main.session.state.inventory.count_of(SALVE)
	var dungeon_portal := dungeon.get_node_or_null("PortalToHub") as PortalInteractable
	assert_not_null(dungeon_portal, "the dungeon return portal exists")
	if dungeon_portal == null:
		return
	_place_player(player, dungeon_portal.global_position, 2.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), dungeon_portal, "the return portal is focused")
	var back := controller.try_interact()
	assert_true(back.succeeded(), "the return travel starts: %s" % back)
	await wait_physics_frames(3)

	assert_eq(_main.router.current_world_id(), HUB_WORLD, "the return landed in the hub")
	assert_eq(_main.world_slot.get_child_count(), 1, "one world is hosted after the return")
	assert_eq(_count_players(_main), 1, "one player rig after the return")
	player = _main.router.current_player()
	if player == null:
		fail("no player after the return travel")
		return
	controller = InteractionController.find_on(player)
	health = HealthComponent.find_on(player)
	var hub_again := _main.router.current_world()
	assert_not_null(controller, "the returned rig has an InteractionController")
	assert_not_null(health, "the returned rig has a HealthComponent")
	assert_not_null(hub_again, "the hub world is loaded after the return")
	if controller == null or health == null or hub_again == null:
		return
	var portal_marker := hub_again.resolve_spawn(&"spawn.hub.dungeon_portal")
	assert_not_null(portal_marker, "the hub portal-arrival marker resolves")
	if portal_marker != null:
		var portal_offset := MeleeRules.horizontal_distance(
			player.global_position, portal_marker.global_position
		)
		assert_true(
			portal_offset < 0.5,
			"the return spawned at spawn.hub.dungeon_portal (%.2f m off)" % portal_offset
		)
	assert_almost_eq(_main.session.state.health, hp_before_travel, 0.0001, "HP survived the travel")
	assert_almost_eq(health.current_health, hp_before_travel, 0.0001, "the fresh rig carries the same HP")
	assert_eq(_main.session.state.gold, gold_before_travel, "gold survived the travel")
	assert_eq(
		_main.session.state.inventory.count_of(SALVE),
		salve_before_travel,
		"the inventory survived the travel"
	)
	assert_eq(_main.session.state.world_id, HUB_WORLD, "the session location is the hub again")
	assert_true(
		_main.hud.world_label.text.contains("world.hub"),
		"the HUD followed the return: '%s'" % _main.hud.world_label.text
	)

	# --- 9. save at the hub shrine ----------------------------------------------
	var shrine := hub_again.get_node_or_null("Shrine") as SaveShrineInteractable
	assert_not_null(shrine, "the hub shrine exists")
	if shrine == null:
		return
	_place_player(player, shrine.global_position, 1.5, -0.5)
	await wait_physics_frames(3)
	assert_eq(controller.current_focus(), shrine, "the shrine is focused through the real ray")
	var saved_hp := health.current_health
	assert_true(saved_hp > 0.0 and saved_hp < 100.0, "the saved HP is provably not full (%.1f)" % saved_hp)
	var save_interaction := controller.try_interact()
	assert_true(save_interaction.succeeded(), "the shrine saves: %s" % save_interaction)
	assert_true(
		save_interaction.message.contains("Progress saved"),
		"the shrine reports a successful SaveResult: '%s'" % save_interaction.message
	)

	assert_true(_main.save_manager.snapshot_exists(), "the save file exists after the shrine interaction")
	var loaded := _main.save_manager.load_snapshot()
	assert_eq(loaded.status, SaveResult.Status.OK, "the written file loads back as SaveResult OK")
	assert_not_null(loaded.snapshot, "the load produced a snapshot")
	if loaded.snapshot != null:
		assert_almost_eq(loaded.snapshot.health, saved_hp, 0.0001, "the save holds the live HP")
		assert_eq(
			loaded.snapshot.gold,
			COMPLETION_GOLD + GRUNT_GOLD + CHEST_GOLD,
			"the save holds the earned gold"
		)
		assert_eq(loaded.snapshot.world_id, HUB_WORLD, "the save holds the hub world id")
		assert_eq(
			loaded.snapshot.spawn_id, &"spawn.hub.dungeon_portal", "the save holds the arrival spawn id"
		)
		assert_false(
			loaded.snapshot.claimed_reward_keys.has(String(GRUNT_KEY)),
			"the run-scoped drop key is NOT persisted (ADR-013)"
		)
		assert_false(
			loaded.snapshot.claimed_reward_keys.has(String(CHEST_KEY)),
			"nor is the chest key"
		)
		assert_true(
			loaded.snapshot.claimed_reward_keys.has(String(STORY_KEY)),
			"the one-time story key IS persisted"
		)
		assert_eq(
			loaded.snapshot.dungeon_progress.get("completed", []),
			PackedStringArray(["dungeon.01"]),
			"the save holds the dungeon completion"
		)
	for suffix in [".tmp", ".bak"]:
		assert_false(
			FileAccess.file_exists(TEST_SAVE_PATH + suffix),
			"a successful shrine save leaves no %s behind" % suffix
		)

	# --- 10. relaunch: a second, fresh Main on the same save path ---------------
	var expected_entries := _main.session.state.inventory.entries()
	var expected_gold := _main.session.state.gold
	var expected_world := _main.session.state.world_id
	var expected_spawn := _main.session.state.spawn_id
	var expected_key_count := _main.session.state.claimed_reward_keys.size()
	_main.queue_free()
	_main = null
	await wait_process_frames(3)

	var relaunched := _instantiate_main()
	if relaunched == null:
		return
	await wait_physics_frames(30)

	assert_eq(relaunched.boot_result.status, SaveResult.Status.OK, "the relaunch loaded the save")
	assert_true(
		relaunched.boot_result.warnings.is_empty(),
		"with no semantic warnings: %s" % relaunched.boot_result.warnings
	)
	assert_almost_eq(relaunched.session.state.health, saved_hp, 0.0001, "HP is identical after the relaunch")
	assert_eq(relaunched.session.state.gold, expected_gold, "gold is identical after the relaunch")
	assert_eq(
		relaunched.session.state.inventory.entries(), expected_entries, "inventory entries are identical"
	)
	assert_eq(relaunched.session.state.world_id, expected_world, "the world location is identical")
	assert_eq(relaunched.session.state.spawn_id, expected_spawn, "the spawn id is identical")
	assert_true(relaunched.session.state.is_claimed(STORY_KEY), "the story claim survives")
	assert_false(
		relaunched.session.state.is_claimed(GRUNT_KEY),
		"the run-scoped drop key was never persisted (ADR-013)"
	)
	assert_false(relaunched.session.state.is_claimed(CHEST_KEY), "nor was the chest key")
	assert_eq(
		relaunched.session.state.claimed_reward_keys.size(),
		expected_key_count,
		"exactly the persistent (story) keys are restored"
	)

	assert_eq(_count_players(relaunched), 1, "the relaunch has exactly one player rig")
	assert_eq(_count_players(runner_root), 1, "the whole tree holds exactly one player rig")
	assert_eq(_count_worlds(runner_root), 1, "and exactly one world")
	assert_eq(_count_enemies(runner_root), 0, "the hub hosts no enemies")

	var relaunched_player := relaunched.router.current_player()
	assert_not_null(relaunched_player, "the relaunched router owns a player")
	if relaunched_player != null:
		var relaunched_health := HealthComponent.find_on(relaunched_player)
		assert_not_null(relaunched_health, "the relaunched rig has a HealthComponent")
		if relaunched_health != null:
			assert_almost_eq(
				relaunched_health.current_health, saved_hp, 0.0001, "the live rig carries the saved HP"
			)
		var relaunched_marker := relaunched.router.current_world().resolve_spawn(expected_spawn)
		assert_not_null(relaunched_marker, "the saved spawn marker resolves")
		if relaunched_marker != null:
			var relaunched_offset := MeleeRules.horizontal_distance(
				relaunched_player.global_position, relaunched_marker.global_position
			)
			assert_true(
				relaunched_offset < 0.5,
				"the relaunch spawned at the saved location (%.2f m off)" % relaunched_offset
			)
	assert_not_null(relaunched.hud, "the relaunched HUD is wired")
	if relaunched.hud != null:
		assert_true(
			relaunched.hud.world_label.text.contains("world.hub"),
			"the relaunched HUD shows the hub: '%s'" % relaunched.hud.world_label.text
		)

	# --- 11. the claimed key really stops the drop from ever reappearing --------
	# World state is not persisted (ADR-009): the grunt is alive again on the second
	# visit, a fresh run starts, so the drop reappears and the ordinary rewards can be
	# earned again (ADR-012 rules 6-7); the one-time story reward stays claimed.
	relaunched.session.loot.reward_granted.connect(_on_reward_granted)
	var again := relaunched.router.request_travel(DUNGEON_WORLD, &"spawn.dungeon.entry")
	assert_eq(again, WorldRouter.CODE_TRAVEL_STARTED, "the relaunch can re-enter the dungeon")
	await wait_physics_frames(5)
	var dungeon_again := relaunched.router.current_world()
	assert_eq(relaunched.router.current_world_id(), DUNGEON_WORLD, "the second visit is in the dungeon")
	assert_true(relaunched.session.dungeons.is_run_active(), "the second visit has its own run")
	assert_false(
		relaunched.session.loot.is_claimed_in_run(GRUNT_KEY),
		"the new run ledger is empty, so the drop is earnable again"
	)
	var player_again := relaunched.router.current_player()
	var enemy_again := dungeon_again.get_node_or_null("Enemy") as EnemyBrain
	assert_not_null(player_again, "the second visit spawned a player")
	assert_not_null(enemy_again, "the grunt is alive again (world state is not persisted)")
	if player_again == null or enemy_again == null:
		return
	var story_gold_before := relaunched.session.state.gold
	_place_player(player_again, enemy_again.global_position, 1.9, 0.0)
	await wait_physics_frames(2)
	for swing in 3:
		var result := await _swing(player_again)
		assert_not_null(result, "second-visit swing %d resolved" % (swing + 1))
		if result == null:
			return
		assert_true(result.applied, "second-visit swing %d landed (%s)" % [swing + 1, result])
	assert_eq(enemy_again.fsm_state, EnemyFsm.State.DEAD, "the grunt died again")
	assert_eq(
		_find_pickups(dungeon_again).size(), 1, "the drop reappears in the new run (ADR-012 rule 6)"
	)
	assert_eq(
		relaunched.session.state.gold,
		story_gold_before + COMPLETION_REGULAR_GOLD,
		"only the repeatable completion reward is granted again"
	)
	assert_true(
		relaunched.session.state.inventory.count_of(&"item.rusty_dagger") == 1,
		"the one-time story item is NOT granted twice"
	)

	# The chest is fresh in the new run and pays its ordinary reward again.
	var chest_again := dungeon_again.get_node_or_null("Chest") as ChestInteractable
	assert_not_null(chest_again, "a fresh chest is back on the second visit")
	if chest_again == null:
		return
	var controller_again := InteractionController.find_on(player_again)
	assert_not_null(controller_again, "the second-visit rig has an InteractionController")
	_place_player(player_again, chest_again.global_position, 1.5, -0.6)
	await wait_physics_frames(3)
	if controller_again == null:
		return
	assert_eq(controller_again.current_focus(), chest_again, "the fresh chest is focused")
	var open_again := controller_again.try_interact()
	assert_true(open_again.succeeded(), "the fresh chest opens again: %s" % open_again)
	assert_eq(open_again.message, "granted", "and grants its ordinary reward in the new run")
	assert_eq(
		relaunched.session.state.gold,
		story_gold_before + COMPLETION_REGULAR_GOLD + CHEST_GOLD,
		"the chest pays again in a new run"
	)
	assert_eq(
		relaunched.session.state.inventory.count_of(SALVE),
		CHEST_ITEM_COUNT * 2,
		"and adds another salve"
	)
	assert_eq(_grants.get(CHEST_KEY, 0), 2, "reward_granted fires once per run for the chest key")
