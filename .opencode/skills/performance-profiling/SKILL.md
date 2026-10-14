---
name: performance-profiling
description: Measure Godot first-person dungeon rendering, physics, draw calls and memory before proposing optimizations.
---

# performance-profiling

## Method
1. Establish reproducible hardware, renderer, resolution, scene and framerate baseline.
2. Measure frame time, graphics time, physics time, memory and draw calls with profiler evidence.
3. Prioritize actual bottlenecks, not conjecture; preserve gameplay correctness.
4. Test batching/instancing, collision complexity, AI tick budgets, texture sizes and occlusion only as indicated by metrics.
5. Compare before/after using same scene and quality settings; document visual tradeoffs.
## Finish
Report benchmark conditions and metrics; no invented FPS numbers.
