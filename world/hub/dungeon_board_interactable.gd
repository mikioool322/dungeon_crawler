class_name DungeonBoardInteractable
extends Interactable

## Hub furniture that opens the dungeon selection panel (ADR-012).
##
## It only announces the request: the panel reads `DungeonProgress` and the router owns
## the travel gate, so the board itself can never unlock or start anything.

signal board_requested()


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	board_requested.emit()
	return InteractionResult.ok("dungeon_board")
