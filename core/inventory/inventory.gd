class_name Inventory
extends RefCounted

## Counted item bag with stack awareness (ADR-009).
##
## Invariants:
## - One dictionary per stack, kept in insertion order: `{"id": StringName, "count": int}`.
##   `entries()` hands out copies (`{"id": String, "count": int}`), so a caller can
##   never alias or mutate the internal bag.
## - `add()` tops up existing stacks up to `definition.max_stack` before appending new
##   ones, so a non-stackable item (`max_stack == 1`) always occupies its own entry.
## - `remove()` drains the newest stacks first: the oldest, fullest stacks survive a
##   partial removal, and an empty stack is dropped from the bag.
## - Only definitions that pass `ItemDefinition.is_valid()` are accepted. Invalid input
##   (null, empty id, non-positive count) returns 0 and mutates nothing.
## - No slot cap in Sprint 02 (deliberately deferred).
## - `changed` fires once per mutation that actually changed the bag; no-ops stay silent
##   so listeners never re-render for a rejected add.
## - Never references a Node; safe to hold in the serialisable `PlayerSessionState`.

signal changed()

var _stacks: Array[Dictionary] = []


## Adds up to `count` copies of `definition` and returns the amount actually added.
##
## Returns 0 when the definition is null/invalid or `count <= 0`; the bag is then
## untouched and `changed` is not emitted.
func add(definition: ItemDefinition, count: int = 1) -> int:
	if definition == null or count <= 0 or not definition.is_valid():
		return 0
	var max_stack: int = definition.max_stack
	var remaining: int = count
	for stack in _stacks:
		if remaining <= 0:
			break
		if (stack["id"] as StringName) != definition.id:
			continue
		var room: int = max_stack - int(stack["count"])
		if room <= 0:
			continue
		var moved: int = mini(room, remaining)
		stack["count"] = int(stack["count"]) + moved
		remaining -= moved
	while remaining > 0:
		var take: int = mini(max_stack, remaining)
		_stacks.append({"id": definition.id, "count": take})
		remaining -= take
	var added: int = count - remaining
	if added > 0:
		changed.emit()
	return added


## Removes up to `count` copies of `item_id` and returns the amount actually removed.
##
## Drains the newest stacks first; a call larger than what is held removes everything
## and returns the held amount. Returns 0 (no mutation) for an empty id or `count <= 0`.
func remove(item_id: StringName, count: int) -> int:
	if item_id == &"" or count <= 0:
		return 0
	var remaining: int = count
	var index: int = _stacks.size() - 1
	while index >= 0 and remaining > 0:
		var stack: Dictionary = _stacks[index]
		if (stack["id"] as StringName) == item_id:
			var taken: int = mini(int(stack["count"]), remaining)
			stack["count"] = int(stack["count"]) - taken
			remaining -= taken
			if int(stack["count"]) <= 0:
				_stacks.remove_at(index)
		index -= 1
	var removed: int = count - remaining
	if removed > 0:
		changed.emit()
	return removed


## Total copies of `item_id` across all its stacks.
func count_of(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	var total: int = 0
	for stack in _stacks:
		if (stack["id"] as StringName) == item_id:
			total += int(stack["count"])
	return total


## Number of stack entries holding `item_id`.
func stack_count(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	var count: int = 0
	for stack in _stacks:
		if (stack["id"] as StringName) == item_id:
			count += 1
	return count


## Sorted, unique item ids currently held.
func ids() -> PackedStringArray:
	var unique: Dictionary = {}
	for stack in _stacks:
		unique[stack["id"]] = true
	var result: PackedStringArray = PackedStringArray()
	for key in unique.keys():
		result.append(String(key))
	result.sort()
	return result


## One dictionary per stack, in insertion order: `[{"id": String, "count": int}]`.
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stack in _stacks:
		result.append({"id": String(stack["id"]), "count": int(stack["count"])})
	return result


## Total number of items across every stack.
func total_item_count() -> int:
	var total: int = 0
	for stack in _stacks:
		total += int(stack["count"])
	return total


func is_empty() -> bool:
	return _stacks.is_empty()


## Empties the bag; a no-op (and no signal) when it is already empty.
func clear() -> void:
	if _stacks.is_empty():
		return
	_stacks.clear()
	changed.emit()


func _to_string() -> String:
	return "Inventory(%d stack(s), %d item(s))" % [_stacks.size(), total_item_count()]
