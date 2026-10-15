# Architecture — living contract

## Technology
- Godot 4.x, GDScript, single-player, first-person.
- Modular monolith in a single Godot project; no network backend at this stage.
- Begin with greybox assets and small, playable end-to-end slices.

## Layers and dependency direction
1. **Domain rules:** attack definitions, damage rules, inventory semantics, persistent IDs. No dependency on UI, VFX, or specific scenes.
2. **Gameplay components:** health, attack execution, hit detection, interaction, AI state transitions. Read domain data; expose small contracts.
3. **World orchestration:** encounters, hub↔dungeon transition, loot distribution, progression, save coordination.
4. **Presentation:** viewmodel rigs, animation, audio, UI, gallery/media; reacts to state/events, never owns authoritative gameplay state.
5. **Content definitions:** Godot Resources with stable IDs; imports and AI assets mapped into PackedScenes and Resources.

Allowed dependencies generally point downward. Direct references for local, synchronous behavior. Local signals for component events. Global event bus only for facts consumed across multiple features; document every global event schema. No circular ownership.

## Actor composition
`CharacterBody3D` host (player/enemy), `HealthComponent`, `AttackController`, `HitDetector`, and independent movement/control logic. Player input and enemy decisions feed intentions to components. AI does not modify player health directly.

## Combat MVP contract
Attack definition: id, damage, reach, windup, active window, recovery, cooldown. On active frame query collision/contact; resolve valid targets, distance and occlusion; apply damage once per target per swing. Target stepping out of reach before hit => MISS. No dodge action, iframes, parry, stagger or magic in MVP. Keep animation cues swappable.

## Game flow
Hub and dungeon separate PackedScenes managed by one transition coordinator. Use explicit spawn IDs. On return, persist durable player progression and rewards, not transient scene nodes. Failure/retry rules and data ownership must be documented before adding procedural generation.

## Persistence
Versioned plain DTOs; stable IDs for item and unlock references. Save atomically via temporary file/rename where supported; handle errors, corrupted saves and unknown IDs with safe fallbacks. Provide migration tests when schema evolves. Runtime Nodes never serialized.

## Extensibility seams (contract only until needed)
- AttackDefinition as `Resource`; later attack effects as composable data/handlers.
- EnemyDefinition `Resource` referencing visuals, brain configuration, drop table and unique ID.
- World/RoomDefinition for authored layouts; generator can be added without rewriting combat.
- Repeatable dungeons (ADR-012): `DungeonDefinition` (content) + `DungeonProgress` (persistent,
  owned by `GameSession`) + `DungeonRunState` (transient, never saved). Shipped in Sprint 03;
  the save format carries a `dungeon_progress` section (version 2).
- Character stats and equipment (ADR-015/ADR-016): `PlayerDefinition` (content) owns the base
  stats, `ItemDefinition` owns each item's own numbers, `CharacterStats` computes the effective
  values from one additive bucket per source, and `EquipmentState` (ownership A: an equipped item
  leaves the bag) is the durable record. Effective stats are never saved; they are recomputed.
  A future stat or slot is a data plus enum change; buffs only need another `set_modifiers()` caller.
- NPC and trading (ADR-017): `NpcDefinition` + `NpcInteractable` announce a dialogue and know
  nothing about the player, the bag, gold or the save; `TradingService` is the only trade writer
  and the only place with a price rule; merchant stock is transient and never saved.
- RewardCatalog maps event/reward IDs to gallery media; no direct gallery calls from enemies.
- Asset import adapter maps .glb/.png/.webp/.spritesheet to imported scenes/content definitions.

## Folder boundaries (suggested; create only when needed)
`core/` (content, session, dungeon, stats, equipment, inventory, combat, physics),
`actors/player/`, `actors/enemies/`, `systems/` (combat, ai, interaction, inventory, loot, save,
content, dungeon, trade), `world/hub/`, `world/dungeons/`, `content/`, `presentation/`, `assets/`,
`tests/`, `tools/`.

## Decision policy
When proposing a public API change, write: callers, migration strategy, save compatibility, tests, alternatives. Record agreed decisions in `docs/DECISIONS.md`. Do not fill future subsystem folders with empty stubs.
