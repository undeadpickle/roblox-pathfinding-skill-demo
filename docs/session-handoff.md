# Session Handoff

> Updated: 2026-02-26
> Focus: NPC Sandbox — on-demand spawning via debug panel

---

## What Got Done

- **Sandbox conversion**: Removed `initializeDemo()` — scene starts empty. NPCs spawned on-demand via debug panel buttons. Cut `SPAWN_POSITIONS`, `DISPLAY_NAME` fields, `getNPCSpawnPosition()`, `TELEPORT_TO_NPC` remote + handler + UI subsection.
- **Spawn system**: New `SPAWN_NPC` remote + handler in DebugService. Auto-naming (`Chase 1`, `Patrol 1`...) with monotonic counters. NPCs spawn 10 studs in front of player.
- **Position-relative configs**: `generateSpawnConfig()` creates waypoints/center relative to spawn position — patrol gets 20x20 square, wander gets spawn pos as center, guard gets 15-radius pentagon. Also used by SET_BEHAVIOR handler so waypoints reposition around NPC's current location.
- **Despawn controls**: Per-NPC despawn buttons (red grid) + Clear All button (calls `NPCManager.cleanup()`). New `DESPAWN_NPC` and `CLEAR_ALL_NPCS` remotes.
- **Panel redesign**: Renamed to "NPC Sandbox". New layout: Spawn (1) → Visual Toggles (2) → NPC Status (3) → Teleport (4, simplified — removed "To Spawn Zone") → Behavior (5) → Despawn (6). Spawn section deferred-built on first poll when `availableBehaviors` arrives from server.
- **CLAUDE.md updated**: Overview, key modules, NPC system, debug panel sections all reflect sandbox paradigm.

## What's Next

1. **Playtest in Studio** — Verify spawn, despawn, clear-all, behavior swap, teleport, and visual toggles all work end-to-end in play mode.
2. **NPC house placement** — Place NPCs inside the suburban house (MCP-constructed at `Workspace.SuburbanHouse`). Guard NPC patrolling hallways would showcase LOS-breaking walls.
3. **Polish** — Waypoint tag resolver utility, optional camelCase config field rename, API documentation.
4. **Branch merge** — `feat/toolkit-refactor` has accumulated significant work. Consider merging to main.

## Blockers

None.

---

## Architecture Notes

- **cleanup() → spawnNPC() cycle**: Verified safe. `cleanup()` disconnects PostSimulation tick and clears `activeNPCs`. Next `spawnNPC()` call runs `ensureTickRunning()` which reconnects it. `debugStateCallback` persists intentionally (set once by DebugService). `BehaviorHelpers.clearCache()` is safe — lazy re-populates on next use.
- **Frozen config shallow copy**: `generateSpawnConfig` uses `table.clone(baseConfig)` to copy frozen GameConfig tables before overwriting position fields. Chase config returned as-is (no position-dependent fields).
- **Spawn counters**: Module-local in DebugService, never reset within a session. Even after despawning `Chase 1`, next chase NPC is `Chase 2`. Prevents naming collisions and stale UI references.
- **Plan file**: `.claude/plans/lexical-toasting-papert.md` — full design doc for the sandbox conversion.

## CLAUDE.md Suggestions

None — updated this session.
