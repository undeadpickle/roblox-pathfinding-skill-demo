# Session Handoff

> Updated: 2026-02-25 (Session 18)
> Focus: Migrate obstacles from runtime generation to permanent Studio placement

---

## What Got Done

### Obstacle Migration to Studio
Moved all 24 obstacle parts (16 walls/blocks + 8 staircase steps) from runtime config-driven generation to permanent Studio-placed instances via MCP `run_code`. Idempotent script destroys and recreates `Workspace.Obstacles` folder.

### Code Cleanup
- **Deleted** `src/server/modules/MapSetup.luau` — runtime obstacle generator (76 lines)
- **Removed** `GameConfig.MAP` section from `src/shared/GameConfig.luau` (120 lines of obstacle config)
- **Removed** MapSetup require, initialize, and cleanup calls from `src/server/init.server.luau`

### Docs Cleanup
- **CLAUDE.md** — Removed MapSetup from Key Modules, updated GameConfig description, rewrote Map & Obstacles section to reflect Studio-placed parts
- **docs/luau-patterns.md** — Updated Init Order pattern example to use existing modules (NPCManager, DebugService) instead of deleted MapSetup

## Files Changed

### Source
- `src/server/modules/MapSetup.luau` — **Deleted**
- `src/server/init.server.luau` — Removed MapSetup require/init/cleanup (3 lines)
- `src/shared/GameConfig.luau` — Removed `GameConfig.MAP` block (lines 52-170)

### Docs
- `CLAUDE.md` — MapSetup references removed, obstacle section rewritten
- `docs/luau-patterns.md` — Init Order example updated
- `docs/session-handoff.md` — This file

## What's Next

### House NPCs (carried forward)
1. **Add NPCs to the house** — Place pathfinding NPCs inside the suburban home to test multi-room and multi-story navigation
2. **Test staircase pathfinding** — Verify NPCs can navigate stairs between floors (may need AgentCanClimb or step height tuning)

### Debug Panel Roadmap (carried forward)
3. **Batch 2**: Force state transitions + Respawn individual NPC
4. **Batch 3**: Config overrides / tuning sliders (live walk speed, detection radius)
5. **Batch 4**: Event log (timestamped state transitions) + Player state inspector

### Separation of Concerns Follow-ups (optional)
6. **Extract behavior debug visuals** — Move waypoint marker creation from PatrolStates/GuardStates/WanderStates into DebugVisuals
7. **Type the `ctx` parameter** — Define a typed `NpcContext` interface to replace `any` in behavior states and BehaviorHelpers
8. **Remove unused Wally deps** — Promise, GoodSignal, Trove are installed but not imported

### Other
9. **Phase 1 core loop**: Player-facing UI, one complete player flow

## Blockers

None.

---

## Key Architecture Notes for Next Session

- **Obstacles are now Studio-placed, not runtime-generated.** `Workspace.Obstacles` folder with 24 parts exists in the place file. Not in source code — similar to the SuburbanHouse model.
- **BehaviorHelpers still references `Workspace.Obstacles` by name.** `getObstacleFolder()` caches `Workspace:FindFirstChild("Obstacles")` for wander raycast validation. No code changes were needed — it doesn't care how the folder got there.
- **DebugVisuals uses a getter function for callbacks.** `makeStateLabelUpdater` receives `getDebugCallback` (a function that returns the current callback) instead of the callback value directly. Late-binding pattern because NPCManager.initialize runs before DebugService.initialize.
- **House is MCP-constructed, not in source code.** The `SuburbanHouse` model exists only in the Studio place file. To rebuild, re-run the construction scripts (plan file: `.claude/plans/ethereal-wiggling-sonnet.md`).
- **Staircase pathfinding may need tuning.** Steps are 1 stud high x ~1.17 studs deep. Default agent parameters (`AgentCanClimb = false`) may not handle stairs.
- **NPCPathfinder type errors are expected.** The metatable OOP pattern (`setmetatable({}, Class)`) doesn't type-check under `--!strict`. These are false positives — ignore them.
