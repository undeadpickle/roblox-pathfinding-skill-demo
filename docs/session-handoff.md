# Session Handoff

> Updated: 2026-02-22 (Session 5)
> Focus: Obstacle system, chase speed tuning, wander NPC stability fixes

---

## What Got Done

- **Obstacle system**: New `MapSetup` module reads `GameConfig.MAP.OBSTACLES` and spawns anchored Parts in a `Workspace.Obstacles` folder. PathfindingService auto-carves them from the navmesh.
- **14 obstacles placed**: Center wall (bisects map), 3 patrol leg walls (south/west/north), L-shaped barrier near chase spawn, 8 wander zone obstacles (6 blocks + 2 walls).
- **Chase NPC speed**: Added `WALK_SPEED = 24` to chase config (50% faster than default 16). Applied to humanoid after spawn.
- **Wander NPC stability**: Fixed two bugs causing stuck/fallen NPCs:
  - Re-enabled `FallingDown`/`GettingUp`/`Freefall`/`Landed` humanoid states — they were disabled as a flat-baseplate optimization but NPCs need the physics recovery cycle around obstacles.
  - `getRandomPointInRadius` now raycasts down to reject points inside obstacle footprints and snaps Y to actual ground height.
- **Cleanup audit**: Subagent audit confirmed no memory/connection/thread leaks. One fix: cached `Workspace:FindFirstChild("Obstacles")` lookup to avoid per-attempt overhead in wander retry loop.
- **Logger bug fix**: MapSetup originally called `Logger.info()` statically instead of creating an instance. The error was silently swallowed by the `pcall` in init.server.luau, which also prevented NPCManager from loading.
- **Post-mortem completed**: 4 new lessons in `tasks/lessons.md`, CLAUDE.md updated with MapSetup module, Map & Obstacles architecture section, and humanoid state gotcha.

## What's Next

1. **Phase 1 UI**: BillboardGuis showing NPC state names above heads. `stateMachine:getCurrentState()` is already exposed. Relevant files: `src/server/modules/NPCManager.luau`
2. **Wander radius visualization**: Debug circle showing wander boundary, similar to patrol waypoint markers. Gate behind `GameConfig.GAME.DEBUG`.
3. **Polish NPC behaviors**: Tune detection distances, patrol waypoints. Consider health bars.
4. **More obstacle variety**: Ramps, elevated platforms to test `AgentCanJump` waypoints.

## Blockers

- None

---

## Session Retrospective

### What Worked

- **Config-driven obstacle spawning**: Defining obstacles in GameConfig and creating via MapSetup kept everything version-controllable. PathfindingService handles navmesh carving automatically — zero pathfinder code changes.
- **Subagent cleanup audit**: Thorough Explore agent confirmed no leaks and caught the `FindFirstChild` per-attempt overhead.
- **Raycast validation for wander targets**: Clean solution that both avoids obstacles and provides accurate Y-snapping to ground height.

### What Broke

- **Logger static call killed all NPCs**: `Logger.info()` instead of `log:info()` errored inside `pcall`, silently preventing NPCManager initialization. The single `pcall` error boundary in init.server.luau masked the failure.
- **Wander NPC fell over permanently**: Disabled humanoid recovery states (`FallingDown`/`GettingUp`) prevented NPCs from recovering after obstacle collisions.
- **Wander NPC stuck in floor**: Random target points landed inside obstacle geometry. No validation existed before obstacles were added.
- **Patrol blocker missed the path**: Original placement was inside the patrol rectangle but not on any actual patrol leg. Required re-analysis of exact waypoint coordinates.

### Wrong Assumptions

- Assumed `_disableUnusedStates` optimization would remain safe when obstacles were added. It was environment-dependent.
- Assumed random point generation on a flat baseplate would work the same with obstacles. Needed obstacle-aware validation.

---

## Key Architecture Notes for Next Session

- **MapSetup runs before NPCManager** in init.server.luau so navmesh includes obstacles on first path computation.
- **Obstacle folder cached** in NPCManager (`cachedObstacleFolder`) — cleared in `cleanup()`.
- **Wander point generation** retries up to 10 times, falling back to center if all attempts hit obstacles.
- **Chase NPC WalkSpeed** set on humanoid after spawn, driven by `GameConfig.NPC.CHASE.WALK_SPEED`.
- **Physics recovery states** (`FallingDown`, `GettingUp`, `Freefall`, `Landed`) are now kept enabled in `_disableUnusedStates`.

---

## CLAUDE.md Suggestions

None — CLAUDE.md was updated this session with MapSetup in Key Modules, Map & Obstacles architecture section, and humanoid state gotcha.
