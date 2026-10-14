---
name: dungeon-generation
description: Design modular authored and later procedural dungeon layouts with reachability, encounters and puzzle constraints.
---

# dungeon-generation

## Method
1. Start from an authored greybox dungeon; only introduce procedural assembly after core gameplay works.
2. Describe room sockets, entrance/exit connectivity, seeds and resource IDs.
3. Enforce reachable critical path, playable collision/navigation and spawn safety.
4. Separate layout construction from encounter placement, rewards and rendering.
5. Add deterministic seeded tests for dead ends, inaccessible exits, overlaps, missing doors and puzzle solvability.
6. Profile generation latency and scene instantiation under representative room counts.
## Finish
Provide reproducible seed and playability proof; no untested “infinite generation” claims.
