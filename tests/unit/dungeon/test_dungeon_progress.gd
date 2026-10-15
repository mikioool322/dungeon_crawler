extends "res://tests/test_case.gd"

## AC (progress) - durable story progress: explicit mutations, idempotency, tolerant
## serialisation, and no way for a UI to mutate the collections directly.

const START_IDS: Array[StringName] = [&"dungeon.01"]


func _ids(values: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in values:
		ids.append(StringName(value))
	return ids


func _progress() -> DungeonProgress:
	var progress := DungeonProgress.new()
	progress.reset_to_new_game(START_IDS)
	return progress


func test_a_new_game_unlocks_only_the_start_dungeons() -> void:
	var progress := _progress()
	assert_true(progress.is_unlocked(&"dungeon.01"), "the start dungeon is available")
	assert_false(progress.is_unlocked(&"dungeon.02"), "everything else is locked")
	assert_false(progress.is_completed(&"dungeon.01"), "nothing is completed")
	assert_eq(progress.completed_ids().size(), 0, "no completions")
	assert_eq(progress.unlocked_ids(), START_IDS, "only the seed")


func test_mark_completed_reports_the_first_completion_only_once() -> void:
	var progress := _progress()
	assert_true(progress.mark_completed(&"dungeon.01"), "first completion")
	assert_false(progress.mark_completed(&"dungeon.01"), "a repeat is not a first clear")
	assert_true(progress.is_completed(&"dungeon.01"), "it stays completed")
	assert_false(progress.mark_completed(&""), "an empty id is refused")


func test_unlock_is_idempotent_and_reports_newly_unlocked() -> void:
	var progress := _progress()
	assert_true(progress.unlock(&"dungeon.02"), "newly unlocked")
	assert_false(progress.unlock(&"dungeon.02"), "already unlocked")
	assert_false(progress.unlock(&""), "an empty id is refused")
	assert_eq(progress.unlock_all([&"dungeon.02", &"dungeon.03"] as Array[StringName]), 1, "one new id")


func test_first_clear_claims_are_one_shot() -> void:
	var progress := _progress()
	assert_false(progress.was_first_clear_claimed(&"dungeon.01"), "not claimed yet")
	assert_true(progress.mark_first_clear_claimed(&"dungeon.01"), "claimed")
	assert_false(progress.mark_first_clear_claimed(&"dungeon.01"), "claiming twice is refused")
	assert_true(progress.was_first_clear_claimed(&"dungeon.01"), "and it stays claimed")


func test_story_flags_are_one_shot() -> void:
	var progress := _progress()
	assert_false(progress.has_flag(&"story.intro_seen"), "unset")
	assert_true(progress.set_flag(&"story.intro_seen"), "set")
	assert_false(progress.set_flag(&"story.intro_seen"), "setting twice is refused")
	assert_true(progress.has_flag(&"story.intro_seen"), "it stays set")


func test_save_dict_round_trip_is_stable_and_sorted() -> void:
	var progress := _progress()
	progress.mark_completed(&"dungeon.02")
	progress.mark_completed(&"dungeon.01")
	progress.unlock(&"dungeon.03")
	progress.mark_first_clear_claimed(&"dungeon.01")
	progress.set_flag(&"story.intro_seen")

	var data := progress.to_save_dict()
	assert_eq(data["completed"], PackedStringArray(["dungeon.01", "dungeon.02"]), "sorted ids")
	assert_eq(data["unlocked"], PackedStringArray(["dungeon.01", "dungeon.03"]), "sorted unlocks")
	assert_eq(data["first_clear_claimed"], PackedStringArray(["dungeon.01"]), "claims")
	assert_eq(data["story_flags"], PackedStringArray(["story.intro_seen"]), "flags")

	var restored := DungeonProgress.from_save_dict(data)
	assert_eq(restored.completed_ids(), progress.completed_ids(), "completions survive")
	assert_eq(restored.unlocked_ids(), progress.unlocked_ids(), "unlocks survive")
	assert_true(restored.was_first_clear_claimed(&"dungeon.01"), "claims survive")
	assert_true(restored.has_flag(&"story.intro_seen"), "flags survive")


func test_from_save_dict_is_tolerant() -> void:
	var empty := DungeonProgress.from_save_dict({})
	assert_eq(empty.completed_ids().size(), 0, "an empty dictionary is empty progress")
	assert_eq(empty.unlocked_ids().size(), 0, "no unlocks invented")

	var junk := DungeonProgress.from_save_dict({
		"completed": [1, null, &"dungeon.01"],
		"unlocked": "not an array",
		"first_clear_claimed": [&"", &"dungeon.02"],
	})
	assert_eq(junk.completed_ids(), _ids([&"dungeon.01"]), "only string ids are kept")
	assert_eq(junk.unlocked_ids().size(), 0, "a wrong type yields nothing")
	assert_eq(junk.first_clear_claimed_ids(), _ids([&"dungeon.02"]), "empty ids are dropped")


func test_reset_to_new_game_clears_everything_but_the_seed() -> void:
	var progress := _progress()
	progress.mark_completed(&"dungeon.01")
	progress.unlock(&"dungeon.02")
	progress.mark_first_clear_claimed(&"dungeon.01")
	progress.set_flag(&"story.intro_seen")
	progress.reset_to_new_game(START_IDS)
	assert_eq(progress.completed_ids().size(), 0, "completions cleared")
	assert_eq(progress.unlocked_ids(), START_IDS, "only the seed remains")
	assert_eq(progress.first_clear_claimed_ids().size(), 0, "claims cleared")
	assert_false(progress.has_flag(&"story.intro_seen"), "flags cleared")
