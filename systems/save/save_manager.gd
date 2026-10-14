class_name SaveManager
extends RefCounted

## Owns the save file: path, atomic write and the load policy (ADR-010).
##
## Invariants:
## - Content-agnostic: it validates the *shape* of the JSON and the schema version,
##   never gameplay semantics (unknown ids, invalid worlds and loot filtering belong
##   to `GameSession.apply_snapshot`). `SaveSnapshot` owns the DTO itself.
## - Atomic write: `<path>.tmp` is written, flushed and closed first; the previous
##   file is moved to `<path>.bak`, `.tmp` is renamed onto `<path>` and `.bak` is
##   deleted. Any failure restores `.bak` and returns `IO_ERROR`; a partial file never
##   becomes the save and a successful save leaves no `.tmp`/`.bak` behind.
## - Load policy: missing -> `MISSING` (new game); unreadable/unparseable/wrong shape
##   -> best-effort quarantine to `<path>.corrupt` + `CORRUPT`; `version > CURRENT_VERSION`
##   -> `UNSUPPORTED_VERSION` with the file left untouched; `version < CURRENT_VERSION`
##   -> the `MIGRATIONS` chain, and a version with no migration path is quarantined like
##   unusable data (it cannot be read by this build either).
## - One slot per manager instance; `setup()` is the injection point for tests.

const DEFAULT_PATH: String = "user://save_slot0.json"

## Migration chain: `from_version -> Callable(Dictionary) -> Dictionary` (the next
## version's dictionary). Empty in Sprint 02; adding an entry for a new
## `SaveSnapshot.CURRENT_VERSION` plus a migration test is the extension point.
const MIGRATIONS: Dictionary = {}

const TMP_SUFFIX: String = ".tmp"
const BACKUP_SUFFIX: String = ".bak"
const QUARANTINE_SUFFIX: String = ".corrupt"

var _path: String = DEFAULT_PATH


## Selects the save file; an empty path keeps `DEFAULT_PATH`.
func setup(path: String = "") -> void:
	_path = DEFAULT_PATH if path == "" else path


## True when a save file exists at the configured path. Corrupt files count as
## existing until a load quarantines them.
func snapshot_exists() -> bool:
	return FileAccess.file_exists(_path)


## Writes `snapshot` atomically. Returns `OK` or `IO_ERROR`; the previous save is
## either replaced or restored, never left half-written.
func save(snapshot: SaveSnapshot) -> SaveResult:
	var result := SaveResult.new()
	if snapshot == null:
		result.message = "snapshot must not be null"
		return result

	var text := JSON.stringify(snapshot.to_dict(), "\t")
	if text.is_empty():
		result.message = "snapshot could not be serialised to JSON"
		return result

	var tmp_path := _path + TMP_SUFFIX
	var write_error := _write_text(tmp_path, text)
	if write_error != OK:
		_remove(tmp_path)
		result.message = "could not write %s (error %d)" % [tmp_path, write_error]
		return result

	# Step 2: move any previous save aside, so the old file can be restored if the
	# promotion below fails.
	var bak_path := _path + BACKUP_SUFFIX
	var had_previous := FileAccess.file_exists(_path)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(_path, bak_path)
		if backup_error != OK:
			_remove(tmp_path)
			result.message = "could not move the previous save to %s (error %d)" % [
				bak_path, backup_error
			]
			return result

	# Step 3: promote the fully written temporary file.
	var promote_error := DirAccess.rename_absolute(tmp_path, _path)
	if promote_error != OK:
		_remove(tmp_path)
		if had_previous:
			DirAccess.rename_absolute(bak_path, _path)
		result.message = "could not replace %s (error %d)" % [_path, promote_error]
		return result

	# Step 4: drop the backup; the new save is already in place. Unconditional, so a
	# stale `.bak` left by a crash mid-save cannot survive a successful save.
	_remove(bak_path)

	result.status = SaveResult.Status.OK
	result.snapshot = snapshot
	result.message = "saved %s" % _path
	return result


## Reads the save file and applies the ADR-010 policy. Never throws: every failure
## is a `SaveResult` with a diagnostic.
func load_snapshot() -> SaveResult:
	var result := SaveResult.new()

	if not FileAccess.file_exists(_path):
		result.status = SaveResult.Status.MISSING
		result.message = "no save file at %s" % _path
		return result

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _corrupt_result("unreadable (error %d)" % FileAccess.get_open_error())
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return _corrupt_result("the file is empty")

	var json := JSON.new()
	if json.parse(text) != OK:
		return _corrupt_result(
			"invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
	if not json.data is Dictionary:
		return _corrupt_result("the root is not a JSON object")

	var data: Dictionary = json.data
	var raw_version: Variant = SaveSnapshot.version_of(data)
	if raw_version == null:
		return _corrupt_result("the version field is missing or is not an integer")
	var version: int = raw_version

	# Gate before anything else touches the data: a newer save must survive intact.
	if version > SaveSnapshot.CURRENT_VERSION:
		result.status = SaveResult.Status.UNSUPPORTED_VERSION
		result.message = "save version %d is newer than the supported %d; %s was not modified" % [
			version, SaveSnapshot.CURRENT_VERSION, _path
		]
		return result

	if version < SaveSnapshot.CURRENT_VERSION:
		var migrated: Variant = _migrate(data, version)
		if migrated == null:
			return _corrupt_result(
				"no migration path from version %d to %d" % [
					version, SaveSnapshot.CURRENT_VERSION
				]
			)
		data = migrated

	var snapshot := SaveSnapshot.from_dict(data)
	if snapshot == null:
		return _unusable_shape_result()

	result.status = SaveResult.Status.OK
	result.snapshot = snapshot
	result.message = "loaded %s (version %d)" % [_path, version]
	return result


# --- migration ----------------------------------------------------------------

## Runs one migration step per version. Returns null when a step is missing or does
## not return a dictionary, so the caller reports "no migration path".
func _migrate(data: Dictionary, from_version: int) -> Variant:
	var migrated: Dictionary = data.duplicate(true)
	var version := from_version
	while version < SaveSnapshot.CURRENT_VERSION:
		if not MIGRATIONS.has(version):
			return null
		var step: Variant = MIGRATIONS[version]
		if not step is Callable:
			return null
		var stepped: Variant = step.call(migrated)
		if not stepped is Dictionary:
			return null
		migrated = stepped
		version += 1
	return migrated


# --- file helpers -------------------------------------------------------------

## Builds the failure result for unusable data, quarantining the file best-effort so
## the boot can continue with a new game instead of reading the same file again.
func _corrupt_result(reason: String) -> SaveResult:
	var result := SaveResult.new()
	result.status = SaveResult.Status.CORRUPT
	var quarantine_path := _path + QUARANTINE_SUFFIX
	if _quarantine(quarantine_path):
		result.message = "corrupt save at %s (%s); quarantined to %s" % [
			_path, reason, quarantine_path
		]
	else:
		result.message = "corrupt save at %s (%s); quarantine failed" % [_path, reason]
	return result


func _unusable_shape_result() -> SaveResult:
	return _corrupt_result("the save data has an unusable shape")


## Moves the unusable file out of the way; returns false when that was not possible.
func _quarantine(quarantine_path: String) -> bool:
	# Keep the most recent corrupt file: on Windows a rename onto an existing path
	# fails, which would silently disable quarantine for every later corruption.
	_remove(quarantine_path)
	return DirAccess.rename_absolute(_path, quarantine_path) == OK


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error


func _remove(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var remove_error := DirAccess.remove_absolute(path)
	if remove_error != OK:
		push_warning("SaveManager: could not remove %s (error %d)" % [path, remove_error])
