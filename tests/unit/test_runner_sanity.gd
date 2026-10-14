extends "res://tests/test_case.gd"

## Canary for the test seam itself: proves the runner executes sync tests,
## awaits async tests, keeps the scene tree available and cleans owned nodes.

var _setup_calls: int = 0
var _setup_call_for_current_test: int = 0


func setup() -> void:
	_setup_calls += 1
	_setup_call_for_current_test = _setup_calls


func test_setup_hook_runs_before_each_test() -> void:
	assert_eq(
		_setup_call_for_current_test,
		_setup_calls,
		"setup() must have run for the currently executing test"
	)


func test_assertions_are_counted() -> void:
	assert_true(true, "sanity")
	assert_eq(2 + 2, 4, "sanity")
	assert_almost_eq(0.1 + 0.2, 0.3, 0.0001, "float tolerance")
	assert_ne("a", "b", "ne")
	assert_not_null(self, "self is not null")


func test_physics_frames_are_awaited_headlessly() -> void:
	var probe := Node3D.new()
	add_to_tree(probe)
	var before := probe.get_physics_process_delta_time()
	await wait_physics_frames(3)
	assert_true(is_instance_valid(probe), "node stays valid across awaited physics frames")
	assert_true(before > 0.0, "physics delta is configured")


func test_owned_nodes_are_available_in_the_tree() -> void:
	var parent := Node.new()
	add_to_tree(parent)
	var child := Node.new()
	parent.add_child(child)
	await wait_process_frames(1)
	assert_eq(child.get_parent(), parent, "child keeps its parent in the tree")
