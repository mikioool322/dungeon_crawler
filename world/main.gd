class_name Main
extends Node

## Composition root of the game (ADR-007): the only place that knows the concrete
## classes, their construction order and the content manifest path.
##
## `Main` is the main scene and never unloads; the current world is swapped inside
## `WorldRouter.world_slot`, so the session survives every travel. It owns no
## gameplay state of its own.

const MANIFEST_PATH: String = "res://content/definitions/content_manifest.tres"

@export var world_slot: Node3D = null
@export var router: WorldRouter = null
@export var hud: GameHud = null

## Save slot path; empty means the shipped default (`user://save_slot0.json`).
## Tests inject a temporary path so they never touch a real save.
@export var save_path: String = ""

var registry: ContentRegistry = null
var save_manager: SaveManager = null
var session: GameSession = null
var boot_result: SaveResult = null


func _ready() -> void:
	registry = ContentRegistry.build(load(MANIFEST_PATH) as ContentManifest)
	if not registry.is_valid():
		push_error("Main: content manifest is not valid: %s" % "; ".join(registry.errors))

	save_manager = SaveManager.new()
	save_manager.setup(save_path)

	session = GameSession.new()
	session.setup(registry, save_manager)
	boot_result = session.load_or_new()

	# Retry story rewards whose claim was never recorded (broken content on the first
	# attempt). Idempotent: an already claimed reward is skipped.
	var pending_rewards := session.dungeons.claim_pending_first_clear_rewards()
	if pending_rewards > 0:
		print("[Main] granted %d pending first-clear reward(s)" % pending_rewards)

	if router == null:
		push_error("Main: router is not assigned; nothing will be loaded")
		return
	router.world_slot = world_slot
	router.configure(session, registry)

	if hud != null:
		hud.bind(session, router, registry)

	var travel_code := router.bootstrap(session.state.world_id, session.state.spawn_id)
	if travel_code != WorldRouter.CODE_TRAVEL_STARTED:
		# A save that points at a world this build cannot enter must not brick the boot.
		push_warning(
			"Main: could not load '%s' (%s); falling back to the hub" % [
				session.state.world_id, travel_code
			]
		)
		router.bootstrap(GameSession.DEFAULT_WORLD_ID, &"")

	# After the bootstrap so the boot outcome (new game / loaded / corrupt) is what the
	# player sees first, instead of the "Entered world..." travel line.
	if hud != null:
		hud.set_status(boot_message(boot_result))


## Human-readable boot outcome for the HUD (never parsed for logic).
func boot_message(result: SaveResult) -> String:
	if result == null:
		return "New game"
	var suffix := ""
	if not result.warnings.is_empty():
		suffix = " (%d warning(s))" % result.warnings.size()
	match result.status:
		SaveResult.Status.OK:
			return "Save loaded%s" % suffix
		SaveResult.Status.MISSING:
			return "New game (no save found)"
		SaveResult.Status.CORRUPT:
			return "Save unreadable; started a new game"
		SaveResult.Status.UNSUPPORTED_VERSION:
			return "Save version unsupported; started a new game"
		_:
			return "Save error: %s" % result.message
