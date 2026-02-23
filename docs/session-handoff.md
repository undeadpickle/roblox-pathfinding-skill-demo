# Session Handoff

> Updated: 2026-02-23 (Session 8)
> Focus: Chase NPC smooth pursuit — fixed stop-start stutter, added SimplePath-inspired improvements

---

## What Got Done

- **Chase followTarget() rewrite**: Replaced sequential compute-traverse-wait loop (50% idle time) with continuous 0.1s tick loop. NPC always has an active MoveTo — no dead time between recompute cycles.
- **Event-driven waypoint advancement**: Replaced distance polling with `MoveToFinished` listener. Waypoint-to-waypoint transitions are instant instead of up to 0.1s late.
- **Stuck detection + auto-jump**: `followTarget` now tracks progress via `_lastProgressPosition`/`_lastProgressTime`. If no movement for 2s, NPC jumps and force-recomputes path. Prevents permanent wedging against geometry.
- **Jump on Path.Blocked**: `_onPathBlocked` now fires `Humanoid.Jump = true` before the deferred recompute — cheap recovery for small dynamic obstacles.
- **Waypoint visualization**: Color-coded neon spheres (orange=normal, red=jump, green=destination) at each computed waypoint. Recreated on every path recompute, destroyed on stop. Gated by `visualize` option passed from NPCManager.
- **Detection radius disc**: Red semi-transparent cylinder welded to chase NPC root part showing 50-stud detection radius. Gated by `GameConfig.GAME.DEBUG`.
- **Removed dead code**: `_traverseWaypointsNonBlocking()` deleted — replaced by the continuous loop + MoveToFinished pattern.
- **lessons-learned.md updated**: 5 new rules from this session (continuous loop vs compute-wait, MoveToFinished vs polling, arrival MoveTo, jump on blocked, stuck detection in followTarget).
- **CLAUDE.md updated**: NPC Pathfinding System section now describes the new chase architecture and all debug visuals.

## Files Changed

- `src/server/modules/NPCPathfinder.luau` — followTarget rewrite, _onPathBlocked jump, visual waypoint helpers, _traverseWaypointsNonBlocking removed
- `src/server/modules/NPCManager.luau` — detection radius disc, visualize option wired to followTarget
- `docs/lessons-learned.md` — new session entry
- `CLAUDE.md` — architecture section updated

## What's Next

1. **Playtest verification**: Rojo sync + Studio playtest to confirm smooth chase, waypoint visuals, stuck recovery, and no regressions on patrol/wander
2. **Detection radius disc orientation bug**: The disc was created but user reported not seeing it — may need CFrame debugging (cylinder orientation, ground-level positioning)
3. **Chase NPC orientation**: NPC doesn't face the player during pursuit — may need CFrame.lookAt or MoveTo direction tuning
4. **Wander radius visualization**: Debug circle for wander boundary (same pattern as detection disc)
5. **More obstacle variety**: Ramps, elevated platforms to test AgentCanJump waypoints
6. **Phase 1 core loop**: Basic UI showing game state, one complete player flow

## Blockers

- **Detection radius disc not visible** — reported by user before session was interrupted. Needs investigation (may be Y-positioning, cylinder orientation, or transparency issue).
- **Chase NPC not facing player** — reported alongside disc issue. The Humanoid steers toward MoveTo target but may not rotate fast enough or may face waypoint direction instead of target direction.

---

## Session Retrospective

### What Worked

- **SimplePath source code analysis**: Reading the actual module code (not just the forum post) revealed concrete patterns worth stealing — especially MoveToFinished-driven advancement and stuck detection. The comparison framework (what to steal vs what we do better) kept the scope focused.
- **Incremental plan → execute flow**: Planning the followTarget rewrite separately from the SimplePath improvements prevented scope creep. Each change was testable independently.
- **Existing field reuse**: `_lastProgressPosition`/`_lastProgressTime` were already in the constructor from the skill asset — just unused by followTarget. No new fields needed for stuck detection.

### What Broke

- Detection radius disc visualization not confirmed working — user reported not seeing it. Created but possibly wrong CFrame orientation or Y-offset.
- Chase NPC face orientation issue surfaced but wasn't addressed (session pivoted to SimplePath analysis).

### Wrong Assumptions

- Assumed the cylinder CFrame for the detection disc was correct without playtesting. Should have offered to verify via MCP `run_code` before moving on.

---

## Key Architecture Notes for Next Session

- **followTarget is now a 0.1s continuous loop** with MoveToFinished event for waypoint advancement. The loop handles 3 zones: arrival (MoveTo target), direct chase (LoS, skip pathfinding), and pathfinding (timer-based recompute). Stuck detection runs in the pathfinding zone only.
- **MoveToFinished connection is local** to the followTarget thread — created before the loop, disconnected on exit. Not stored on self, so no stale connection risk.
- **Visual waypoints use a clone template** (`waypointTemplate` module-level Part). Cloned per waypoint, destroyed on recompute and stop. Gated by `options.visualize`, not directly by GameConfig (keeps NPCPathfinder decoupled from GameConfig).
- **Detection radius disc is welded** to the NPC root part via WeldConstraint. Parented to Workspace (not the model) so it doesn't affect the model hierarchy.

---

## CLAUDE.md Suggestions

None — updated during this session.
