class_name DungeonProgress
extends RefCounted

## Durable story progress for dungeons (ADR-012). Survives travel, runs, save/load and
## restarts; never holds a Node reference and never stores transient run state.
##
## Invariants:
## - Only `GameSession`/`DungeonService` mutate it; UI and portals read it.
## - `mark_completed()` reports whether the completion was the *first* one, so the
##   caller can grant a story reward exactly once.
## - `unlock()` is idempotent and reports whether the dungeon was newly unlocked.
## - Serialisation is a plain JSON-compatible dictionary of stable ids.

var _completed: Dictionary = {}
var _unlocked: Dictionary = {}
var _first_clear_claimed: Dictionary = {}
var _story_flags: Dictionary = {}


## New game: no completions, no claims, only the start dungeons unlocked.
func reset_to_new_game(start_dungeon_ids: Array[StringName]) -> void:
	_completed.clear()
	_unlocked.clear()
	_first_clear_claimed.clear()
	_story_flags.clear()
	unlock_all(start_dungeon_ids)


func is_unlocked(id: StringName) -> bool:
	return id != &"" and _unlocked.has(id)


func is_completed(id: StringName) -> bool:
	return id != &"" and _completed.has(id)


func was_first_clear_claimed(id: StringName) -> bool:
	return id != &"" and _first_clear_claimed.has(id)


func completed_ids() -> Array[StringName]:
	return _sorted_ids(_completed)


func unlocked_ids() -> Array[StringName]:
	return _sorted_ids(_unlocked)


func first_clear_claimed_ids() -> Array[StringName]:
	return _sorted_ids(_first_clear_claimed)


## Unlocks one dungeon; true when it was not unlocked before.
func unlock(id: StringName) -> bool:
	if id == &"" or _unlocked.has(id):
		return false
	_unlocked[id] = true
	return true


## Unlocks a list; returns how many were newly unlocked.
func unlock_all(ids: Array[StringName]) -> int:
	var newly := 0
	for id in ids:
		if unlock(id):
			newly += 1
	return newly


## Records a completion; true when this was the first completion of that dungeon.
func mark_completed(id: StringName) -> bool:
	if id == &"" or _completed.has(id):
		return false
	_completed[id] = true
	return true


## Records that the one-time story reward of `id` was granted. True when newly recorded.
func mark_first_clear_claimed(id: StringName) -> bool:
	if id == &"" or _first_clear_claimed.has(id):
		return false
	_first_clear_claimed[id] = true
	return true


func has_flag(flag: StringName) -> bool:
	return flag != &"" and _story_flags.has(flag)


## Records a durable story flag. True when it was not set before.
func set_flag(flag: StringName) -> bool:
	if flag == &"" or _story_flags.has(flag):
		return false
	_story_flags[flag] = true
	return true


## JSON-compatible, stable-ordered representation for the save file.
func to_save_dict() -> Dictionary:
	return {
		"completed": _ids_to_strings(_completed),
		"unlocked": _ids_to_strings(_unlocked),
		"first_clear_claimed": _ids_to_strings(_first_clear_claimed),
		"story_flags": _ids_to_strings(_story_flags),
	}


## Tolerant parse (ADR-010): malformed entries are dropped, never a failure. A missing
## or unusable dictionary yields empty progress; the session then seeds the start
## dungeons, so the first dungeon stays available after a v1 migration.
static func from_save_dict(data: Dictionary) -> DungeonProgress:
	var progress := DungeonProgress.new()
	progress._read_ids(data.get("completed"), progress._completed)
	progress._read_ids(data.get("unlocked"), progress._unlocked)
	progress._read_ids(data.get("first_clear_claimed"), progress._first_clear_claimed)
	progress._read_ids(data.get("story_flags"), progress._story_flags)
	return progress


func _read_ids(value: Variant, target: Dictionary) -> void:
	if not value is Array and not value is PackedStringArray:
		return
	for entry: Variant in value:
		var id := _as_id(entry)
		if id != &"":
			target[id] = true


static func _as_id(value: Variant) -> StringName:
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return &""


func _sorted_ids(source: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in source.keys():
		ids.append(id)
	ids.sort()
	return ids


func _ids_to_strings(source: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _sorted_ids(source):
		out.append(String(id))
	return out


func _to_string() -> String:
	return "DungeonProgress(completed=%d, unlocked=%d, claimed=%d)" % [
		_completed.size(), _unlocked.size(), _first_clear_claimed.size()
	]
