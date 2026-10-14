---
name: combat-system
description: Implement first-person melee attack, hit resolution, range-based evasion, cooldown and telegraph testing.
---

# combat-system

## Initial rules
One melee attack, enemy windup/active/recovery, evasion via moving out of reach. No dodge invincibility frames.
## Method
1. Define AttackDefinition `Resource` with stable ID, reach, damage, windup, active window and recovery.
2. Separate attack intent, active hit queries, damage resolution and feedback.
3. Validate distance at hit frame; check collision and occlusion; avoid hits through walls.
4. Track hit targets per attack instance so a swing cannot apply damage twice.
5. Do not use render animation completion as sole authority for gameplay timing.
6. Write tests: in reach hit, out-of-range miss, backs away before active frame miss, cooldown, death interruption, duplicate collision one hit.
## Finish
Show a greybox reproduction scene; document actual tested behavior.
