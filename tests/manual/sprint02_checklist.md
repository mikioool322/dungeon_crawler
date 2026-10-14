# Sprint 02 — manual (graphical) acceptance checklist

Scope: the Sprint 02 definition of done (hub → portal → dungeon → fight → loot →
return → save → relaunch → restore) plus the automated coverage map for
AC-20..AC-34. Run on the reference machine with the pinned engine (ADR-002):

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

"%GODOT%" --path .            # opens the project's main scene: res://world/main.tscn
```

Controls: WASD move, mouse look, left click attack, `E` interact (portal / pickup /
chest / shrine), `Esc` releases the mouse (a click re-captures it). There is no jump,
no dash and no block; evasion is walking backwards out of reach. Saving happens only
at the hub shrine; loading happens only at boot.

The real save slot is `%APPDATA%\Godot\app_userdata\Dark Fantasy ARPG\save_slot0.json`
(`user://save_slot0.json`). To repeat "first launch" behaviour, quit the game and
delete that file (plus any `.tmp`/`.bak`/`.corrupt` next to it).

## Verification status of this document

**Every M item below is NOT RUN.** W5 was executed in a headless environment; no
graphical session, screenshot or human play-through was performed, so no manual item
may be marked PASS. Where a headless test proves the *rule* behind an item, it is
named in the "automated equivalent" column — that is evidence about logic and physics,
**not** about feel, readability, HUD layout or frame pacing.

Column to fill in during a real session: `Status` (`PASS` / `FAIL` / `BLOCKED` /
`NOT RUN`), with date, engine build and a one-line note. A FAIL needs the observable
symptom, the expected behaviour and the run state (HP, gold, items, location from the
HUD).

| # | What to do | What to look for | Status | Automated equivalent (headless, rule-level only) |
|---|------------|------------------|--------|--------------------------------------------------|
| M1 | Launch the game with no save file present. Watch the first frame. | The hub greybox loads; the HUD reads `HP: 100 / 100`, `Gold: 0`, `Items: (empty)`, `Location: world.hub @ spawn.hub.start`, status `New game (no save found)`; the camera starts at the south start marker looking into the hall; the Output panel has no red lines. | NOT RUN | `tests/integration/test_sprint02_loop.gd::test_fresh_boot_starts_in_the_hub_with_one_rig_and_the_hub_hud`, `test_main_boot.gd::test_boot_loads_the_hub_with_one_player_at_the_start_marker`, `::test_boot_binds_the_hud_to_the_live_rig` (state and label text, not the rendered image) |
| M2 | Walk to the blue portal on the north wall. Look at it from ~2 m, then look away and step back. | The prompt `[E] Enter` appears only while the portal is the thing being looked at and inside ~2.5 m; it disappears when looking at the wall, another interactable or when stepping out of reach; walking into the portal body does not travel by itself. | NOT RUN | `tests/integration/test_interaction_ray.gd` (focus/prompt/occlusion/reach rules); the loop test drives the same ray at the real hub portal |
| M3 | Press `E` at the hub portal. | The swap to the dungeon is immediate: the player stands at `spawn.dungeon.entry` on the south side facing the hall; HUD `Location: world.dungeon.proto01 @ spawn.dungeon.entry`; HP/gold/items unchanged; no black frame, no stacked geometry, no double player. | NOT RUN | `test_sprint02_loop.gd::test_full_loop_hub_to_dungeon_loot_return_save_and_reload` (steps 1-2), `test_main_boot.gd::test_hud_survives_a_world_swap_without_duplicating_actors`; transition *smoothness* is not judged |
| M4 | Walk up to the grunt. Let it telegraph one swing, backpedal out of reach until the swing ends, then kill it with three left clicks. | The warm-orange windup is readable while moving; backpedalling makes the swing miss (no HP loss, the grunt still completes it); each hit flashes the grunt; enemy HP goes 100 → 66 → 32 → 0; the body turns grey and never attacks again; the HUD HP drops only when a swing actually lands. | NOT RUN | `tests/integration/test_encounter.gd` (rig-level evade/kill), `test_sprint02_loop.gd` (real 3-swing kill in the real dungeon); telegraph readability and hit feedback need eyes |
| M5 | Walk over the golden drop the grunt leaves and press `E`. | The prompt `[E] Pick up` appears; the drop disappears on the press; HUD `Gold: 3`; status `Collected: 3 gold (gold 3)`; pressing `E` again where it stood does nothing and never pays twice. | NOT RUN | `test_sprint02_loop.gd` (exactly one drop, one grant, consumed, second interact refused), `tests/unit/loot/test_loot_service.gd` |
| M6 | Walk to the chest in the north-west corner and press `E`. | The prompt `[E] Open`; the chest stays in the world but reads as opened; `Items: Minor Salve x1`; `Gold: 8`; a second press does nothing. | NOT RUN | `test_sprint02_loop.gd` (one-shot chest, +1 salve, +5 gold, stays in the world), `test_interaction_ray.gd::test_a_chest_stays_in_the_world_and_a_claimed_key_never_grants_twice` |
| M7 | Walk back through the dungeon portal on the south wall and press `E`. | Back in the hub at the portal-arrival spot (`Location: world.hub @ spawn.hub.dungeon_portal`); HP, gold and items identical to the moment before the press; one player, no leftover dungeon geometry. | NOT RUN | `test_sprint02_loop.gd` (step 8: exact HP/gold/item equality across the travel, one world, one rig) |
| M8 | Walk to the glowing shrine and press `E`. | The prompt `[E] Save progress`; status `Progress saved`; the file `save_slot0.json` appears in the user data folder and no `.tmp`/`.bak` is left beside it. | NOT RUN | `test_sprint02_loop.gd` (shrine interaction, `SaveResult` OK via a fresh load, no `.tmp`/`.bak`), `tests/integration/test_save_round_trip.gd` |
| M9 | Quit the game, relaunch, then re-enter the dungeon and kill the grunt again. | Boot status `Save loaded`; HP/gold/items/location exactly as saved; the grunt's drop does not reappear (the reward key is claimed) and it cannot be collected twice; the chest cannot be re-opened for a second reward. | NOT RUN | `test_sprint02_loop.gd` (steps 10-11: second `Main` restores the state, re-kill spawns no drop and grants nothing), `test_save_round_trip.gd` (round trip and edges) |
| M10 | Let the grunt kill the player in the dungeon (stand still, no evasion). | Death is immediate; the run respawns in the hub at `spawn.hub.start` with full HP; gold, items and claimed keys are kept; exactly one player exists; no death screen, no corpse left behind, no stuck input. | NOT RUN | `tests/integration/test_death_respawn.gd` (lethal damage, respawn location, full HP, progress kept, dead rig freed) |
| M11 | Play the loop for ~2 minutes (fight, die, re-enter, save) and watch the Output panel and frame pacing. | No red errors or script errors at any point; no stutter on the first swap or the first enemy encounter; the frame rate stays steady while the telegraph, the drop and the HUD are all on screen. | NOT RUN | `"%GODOT%" --headless --path . --quit-after 300` (exit 0, no error lines) and the full suite (337 tests, 0 failing, no `SCRIPT ERROR`/ObjectDB leak lines). A headless run cannot reproduce graphical-driver, rendering or pacing problems. |

## Automated coverage map (AC-20..AC-34)

Status is what the W5 run actually observed on this machine (2026-10-14, Godot
4.7.2-stable, `--headless`). "NOT RUN" means no evidence exists yet and must not be
reported as PASS. The graphical half of AC-34 is M11.

| AC | Criterion (short) | Status | Artefact |
|----|-------------------|--------|----------|
| AC-20 | Layer 5 + `interact` in `project.godot`, `PhysicsLayers` and the lock tests | PASS | `tests/unit/test_project_contract.gd`, `tests/integration/test_project_scripts.gd` (in the 337-test run); `--editor --quit` exit 0 |
| AC-21 | Inventory add/remove/count, stacking to `max_stack`, non-stackables, invalid rejection | PASS | `tests/unit/inventory/test_inventory.gd`; the loop test observes the real 1-salve stack |
| AC-22 | Loot: one grant per key, duplicate → `duplicate`, invalid/unknown refused, key survives a snapshot | PASS | `tests/unit/loot/test_loot_service.gd`; `test_sprint02_loop.gd` (one grant, second interact refused, key restored and re-kill spawns no drop) |
| AC-23 | Session defaults, `claim()`, location change, snapshot round trip, no Objects in the DTO | PASS | `tests/unit/session/test_player_session_state.gd`, `test_save_snapshot.gd`; `test_save_round_trip.gd` |
| AC-24 | Registry duplicate/empty/null/invalid/cross-reference reporting; shipped manifest valid | PASS | `tests/unit/content/test_content_registry.gd`, `tests/integration/test_content_graph.gd` |
| AC-25 | Save round trip, atomic (no `.tmp`/`.bak`), `MISSING`, `CORRUPT` + quarantine, `UNSUPPORTED_VERSION` | PASS | `tests/unit/save/test_save_manager.gd`; `test_save_round_trip.gd` (round trip, garbage quarantine, version 999 untouched, overwrite path, unknown-id filtering) |
| AC-26 | `HealthComponent.restore()` without changing `apply_damage`/`reset` semantics | PASS | `tests/unit/combat/test_health_component_restore.gd`; `test_save_round_trip.gd::test_zero_health_in_the_save_becomes_full_hp_on_the_next_boot` (real boot path) |
| AC-27 | Interaction focus/prompt, walls block, out of reach, repeat `E`, portal returns the router code | PASS | `tests/unit/interaction/**`, `tests/integration/test_interaction_ray.gd`; the loop test drives the real rays on portal/drop/chest/portal/shrine |
| AC-28 | Enemies emit `defeated` exactly once with a reward and never without one | PASS | `tests/integration/test_enemy_defeat_signal.gd`; the loop test observes exactly one drop per kill and none for a claimed key |
| AC-29 | Both worlds instantiate, host binds, markers resolve, dungeon has a pickup scene, graph valid | PASS | `tests/integration/test_world_scenes.gd`, `test_content_graph.gd` |
| AC-30 | Main scene == `world/main.tscn`, hub loads, one player at `spawn.hub.start`, HUD bound | PASS | `tests/integration/test_main_boot.gd`; `test_sprint02_loop.gd::test_fresh_boot_...` |
| AC-31 | Loop: hub → travel → kill → pickup → interact once → return → state kept → save → fresh `Main` restores once | PASS | `tests/integration/test_sprint02_loop.gd` (133 assertions incl. the relaunch, the claimed-key re-kill and the already-collected chest), `test_save_round_trip.gd` |
| AC-32 | Death respawns in the hub with full HP, inventory kept, no duplicate actors | PASS | `tests/integration/test_death_respawn.gd` (34 assertions) |
| AC-33 | Every Sprint 01 test still passes | PASS | Full suite: **337 tests / 2517 assertions / 0 failing**, exit 0 (baseline 328/2243/0; +9 new W5 tests) |
| AC-34 | Runtime cleanliness: no `SCRIPT ERROR`, no ObjectDB leak warning, boot smoke exit 0 | PASS (headless) | Suite output: no `SCRIPT ERROR`, no `ObjectDB`/leak lines; warnings are the 13 pre-existing "world without context" warnings plus the 1 expected `GameSession: stored HP 0.000000 is not playable` warning from the zero-health test; `--quit-after 300` exit 0; `--editor --quit` exit 0. **The graphical half (red errors while playing, driver-level issues) is M11 and NOT RUN.** |

## Validation evidence (W5, headless)

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

& $GODOT --headless --path . --editor --quit          # exit 0, no parse errors
& $GODOT --headless --path . -s res://tests/run_tests.gd
    === summary: 337 test(s), 2517 assertion(s), 0 failing test(s) ===
    RESULT: PASS  (exit 0)   [run twice on the final content: identical, exit 0 both times]
& $GODOT --headless --path . --quit-after 300         # exit 0, no error/warning lines
```

W5 test files: `test_sprint02_loop.gd` (2 tests, 147 assertions),
`test_save_round_trip.gd` (6 tests, 69 assertions),
`test_death_respawn.gd` (1 test, 34 assertions). The temporary save slots they use
(`user://test_sprint02_loop_slot.json`, `user://test_save_round_trip_slot.json`,
`user://test_death_respawn_slot.json`) are deleted in setup/teardown; the real slot
was never created during the W5 run.

## What headless verification cannot judge

The automated suite is real evidence for rules, timing, physics, data and state — but
it ends where presentation begins. These must be judged by a human in a graphical
session, and no headless run may report them as PASS:

- **Feel**: mouse-look sensitivity, walk acceleration, weapon-swing weight, hit
  feedback, the punch of the world swap.
- **Prompt legibility**: whether `[E] Enter` / `[E] Pick up` / `[E] Open` /
  `[E] Save progress` are readable at the target resolution against the dark walls,
  and whether they appear/disappear without flicker.
- **HUD layout**: whether HP, gold, items, location and status fit the screen without
  overlapping; whether the status line's messages are readable and timely.
- **Readability in the dungeon**: whether the golden drop is visible on the dark
  floor, whether the chest reads as openable, whether the greybox silhouettes are
  distinguishable, whether the warm-orange telegraph is noticeable at combat distance
  while moving.
- **Rendering**: lighting, transition popping, shadow and material artefacts,
  GPU-driver-level errors.
- **Frame pacing / performance**: frame time on the first world swap, during the
  enemy encounter, and while the drop + HUD are on screen.
