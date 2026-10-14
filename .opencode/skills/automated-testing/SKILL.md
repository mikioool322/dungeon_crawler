---
name: automated-testing
description: Create and run Godot unit, integration and gameplay regression tests with truthful pass/fail evidence.
---

# automated-testing

## Method
1. Check which Godot version/test runner is installed; never assume GdUnit4 or GUT is present.
2. Make domain logic deterministic and testable without scene rendering where possible.
3. Use fixture scenes for combat, doors, spawning, save/load and interaction.
4. Run `godot --headless --path . --editor --quit` after import/resource changes.
5. Run runner commands only if runner is installed; capture exit code and relevant stdout/stderr.
6. For graphical mechanics, state required manual/input automation verification and perform if tools available.
7. On failures, minimize reproduction and fix root cause; never suppress tests merely to pass.
## Finish
Test inventory: PASS / FAIL / NOT RUN + why; unknowns remain unknown.
