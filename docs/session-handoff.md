# Session Handoff

> Updated: 2026-02-27
> Focus: NPC Humanoid Animations

---

## What Got Done

- **NPCAnimator module**: Created signal-driven animation controller (`src/server/modules/NPCAnimator.luau`, 170 lines). Loads idle/walk/run/jump/fall tracks from config, driven by `Humanoid.Running` + `Humanoid.StateChanged`. Returns cleanup closure. Zero coupling to state machines or pathfinder.
- **GameConfig animation config**: Added `NPC.ANIMATIONS` table with default R15 asset IDs, fade time (0.15s), and run speed threshold (8 studs/s).
- **NPCManager integration**: 5 small additions — require, type field, setup call in `registerEntry`, cleanup calls in `despawnNPC` and `cleanup`.
- **Docs updated**: CLAUDE.md (NPCAnimator in Key Modules, animation description in NPC Pathfinding System), lessons-learned.md (1 new lesson).

## What's Next

1. **Extended playtest** — Verify all 4 NPC types animate correctly in various scenarios (spawn, despawn, behavior swap, clear-all, obstacle navigation). Check for walk/idle flicker during `stop()` calls.
2. **NPC house placement** — Place NPCs inside the suburban house (`Workspace.SuburbanHouse`). Guard NPC patrolling hallways would showcase LOS-breaking walls + animations together.
3. **Branch merge** — `feat/toolkit-refactor` has 7+ unpushed commits of significant work. Consider merging to main.
4. **Polish** — Waypoint tag resolver utility, optional camelCase config field rename, API documentation.

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Research-first with parallel agents**: Two Explore agents (animation docs + codebase analysis) gave comprehensive understanding before any code was written. No mid-implementation surprises.
- **Signal-driven architecture**: `Humanoid.Running` handles all movement sources automatically — patrol pauses, wander delays, chase pursuit, guard returns — without touching any behavior modules. Cleanest possible integration.
- **Pre-mortem review**: Caught `MoveTo(currentPosition)` flicker risk and `Humanoid.Running` reliability concern before implementation. Both turned out fine in practice.

### What Broke

- **MCP validation in edit mode**: Attempted to validate `Humanoid.Running` via MCP `run_code` but Studio was in edit mode, not play mode. Wasted 4 MCP calls. Fix: check `RunService:IsRunning()` first.

### Wrong Assumptions

- **"Playtest is running" ambiguity**: Assumed user had Studio in play mode; they had it open in edit mode. Lesson: verify programmatically, don't rely on verbal confirmation.

---

## Architecture Notes

- **NPCAnimator is stateless**: No internal registry. Each `setup()` call returns a self-contained cleanup closure stored on the NPCEntry as `_animCleanup`. This means behavior swaps (`setBehavior`) don't need to touch animations — the Humanoid signals keep firing regardless of which state machine is running.
- **Walk vs run threshold**: `RUN_SPEED_THRESHOLD = 8` in GameConfig. `Humanoid.Running` reports actual movement speed. Chase NPCs (WalkSpeed 4) always walk-animate, guard NPCs (WalkSpeed 10) run-animate. Patrol/wander use default WalkSpeed (16) so they run-animate.
- **Animation priorities**: Idle < Movement < Action. Jump/fall at Action priority naturally override walk/idle without manual stop calls.

## CLAUDE.md Suggestions

None — updated this session.
