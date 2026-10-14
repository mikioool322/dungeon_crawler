class_name SaveResult
extends RefCounted

## Outcome of one `SaveManager.save()` / `SaveManager.load_snapshot()` call (ADR-010).
##
## A result is data, never an exception: callers branch on `status` and surface
## `message` / `warnings` instead of crashing. `snapshot` is non-null only for `OK`,
## so a caller that ignores `status` cannot mistake a failure for an empty save.
##
## `MISSING` is a normal boot case (a new game), not an error.

enum Status { OK, MISSING, CORRUPT, UNSUPPORTED_VERSION, IO_ERROR }

## What happened. Defaults to the only status a caller must always handle.
var status: Status = Status.IO_ERROR

## Human-readable diagnostic; always set, never a machine-readable code.
var message: String = ""

## Non-fatal notes (for example content dropped by a later semantic pass).
var warnings: PackedStringArray = PackedStringArray()

## Loaded snapshot; null unless `status == OK`.
var snapshot: SaveSnapshot = null


## True when the operation succeeded and `snapshot` is usable.
func ok() -> bool:
	return status == Status.OK


func _to_string() -> String:
	return "SaveResult(%s, '%s')" % [Status.keys()[status], message]
