class_name ContentManifest
extends Resource

## Explicit, editor-authored list of every content definition the game ships (ADR-011).
##
## Invariants:
## - It is data, not logic: `ContentRegistry.build()` validates it and reports every
##   authoring problem as `errors`; nothing here scans folders or deduplicates.
## - Content is referenced by stable ids; an entry that is not listed here is not
##   resolvable at runtime.
## - Every bucket is typed to its concrete definition class, so a wrong-kind entry
##   cannot even be stored; `ContentRegistry` re-checks the kind as defence in depth.
## - `tools/generate_content_manifest.gd` is the source of truth for this resource:
##   add content there and re-run it instead of hand-editing the `.tres`.

## Attack definitions, indexed by `AttackDefinition.id`.
@export var attacks: Array[AttackDefinition] = []

## Enemy archetypes, indexed by `EnemyDefinition.id`.
@export var enemies: Array[EnemyDefinition] = []

## Items, indexed by `ItemDefinition.id`.
@export var items: Array[ItemDefinition] = []

## Loot rewards, indexed by `RewardDefinition.id`.
@export var rewards: Array[RewardDefinition] = []

## Worlds, indexed by `WorldDefinition.id`.
@export var worlds: Array[WorldDefinition] = []

## Dungeons, indexed by `DungeonDefinition.dungeon_id` (ADR-012).
@export var dungeons: Array[DungeonDefinition] = []
