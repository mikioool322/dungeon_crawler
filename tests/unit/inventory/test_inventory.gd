extends "res://tests/test_case.gd"

## AC-21 — counted item bag: add/count/remove, stack filling, invalid input, `changed`.
## Pure domain logic: no SceneTree and no resources on disk (ADR-006).

const STACK_ID := &"item.test.stack"
const SOLO_ID := &"item.test.solo"

var _bag: Inventory = null
var _change_count: int = 0


func setup() -> void:
	_bag = Inventory.new()
	_change_count = 0
	_bag.changed.connect(_on_changed)


func _on_changed() -> void:
	_change_count += 1


func _make_item(id: StringName, stackable: bool, max_stack: int) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = id
	definition.display_name = String(id)
	definition.stackable = stackable
	definition.max_stack = max_stack
	return definition


func _stackable(max_stack: int = 5) -> ItemDefinition:
	return _make_item(STACK_ID, true, max_stack)


func _solo() -> ItemDefinition:
	return _make_item(SOLO_ID, false, 1)


# --- empty bag ----------------------------------------------------------------

func test_empty_bag_defaults() -> void:
	assert_true(_bag.is_empty(), "a new bag is empty")
	assert_eq(_bag.total_item_count(), 0, "no items at all")
	assert_eq(_bag.ids().size(), 0, "no ids")
	assert_eq(_bag.entries().size(), 0, "no stack entries")
	assert_eq(_bag.count_of(STACK_ID), 0, "an unknown id counts 0")
	assert_eq(_bag.stack_count(STACK_ID), 0, "an unknown id has no stacks")
	assert_eq(_bag.remove(STACK_ID, 1), 0, "removing from an empty bag removes nothing")
	assert_eq(_bag.count_of(&""), 0, "an empty id counts 0")
	assert_eq(_change_count, 0, "no mutation, no signal")


# --- add / count / remove ------------------------------------------------------

func test_add_count_and_remove_round_trip() -> void:
	var item := _stackable()
	assert_eq(_bag.add(item, 3), 3, "add reports what it added")
	assert_eq(_bag.count_of(STACK_ID), 3, "count_of sees the copies")
	assert_eq(_bag.stack_count(STACK_ID), 1, "three copies fit one stack of five")
	assert_eq(_bag.total_item_count(), 3, "total counts every stack")
	assert_false(_bag.is_empty(), "the bag is no longer empty")
	var entries := _bag.entries()
	assert_eq(entries.size(), 1, "one entry")
	assert_eq(entries[0]["id"], String(STACK_ID), "the entry id is a String")
	assert_eq(entries[0]["count"], 3, "the entry count")
	assert_eq(_bag.remove(STACK_ID, 2), 2, "remove reports what it removed")
	assert_eq(_bag.count_of(STACK_ID), 1, "one copy left")
	assert_eq(_bag.remove(STACK_ID, 5), 1, "removing more than held removes only what is held")
	assert_eq(_bag.count_of(STACK_ID), 0, "nothing left, nothing negative")
	assert_true(_bag.is_empty(), "and the bag is empty again")
	assert_eq(_bag.entries().size(), 0, "an emptied stack is dropped from the bag")


func test_remove_drains_the_newest_stacks_first() -> void:
	assert_eq(_bag.add(_stackable(), 7), 7, "seven copies in two stacks")
	assert_eq(_bag.stack_count(STACK_ID), 2, "5 + 2")
	assert_eq(_bag.remove(STACK_ID, 3), 3, "three copies removed")
	var entries := _bag.entries()
	assert_eq(entries.size(), 1, "the drained newest stack disappeared")
	assert_eq(entries[0]["count"], 4, "the older stack lost 3 of its 5")
	assert_eq(_bag.count_of(STACK_ID), 4, "4 copies remain in one stack")


func test_stackable_adds_split_at_max_stack() -> void:
	assert_eq(_bag.add(_stackable(5), 7), 7, "seven copies of a max_stack 5 item")
	var entries := _bag.entries()
	assert_eq(entries.size(), 2, "the bag splits 5 + 2")
	assert_eq(entries[0]["count"], 5, "the full stack comes first")
	assert_eq(entries[1]["count"], 2, "the remainder is a second entry")
	assert_eq(_bag.stack_count(STACK_ID), 2, "two stacks")
	assert_eq(_bag.count_of(STACK_ID), 7, "seven copies in total")
	assert_eq(_bag.total_item_count(), 7, "and the total agrees")


func test_stackable_adds_top_up_partial_stacks_before_appending() -> void:
	_bag.add(_stackable(5), 3)
	assert_eq(_bag.add(_stackable(5), 4), 4, "four more copies")
	var entries := _bag.entries()
	assert_eq(entries.size(), 2, "the first stack was topped up instead of a third stack")
	assert_eq(entries[0]["count"], 5, "stack 0 is full")
	assert_eq(entries[1]["count"], 2, "the remainder landed in a new stack")
	assert_eq(_bag.count_of(STACK_ID), 7, "seven copies in total")


func test_non_stackable_items_never_merge() -> void:
	var dagger := _solo()
	assert_eq(_bag.add(dagger, 1), 1, "first dagger")
	assert_eq(_bag.add(_solo(), 1), 1, "second dagger")
	assert_eq(_bag.stack_count(SOLO_ID), 2, "a non-stackable item always gets its own entry")
	assert_eq(_bag.count_of(SOLO_ID), 2, "two daggers")
	var entries := _bag.entries()
	assert_eq(entries.size(), 2, "two entries")
	for entry in entries:
		assert_eq(entry["count"], 1, "each entry holds exactly one dagger")


func test_ids_are_sorted_and_unique() -> void:
	_bag.add(_stackable(), 3)
	_bag.add(_solo(), 2)
	_bag.add(_stackable(), 2)
	assert_eq(
		_bag.ids(),
		PackedStringArray([String(SOLO_ID), String(STACK_ID)]),
		"sorted and unique, independent of insertion order"
	)
	assert_eq(_bag.count_of(STACK_ID), 5, "both adds counted")


# --- invalid input -------------------------------------------------------------

func test_zero_and_negative_counts_add_nothing() -> void:
	var item := _stackable()
	assert_eq(_bag.add(item, 0), 0, "adding zero adds nothing")
	assert_eq(_bag.add(item, -1), 0, "adding a negative count adds nothing")
	assert_eq(_bag.add(null, 3), 0, "a null definition adds nothing")
	assert_true(_bag.is_empty(), "the bag is still empty")
	assert_eq(_change_count, 0, "rejected adds never emit changed")


func test_invalid_definitions_add_nothing() -> void:
	var broken := _stackable()
	broken.id = &""
	assert_eq(_bag.add(broken, 1), 0, "an empty id adds nothing")
	broken = _stackable()
	broken.display_name = ""
	assert_eq(_bag.add(broken, 1), 0, "a missing display name adds nothing")
	broken = _stackable()
	broken.stackable = false
	assert_eq(_bag.add(broken, 1), 0, "stackable/max_stack disagreement adds nothing")
	assert_true(_bag.is_empty(), "the bag is untouched")
	assert_eq(_bag.remove(&"", 1), 0, "removing an empty id removes nothing")
	assert_eq(_bag.remove(STACK_ID, 0), 0, "removing zero removes nothing")
	assert_eq(_bag.remove(STACK_ID, -2), 0, "removing a negative count removes nothing")


# --- copies, clear, signal -----------------------------------------------------

func test_entries_are_copies_and_cannot_alias_the_bag() -> void:
	_bag.add(_stackable(), 3)
	var entries := _bag.entries()
	entries[0]["count"] = 99
	entries[0]["id"] = "tampered"
	assert_eq(_bag.entries()[0]["count"], 3, "mutating a returned entry does not change the bag")
	assert_eq(_bag.count_of(STACK_ID), 3, "and the count is unchanged")
	assert_eq(_bag.ids(), PackedStringArray([String(STACK_ID)]), "and the id is unchanged")


func test_clear_empties_the_bag() -> void:
	_bag.add(_stackable(), 6)
	_bag.clear()
	assert_true(_bag.is_empty(), "clear empties the bag")
	assert_eq(_bag.total_item_count(), 0, "no items left")
	assert_eq(_bag.entries().size(), 0, "no entries left")
	assert_eq(_bag.ids().size(), 0, "no ids left")


func test_changed_signal_fires_only_on_real_mutations() -> void:
	var item := _stackable()
	_bag.add(item, 1)
	assert_eq(_change_count, 1, "an add that changes the bag signals once")
	_bag.add(item, 0)
	assert_eq(_change_count, 1, "a zero add is a no-op and stays silent")
	_bag.add(item, -3)
	assert_eq(_change_count, 1, "a negative add is a no-op and stays silent")
	_bag.remove(STACK_ID, 1)
	assert_eq(_change_count, 2, "a remove that changes the bag signals once")
	_bag.remove(STACK_ID, 1)
	assert_eq(_change_count, 2, "removing from an empty bag is a no-op and stays silent")
	_bag.clear()
	assert_eq(_change_count, 2, "clearing an already empty bag is a no-op and stays silent")
	_bag.add(item, 1)
	assert_eq(_change_count, 3, "the next real add signals again")
	_bag.clear()
	assert_eq(_change_count, 4, "and a non-empty clear signals once")
