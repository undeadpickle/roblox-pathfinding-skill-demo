# Session Handoff

> Updated: 2026-02-25 (Session 18 → 19)
> Focus: Refactor from demo to toolkit — make NPC behaviors assignable to any humanoid

---

## What Got Done (Session 18)

### Obstacle Migration to Studio
Moved all 24 obstacle parts from runtime config-driven generation to permanent Studio-placed instances via MCP `run_code`. Deleted MapSetup module, GameConfig.MAP config, and all related init code. ~200 lines removed.

### Pushed to GitHub
Repo live at https://github.com/undeadpickle/roblox-pathfinding-skill-demo.git

---

## Session 19 Goal: Demo → Toolkit Refactor

The system currently works as a fixed demo: NPCManager creates exactly 4 NPCs with hardcoded behaviors on a specific map. The goal is to refactor it into a toolkit where:

1. **Any existing humanoid model** can be registered as an NPC (no runtime rig creation required)
2. **Behaviors are assignable** — pick chase, patrol, wander, or guard for any registered NPC
3. **Behaviors are swappable at runtime** — change an NPC's personality without destroying and rebuilding it
4. **Individual NPC lifecycle** — spawn one, despawn one, not all-or-nothing

### What's Already Solid (don't rewrite)
- **NPCPathfinder** — Generic movement engine. `NPCPathfinder.new(model)` already accepts any model. Methods: moveTo, patrol, followTarget, wander, hasLineOfSight. No demo coupling.
- **NPCStateMachine** — Generic state machine. Takes a state map + initial state. Reusable.
- **Behavior state modules** (ChaseStates, PatrolStates, WanderStates, GuardStates) — Self-contained state definitions. Each exports a function that returns a state map. Clean separation.
- **BehaviorHelpers** — Utility functions (findNearestPlayer, getRandomPointInRadius, etc.). No demo coupling.

### What Needs Refactoring
- **NPCManager** (~452 lines) — This is the bottleneck. Currently:
  - Creates R15 rigs from scratch (should also accept pre-placed models)
  - Hardcodes 4 NPC configs in `initialize()` (should be a registry with `registerNPC()` / `spawnNPC()`)
  - No individual despawn (only bulk `cleanup()`)
  - No behavior swapping (state machine is set once, forever)
  - Debug visuals are wired at spawn time with no swap path

### Key Design Questions to Resolve
1. **How should NPC config be provided?** Options: Roblox attributes/tags on the model, a config table passed to `registerNPC()`, or a hybrid. Attributes would let level designers configure NPCs in Studio without code.
2. **What does behavior swap look like?** Stop current state machine → clean up behavior-specific visuals (waypoint markers, beams) → create new state machine with new states → restart tick. Need a clean teardown per behavior type.
3. **How do waypoints/zones get defined for toolkit use?** Patrol needs waypoint positions, guard needs a home zone + waypoints, wander needs a center + radius, chase just needs a detection radius. Could use Workspace markers (Parts tagged as waypoints) or config tables.
4. **Should rig creation stay as an option?** Useful for runtime spawning. Could be `NPCManager.spawnNPC(config)` (creates rig) vs `NPCManager.registerNPC(existingModel, config)` (adopts model).

---

## Architecture Notes

- **Obstacles are Studio-placed** in `Workspace.Obstacles` (24 parts). Not in source code.
- **SuburbanHouse is MCP-constructed** in `Workspace.SuburbanHouse` (96 parts). Not in source code.
- **DebugVisuals uses late-binding getter pattern** for callbacks (NPCManager inits before DebugService).
- **NPCPathfinder type errors under --!strict are false positives** — metatable OOP pattern. Ignore them.
- **Branch:** Work should happen on a new branch (`feat/toolkit-refactor` or similar). `main` preserves the working demo as a revert point.

## Blockers

None.
