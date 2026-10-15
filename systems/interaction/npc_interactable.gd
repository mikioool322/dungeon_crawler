class_name NpcInteractable
extends Interactable

## A talkable NPC (ADR-017). It announces the dialogue and nothing else: it never reads
## gold, the bag, the save, the player controller or combat. The world host re-emits the
## request and the HUD decides what to show (dialogue, and a shop button when the NPC has
## a merchant).

signal dialogue_requested(npc: NpcDefinition)

## The NPC this node speaks for; null makes the interactable inert.
@export var npc: NpcDefinition = null


func can_interact() -> bool:
	return super.can_interact() and npc != null


func _perform_interact(_interactor: Node3D) -> InteractionResult:
	if npc == null:
		return InteractionResult.rejected(&"no_npc", "Nobody is here.")
	dialogue_requested.emit(npc)
	return InteractionResult.ok()
