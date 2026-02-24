# Session Handoff

> Updated: 2026-02-23 (Session 11)
> Focus: Debug Panel MVP — live NPC status, visual toggles, teleport, state change push

---

## What Got Done

- **Debug Panel MVP**: Full client-side debug panel with 3 sections: Visual Toggles, NPC Status, Teleport. Toggle with F8 key. Raw Roblox UI (no framework).
- **4 new files**: `DebugRemotes.luau` (shared remote name constants), `DebugService.luau` (server remote handlers), `DebugPanelUI.luau` (UI factories), `DebugPanel.luau` (client logic).
- **NPCManager debug API**: Added `getAllNPCStatus(playerPos)`, `setDebugVisualEnabled(npcName, visualType, enabled)`, `setDebugStateCallback(callback)`. Status returns state, position, distance, LOS, isMoving, walkSpeed, detectionRadius, behaviorType per NPC.
- **Hybrid polling + push**: Client polls server every 0.5s for full status data. State changes pushed instantly via `NPC_STATE_CHANGED` RemoteEvent for immediate label updates.
- **Per-visual toggles**: 4 toggle types — detection discs (transparency), state labels (BillboardGui.Enabled), waypoint markers (folder children), wander beam (flag + instances). Each toggle fires for all NPCs.
- **Teleport buttons**: 2x2 grid teleporting player to each NPC's spawn zone with 5-stud offset.
- **Wander beam toggle persistence**: Added `_wanderBeamVisible` flag to NPCEntry so beam/marker toggle state survives state cycle recreation.
- **State change callback chaining**: Modified `makeStateLabelUpdater` to accept `npcName` param and chain a debug callback alongside the in-world label updater.
- **Guard Returning dwell time**: Added `RETURN_DWELL = 0.8` config so Returning state is observable in the debug panel (was completing in 1-2 frames).
- **F9→F8 key change**: F9 conflicts with Roblox Developer Console in Studio play mode. Changed to F8.
- **Pre-mortem caught 3 issues**: Single callback blocker, wander beam persistence risk, RemoteFunction validator mismatch.

## Files Changed

- `src/shared/DebugRemotes.luau` — **NEW** — Remote name string constants
- `src/server/modules/DebugService.luau` — **NEW** — Server remote handlers (status, toggle, teleport, state push)
- `src/client/modules/DebugPanelUI.luau` — **NEW** — UI factory functions (panel, sections, toggles, status rows, buttons, teleport grid)
- `src/client/modules/DebugPanel.luau` — **NEW** — Client panel logic (polling, toggles, teleport, F8 key binding)
- `src/server/modules/NPCManager.luau` — Added debug API methods, wander beam flag, state callback chaining, Guard return dwell
- `src/shared/GameConfig.luau` — Added `GUARD.RETURN_DWELL = 0.8`
- `src/client/init.client.luau` — Wired DebugPanel.initialize()
- `src/server/init.server.luau` — Wired DebugService.initialize() after NPCManager
- `docs/lessons-learned.md` — 5 new rules (F9 conflict, onInvoke validator, callback chaining, beam persistence, dwell time)
- `CLAUDE.md` — Updated overview, key modules, debug panel architecture notes

## What's Next

1. **Debug panel follow-up**: Force state transitions, respawn individual NPCs, tuning sliders (walk speed, detection radius, patrol pause)
2. **Playtest verification**: Stairs pathfinding, NPC orientation during chase, wander beam rendering
3. **More elevation variety**: Ramps, platforms, multi-level terrain
4. **Phase 1 core loop**: Player-facing UI (Fusion candidate), one complete player flow

## Blockers

None.

---

## Session Retrospective

### What Worked

- **Pre-mortem prevented 3 bugs**: The `onStateChanged` single-callback blocker (would have overwritten in-world label updater), wander beam toggle not persisting across state cycles (would silently reset on each wander loop), and `Remotes.onInvoke` validator mismatch (no client data to validate).
- **Reusing GameConfig patterns**: `UI.COLORS`, `UI.FONTS`, `STATE_LABEL.COLORS` — all existed but were unused. Debug panel gave them consumers without adding new config.
- **`isMoving()` found its purpose**: NPCPathfinder's `isMoving()` was flagged as unused in cleanup. Debug panel status readout now uses it.
- **Clean client-server separation**: Server is source of truth. Client is a dumb terminal — sends commands, displays data, never touches NPC state directly.

### What Broke

- **F9 key conflict**: F9 opens Roblox Developer Console in Studio play mode. Was predicted in plan gotchas, confirmed by user screenshot. Switched to F8.
- **Guard Returning state invisible**: Returning completed in 1-2 frames when guard was near a waypoint. `moveTo` resolved nearly instantly, and the push event was overwritten by the next state. Fixed with `RETURN_DWELL = 0.8s` minimum.

### Wrong Assumptions

- Assumed F9 was safe despite noting the potential conflict in the plan. Should have defaulted to F8 from the start.
- Assumed instant state transitions would be observable in a 0.5s polling UI. Even with push events, transitions under ~2 frames are effectively invisible in the panel.

---

## Key Architecture Notes for Next Session

- **Debug panel toggle**: F8 key. Panel starts hidden (`ScreenGui.Enabled = false`). Polling starts/stops with panel visibility.
- **Remote architecture**: `DebugRemotes.luau` holds string constants. `Remotes.getEvent()`/`getFunction()` used for all communication. No custom remote creation — reuses existing Remotes module.
- **Visual toggle types**: `"disc"` (transparency), `"stateLabel"` (BillboardGui.Enabled), `"waypoints"` (folder children toggle), `"wanderBeam"` (flag + instance toggle). Applied per-NPC from server.
- **State push callback**: `NPCManager.setDebugStateCallback()` stores a module-level callback. `makeStateLabelUpdater` chains it with the in-world label updater. No changes to NPCStateMachine needed.
- **Guard dwell**: `RETURN_DWELL = 0.8` in GameConfig. Returning `onUpdate` accumulates `guardReturnDwell` timer after waypoint reached before transitioning to Guarding.
- **Follow-up scope**: Force state transitions (`stateMachine:transitionTo()`), respawn NPCs (extract spawn logic), tuning sliders (`_override` fields on NPCEntry).

---

## CLAUDE.md Suggestions

None — updated during this session.
