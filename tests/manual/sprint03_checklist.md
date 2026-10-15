# Sprint 03 — manual (graphical) acceptance checklist

Scope: the Sprint 03 definition of done — repeatable dungeons with persistent story
progress (hub board → run → objective completion → first-clear story reward and unlock →
repeat run → save and relaunch) — plus the carried-over Sprint 01/02 checks (movement,
look, attack, evasion by leaving reach, telegraph readability, runtime cleanliness), plus
the coverage map for the Sprint 03 acceptance scenarios.

Engine (ADR-002, pinned):

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

& $GODOT --path .            # main scene: res://world/main.tscn
```

Controls: WASD move, mouse look, left click attack, `E` interact (board / portal / pickup /
chest / shrine), `Esc` releases the mouse or closes an open panel (a click re-captures it).
No jump, no dash, no block; evasion is walking backwards out of reach. Saving happens only
at the hub shrine; loading happens only at boot.

Save slot: `%APPDATA%\Godot\app_userdata\Dark Fantasy ARPG\save_slot0.json`
(`user://save_slot0.json`). Delete it (plus any `.tmp` / `.bak` / `.corrupt` beside it) to
repeat the "first launch" behaviour.

Sprint 03 semantics the manual pass must keep in mind (ADR-012/013/014):

- The board is hub furniture and never opens by itself: look at it and press `E`.
- A run is transient: re-entering a dungeon always resets its enemies, its chest and its
  ordinary loot, even after a crash. Only story progress is saved.
- The first clear of dungeon 01 grants the story reward once and unlocks dungeon 02.
  The story reward can never be granted twice; ordinary rewards can be re-earned.
- A version 1 (Sprint 02) save loses its legacy reward keys by design and keeps HP, gold,
  items, world and spawn; it never invents a dungeon completion.

## Verification status of this document

**Every M item below is NOT RUN.** This pass was executed entirely headless (`--headless`
suite, `--editor --quit`, boot smoke). No graphical session, no screenshot and no human
play-through was performed, so no manual item may be marked PASS, FAIL or BLOCKED. Where a
headless test proves the *rule* behind an item, it is named in the last column — that is
evidence about logic, physics and state, **not** about feel, readability, layout, timing or
frame pacing.

Column to fill in during a real session: `Status` (`PASS` / `FAIL` / `BLOCKED` / `NOT RUN`),
with date, engine build and a one-line note. A FAIL needs the observable symptom, the
expected behaviour and the run state (HP, gold, items, location from the HUD).

## Manual items

| # | What to do | What to look for | Status | Automated equivalent (headless, rule-level only) |
|---|------------|------------------|--------|--------------------------------------------------|
| M1 | Launch with no save file present and watch the first frame. | The hub greybox loads; HUD reads `HP: 100 / 100`, `Gold: 0`, `Items: (empty)`, `Location: world.hub @ spawn.hub.start`, status `New game (no save found)`; the camera starts at the south marker looking into the hall; the Output panel shows no red lines and no `SCRIPT ERROR`. | NOT RUN | `tests/integration/test_main_boot.gd::test_boot_loads_the_hub_with_one_player_at_the_start_marker`, `::test_boot_binds_the_hud_to_the_live_rig`, `tests/integration/test_sprint02_loop.gd::test_fresh_boot_starts_in_the_hub_with_one_rig_and_the_hub_hud` |
| M2 | Walk to the wooden board (west of the start, next to the shrine side of the hall), look at it from ~2 m and press `E`. | Prompt `[E] Dungeons` appears only while the board is the thing being looked at and inside reach; the panel opens: a dark dim over the world, the title `Dungeons`, a row `Dungeon 01 - Collapsed Hall [ENTER]` and a row `Dungeon 02 - Sunken Vault [LOCKED]`, and a `Close [Esc]` button. Text is readable against the dim, the rows are distinguishable, nothing overlaps at the target resolution. | NOT RUN | `tests/integration/test_dungeon_board.gd::test_open_builds_rows_and_close_restores_cursor_and_input`, `::test_rows_follow_manifest_order_and_live_progress` (view model and button text, not the rendered layout) |
| M3 | While the panel is open, try to click the `Dungeon 02` row (and hover it). | The row is greyed out, does not react to clicks, and its tooltip explains the lock (`Requires Dungeon 01 - Collapsed Hall`). Pressing `E`/Enter on it does nothing; the player does not travel. | NOT RUN | `test_dungeon_board.gd::test_select_refuses_locked_and_records_one_travel_for_unlocked`, `tests/integration/test_sprint03_loop.gd::test_a_locked_dungeon_cannot_be_entered_from_the_board`, `tests/integration/test_dungeon_gate.gd::test_travel_into_a_locked_dungeon_is_blocked_and_changes_nothing` |
| M4 | With the panel open, move the mouse, try to look around, press WASD and left click; then press `Esc` (or click `Close`) and repeat. | While open: the cursor is visible and free (released by the panel, not by `Esc`), look does not turn the camera, WASD does not move the rig and left click does not swing. After closing: the cursor is captured again, look/move/attack work immediately, and a later click re-captures after an `Esc` release. No stuck input, no double cursor. | NOT RUN | `test_dungeon_board.gd::test_open_builds_rows_and_close_restores_cursor_and_input`, `::test_ui_cancel_closes_an_open_panel` (input lockout, movement freeze and cursor flag, not the rendered cursor or feel) |
| M5 | Click the `Dungeon 01` row (or walk to the north portal and press `E`). Walk the hall: both pillars, all four walls, the chest corner, the return portal. | The swap is immediate: the player stands at `spawn.dungeon.entry` on the south side; HUD `Location: world.dungeon.proto01 @ spawn.dungeon.entry`; the grunt is visible north of the entry; geometry has no gaps, the pillars block movement, no black frame, no stacked geometry, no second player. | NOT RUN | `test_sprint03_loop.gd::test_the_full_progression_loop` (step 1), `tests/integration/test_world_scenes.gd::test_dungeon_scene_contract`, `tests/integration/test_dungeon_gate.gd` (one world / one rig per travel); walkability *feel* and rendering are not judged |
| M6 | Complete dungeon 01 once (see M7/M8), return to the hub, then click `Dungeon 02 - Sunken Vault [ENTER]` and walk that hall. | The second dungeon loads with its own warmer, darker lighting and a narrower hall; HUD `Location: world.dungeon.proto02 @ spawn.dungeon.entry`; two enemies are visible (one ordinary, one objective) plus a chest; the return portal brings the player back to the hub. | NOT RUN | `test_sprint03_loop.gd::test_the_full_progression_loop` (step 5), `tests/integration/test_content_graph.gd::test_every_dungeon_points_at_a_loadable_world_and_entry_spawn`, `test_world_scenes.gd` |
| M7 | In dungeon 01, look at the enemy north of the entry and try to tell whether it is *the* objective enemy; kill it and watch the HUD/board. | A human should be able to recognise the enemy whose death completes the dungeon. In the current greybox the objective enemy is visually identical to an ordinary one (same capsule, same material, same telegraph); the only marker is the `objective_id` in the scene. Report honestly whether this is discoverable in play (today: only by killing everything). The kill must still complete the dungeon exactly once, print the completion status line and unlock dungeon 02. | NOT RUN | `tests/integration/test_dungeon_completion.gd::test_the_objective_enemy_death_completes_once_even_when_reported_twice` (rule), `::test_an_ordinary_enemy_death_does_not_complete_the_dungeon`; *readability* has no headless evidence |
| M8 | After the objective enemy dies, read the status line, then reopen the board at the hub. | Status line reports the rewards (`Collected: Rusty Dagger x1, 10 gold (gold N)` for the story grant, plus the 5-gold regular grant) and no second copy after a repeat clear; the board now shows `Dungeon 01 - Collapsed Hall [COMPLETED]` and `Dungeon 02 - Sunken Vault [ENTER]`; the unlock is visible without restarting the game. | NOT RUN | `test_sprint03_loop.gd` (step 2: gold 15, one story item, dungeon 02 unlocked), `tests/integration/test_dungeon_completion.gd` (first clear vs repeat clear), `test_dungeon_board.gd::test_refresh_follows_progress_and_completion` |
| M9 | Re-enter dungeon 01 and let the grunt kill the player (stand still, no evasion). Then re-enter again and clear the chest. | Death respawns in the hub at `spawn.hub.start` with full HP; gold, items and story claims are kept; the interrupted run is gone (no completion, no run state); the next entry starts a fresh run: the enemy and the chest are back and their ordinary loot can be earned again, while the story reward is not granted a second time. | NOT RUN | `tests/integration/test_death_respawn.gd::test_lethal_damage_in_the_dungeon_respawns_in_the_hub_with_progress_kept`, `test_sprint03_loop.gd` (step 6), `tests/integration/test_dungeon_gate.gd::test_leaving_the_hub_ends_the_run_and_a_second_entry_starts_clean` |
| M10 | Save at the hub shrine, quit the game, relaunch it. | Status `Progress saved`, then `Save loaded` on the next boot; HP, gold, items and location exactly as saved; the board still shows dungeon 01 as `COMPLETED` and dungeon 02 as `ENTER`; re-entering dungeon 01 and killing the objective enemy pays only the ordinary reward; no `.tmp` / `.bak` file is left beside the save. | NOT RUN | `test_sprint03_loop.gd` (steps 7 and the relaunch), `tests/integration/test_save_round_trip.gd::test_dungeon_progress_round_trips_through_a_fresh_main`, `tests/unit/save/test_save_manager.gd::test_a_successful_save_leaves_no_temp_or_backup_files` |
| M11 | Sprint 01/02 carry-over in the same session: walk with WASD, look with the mouse, kill a grunt with three left clicks, let one swing wind up and backpedal out of reach, then let a later swing land. | Movement is smooth and the camera does not clip the walls; each left click costs a visible swing; the grunt telegraphs in warm orange before the ACTIVE tick and the swing is readable while moving; backpedalling makes the swing miss (no HP loss) and standing in reach loses HP; the drop appears where the body fell and cannot be collected twice. | NOT RUN | `tests/integration/test_player_movement.gd`, `tests/integration/test_encounter.gd`, `tests/integration/test_hit_resolution.gd`, `tests/integration/test_enemy_brain.gd`, `tests/integration/test_interaction_ray.gd` (rules and physics, not feel or readability) |
| M12 | Play for ~2 minutes across hub, both dungeons, deaths and saves, watching the Output panel and frame pacing. | No red errors and no `SCRIPT ERROR` at any point; no stutter on the first world swap or the first encounter; the frame rate stays steady with the panel open, the telegraph active and a drop on screen. | NOT RUN | `& $GODOT --headless --path . --quit-after 300` (exit 0) and the full suite (425 tests / 3445 assertions / 0 failing). A headless run cannot reproduce rendering, driver-level or pacing problems. |

## Sprint 03 acceptance-scenario coverage map

Status is what this QA pass actually observed on this machine (2026-10-15, Godot
4.7.2-stable, `--headless`). "NOT RUN" means no evidence exists yet and must not be
reported as PASS.

The plan of record (`docs/SPRINT_03.md`, "Acceptance criteria") counts 45 scenarios; this
map enumerates **47** because the "Domain and content" paragraph alone contains ten
separable statements. Every statement is listed individually rather than merged, so
nothing is silently dropped.

### A — Domain and content

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-A1 | `DungeonDefinition` field validation reports every missing/invalid field | PASS | `tests/unit/dungeon/test_dungeon_definition.gd` (5 tests: `test_every_required_field_is_reported`, `test_id_lists_reject_empty_duplicate_and_self_references`, …) |
| S03-A2 | Registry reports empty / duplicate **dungeon** ids | NOT RUN | The shared `ContentRegistry._collect()` path is covered for items and attacks only (`tests/unit/content/test_content_registry.gd::test_duplicate_ids_within_a_kind_are_reported`, `::test_empty_ids_and_null_entries_are_reported`); no fixture drives the `dungeons` bucket with a duplicate or empty `dungeon_id` |
| S03-A3 | Registry reports a dungeon whose world is not listed | NOT RUN (verified by ad-hoc repro, no committed test) | Repro `R1` (see "Findings and reproductions"): error `dungeon 'dungeon.repro.b': world 'world.missing' is not listed in the manifest` |
| S03-A4 | Registry reports an unknown prerequisite | NOT RUN (verified by ad-hoc repro, no committed test) | Repro `R2`: error `prerequisite 'dungeon.missing' is not listed in the manifest` |
| S03-A5 | Registry reports an unknown first-clear unlock target | NOT RUN (verified by ad-hoc repro, no committed test) | Repro `R3`: error `first-clear unlock 'dungeon.missing' is not listed in the manifest` |
| S03-A6 | Registry reports an unknown dungeon reward | NOT RUN (verified by ad-hoc repro, no committed test) | Repro `R4` / `R5`: `regular_reward_id 'reward.missing' is not listed in the manifest`, `first_clear_reward_id 'reward.missing' is not listed in the manifest` |
| S03-A7 | Registry reports an unreachable dungeon | NOT RUN (verified by ad-hoc repro, no committed test) | Repro `R6`: error `dungeon 'dungeon.repro.b': cannot be unlocked - no start dungeon reaches it` |
| S03-A8 | Registry reports a **duplicate world mapping** (two dungeons → one world) | **FAIL** | Repro `R8`: no error is produced; `ContentRegistry._check_dungeon_references()` has no such check, and `find_dungeon_for_world()` silently returns the first dungeon. See FINDINGS F1 |
| S03-A9 | An empty dungeon bucket stays valid | PASS | `tests/unit/content/test_content_registry.gd::test_an_empty_manifest_is_valid`, `::test_a_null_manifest_degrades_without_crashing` |
| S03-A10 | The shipped manifest is valid with `dungeon.01` as the only start dungeon | PASS | `tests/integration/test_content_graph.gd::test_the_shipped_manifest_is_valid`, `::test_the_shipped_dungeon_graph_has_one_start_and_one_unlock`, `tests/integration/test_sprint03_loop.gd::test_a_new_game_has_one_unlocked_dungeon_and_the_board_says_so` |

### B — Progress

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-B1 | A new game unlocks exactly the start dungeons and completes nothing | PASS | `tests/unit/dungeon/test_dungeon_progress.gd::test_a_new_game_unlocks_only_the_start_dungeons`, `test_sprint03_loop.gd::test_a_new_game_has_one_unlocked_dungeon_and_the_board_says_so` |
| S03-B2 | `mark_completed` reports the first completion only once | PASS | `test_dungeon_progress.gd::test_mark_completed_reports_the_first_completion_only_once` |
| S03-B3 | `unlock` is idempotent | PASS | `test_dungeon_progress.gd::test_unlock_is_idempotent_and_reports_newly_unlocked` |
| S03-B4 | `to_save_dict` / `from_save_dict` round trip is tolerant and stable-ordered | PASS | `test_dungeon_progress.gd::test_save_dict_round_trip_is_stable_and_sorted`, `::test_from_save_dict_is_tolerant` |
| S03-B5 | Unknown ids in the save are dropped with warnings | **FAIL** (dungeon section) | The item/reward/world-key path is covered (`tests/integration/test_save_round_trip.gd::test_unknown_item_reward_and_world_ids_are_dropped_with_warnings`); for `dungeon_progress` the warning is emitted but the id is **not** dropped (FINDINGS F2, repro Part 2) and no test covers that section |

### C — Run lifecycle

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-C1 | Entering a dungeon starts an ACTIVE run with a fresh id | PASS | `tests/integration/test_dungeon_gate.gd::test_travel_into_a_locked_dungeon_is_blocked_and_changes_nothing`, `::test_the_same_travel_succeeds_after_the_unlock_with_a_fresh_run` (new), `tests/unit/dungeon/test_dungeon_service.gd::test_starting_a_run_opens_the_run_ledger` |
| S03-C2 | Entering the hub leaves no active run | PASS | `test_dungeon_gate.gd::test_leaving_the_hub_ends_the_run_and_a_second_entry_starts_clean` (new), `tests/unit/dungeon/test_dungeon_service.gd::test_leaving_the_world_aborts_an_unfinished_run` |
| S03-C3 | A locked dungeon is refused with `blocked` **before** the swap and changes nothing | PASS | `test_dungeon_gate.gd::test_travel_into_a_locked_dungeon_is_blocked_and_changes_nothing` (new): `CODE_BLOCKED`, one `world_load_failed`, same world instance, same rig, same active run, same ledger, progress untouched |
| S03-C4 | A second entry creates a fresh run with no memory of the previous claims | PASS | `test_dungeon_gate.gd::test_leaving_the_hub_ends_the_run_and_a_second_entry_starts_clean` (new, run facts and ledger), `test_sprint03_loop.gd::test_the_full_progression_loop` (step 6) |
| S03-C5 | Death aborts the run and cannot complete a dungeon | PASS | `tests/integration/test_death_respawn.gd::test_lethal_damage_in_the_dungeon_respawns_in_the_hub_with_progress_kept` (asserts `active_run() == null` and a closed run ledger) |
| S03-C6 | A stale run id cannot mutate | PASS | `tests/unit/dungeon/test_dungeon_run_state.gd::test_a_finished_run_refuses_further_mutations`, `tests/unit/loot/test_loot_service.gd::test_a_grant_from_a_stale_run_is_refused` |

### D — Loot

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-D1 | One run-scope claim per run, repeatable in the next run | PASS | `tests/unit/loot/test_loot_service.gd::test_a_second_identical_grant_in_the_same_run_is_a_duplicate`, `::test_a_new_run_grants_the_same_key_again`, `tests/integration/test_interaction_ray.gd::test_a_chest_stays_in_the_world_and_a_claimed_key_never_grants_twice` |
| S03-D2 | Story scope is once ever and across save/load | PASS | `test_loot_service.gd::test_a_story_grant_is_once_per_save_and_needs_no_run`, `::test_a_story_key_restored_from_a_save_is_a_duplicate`, `tests/integration/test_save_round_trip.gd` |
| S03-D3 | A persistent key never blocks a run-scope grant, and vice versa | PASS | `test_loot_service.gd::test_a_persistent_key_does_not_block_a_run_grant`, `::test_a_run_claim_does_not_block_a_story_grant` |
| S03-D4 | A run-scope grant without an active run is `invalid` and mutates nothing | PASS | `test_loot_service.gd::test_a_run_scoped_grant_without_an_active_run_is_invalid` |
| S03-D5 | After N runs the persisted key count equals the story claims only | PASS | `tests/unit/dungeon/test_dungeon_service.gd::test_the_story_reward_cannot_be_granted_twice_across_runs`, `test_sprint03_loop.gd` (step 6: one persistent key after two runs) |

### E — Completion

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-E1 | The objective enemy's death completes the dungeon | PASS | `tests/integration/test_dungeon_completion.gd::test_the_objective_enemy_death_completes_once_even_when_reported_twice` (new, real dungeon 01 scene through `WorldHost`), `test_sprint03_loop.gd` (real swings) |
| S03-E2 | An ordinary enemy's death never completes the dungeon | PASS | `test_dungeon_completion.gd::test_an_ordinary_enemy_death_does_not_complete_the_dungeon` (new): the extra ordinary enemy's death *is* recorded as a run fact, yet completes nothing |
| S03-E3 | A double report completes once | PASS | `test_dungeon_completion.gd::test_the_objective_enemy_death_completes_once_even_when_reported_twice` (new): a second real `died` report changes no gold, no item, no claim and emits nothing |
| S03-E4 | The first clear grants the story reward once and unlocks the next dungeon | PASS | `test_dungeon_completion.gd` (new), `tests/unit/dungeon/test_dungeon_service.gd::test_first_clear_grants_both_rewards_and_unlocks_the_next_dungeon` |
| S03-E5 | A repeat clear grants the regular reward again and nothing else | PASS | `test_dungeon_completion.gd::test_a_second_run_completes_again_with_first_clear_false` (new), `test_dungeon_service.gd::test_a_repeat_clear_grants_only_the_regular_reward` |
| S03-E6 | A failed story grant stays retryable and the retry grants only the missing part | PASS | `test_dungeon_service.gd::test_a_failed_story_grant_stays_retryable`, `test_sprint03_loop.gd` (relaunch: `claim_pending_first_clear_rewards() == 0`) |

### F — Save and load

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-F1 | v1 migrates to v2 (seeded progress, dungeon 01 available, no invented completion, HP/gold/items/world/spawn preserved, legacy keys dropped) | PASS | `tests/integration/test_boot_locked_world.gd::test_a_v1_save_migrates_and_keeps_the_run_state` (new: hand-written v1 file through a real `Main`, plus the rewritten file), `tests/unit/save/test_save_manager.gd::test_a_v1_file_migrates_to_v2_and_drops_the_legacy_reward_keys` |
| S03-F2 | v2 round trips completions, unlocks and story claims through a fresh `Main` | PASS | `tests/integration/test_save_round_trip.gd::test_dungeon_progress_round_trips_through_a_fresh_main`, `test_sprint03_loop.gd` (relaunch block) |
| S03-F3 | A saved world that is a locked dungeon falls back to the hub (with a warning) | PASS | `test_boot_locked_world.gd::test_a_v2_save_pointing_into_a_locked_dungeon_boots_into_the_hub`, `::test_a_v2_save_with_an_unknown_world_boots_into_the_hub` (new) |
| S03-F4 | A future save version is refused untouched | PASS | `tests/unit/save/test_save_manager.gd::test_a_newer_version_is_refused_and_the_file_is_untouched`, `tests/integration/test_save_round_trip.gd::test_a_future_version_is_refused_and_the_file_is_left_untouched` |
| S03-F5 | Corrupt data is quarantined | PASS | `test_save_manager.gd::test_garbage_text_is_corrupt_and_quarantined`, `test_save_round_trip.gd::test_garbage_save_is_quarantined_and_the_boot_degrades_to_a_new_game` |
| S03-F6 | Atomic write and backup recovery are intact | PASS | `test_save_manager.gd::test_a_leftover_backup_is_recovered_when_the_main_file_is_gone`, `::test_a_successful_save_leaves_no_temp_or_backup_files`, `::test_a_stale_temp_or_backup_from_a_crash_does_not_survive_the_next_save` |
| S03-F7 | No run data in the snapshot | PASS | `tests/unit/save/test_save_snapshot.gd`, `test_save_round_trip.gd` (the run ledger key is not persisted), `test_sprint03_loop.gd` (no run survives the relaunch) |

### G — End to end

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-G1 | The full loop: hub → dungeon 01 → objective → story reward + unlock → hub → dungeon 02 → re-enter dungeon 01 with reset content and re-earned ordinary loot → no second story reward → save → relaunch restores progress | PASS | `test_sprint03_loop.gd::test_the_full_progression_loop` (53 assertions, real swings, real board, real shrine) |
| S03-G2 | Exactly one player rig and one world at every step | PASS | `test_sprint03_loop.gd` (after every travel), `tests/integration/test_dungeon_gate.gd` (new: after the blocked refusal, after the unlock travel, after the re-entry, after the re-entrant `busy` refusal), `tests/integration/test_main_boot.gd::test_hud_survives_a_world_swap_without_duplicating_actors`, `tests/integration/test_death_respawn.gd` |
| S03-G3 | No leaks | **FAIL (pre-existing)** | The suite still exits with `WARNING: 31 ObjectDB instances were leaked at exit` and `ERROR: 13 resources still in use at exit`. Both lines are present at the pre-Sprint-03-QA tip (`5ee3711`, 415 tests) with the same counts, so this QA branch adds no leak — but the criterion itself is not met. See FINDINGS F3 |

### H — Manual / graphical

| ID | Scenario (short) | Status | Artefact |
|----|------------------|--------|----------|
| S03-H1 | Board readability and mouse release/capture | NOT RUN | M2 + M4 |
| S03-H2 | Walking dungeon 01 and dungeon 02 | NOT RUN | M5 + M6 |
| S03-H3 | Recognising the objective enemy | NOT RUN | M7 |
| S03-H4 | HUD feedback after an unlock | NOT RUN | M8 |
| S03-H5 | No runtime errors in a graphical session (~2 minutes) | NOT RUN | M12 |

## What headless verification cannot judge

The automated suite is real evidence for rules, timing, physics, data and state — but it
ends where presentation begins. These must be judged by a human in a graphical session, and
no headless run may report them as PASS:

- **Feel**: mouse-look sensitivity, walk acceleration, weapon-swing weight, hit feedback,
  the punch of the world swap, the weight of the dungeon dim behind the board.
- **Board readability**: whether the dim, the title, the two rows and the `Close [Esc]`
  button are legible against the dark hub, whether the disabled row reads as disabled,
  whether the tooltip is discoverable at all, and whether the panel fits the target
  resolution.
- **Cursor behaviour**: whether releasing/capturing the mouse around the panel feels
  correct, whether the free cursor can reach the rows, and whether `Esc` vs `Close` differ.
- **Objective readability**: whether a player can tell *which* enemy completes a dungeon.
  The greybox gives no visual marker today (M7), which is a design/readability question no
  headless test can answer.
- **Prompt legibility**: `[E] Dungeons`, `[E] Enter`, `[E] Pick up`, `[E] Open`,
  `[E] Save progress` against dark walls, without flicker.
- **HUD layout and timing**: whether the status line's reward/unlock messages are readable
  and timely, and whether `COMPLETED` vs `ENTER` in the board is obvious.
- **Dungeon readability**: silhouette separation, whether the second dungeon reads as a
  different place, whether the drop is visible on the dark floor.
- **Rendering and pacing**: lighting, transition popping, shadow and material artefacts,
  GPU-driver errors, frame time on the first swap, in a fight, and with the panel open.

## Validation evidence (headless, final state)

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

& $GODOT --headless --path . --editor --quit          # exit 0, no parse errors
& $GODOT --headless --path . -s res://tests/run_tests.gd
    === summary: 440 test(s), 3510 assertion(s), 0 failing test(s) ===
    RESULT: PASS  (exit 0)
& $GODOT --headless --path . --quit-after 300         # boot smoke, exit 0, 0 error/leak lines
python tools/validate_pack.py                         # PASS: 10 skills, 7 agents, exit 0
```

History (same machine, same engine):

| Run | Tests | Assertions | Failing | `SCRIPT ERROR` lines | ObjectDB leak line |
|-----|-------|------------|---------|----------------------|--------------------|
| QA branch `feat/s03-qa` (`b4e36f3`) | 425 | 3445 | 0 | 1 (`test_sprint02_loop.gd:522`) | 31 leaked / 13 resources |
| final `master` (`c004e56`) | 440 | 3510 | 0 | none | none |

The QA-found defects (duplicate world mapping, unknown dungeon id retained, leaks, the
type-mismatched assertion) and the review findings were fixed in `ef8c25c` and `c004e56`; the
suite now exits with no `SCRIPT ERROR` and no leak warning at all. The warnings added by the new
tests are only the deliberate ones: one duplicate objective report and two blocked travels.

Temporary save slots used by the new tests (`user://test_dungeon_gate_slot.json`,
`user://test_boot_locked_world_slot.json`, `user://test_dungeon_completion_slot.json`) are
deleted in `setup()`/`teardown()`; the real slot `user://save_slot0.json` is never created
or read.

## Mutation checks (throwaway copy of the repository)

Each safeguard was disabled alone on a copy of the repository under `%TEMP%` (deleted
afterwards); the suite was then run unchanged. Every mutation was caught, and the tests
that failed are the ones the safeguard exists for.

| Mutation (one at a time) | Suite result | Tests that failed |
|--------------------------|--------------|-------------------|
| (a) `DungeonService.can_enter()` returns `CODE_OK` unconditionally (the unlock/repeatable checks removed) | FAIL: 9 failing / 3438 assertions | `test_dungeon_gate.gd::test_travel_into_a_locked_dungeon_is_blocked_and_changes_nothing`, `::test_the_same_travel_succeeds_after_the_unlock_with_a_fresh_run`, `test_boot_locked_world.gd::test_a_v2_save_pointing_into_a_locked_dungeon_boots_into_the_hub`, `test_dungeon_completion.gd::test_an_ordinary_enemy_death_does_not_complete_the_dungeon`, `test_dungeon_board.gd::test_select_refuses_locked_and_records_one_travel_for_unlocked`, `test_sprint03_loop.gd::test_a_locked_dungeon_cannot_be_entered_from_the_board`, `unit/dungeon/test_dungeon_service.gd::test_can_enter_reflects_progress_and_repeatability`, `::test_a_locked_dungeon_cannot_start_a_run`, `::test_a_non_repeatable_completed_dungeon_is_refused` |
| (b) `LootService.grant()` skips the run-ledger duplicate check | FAIL: 4 failing | `unit/loot/test_loot_service.gd::test_a_second_identical_grant_in_the_same_run_is_a_duplicate`, `::test_a_new_run_grants_the_same_key_again`, `::test_a_persistent_key_does_not_block_a_run_grant`, `test_interaction_ray.gd::test_a_chest_stays_in_the_world_and_a_claimed_key_never_grants_twice` |
| (c) `DungeonService._grant_first_clear()` marks the claim even when the grant failed | FAIL: 1 failing | `unit/dungeon/test_dungeon_service.gd::test_a_failed_story_grant_stays_retryable` |
| (d) `WorldRouter._apply_run_lifecycle()` is a no-op | FAIL: 7 failing / 3331 assertions | `test_dungeon_gate.gd` (all four tests), `test_sprint03_loop.gd::test_the_full_progression_loop`, `test_sprint02_loop.gd::test_full_loop_hub_to_dungeon_loot_return_save_and_reload`, `test_death_respawn.gd::test_lethal_damage_in_the_dungeon_respawns_in_the_hub_with_progress_kept` |
| control: untouched copy | PASS: 425 tests / 3445 assertions / 0 failing | — |

## Findings and reproductions (this pass)

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| F1 | MEDIUM | The "duplicate world mapping" acceptance criterion was not implemented: two dungeons could point at the same `world_id` and the registry stayed valid; `find_dungeon_for_world()` then returned the first one, so the second dungeon's gate never applied. | **FIXED in `ef8c25c`** (`ContentRegistry` reports a world already owned by another dungeon) + `tests/unit/content/test_dungeon_registry.gd` |
| F2 | LOW | `GameSession._apply_progress()` warned `dropped unknown dungeon id from save: X` but kept `X` in `DungeonProgress`; the next save wrote it back. | **FIXED in `ef8c25c`** (`DungeonProgress.drop_unknown()` + the session drops unknown ids) + a `test_save_round_trip.gd` case |
| F3 | LOW | Runtime cleanliness: the suite reported `31 ObjectDB instances were leaked at exit` and `13 resources still in use at exit`. | **FIXED in `ef8c25c`** (a reference cycle between the domain test and the service it connected lambdas to) — the final suite exits with no leak line |
| F4 | LOW | `tests/integration/test_sprint02_loop.gd:522` compared a JSON `Array` with a `PackedStringArray`, which raised `SCRIPT ERROR` inside `assert_eq`; the assertion never ran while the test counted as PASS. | **FIXED in `ef8c25c`** (both sides wrapped in `Array(...)`) |

The independent review that followed (`c004e56`) found 0 CRITICAL/HIGH and 6 LOW + 3 INFO; the LOW
items are fixed in that commit (the board's entry button now follows the gate, the interaction ray
is suspended while the panel is open, the board no longer writes jargon into the status line,
`load_or_new` appends instead of replacing load warnings, and the comments/docstrings named in the
review were corrected). The three INFO items were documentation-only and are also corrected.

Reproduction output from the QA pass (read-only script run in a throwaway copy; not committed),
kept as the historical evidence for F1/F2:

```
--- Part 1: dungeon registry rules (negative paths) ------------------
R1 unknown world | expected 'world 'world.missing' is not listed' | REPORTED
R2 unknown prerequisite | expected 'prerequisite 'dungeon.missing' is not listed' | REPORTED
R3 unknown unlock target | expected 'first-clear unlock 'dungeon.missing' is not listed' | REPORTED
R4 unknown regular reward | expected 'regular_reward_id 'reward.missing' is not listed' | REPORTED
R5 unknown story reward | expected 'first_clear_reward_id 'reward.missing' is not listed' | REPORTED
R6 unreachable dungeon | expected 'cannot be unlocked - no start dungeon reaches it' | REPORTED
R7 duplicate dungeon id | expected 'duplicates the id 'dungeon.repro.a'' | REPORTED
R8 duplicate world mapping | expected 'duplicate world' | NOT REPORTED  (fixed in ef8c25c)
        observed errors: []
--- Part 2: unknown completed dungeon id ----------------------------
warnings                     = ["dropped unknown dungeon id from save: dungeon.ghost"]
progress.completed_ids()     = [&"dungeon.ghost"]   (fixed: now dropped)
progress.is_completed(ghost) = true
re-saved completed list       = ["dungeon.ghost"]
```

F1 expected vs observed: expected the registry to reject a manifest in which two dungeons
share one `world_id`; observed `ContentRegistry.errors == []` (a fully valid registry) and
`find_dungeon_for_world()` returning the first dungeon only. F2 expected vs observed:
expected the warned id to be dropped from `dungeon_progress`; observed it retained in the
progress and written back by the next save.
