class_name SaveShrineInteractable
extends Interactable

## Hub furniture that persists the run (ADR-010): saving is an in-world interaction,
## not a keybind. It knows nothing about the router, the session or the save format;
## the world host injects a save callable that returns a `SaveResult`.

var _save_provider: Callable = Callable()


## Injected by `WorldHost._bind_interactables()`.
func set_save_provider(save_callable: Callable) -> void:
	_save_provider = save_callable


func has_save_provider() -> bool:
	return _save_provider.is_valid()


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	if not _save_provider.is_valid():
		return InteractionResult.rejected(&"no_save_provider", "Saving is unavailable here.")
	var result: Variant = _save_provider.call()
	if not (result is SaveResult):
		return InteractionResult.rejected(&"save_failed", "Saving failed.")
	var save_result := result as SaveResult
	if save_result.ok():
		var warnings := ""
		if not save_result.warnings.is_empty():
			warnings = " (%d warning(s))" % save_result.warnings.size()
		return InteractionResult.ok("Progress saved%s" % warnings)
	return InteractionResult.rejected(&"save_failed", "Save failed: %s" % save_result.message)
