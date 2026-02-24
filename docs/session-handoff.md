# Session Handoff

> Updated: 2026-02-24 (Session 13)
> Focus: Debug panel feature prioritization, perf strip, enhanced teleport

---

## What Got Done

### Feature Prioritization

- Evaluated 20 debug panel feature ideas against the project (solo NPC pathfinding prototype)
- Cut 12 features that don't apply (no production, no noise system, no multiplayer, no custom camera, no UI yet, etc.)
- Produced ranked top 10 with implementation plan in 5 batches — saved to `.claude/plans/harmonic-sauteeing-torvalds.md`

### Batch 1: Perf Strip + Enhanced Teleport

- **Performance strip** (always visible, top-left): FPS, frame time (ms), instance count. Color-coded green/yellow/red by frame time thresholds (16ms/33ms). Instance count polls every 3s. Independent of F8 panel toggle.
- **Enhanced teleport** — 3 modes in the Teleport section:
  - "To Spawn Zone" — existing behavior (unchanged)
  - "To NPC (Current Pos)" — teleports player near NPC's live position
  - "Summon NPC to Me" — stops NPC pathfinder, teleports NPC to player's position
- **New NPCManager API**: `getNPCPosition(displayName)`, `teleportNPC(displayName, position)` — `teleportNPC` calls `pathfinder:stop()` before `PivotTo` so movement doesn't fight the teleport.
- **New DebugPanelUI factories**: `createPerfStrip()`, `createSubLabel()` — sub-labels used to organize teleport section into labeled groups.

## Files Changed

- `src/client/modules/DebugPanel.luau` — Perf strip wiring (RenderStepped + instance count timer), 3 teleport sub-sections
- `src/client/modules/DebugPanelUI.luau` — `createPerfStrip()`, `createSubLabel()` factory functions
- `src/server/modules/DebugService.luau` — `TELEPORT_TO_NPC_CURRENT`, `TELEPORT_NPC_TO_PLAYER` handlers
- `src/server/modules/NPCManager.luau` — `getNPCPosition()`, `teleportNPC()` public methods
- `src/shared/DebugRemotes.luau` — 2 new remote constants
- `CLAUDE.md` — Updated NPCManager methods list, debug panel description, added perf strip docs

## What's Next

### Debug Panel Roadmap (from prioritized plan)

1. **Batch 2**: Force state transitions + Respawn individual NPC
2. **Batch 3**: Config overrides / tuning sliders (live walk speed, detection radius)
3. **Batch 4**: Event log (timestamped state transitions) + Player state inspector
4. **Batch 5**: NPC tick health dashboard + Noclip/fly mode

### Other

5. **More elevation variety**: Ramps, platforms, multi-level terrain
6. **Phase 1 core loop**: Player-facing UI, one complete player flow

## Blockers

None.

---

## Key Architecture Notes for Next Session

- **Force state transitions (Batch 2)**: `NPCStateMachine` has `transitionTo(stateName)` already. Gotcha: forcing Guard into Chasing without a target — `onEnter` expects `ctx.guardTarget`. Need to auto-assign nearest player or warn.
- **Respawn NPC (Batch 2)**: Per-NPC cleanup path exists in `NPCManager.cleanup()`. Need to extract into reusable `spawnAndConfigureNPC(behaviorType)` — the monolithic `initialize()` does all 4 inline currently.
- **Config sliders (Batch 3)**: `GameConfig` is frozen (`table.freeze`). Sliders must set values on runtime objects directly. Detection radius needs a `ctx.detectionRadiusOverride` field (same pattern as `_wanderBeamVisible`).
- **Perf strip**: Lives in its own ScreenGui (`PerfStrip`, DisplayOrder 101), always enabled. Labels updated via RenderStepped (FPS/frame time) and spawned task (instance count, 3s).
- **Teleport NPC to player**: Calls `pathfinder:stop()` before `PivotTo`. State machine picks up from new position naturally since states read `rootPart.Position` each tick.

---

## CLAUDE.md Suggestions

None — updated during this session.
