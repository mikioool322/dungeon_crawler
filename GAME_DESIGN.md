# Game design — current assumptions

## Confirmed vision
- Single-player semi-realistic, medium-poly dark fantasy FPS ARPG.
- Visible first-person weapon.
- One town/hub as home base; departure to isolated dungeons/instances.
- Combat, treasure, puzzles, enemies and progression.
- Starting combat: one melee swing and avoiding an enemy attack by physically moving outside its range. No special dodge ability.
- Art pipeline comes later; initial gameplay uses placeholder meshes.
- Future optional gallery / mature-content rewards are high-resolution pixel-art media, not real-time 3D gameplay animation.

## Repeatable dungeons (confirmed — ADR-012)

Dungeons are replayable content with durable story progress; the two lifetimes are separate.

1. The player starts with access to the first dungeon.
2. Completing a dungeon for the first time is a story event.
3. A first clear unlocks the next dungeon according to the progression configuration.
4. Once unlocked, a dungeon stays available.
5. A dungeon can be entered and completed repeatedly.
6. Starting a new run resets ordinary enemies, bosses and ordinary loot for that run.
7. Repeating a dungeon re-earns ordinary rewards, XP and gold.
8. One-time story rewards can never be granted a second time.
9. First-clear story events must not fire again on a repeat.
10. Persistent story progress is saved independently of the transient run state.

Intended split (shipped in Sprint 03):
`DungeonDefinition` (static content: id, scene, prerequisites, first-clear unlocks, repeatable flag,
reward references), `DungeonProgress` (persistent: completed and unlocked ids, first-clear claims,
story progress) and `DungeonRunState` (transient per run: current dungeon, enemy state, chests opened,
loot collected — never saved). Details and the cooperation with `GameSession`, `SaveManager`,
`ContentRegistry`, `WorldRouter` and `LootService` are recorded in ADR-012.

## Character stats, equipment, NPC and trading (confirmed — ADR-015/016/017, Sprint 04)

1. The player has four base stats: max health, attack damage, defense and movement speed.
2. Base values live in one `PlayerDefinition` resource; equipment contributes additive modifiers only.
3. Effective values are computed in one place (`CharacterStats`), never saved, and never accumulated
   twice by equipping the same item again.
4. Two equipment slots ship now: `MAIN_HAND` and `CHEST_ARMOR`. More slots are a data plus enum change.
5. An equipped item is not in the bag (ownership semantics A): equipping moves a copy out, unequipping
   returns it, swapping returns the previous one in the same operation.
6. A weapon owns its reach and timing profile; the stats own the damage number.
7. Damage received is mitigated by the target's defense with one deterministic formula; defense never
   makes an actor immune.
8. A changing maximum HP never heals: the ceiling moves and the current HP is clamped.
9. The hub has one merchant NPC. Talking to it opens a dialogue; the dialogue opens the shop.
10. One price rule for the whole game: buy price is the item's base value, sell price is half of it
    (at least one gold). Selling is never profitable, so no gold loop exists.
11. Buying and selling are atomic: either both sides change or nothing does.
12. Merchant stock is unlimited and transient in Sprint 04; it is never saved.
13. Equipment, gold and dungeon progress survive a restart; the shrine remains the only save point.

Out of scope in this increment: critical hits, resistances, status effects, buffs, talent trees,
crafting, random affixes, durability, multi-currency economy, NPC reputation, dialogue trees, quests,
dynamic shop stock.

## First playable vertical slice
Greybox hub, greybox dungeon, door transition, player movement and camera, placeholder weapon swing, telegraphed enemy attack, actual range dodge, one enemy with HP/death, simple reward, save/load round trip.

## Not decided yet
Specific engine patch version, platform targets, player progression formula (XP curve, levels, rewards), mature rating/distribution, exact enemy roster, animation pipeline, rendering budget and procedural dungeon generation. Dungeon *repeatability* and *story-progress persistence* are decided (ADR-012); how a dungeon layout is produced (authored vs generated) is not. Agents must not treat the open items as decided.

## Non-goals for first increment
Multiplayer, open-world travel, procedural story, complex skill trees, full-body multiplayer rigs, 3D cinematic intimacy, network services, production asset generation.
