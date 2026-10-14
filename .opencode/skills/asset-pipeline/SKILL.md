---
name: asset-pipeline
description: Import AI-generated or authored Blender/GLB characters, props and environments into Godot reproducibly.
---

# asset-pipeline

## Method
1. Record source, license and commercial-use terms in `docs/ASSET_LICENSES.md`.
2. Validate units, axis orientation, pivots, mesh scale, materials, UVs, collision and LOD expectations.
3. Keep raw/processed/engine-imported assets separated by documented convention.
4. Automate Blender exports with scripts where repeatable; never alter raw inputs destructively.
5. Verify a placeholder-to-final swap without gameplay code edits.
6. Test import logs, visible materials, performance and animation compatibility.
## Finish
List source→output paths, transformations and unresolved cleanup.
