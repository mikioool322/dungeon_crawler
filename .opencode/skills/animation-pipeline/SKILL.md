---
name: animation-pipeline
description: Integrate first-person weapon animation, enemy rigs, telegraphs and Godot AnimationTree cleanly.
---

# animation-pipeline

## Method
1. Specify skeleton/rig assumptions, coordinate orientation, animation clips and retargeting limitations.
2. Separate authoritative attack timing from rendering animation state.
3. Make windup/active/recovery frames unmistakable and synchronized via explicit cues.
4. Check looping, transitions, interruptions, root motion, clipping, weapon attachment and FPS camera motion.
5. Use placeholder animations before spending on new generated assets.
6. Validate playback visually and test gameplay hit frame independently.
## Finish
Document animation interface, missing clips and player-facing defects.
