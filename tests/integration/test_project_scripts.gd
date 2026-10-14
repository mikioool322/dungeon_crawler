extends "res://tests/test_case.gd"

## W6 project-wide parser, scene and settings validation (AC-10 "Godot parser
## validation", ADR-005, ADR-006).
##
## Scope: everything the project ships, not just the combat slice — every `.gd`,
## every `.tscn`, every `.tres` under `content/`, plus the cross-module settings the
## sprint froze (InputMap action list, 3D physics layer names).
##
## Why the scanner asserts a minimum file count: a silent DirAccess failure would
## otherwise turn this file into a no-op that always passes.

const TEST_CASE_PATH := "res://tests/test_case.gd"

## Directories `tests/run_tests.gd` discovers tests in (the discovery contract).
const SCANNED_TEST_DIRS: Array[String] = ["res://tests/unit", "res://tests/integration"]

## ADR-005 closed list: actions the project is allowed to define.
const ADR_005_ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"attack_primary",
]

## ADR-005 physics layers: index -> the name `project.godot` must carry.
const EXPECTED_LAYER_NAMES: Dictionary = {
	1: "world",
	2: "player_body",
	3: "enemy_body",
	4: "hurtbox",
}

const MIN_SCRIPT_COUNT := 20
const MIN_SCENE_COUNT := 3
const MIN_TEST_COUNT := 10


# --- scanning ----------------------------------------------------------------

## Recursively collects files ending in `extension` under `directory`. Hidden
## directories (`.godot/`, `.opencode/`) are skipped: they are caches/tooling, not
## project content, and the import cache holds no authored `.gd`.
func _collect(directory: String, extension: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := directory.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect(full_path, extension, out)
		elif entry.ends_with(extension):
			out.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()


func _collect_or_fail(directory: String, extension: String, minimum: int) -> PackedStringArray:
	var found := PackedStringArray()
	_collect(directory, extension, found)
	found.sort()
	assert_true(
		found.size() >= minimum,
		"the scanner found at least %d %s file(s) under %s (got %d)" % [
			minimum, extension, directory, found.size()
		]
	)
	return found


# --- scripts -----------------------------------------------------------------

func test_every_gd_script_loads_and_instantiates() -> void:
	var paths := _collect_or_fail("res://", ".gd", MIN_SCRIPT_COUNT)
	for path in paths:
		var script := load(path) as GDScript
		assert_not_null(script, "script loads without a parse error: %s" % path)
		if script == null:
			continue
		assert_true(script.can_instantiate(), "script can be instantiated: %s" % path)
		if not script.can_instantiate():
			continue
		var base_type: StringName = script.get_instance_base_type()
		if base_type == &"MainLoop" or base_type == &"SceneTree":
			# `tests/run_tests.gd` is the running main loop; constructing a second
			# SceneTree inside it would test the engine, not the parser. Loading and
			# `can_instantiate()` above are the parser checks for this one file.
			continue
		var instance: Object = script.new()
		assert_not_null(instance, "script instantiates as a real object: %s" % path)
		if instance is Node:
			# Orphan nodes: `_ready` never runs, so no scene wiring is triggered.
			(instance as Node).free()


func test_every_test_file_extends_the_shared_test_case() -> void:
	var paths := _collect_or_fail("res://tests", ".gd", MIN_TEST_COUNT)
	var test_case := load(TEST_CASE_PATH) as GDScript
	assert_not_null(test_case, "the shared test case loads: %s" % TEST_CASE_PATH)
	if test_case == null:
		return

	var test_paths := PackedStringArray()
	for path in paths:
		var file_name := path.get_file()
		# `test_case.gd` is the shared base class, not a test file.
		if file_name.begins_with("test_") and file_name != "test_case.gd":
			test_paths.append(path)
	assert_true(
		test_paths.size() >= MIN_TEST_COUNT,
		"the scanner found at least %d test file(s) (got %d)" % [MIN_TEST_COUNT, test_paths.size()]
	)

	for path in test_paths:
		var scanned := false
		for directory in SCANNED_TEST_DIRS:
			if path.begins_with(directory + "/"):
				scanned = true
		assert_true(
			scanned,
			"%s is under a directory tests/run_tests.gd discovers (unit/integration)" % path
		)

		var script := load(path) as GDScript
		assert_not_null(script, "test file loads: %s" % path)
		if script == null:
			continue
		assert_eq(
			script.get_base_script(),
			test_case,
			"%s extends res://tests/test_case.gd" % path
		)
		assert_true(script.can_instantiate(), "test file can be instantiated: %s" % path)
		if not script.can_instantiate():
			continue
		var instance: Object = script.new()
		assert_true(
			instance.has_method("assert_true"),
			"%s passes the runner's own discovery check" % path
		)


# --- scenes and resources -----------------------------------------------------

func test_every_scene_loads_and_instantiates_as_a_node() -> void:
	var paths := _collect_or_fail("res://", ".tscn", MIN_SCENE_COUNT)
	for path in paths:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "scene loads without a parse error: %s" % path)
		if packed == null:
			continue
		assert_true(packed.can_instantiate(), "packed scene can be instantiated: %s" % path)
		var instance := packed.instantiate()
		assert_not_null(instance, "scene instantiates: %s" % path)
		if instance == null:
			continue
		assert_true(
			instance is Node, "scene root instantiates as a Node: %s (got %s)" % [path, instance.get_class()]
		)
		if instance is Node:
			(instance as Node).free()


func test_every_content_resource_loads() -> void:
	var paths := _collect_or_fail("res://content", ".tres", 1)
	for path in paths:
		var resource := load(path)
		assert_not_null(resource, "content resource loads: %s" % path)
		assert_true(
			resource is Resource,
			"content definition is a Resource: %s (%s)" % [path, type_string(typeof(resource))]
		)


# --- frozen settings (ADR-005) ------------------------------------------------

func test_input_map_still_matches_the_adr_005_closed_list() -> void:
	var declared := PackedStringArray()
	for action: StringName in InputMap.get_actions():
		# `ui_*` are engine built-ins (ui_cancel is used to release the mouse).
		if not String(action).begins_with("ui_"):
			declared.append(String(action))
	declared.sort()

	var expected := PackedStringArray()
	for action in ADR_005_ACTIONS:
		expected.append(String(action))
	expected.sort()
	assert_eq(declared, expected, "the project defines exactly the ADR-005 actions")

	for action in ADR_005_ACTIONS:
		assert_true(InputMap.has_action(action), "ADR-005 action exists: %s" % action)
		assert_eq(
			InputMap.action_get_events(action).size(),
			1,
			"action %s keeps exactly one bound event" % action
		)


func test_physics_layer_names_still_match_project_settings() -> void:
	for layer_index: int in EXPECTED_LAYER_NAMES:
		var key := "layer_names/3d_physics/layer_%d" % layer_index
		assert_eq(
			ProjectSettings.get_setting(key),
			EXPECTED_LAYER_NAMES[layer_index],
			"3D physics layer %d keeps its ADR-005 name" % layer_index
		)
	for layer_index in range(EXPECTED_LAYER_NAMES.size() + 1, 33):
		var key := "layer_names/3d_physics/layer_%d" % layer_index
		var value: Variant = ProjectSettings.get_setting(key, null)
		assert_true(
			value == null or String(value) == "",
			"unused 3D physics layer %d must stay unnamed (got '%s')" % [layer_index, value]
		)


func test_physics_layer_bits_still_match_the_named_layers() -> void:
	## The layer names above are only documentation unless the bit constants agree.
	assert_eq(PhysicsLayers.WORLD, 1 << (1 - 1), "world is the first named layer")
	assert_eq(PhysicsLayers.PLAYER_BODY, 1 << (2 - 1), "player_body is the second named layer")
	assert_eq(PhysicsLayers.ENEMY_BODY, 1 << (3 - 1), "enemy_body is the third named layer")
	assert_eq(PhysicsLayers.HURTBOX, 1 << (4 - 1), "hurtbox is the fourth named layer")
	assert_true(
		PhysicsLayers.PLAYER_BODY & PhysicsLayers.ENEMY_BODY == 0,
		"player and enemy bodies are distinct layers"
	)
