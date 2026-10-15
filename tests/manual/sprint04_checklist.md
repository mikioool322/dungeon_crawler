# Sprint 04 manual / graphical checklist

Scope: RPG foundations — character stats, equipment, NPC dialogue and trading, save v3.
Everything below is a **human, graphical** check: none of it can be proven by the headless suite,
so every item is `NOT RUN` until a person with a window performs it. Never mark an item `PASS`
from headless evidence (AGENTS.md).

How to run: launch the project (`godot --path .` from a graphical session), the shrine in the hub
is the only save point, `TAB` opens the character panel, `E` interacts, `ESC` closes a panel.

## Sprint 04 items

| ID | Check | Expected | Status |
|----|-------|----------|--------|
| M1 | Press `TAB` in the hub | The character panel opens; the cursor is released; the player stops moving and cannot attack or interact | NOT RUN |
| M2 | Read the stats section | HP / Max HP, Attack, Defense, Movement Speed with the base value; the bonus column appears once something is equipped | NOT RUN |
| M3 | Read the inventory list | Item name, count, type and the equip button only for equippable items; empty bag shows an empty-state message | NOT RUN |
| M4 | Equip the story dagger or the bought sword | The row leaves the bag, the `Main Hand` slot fills, the Attack number rises by exactly the item's bonus | NOT RUN |
| M5 | Unequip | The item returns to the bag and the Attack number drops back to the base value | NOT RUN |
| M6 | Equip the leather vest | The `Chest Armor` slot fills and Defense rises | NOT RUN |
| M7 | Close with `TAB` and with `ESC` | The panel hides, the cursor is captured again, movement/attack/interaction work immediately | NOT RUN |
| M8 | Walk to the smith in the hub and press `E` | A dialogue panel shows the NPC's name and greeting, with a `Shop` button and a `Close` button | NOT RUN |
| M9 | Press `Shop` | The shop panel opens with the merchant's stock, the buy price, the owned count and a sell list of bagged items | NOT RUN |
| M10 | Buy the iron sword with enough gold | Gold drops by exactly the buy price, the sword appears in the inventory list | NOT RUN |
| M11 | Try to buy with too little gold | The button/action is refused and a status message explains why; gold and bag are unchanged | NOT RUN |
| M12 | Sell a loot item | The row leaves the bag and gold rises by exactly the sell price | NOT RUN |
| M13 | Equip the bought sword and watch the viewmodel | The placeholder weapon's appearance changes (tint/visibility) and combat timing feels unchanged | NOT RUN |
| M14 | Attack a dungeon enemy with and without the weapon | The damage difference is noticeable; a swing started before the swap keeps its own range/damage | NOT RUN |
| M15 | Wear the vest and take a hit | Incoming damage is visibly reduced (never zero) | NOT RUN |
| M16 | Save at the shrine, quit, relaunch | Equipment, gold, HP, inventory and dungeon progress all come back; the stats show the same numbers | NOT RUN |
| M17 | Open the panel during a dungeon run | Nothing crashes; closing it restores control; the dungeon objective enemy is still killable | NOT RUN |
| M18 | Readability pass | No panel hides the HUD health/gold labels permanently, no text is unreadable at the default window size | NOT RUN |

## Carried over from Sprints 01-03 (still unverified graphically)

| ID | Check | Status |
|----|-------|--------|
| H1 | First-person movement, mouse look, attack feel, enemy telegraph, evade by walking backwards out of reach | NOT RUN |
| H2 | Hub -> dungeon 01 travel, return portal, run reset on re-entry | NOT RUN |
| H3 | Hub board: rows, locked/unlocked buttons, panel focus | NOT RUN |
| H4 | Death in a dungeon respawns in the hub with progress kept | NOT RUN |
| H5 | Chest and drop pickup prompts and their loot messages | NOT RUN |

## Acceptance criteria map (automated evidence)

| AC | Claim | Evidence |
|----|-------|----------|
| AC-35 | Effective stats: additive buckets per source, replace semantics, clamps, change signal, invalid definition refused | `tests/unit/stats/test_character_stats.gd` |
| AC-36 | Equipment ownership A: equip/swap/unequip, refusal codes, bag-vs-slot invariant, tolerant save mapping | `tests/unit/equipment/test_equipment_state.gd` |
| AC-37 | `ItemDefinition` extensions validate without breaking the frozen "fresh item = 3 errors" contract | `tests/unit/content/test_definitions.gd`, `tests/integration/test_sprint04_content.gd` |
| AC-38 | Combat damage comes from the stats for a stats owner and from the profile for an enemy; a swing pins its profile and damage | `tests/integration/test_stats_combat.gd` |
| AC-39 | Defense mitigation: identity at zero, monotonic, never zero for a positive hit | `tests/integration/test_stats_combat.gd` |
| AC-40 | Max-HP changes clamp without healing and without a `died` report | `tests/integration/test_stats_combat.gd` |
| AC-41 | Movement speed follows the effective stat; the shipped scene value is the default | `tests/integration/test_stats_combat.gd`, `tests/integration/test_player_movement.gd` |
| AC-42 | Trading: one price rule, atomic refusals, no duplication, gold never negative | `tests/unit/trade/test_trading_service.gd` |
| AC-43 | Shipped content graph: player, weapons, armour, sellable loot, merchant, hub NPC, cross-references | `tests/integration/test_sprint04_content.gd` |
| AC-44 | Save v3: equipment round trip, v2->v3, v1->v2->v3, malformed sections, future version refused, corrupt quarantine | `tests/unit/save/test_save_v3_equipment.gd`, `tests/integration/test_save_round_trip.gd` |
| AC-45 | The owner's loop end to end on the real bootstrap scene | `tests/integration/test_sprint04_loop.gd` |
| AC-46 | Panels: rows, explicit operations, refusals, one screen owner, input restore | `tests/integration/test_inventory_panel.gd`, `tests/integration/test_shop_panel.gd` |
| AC-47 | No regression in Sprints 01-03 and no runtime errors or leaks | the full suite + boot smoke |

## Mutation checks

Each mutation is applied by hand, the suite is run, the failing tests are recorded, and the mutation
is reverted before anything is committed. A mutation that nothing catches is a coverage gap. The
runs below are executed by the **independent QA pass**; the "caught by" column is filled from that
run's report, not from the authors' expectation.

| # | Mutation | Caught by (QA evidence) | Reverted |
|---|----------|------------------------|----------|
| 1 | `CharacterStats.set_modifiers` accumulates instead of replacing | pending independent QA report | pending |
| 2 | `EquipmentState.equip` fills the slot without taking the copy out of the bag | pending independent QA report | pending |
| 3 | `AttackController.request_attack` does not pin the damage | pending independent QA report | pending |
| 4 | `TradingService.buy` trusts the caller instead of re-validating | pending independent QA report | pending |
| 5 | `SaveManager._migrate_v2_to_v3` invents a starting weapon | pending independent QA report | pending |
| 6 | `HealthComponent.set_max_health` heals to the new maximum | pending independent QA report | pending |

## Findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | `reset_to_new_game()` replaced the equipment record with an unwired instance, so a first-run player could not equip anything | HIGH | fixed in `6cdfb0e` (`GameSession._wire_equipment()` on setup/new game/load, re-binding the trade service too) |
| 2 | The trade service kept a stale equipment reference after a load, so its defensive "equipped" check could inspect the wrong record | MEDIUM | fixed in `f5021b6` |
| 3 | The live rig did not receive an equipment change (the weapon profile only applied at spawn) | HIGH | fixed in `6cdfb0e` (`WorldRouter._connect_player_loadout`) |
| 4 | Two new HUD tests simulated input without flushing the buffer, so the second toggle could be missed | LOW | fixed in `cc610ad` (`Input.flush_buffered_events()` after every simulated action) |
| 5 | The end-to-end loop left the dialogue panel open, which correctly blocked the player's attack input | LOW | fixed in `cc610ad` (the loop closes the panel through the real `ui_cancel` handler) |
| 6 | `ItemDefinition.validation_errors()` gained rules; the frozen "fresh item = exactly 3 errors" test still passes because no new rule fires for default values | INFO | no action needed, covered by the existing test |
