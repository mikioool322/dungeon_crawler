---
name: gameplay-architecture
description: Design modular Godot gameplay features, contracts, dependency direction and resource-driven extension points.
---

# gameplay-architecture

## Method
1. Read `ARCHITECTURE.md` and investigate existing implementations before recommending abstractions.
2. Sketch owner of each state mutation and lifecycle; check for circular dependencies.
3. Prefer composition, typed small APIs, Resources for definitions, runtime components for state.
4. Evaluate save compatibility, visual decoupling, test seams and content creation burden.
5. Propose smallest implementation with explicit callers, tests and rollback path.
## Anti-patterns
No speculative ECS, unnecessary singletons, silent schema changes, multi-system “god” nodes or duplicate damage implementations.
## Finish
Write an impact table, contract changes, alternatives rejected and decision-log proposal if needed.
