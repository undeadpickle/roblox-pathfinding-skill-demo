# Session Handoff

> Updated: 2026-02-26
> Focus: Phase 2 — Dynamic debug panel, spawn position fix, setBehavior UI

---

## What Got Done

- **Dynamic debug panel**: Replaced hardcoded `NPC_ORDER` (4 demo NPCs) with server-driven dynamic list. Panel rebuilds status/teleport/behavior sections automatically when NPCs are spawned or despawned. Diff logic in poll loop detects add/remove by comparing display names.
- **Spawn position fix**: `TELEPORT_TO_NPC` handler now reads `NPCEntry.spawnPosition` via `NPCManager.getNPCSpawnPosition()` instead of `GameConfig.NPC.SPAWN_POSITIONS[key]`. Works for dynamic NPCs. Removed GameConfig dependency from DebugService (re-added for behavior defaults).
- **setBehavior UI**: New "Behavior" section in debug panel with per-NPC button rows (Chase, Patrol, Wander, Guard). Active behavior highlighted. Buttons fire `SET_BEHAVIOR` remote. Server supplies default GameConfig per behavior type to prevent nil field crashes from incompatible configs.
- **Visual toggle persistence**: Added `visualToggleStates` map tracking toggle state. `syncToggleStatesToNPCs()` fires after every rebuild so newly spawned NPCs get correct visual state.
- **Config compatibility fix**: DebugService SET_BEHAVIOR handler always passes `defaultBehaviorConfigs[behaviorType]` (from GameConfig) to `NPCManager.setBehavior()`, preventing crashes when swapping between behaviors with different required fields.

## What's Next

1. **Phase 3: Polish** — Waypoint tag resolver utility, optional camelCase config field rename, API documentation. Files: various across `src/server/modules/` and `src/shared/`
2. **NPC house placement** — Place NPCs inside the suburban house (MCP-constructed at `Workspace.SuburbanHouse`). Guard NPC patrolling hallways would showcase LOS-breaking walls.
3. **Branch merge** — `feat/toolkit-refactor` has accumulated significant work. Consider merging to main when ready.

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Pre-mortem before implementation**: Caught the Task 2→Task 1 sequencing issue (server expects displayName but client still sends config key) before it could break teleport-to-spawn between tasks. Also identified the visual toggle state persistence gap.
- **Plan-first with parallel explore agents**: Two agents mapped the full debug panel architecture (client data flow, remote contracts, hardcoded assumptions) in parallel before writing any code. Zero ambiguity during implementation.
- **Reusing existing patterns**: `getNPCSpawnPosition` followed `getNPCPosition`'s exact pattern. `createBehaviorRow` reused `createTeleportGrid`'s grid layout. Diff/rebuild kept the poll loop simple.

### What Broke

- **Config compatibility crash on behavior swap**: Swapping Chase NPC to Guard hit `attempt to compare number < nil` on `GuardStates:57` (`ctx.behaviorConfig.DETECT_INTERVAL`). Root cause: `setBehavior` reuses existing config when none provided, but guard needs fields (DETECT_INTERVAL, PATROL_PAUSE, WAYPOINTS) that chase config lacks. Fixed by having DebugService always supply default GameConfig for the target behavior type.

### Wrong Assumptions

- **"NPC just stands still" on incompatible config**: The plan assumed missing config fields would cause graceful degradation. In reality, guard's `onUpdate` does `ctx.guardDetectTimer < ctx.behaviorConfig.DETECT_INTERVAL` on every frame — nil comparison is a hard crash, not silent failure.

---

## Architecture Notes

- **Plan file**: `.claude/plans/reflective-mapping-whisper.md` — Phase 2 design decisions, pre-mortem results, all three task specs.
- **Poll-driven rebuild**: `diffNPCList()` extracts sorted NPC list from status response, compares by display name only (behavior changes don't trigger rebuild — handled by per-poll highlight sync instead).
- **`_meta` convention**: Status response includes `result._meta = { availableBehaviors = {...} }`. Client skips `_meta` key in NPC iteration. Won't collide with NPC display names.
- **Default config pattern**: DebugService maintains `defaultBehaviorConfigs` map (behavior type → GameConfig section). `NPCManager.setBehavior` stays config-agnostic; the "smart defaults" live in the convenience layer.

## CLAUDE.md Suggestions

None — updated this session to reflect all changes.
