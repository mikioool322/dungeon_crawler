---
name: enemy-ai
description: Create small testable enemy finite-state machines for detection, chasing, telegraphed attacks and recovery.
---

# enemy-ai

## Method
1. State ownership: idle, pursuit, windup, active, recovery, dead; transitions explicitly guarded.
2. Use player target references weakly/safely and stop on death or invalid targets.
3. Keep AI decisions separate from AttackController execution and HealthComponent.
4. Make movement, attack radius and detection data-driven; account for physics frame updates.
5. Test: player enters radius, leaves radius mid-windup, obstacle, target disappears, enemy killed during windup, no attack after death.
6. Profile nav/physics if multiple enemies exist; avoid premature behavior trees.
## Finish
Provide transition table and deterministic test cases.
