# Sprint 01 — manual (graphical) acceptance checklist

Scope: the M1–M9 checks from `docs/SPRINT_01.md` plus the automated coverage map for
AC-01..AC-13. Run on the reference machine with the pinned engine (ADR-002):

```
GODOT = "C:\Users\mikio\Desktop\Godot_v4.7.2-stable_win64_console.exe"

"%GODOT%" --path .            # opens the project's main scene: res://world/prototype/proto_arena.tscn
```

Controls: WASD move, mouse look, left click attack, backpedal to evade, `Esc` releases the
mouse (a click re-captures it), `R` restarts the arena (the only reset in Sprint 01).

## Verification status of this document

**Every M item below is NOT RUN.** W6 was executed in a headless environment; no graphical
session, screenshot or human play-through was performed, so no manual item may be marked PASS.
Where a headless test proves the *rule* behind an item, it is named in the "automated
equivalent" column — that is evidence about logic and physics, **not** about feel, readability,
frame pacing or the rendered image.

Column to fill in during a real session: `Status` (`PASS` / `FAIL` / `BLOCKED` / `NOT RUN`),
with date, engine build and a one-line note. A FAIL needs the observable symptom, the expected
behaviour and the arena state (enemy HP/state, player HP from the debug HUD).

| # | What to do | What to look for | Status | Automated equivalent (headless, rule-level only) |
|---|------------|------------------|--------|--------------------------------------------------|
| M1 | Walk with WASD and sweep the mouse across the arena; push the mouse far up and far down. | Movement and look are smooth, no stutter or jitter; the view turns at a constant rate for a constant mouse speed; pitch stops at ±89° instead of flipping or gimbal-locking; the horizon never rolls. | NOT RUN | `tests/integration/test_player_movement.gd::test_mouse_look_yaws_the_body_and_pitches_the_head`, `::test_pitch_is_clamped_so_the_camera_never_flips`, `::test_backpedal_moves_away_from_facing_at_move_speed` (pure input→transform math; says nothing about smoothness) |
| M2 | Click to swing repeatedly and watch the viewmodel through WINDUP → ACTIVE → RECOVERY. | The placeholder blade is visible in the lower right, it visibly pulls back, thrusts on the hit frame and eases back to rest; the swing never locks movement; no visible pop when the swing ends. | NOT RUN | `tests/integration/test_player_scene.gd::test_viewmodel_follows_attack_phases_and_returns_to_rest`, `::test_removing_the_viewmodel_does_not_change_combat_behaviour` (pose offsets only, not framing or feel) |
| M3 | Walk into the grunt's attack range and stop; watch it start a swing. | The telegraph (warm orange windup, brighter yellow on the active frame) is unmistakable at ~2 m, starts *before* the damage lands, and is readable while moving. | NOT RUN | `tests/unit/combat/test_attack_controller.gd` (phase timing: 0.7 s windup before the single hit query). Telegraph colour logic is presentation-only and asserted nowhere — it needs eyes. |
| M4 | Stand inside reach and let the grunt's active frame arrive. | The swing lands, the debug HUD shows player HP `100 -> 88`, and the enemy returns to chasing afterwards. | NOT RUN | `tests/integration/test_encounter.gd::test_a_enemy_swing_damages_the_player_rig_exactly_once`, `::test_c_control_standing_still_in_the_same_window_takes_the_hit` |
| M5 | Let the grunt start its windup, then hold `S` (backpedal) until the swing ends. | No HP loss at all; the grunt still completes the swing (no freeze, no cancel); HP shows `100 / 100` afterwards. | NOT RUN | `tests/integration/test_encounter.gd::test_b_backpedalling_from_the_telegraph_avoids_the_swing` (real rig, real input, asserts the miss and an empty `abort_reason`) |
| M6 | Hit the grunt three times with left click. | Enemy HP goes 100 → 66 → 32 → 0, the body turns grey, it stops moving and never attacks again; the player's HP stops dropping once it is dead. | NOT RUN | `tests/integration/test_encounter.gd::test_e_player_kills_the_enemy_rig_in_three_swings` (incl. 2 s of no post-death damage) |
| M7 | Stand behind `PillarWest`/`PillarEast` with the grunt on the other side; also try swinging at the grunt through a pillar. | Neither side damages through the pillar; the grunt does not even detect the player when the pillar fully blocks the line of sight. | NOT RUN | `tests/integration/test_encounter.gd::test_d1_pillar_blocks_line_of_sight_so_the_encounter_never_starts`, `::test_d2_pending_swing_is_resolved_as_occluded_when_geometry_appears` |
| M8 | Walk far away (beyond ~16 m) while the grunt chases, or break line of sight behind a wall. | The grunt stops chasing, stands still and does not attack; the HUD state line reads `state idle`. | NOT RUN | `tests/integration/test_encounter.gd::test_f_moving_beyond_the_lose_radius_returns_the_enemy_to_idle`, `tests/integration/test_enemy_brain.gd::test_lost_target_returns_the_enemy_to_idle_and_stops_it` |
| M9 | Play for ~2 minutes (fight, die, press `R`, fight again) and watch the Godot Output panel. | No red errors or script errors at any point, including on player death, restart and while the corpse is on screen. | NOT RUN | `"%GODOT%" --headless --path . --quit-after 300` (no error lines), `--headless --path . -s res://tests/run_tests.gd` (no error lines during 170 tests). A headless run cannot reproduce graphical-driver or rendering errors. |

## Automated coverage map (AC-01..AC-13)

Status is what the W6 run actually observed on this machine; "NOT RUN" means no evidence
exists yet and must not be reported as PASS.

| AC | Criterion (short) | Status | Artefact |
|----|-------------------|--------|----------|
| AC-01 | Target inside reach at the hit frame ⇒ `applied`, HP down by `damage` | PASS | `tests/unit/combat/test_melee_rules.gd`, `test_health_component.gd`; `tests/integration/test_hit_resolution.gd::test_in_reach_target_is_hit_once_for_the_definition_damage`; rig-level `tests/integration/test_encounter.gd::test_a_...`, `::test_c_...` |
| AC-02 | Target outside `reach` ⇒ no damage, `out_of_reach` | PASS | `tests/unit/combat/test_melee_rules.gd`; `tests/integration/test_hit_resolution.gd::test_target_out_of_reach_is_missed_and_undamaged`; `tests/integration/test_encounter.gd::test_b_...` (miss reason asserted ∈ {`out_of_reach`, `no_target`}) |
| AC-03 | Retreat before the first ACTIVE tick ⇒ miss, no HP change | PASS | `tests/integration/test_hit_resolution.gd::test_target_retreating_during_windup_is_missed`; real rig + real input: `tests/integration/test_encounter.gd::test_b_...` with control `::test_c_...` and the `abort_reason == ""` assertion |
| AC-04 | Duplicate contact / repeat query ⇒ exactly one application | PASS | `tests/unit/combat/test_hit_registry.gd`; `tests/integration/test_hit_resolution.gd::test_overlapping_collision_shapes_apply_damage_once` |
| AC-05 | Attack during cooldown rejected, accepted after | PASS | `tests/unit/combat/test_attack_controller.gd`; `tests/integration/test_encounter.gd::test_e_...` (player swings again 0.6 s later) |
| AC-06 | Enemy killed during windup aborts the swing; no hit after death | PASS | `tests/unit/combat/test_attack_controller.gd`, `tests/unit/ai/test_enemy_fsm.gd`; `tests/integration/test_enemy_brain.gd::test_lethal_damage_aborts_the_swing_and_prevents_further_attacks`; rig-level `tests/integration/test_encounter.gd::test_e_...` (2 s of no damage after death) and `::test_g_...` |
| AC-07 | Losing the target (> lose radius or freed) ⇒ IDLE and stops | PASS | `tests/unit/ai/test_enemy_fsm.gd`; `tests/integration/test_enemy_brain.gd::test_lost_target_...`, `::test_freed_target_...`; rig-level `tests/integration/test_encounter.gd::test_f_...` |
| AC-08 | `died` emitted once; damage after death ignored; HP clamps at 0 | PASS | `tests/unit/combat/test_health_component.gd`; rig-level `tests/integration/test_encounter.gd::test_g_...` (HP stays 0, miss reason `target_dead`) |
| AC-09 | Attack/enemy resource validation | PASS | `tests/unit/combat/test_attack_definition.gd`, `tests/unit/ai/test_enemy_definition.gd`; shipped-content freeze `tests/integration/test_shipped_definitions.gd` |
| AC-10 | Player/enemy/arena scenes load headless without parser or script errors | PASS | `tests/integration/test_project_scripts.gd` (loads every `.gd`, `.tscn` and `content/*.tres` in the project); `test_player_scene.gd`, `test_arena_boot.gd`; `"%GODOT%" --headless --path . --editor --quit` |
| AC-11 | Arena boots headless with `main_scene` set, no runtime errors | PASS | `tests/integration/test_arena_boot.gd::test_main_scene_is_the_arena`; `"%GODOT%" --headless --path . --quit-after 300` (exit 0, no error output) |
| AC-12 | Full suite PASS + manual checklist executed with notes | PARTIAL | Suite PASS (`--headless --path . -s res://tests/run_tests.gd`); this checklist exists but its M1–M9 items are **NOT RUN** (no graphical session in W6) |
| AC-13 | Independent review without open CRITICAL/HIGH findings; no out-of-ownership edits | NOT RUN | Owned by W7 (`reviewer`, read-only). A QA test pass is not an independent review; no reviewer report exists yet. |

## What headless verification cannot judge

The automated suite above is real evidence for rules, timing, physics and data — but it ends
where presentation begins. These must be judged by a human in a graphical session:

- **Feel**: mouse-look sensitivity, walk acceleration, weapon-swing weight, hit feedback.
- **Readability**: whether the windup telegraph is noticeable at combat distance while moving,
  whether the active frame reads as a strike, whether the greybox silhouettes are distinguishable.
- **Rendering**: lighting, the visible weapon's framing, HUD legibility at the target resolution,
  visible popping, shadow and material artefacts, GPU-driver level errors.
- **Frame pacing / performance**: frame time under load, stutter on first encounter or restart.
