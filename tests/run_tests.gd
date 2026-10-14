extends SceneTree

## Zero-dependency headless test runner (ADR-006 — no external test addon).
##
## Usage:
##   <godot-console> --headless --path . -s res://tests/run_tests.gd
## Exit code: 0 = all tests passed, 1 = failures or no tests discovered.
##
## Discovery: `test_*.gd` under tests/unit and tests/integration that extend
## res://tests/test_case.gd. Test methods are `test_*`; async methods are awaited.

const TEST_CASE_PATH := "res://tests/test_case.gd"
const TEST_DIRS: Array[String] = ["res://tests/unit", "res://tests/integration"]

var _tests_run: int = 0
var _tests_failed: int = 0
var _assertions: int = 0
var _failure_messages: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	var files := _collect_test_files()
	print("=== run_tests | Godot %s ===" % Engine.get_version_info().get("string", "unknown"))
	print("=== %d test file(s) discovered ===" % files.size())
	for file in files:
		await _run_file(file)
	print("")
	print("=== summary: %d test(s), %d assertion(s), %d failing test(s) ===" % [
		_tests_run, _assertions, _tests_failed
	])
	for message in _failure_messages:
		print("  FAIL: %s" % message)
	if _tests_run == 0:
		print("RESULT: FAIL (no tests discovered)")
		quit(1)
	elif _tests_failed > 0:
		print("RESULT: FAIL")
		quit(1)
	else:
		print("RESULT: PASS")
		quit(0)


func _run_file(path: String) -> void:
	var script := load(path) as GDScript
	if script == null:
		_register_file_error(path, "script failed to load")
		return
	if not script.can_instantiate():
		_register_file_error(path, "script has parse errors (run the editor import step)")
		return
	var instance: Object = script.new()
	if instance == null or not instance.has_method("assert_true"):
		_register_file_error(path, "does not extend res://tests/test_case.gd")
		return
	instance.set("runner_root", root)
	instance.set("test_file", path)
	for method_name in _test_methods(instance):
		instance.set("current_test", method_name)
		var failures_before: PackedStringArray = instance.get("failures")
		var count_before: int = failures_before.size()
		var assertions_before: int = instance.get("assertions")
		instance.call("setup")
		var result: Variant = instance.call(method_name)
		if _is_coroutine(result):
			await result
		instance.call("teardown")
		instance.call("_dispose_owned")
		var new_assertions: int = instance.get("assertions") - assertions_before
		_assertions += new_assertions
		_tests_run += 1
		var new_failures := failures_before.slice(count_before)
		if new_failures.is_empty():
			print("PASS  %s::%s (%d assertions)" % [path, method_name, new_assertions])
		else:
			_tests_failed += 1
			print("FAIL  %s::%s (%d assertions)" % [path, method_name, new_assertions])
			for message in new_failures:
				_failure_messages.append(message)


## Coroutine detection: GDScriptFunctionState is not exposed as a GDScript type,
## but an awaiting call returns an Object whose class reports that name.
func _is_coroutine(value: Variant) -> bool:
	return value is Object and value.get_class() == "GDScriptFunctionState"


func _register_file_error(path: String, reason: String) -> void:
	_tests_run += 1
	_tests_failed += 1
	var message := "%s: %s" % [path, reason]
	_failure_messages.append(message)
	print("FAIL  %s" % message)


func _test_methods(instance: Object) -> PackedStringArray:
	var names := PackedStringArray()
	for method in instance.get_method_list():
		var name: String = method.get("name", "")
		if name.begins_with("test_") and not names.has(name):
			names.append(name)
	names.sort()
	return names


func _collect_test_files() -> PackedStringArray:
	var files := PackedStringArray()
	for directory in TEST_DIRS:
		_scan_dir(directory, files)
	files.sort()
	return files


func _scan_dir(directory: String, files: PackedStringArray) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan_dir(directory.path_join(entry), files)
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			files.append(directory.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
