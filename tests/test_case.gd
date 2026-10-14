extends RefCounted

## Base class for the zero-dependency test suite (ADR-006).
##
## Test files extend this by PATH, never by global class_name, so test scripts
## cannot collide with gameplay class names:
##
##     extends "res://tests/test_case.gd"
##
## Test discovery rules (see tests/run_tests.gd):
##   - file name matches `test_*.gd` under tests/unit or tests/integration
##   - every `test_*` method is executed; `setup()` and `teardown()` are optional
##   - async test methods may `await wait_physics_frames()`; the runner awaits them
##
## Assertion helpers record into `failures`; the runner decides PASS/FAIL.

## SceneTree root, injected by the runner. Also the parent for add_to_tree().
var runner_root: Window = null

## Human-readable failures, formatted as "<file>::<test>: <message>".
var failures: PackedStringArray = PackedStringArray()

## Total assertion count (used by the runner for evidence output).
var assertions: int = 0

## Current test method and file name, set by the runner.
var current_test: String = ""
var test_file: String = ""

var _owned_nodes: Array[Node] = []


# --- Optional per-test hooks -------------------------------------------------

func setup() -> void:
	pass


func teardown() -> void:
	pass


# --- Assertions --------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	_record(condition, message if message != "" else "expected true, got false")


func assert_false(condition: bool, message: String = "") -> void:
	_record(not condition, message if message != "" else "expected false, got true")


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_record(actual == expected, message if message != "" else "expected %s, got %s" % [expected, actual])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_record(actual != unexpected, message if message != "" else "value must differ from %s" % [unexpected])


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	_record(
		absf(actual - expected) <= tolerance,
		message if message != "" else "expected %f +/- %f, got %f" % [expected, tolerance, actual]
	)


func assert_not_null(value: Variant, message: String = "") -> void:
	_record(value != null, message if message != "" else "expected non-null value")


func assert_null(value: Variant, message: String = "") -> void:
	_record(value == null, message if message != "" else "expected null value")


func assert_instance_of(value: Variant, expected_class: Variant, message: String = "") -> void:
	var type_name: String = str(expected_class)
	var ok: bool = false
	if value is Object:
		ok = value.is_class(type_name)
	_record(ok, message if message != "" else "expected instance of %s, got %s" % [type_name, value])


func fail(message: String) -> void:
	_record(false, message)


# --- Node / frame helpers ----------------------------------------------------

## Adds `node` under the scene tree root and returns it. Freed automatically
## after the current test method finishes.
func add_to_tree(node: Node) -> Node:
	if runner_root == null:
		push_error("test_case.add_to_tree: runner_root not set")
		return node
	runner_root.add_child(node)
	_owned_nodes.append(node)
	return node


## Waits for physics frames; use in async tests that need real collisions.
func wait_physics_frames(count: int = 1) -> void:
	var tree := runner_root.get_tree() if runner_root != null else null
	if tree == null:
		push_error("test_case.wait_physics_frames: no scene tree")
		return
	for _i in count:
		await tree.physics_frame


## Waits for idle frames; use in async tests that need _process or deferred work.
func wait_process_frames(count: int = 1) -> void:
	var tree := runner_root.get_tree() if runner_root != null else null
	if tree == null:
		push_error("test_case.wait_process_frames: no scene tree")
		return
	for _i in count:
		await tree.process_frame


# --- Runner internals --------------------------------------------------------

func _record(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append("%s::%s: %s" % [test_file, current_test, message])


func _dispose_owned() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
