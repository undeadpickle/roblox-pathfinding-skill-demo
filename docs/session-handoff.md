# Session Handoff

> Updated: 2026-02-23 (Session 9)
> Focus: Detection disc visibility fix, NPC orientation fix, debug logging, wander beam visualization, staircase obstacle

---

## What Got Done

- **Detection disc fix**: Root cause was missing `Massless = true` on a 100-stud diameter cylinder welded to the NPC (~1,100 mass units vs ~25 for the humanoid). Switched from WeldConstraint to anchored Part with explicit CFrame update in PostSimulation tick. Added `CastShadow = false`, tuned transparency to 0.85, positioned at Y=0.15.
- **NPC orientation fix**: Resolved by removing the massive welded disc. `Humanoid:MoveTo()` now rotates the assembly correctly since the physics assembly has sane mass/inertia.
- **Chase NPC tuning**: Reduced `WALK_SPEED` from 24 to 4 and `DETECTION_RADIUS` from 50 to 10 for easier testing.
- **Debug zone logging**: Added throttled (2s interval) log messages in `followTarget` for each movement zone (Arrival, DirectChase, Pathfinding) with distance and waypoint count.
- **State transition logging**: Added `log:debug` in `makeStateLabelUpdater` — all NPC state changes are now logged.
- **Wander beam visualization**: Green Beam from wander NPC to its current target + green marker sphere at destination. Uses Attachment pairs (one on rootPart, one on target marker). Gated by `GameConfig.GAME.DEBUG`, cleaned up in `onExit`.
- **Staircase obstacle**: Extended MapSetup to support `type = "staircase"` config entries. Added 8-step staircase at (45, 0, 10) ascending in +Z, northeast of chase NPC spawn. Each step is 6×1×2 studs.
- **Lessons learned**: 4 new rules (anchored vs welded debug visuals, Luau format specifiers, CastShadow on debug parts, Massless on welded parts).
- **CLAUDE.md updated**: Architecture sections updated for new debug visuals, staircase support, and current chase config values.

## Files Changed

- `src/server/modules/NPCManager.luau` — Detection disc rewrite (anchored + tick-updated), wander beam visualization, state transition logging
- `src/server/modules/NPCPathfinder.luau` — Zone logging in followTarget
- `src/server/modules/MapSetup.luau` — Staircase type support
- `src/shared/GameConfig.luau` — Chase speed/radius tuning, staircase obstacle entry
- `docs/lessons-learned.md` — 4 new rules
- `CLAUDE.md` — Architecture updates

## What's Next

1. **Playtest stairs**: Verify chase NPC can pathfind up the staircase when pursuing a player (AgentCanJump should handle 1-stud steps)
2. **NPC orientation verification**: Confirm the NPC now faces the direction of movement during all chase zones (was fixed by removing welded disc mass, but not yet verified in playtest)
3. **Wander beam verification**: Confirm the green beam and target marker render correctly during playtest
4. **More elevation variety**: Ramps, platforms, multi-level terrain to further test vertical pathfinding
5. **Phase 1 core loop**: Basic UI showing game state, one complete player flow

## Blockers

None — all previous blockers (disc visibility, NPC orientation) have been addressed. Pending playtest verification.

---

## Session Retrospective

### What Worked

- **Root cause analysis on disc mass**: Calculating the actual mass (π × 50² × 0.2 × 0.7 ≈ 1,100 vs humanoid ~25) immediately explained both the orientation AND visibility bugs from a single cause. Physics reasoning before code changes saved iteration cycles.
- **Switching from weld to anchored + tick**: Eliminated all physics edge cases (weld activation timing, mass interference, gravity on unanchored parts). More predictable and easier to debug.
- **Beam for wander visualization**: Roblox Beam + Attachment pairs provide a clean dynamic line that automatically follows the NPC without per-frame updates for the line itself. Only the target marker position needs updating.

### What Broke

- **Luau format specifiers**: Used Python-style `:.1f` in interpolated strings, which caused 32 parse errors. Luau interpolation only supports raw expressions. Caught by selene before reaching Studio.
- **Disc Y positioning**: First attempt at Y=0.15 was partially underground. Raised to Y=0.5, then user requested back to Y=0.15 — still works with the anchored approach since there's no physics bob from walking animation affecting it.

### Wrong Assumptions

- Assumed Luau string interpolation supported format specifiers like Python f-strings. Should have checked Luau docs first.
- Initially assumed the disc's WeldConstraint approach was correct — should have recognized the mass problem earlier (it was a 100-stud Part welded to a character).

---

## Key Architecture Notes for Next Session

- **Detection disc is now anchored** (not welded). Its CFrame is explicitly set in the PostSimulation tick loop in NPCManager. Y is fixed at 0.15 regardless of NPC elevation.
- **Wander beam uses Attachment pairs**: npcAttachment on rootPart (contains the Beam child), targetAttachment on targetMarker. Destroying npcAttachment cascades to Beam. Destroying targetMarker cascades to targetAttachment.
- **MapSetup staircase type**: `type = "staircase"` in obstacle config generates individual step Parts. Steps ascend in +Z direction from the base position. Each step offset: `(0, i * stepHeight + stepHeight/2, i * stepDepth + stepDepth/2)`.
- **Chase config is tuned low for testing**: WALK_SPEED=4, DETECTION_RADIUS=10. Will need to be raised for gameplay.

---

## CLAUDE.md Suggestions

None — updated during this session.
