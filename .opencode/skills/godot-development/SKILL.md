---
name: godot-development
description: Implement and debug Godot 4 GDScript, scenes, Resources, signals, input, and CLI import validation.
---

# godot-development

## Method
1. Inspect `project.godot`, Godot version, relevant scenes/scripts and existing naming conventions.
2. Use typed GDScript where clear; prefer editor-inspectable Resources and readable scene trees.
3. Keep input mapping in InputMap and frame-rate independent movement in `_physics_process`.
4. Handle node lifecycle, freed nodes, missing exported resources and scene reloads safely.
5. Prefer small scene scripts; avoid hardcoded `get_node` paths across modules.
6. Validate import and parser in headless editor, run tests if available, and manually exercise a graphical scene when needed.
## Finish
Document changed scene contracts, InputMap additions, command output and visual checks.
