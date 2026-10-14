class_name ContentManifest
extends Resource

## Explicit, editor-authored list of every content definition the game ships (ADR-011).
##
## Invariants:
## - It is data, not logic: `ContentRegistry.build()` validates it and reports every
##   authoring problem as `errors`; nothing here scans folders or deduplicates.
## - Content is referenced by stable ids; an entry that is not listed here is not
##   resolvable at runtime.
## - Sprint 02 dependency note (W1b): `ItemDefinition`, `RewardDefinition` and
##   `WorldDefinition` are W1a deliverables and are not part of this branch yet, so
##   their arrays are typed `Array[Resource]` and validated by member surface at
##   runtime. Retype them to the concrete classes when W1a is merged (one line each,
##   no call-site impact) and re-save the `.tres` so the stored array types match.

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
