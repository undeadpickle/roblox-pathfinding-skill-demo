# Lessons Learned

> Specific, actionable rules discovered through session post-mortems.
> Read at session start by `/session:new-start`. Updated at session end by `/session:postmortem`.
>
> Format: `[Category] Don't X. Do Y instead because Z.`

---

## Session: 2026-02-22 — NPC Pathfinding Implementation

- **[Luau]** Don't call `stop()` from within a thread that `stop()` will `task.cancel()`. The thread kills itself mid-execution. Use a separate `_resetMovement()` method that clears state without thread cancellation.

- **[Luau]** Don't use `Humanoid:MoveTo(currentPosition)` as a "stop moving" mechanism. It fires a stale `MoveToFinished(true)` signal that subsequent `MoveToFinished:Wait()` calls catch instantly, causing rapid-fire path recomputation (77 cycles in 3.3 seconds). Clear waypoint state without issuing a MoveTo call.

- **[Luau]** Don't use `while self._isMoving` as a patrol loop condition when `moveTo()` sets `_isMoving = false` on return. The loop exits after one waypoint. Use `while not self._isDestroyed` and re-assert `_isMoving = true` before each `moveTo` call. External callers use `stop()` with `task.cancel()` as the exit mechanism.

- **[Roblox]** Don't try to enable `PathfindingUseImprovedSearch` via script or MCP. It must be set manually in Studio: Workspace > Properties > PathfindingUseImprovedSearch > Enabled.

- **[MCP]** Don't assume all MCP servers register tools in Claude Code's tool system. The boshyxd `robloxstudio-mcp` works via HTTP API (`curl localhost:3003/mcp/*`), not through Claude Code tool calls. Check health with `curl localhost:3003/health`.

- **[MCP]** Don't assume `npx`-based MCP servers start fast enough for Claude Code's handshake. They can timeout during startup (downloading package). If reliability matters, pre-install globally (`npm install -g`) and point to the binary directly.

- **[Tooling]** Don't assume Rojo sync is working just because `rojo serve` is running. Studio can lose the connection silently. Use MCP (`run_code`) to verify files actually exist in the Explorer before debugging code logic.

- **[Roblox]** Don't use `Instance.new("Part", parent)` — the second arg parents immediately, causing per-property replication. Set all properties first, then `.Parent` last in a single replication packet.

- **[Workflow]** Don't debug code logic when files aren't appearing in Studio. Verify Rojo sync first via MCP (`run_code` to check Explorer), since Studio can silently lose the Rojo connection.

- **[Architecture]** Don't adapt a skill asset module without tracing all method call graphs first. The `moveTo` → `stop` → `task.cancel` self-reference was only visible by reading the full method chain.

- **[Debug]** Don't assume rapid-fire repeated log messages are a logic error in a loop. Check for stale signals/events first — a `MoveToFinished` fired by `MoveTo(currentPos)` was being caught by subsequent `:Wait()` calls.

## Session: 2026-02-22 — NPC Playtest & Bug Fixes

- **[Roblox]** Don't start waypoint traversal at index 1 from `GetWaypoints()`. Waypoint 1 is always the NPC's current position. Start from index 2 to avoid getting stuck on a same-XZ waypoint where Y mismatch (navmesh height vs hip height) fails distance checks.

- **[Roblox]** Don't mix `MoveToFinished:Wait()` and manual 3D distance checks for waypoint arrival. `MoveToFinished` resolves on XZ distance only (ignoring Y), while `Vector3.Magnitude` includes Y. A waypoint directly below the NPC (same XZ, different Y) passes `MoveToFinished` instantly but fails a 3D distance threshold.

- **[Roblox]** Don't leave `SpawnLocation.CanCollide = true` when NPCs path through the spawn area. SpawnLocation is a physical part that blocks movement. Spawning behavior uses the `Enabled` property, not `CanCollide` — safe to disable collision.

- **[MCP]** Don't ask users to paste console output. Use `LogService:GetLogHistory()` via MCP `run_code` to read server logs from edit mode, even after play mode ends. Faster and more complete than screenshots.

## Session: 2026-02-22 — GC Audit & State Machine

- **[Architecture]** Don't add new behavior systems on top of leaky infrastructure. Audit GC/cleanup first — the audit found 2 critical leaks (untracked `PlayerAdded` connection, untracked waypoint marker folder) that would have compounded with the state machine refactor.

- **[Architecture]** Don't manage NPC behavior transitions with boolean flags and `PlayerAdded` connections. Use a state machine — the Idle state's `onUpdate` naturally handles "waiting for player" without special-case logic, and `getCurrentState()` makes behavior queryable for debug UI.
