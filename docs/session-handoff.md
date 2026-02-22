# Session Handoff

> Updated: 2026-02-22 (Session 3)
> Focus: NPC playtest, bug fixes, debug tooling

---

## What Got Done

- **All 3 NPC behaviors playtested and verified working**: Chase, Patrol, and Wander all confirmed functional in Studio via MCP log analysis
- **Chase NPC frozen at spawn fix**: `_computePath` started waypoint traversal at index 1 (NPC's current position). The Y mismatch between navmesh height and HumanoidRootPart hip height caused `_traverseWaypointsNonBlocking`'s 3D distance polling to never resolve. Fixed by starting from index 2.
- **SpawnLocation collision fix**: 12x12x1 SpawnLocation with `CanCollide = true` physically blocked NPC movement. Set `CanCollide = false` via MCP (saved in place file).
- **Patrol waypoint visualization**: Yellow neon markers with numbered labels and connecting lines, gated behind `GameConfig.GAME.DEBUG`. Created in `NPCManager.createWaypointMarkers()`.
- **PathfindingUseImprovedSearch cleanup**: Removed failed script attempt to set it. Property is manual-only in Studio (already enabled and saved in place file).
- **Debug logging cycle**: Added targeted debug logs to chase system, used MCP `LogService:GetLogHistory()` to diagnose remotely, then removed all debug artifacts before committing.
- **Post-mortem completed**: 4 new lessons added to `tasks/lessons.md`, PathfindingService gotchas added to CLAUDE.md.

## What's Next

1. **Polish NPC behaviors**: Tune speeds, distances, patrol waypoints. Consider adding health bars or state indicator BillboardGuis above NPCs.
2. **Phase 1 roadmap**: Basic UI showing NPC states (chasing/patrolling/wandering/idle), one complete player flow (join > see NPCs > interact).
3. **Add obstacles**: Current map is flat baseplate. Add walls/obstacles to test pathfinding around geometry.
4. **Wander radius visualization**: Similar to patrol markers — show the wander boundary circle in debug mode.

## Blockers

- None

---

## Session Retrospective

### What Worked

- **MCP LogService diagnostics**: Used `LogService:GetLogHistory()` via `run_code` to read server Output from edit mode. Diagnosed chase freeze without user needing to paste logs. Reusable pattern for all runtime debugging.
- **Incremental debug logging**: Two rounds of targeted logs narrowed "NPC doesn't move" to "stuck on waypoint 1, Y mismatch" within minutes.
- **MCP pre-flight checks**: Verified Rojo sync, module source, baseplate geometry, and SpawnLocation properties from edit mode before asking for manual playtests. Reduced round-trips.

### What Broke

- **Chase NPC frozen at spawn**: `GetWaypoints()` returns start position as waypoint 1. `_traverseWaypointsNonBlocking` used 3D distance (3.19 studs due to hip height) which exceeded `WaypointReachDistance` (3.0). NPC timed out on waypoint 1 every cycle. Fixed by starting from index 2 in `_computePath`.
- **SpawnLocation blocking chase path**: Default `CanCollide = true` on SpawnLocation created a physical wall NPC couldn't walk over. Fixed by disabling collision (spawning uses `Enabled`, not `CanCollide`).

### Wrong Assumptions

- **Waypoint 1 would be a useful traversal target** — It's always the NPC's current XZ position at navmesh height. Standard Roblox practice is to skip it. The blocking `_traverseWaypoints` (patrol/wander) didn't expose this because `MoveToFinished:Wait()` ignores Y axis.
- **SpawnLocation is non-physical** — It's a standard Part with `CanCollide = true` by default. Anything that walks through the spawn area needs collision disabled.

---

## Quirks Discovered

- `LogService:GetLogHistory()` works from edit-mode MCP `run_code` and includes server logs from the most recent play session — powerful diagnostic shortcut.
- `MoveToFinished:Wait()` resolves based on XZ distance only. Manual `Vector3.Magnitude` checks include Y. These give different results for waypoints at different heights.
- `GetWaypoints()` waypoint 1 is always at navmesh height (Y=0), while `HumanoidRootPart` sits at hip height (Y~3.19 for R15). The 3D distance between them (~3.19 studs) can exceed `WaypointReachDistance` (3.0).

---

## CLAUDE.md Suggestions

None — CLAUDE.md was updated this session with PathfindingService gotchas section.
