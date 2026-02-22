# Session Handoff

> Updated: 2026-02-22 (Session 2)
> Focus: NPC pathfinding implementation + post-mortem system

---

## What Got Done

- **NPC pathfinding system implemented**: NPCPathfinder module (adapted from skill asset), NPCManager (spawn + behavior), GameConfig NPC section, wired into server init
- **3 NPC behaviors**: Chase (follows nearest player), Patrol (loops 4 waypoints), Wander (random points in radius)
- **Critical bug fix**: Thread self-cancellation in `moveTo` → `stop` → `task.cancel` chain. Fixed with `_resetMovement()` separation. Also fixed stale `MoveToFinished` signal and patrol loop lifecycle.
- **MCP troubleshooting**: Official Roblox MCP working via tools. boshyxd MCP working via HTTP API (`curl localhost:3003/mcp/*`), does not register Claude Code tools.
- **Post-mortem system built**: `/session:postmortem` command, `tasks/lessons.md` (11 lessons), updated wrapup flow and session-lifecycle rules
- **CLAUDE.md updated**: Overview, key modules, NPC system docs, MCP server reference

## What's Next

1. **Playtest NPC behaviors**: Bug fixes applied but not yet verified in Studio. All 3 NPCs need re-testing — chase should re-engage, patrol should loop all 4 waypoints, wander should move to random points with pauses.
2. **Enable PathfindingUseImprovedSearch**: Must be set manually in Studio (Workspace > Properties). Reduces NPC zig-zagging.
3. **Polish if behaviors work**: Tune speeds, distances, patrol waypoints. Add visual feedback (health bars, state indicators).
4. **Phase 1 roadmap**: Basic UI showing NPC states, one complete player flow.

## Blockers

- NPC behavior fixes untested — need a playtest to verify

---

## Session Retrospective

### What Worked

- **MCP for sync verification**: Used `run_code` to confirm Rojo sync was broken before debugging code logic
- **Console log pattern analysis**: "reached point x77 in 3.3s" revealed stale signal bug immediately
- **Cross-project knowledge**: Pop-Shot-Paradise's MCP setup notes solved boshyxd troubleshooting
- **Skill asset as starting point**: `roblox-npc-pathfinding` skill provided solid NPCPathfinder base

### What Broke

- **Thread self-cancellation**: `moveTo()` called `stop()` which killed its own calling thread via `task.cancel`. Fixed with `_resetMovement()`.
- **Stale MoveToFinished signal**: `stop()` called `MoveTo(currentPosition)` firing a fake arrival signal. Fixed by not issuing MoveTo in reset.
- **Rojo sync lost silently**: Studio disconnected without error. Fixed by reconnecting plugin.
- **boshyxd MCP tools not in Claude Code**: npx startup too slow for handshake. Works via HTTP API instead.

### Wrong Assumptions

- **`MoveTo(currentPosition)` would be a safe halt** — it fires `MoveToFinished(true)` instantly, poisoning subsequent waits
- **All MCP servers expose tools through Claude Code** — boshyxd only works via HTTP

---

## Quirks Discovered

- `PathfindingUseImprovedSearch` cannot be set via script or MCP — manual Studio property only
- boshyxd MCP health endpoint: `curl localhost:3003/health` — shows `pluginConnected` and `mcpServerActive` status
- `Players:CreateHumanoidModelFromDescription()` creates R15 rigs from script without pre-built models
- `SetNetworkOwner(nil)` gives server physics authority over parts

---

## CLAUDE.md Suggestions

None — CLAUDE.md was updated during postmortem and is current.
