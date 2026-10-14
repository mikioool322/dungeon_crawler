---
name: save-persistence
description: Design versioned, resilient local game saves for inventory, progression, world transitions and reward unlocks.
---

# save-persistence

## Method
1. Specify persistent data owners and stable IDs; never serialize Nodes or transient scene paths.
2. Define schema version, default values, unknown-ID handling and migration strategy.
3. Write saves through a safe temporary-file flow; verify parse/write errors and recovery.
4. Protect against duplicate rewards, repeated event delivery and partial progression writes.
5. Test round trip, corrupted save, missing file, old schema, item removed from catalog and repeated save/load cycles.
6. Keep save logic independent of UI and asset rendering.
## Finish
Record exact schema changes and backwards-compatibility consequences.
