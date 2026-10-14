class_name PhysicsLayers
extends RefCounted

## Single source of truth for physics layer bit values (ADR-005).
##
## Layer names are also registered in `project.godot` (layer_names) so the
## editor shows readable names. Scripts must never use raw layer ints; they use
## these constants so that a layer change is a one-line edit that the compiler
## and code review can trace.

## Static world geometry (floors, walls, pillars). Blocks movement and hits.
const WORLD: int = 1 << 0  # layer 1

## Player character body (CharacterBody3D).
const PLAYER_BODY: int = 1 << 1  # layer 2

## Enemy character bodies (CharacterBody3D).
const ENEMY_BODY: int = 1 << 2  # layer 3

## Reserved for per-actor damage receivers. Unused in Sprint 01 (ADR-005).
const HURTBOX: int = 1 << 3  # layer 4


## Layers a body should collide with (movement collision, not hit queries).
static func movement_mask(body_layer: int) -> int:
	match body_layer:
		PLAYER_BODY:
			return WORLD | ENEMY_BODY
		ENEMY_BODY:
			return WORLD | PLAYER_BODY
		_:
			return WORLD
