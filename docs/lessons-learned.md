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

## Session: 2026-02-22 — Obstacle System

- **[Luau]** Don't call Logger methods with dot syntax (`Logger.info()`). Logger uses instances — always `Logger.new("ModuleName")` then `log:info()`. The colon vs dot distinction causes a runtime error, not a type error.

- **[Architecture]** Don't wrap multiple module initializations in a single `pcall` without checking intermediate results. In `init.server.luau`, a `MapSetup` error silently prevented `NPCManager` from loading. If modules must share one `pcall`, log each module's init separately so failures are visible.

- **[Roblox]** Don't disable `FallingDown`/`GettingUp`/`Freefall`/`Landed` humanoid states when the NPC operates around physical obstacles. These states form the physics recovery cycle — without them, a knocked-over NPC stays down permanently. Only disable on flat geometry with no collision risk.

- **[Architecture]** Don't generate random NPC movement targets without validating against obstacle geometry. Use `Workspace:Raycast` downward to confirm the point is on walkable ground, not inside/on top of an obstacle. Also use the raycast hit position for accurate Y-snapping.

## Session: 2026-02-23 — Docs Audit vs Lessons Learned

- **[Docs]** Don't assume skill reference docs stay in sync with lessons learned. The SKILL.md quick start code iterated all waypoints (`for _, waypoint in waypoints do`) while lessons explicitly said to skip index 1. Periodically audit skill assets, conventions, and patterns docs against accumulated lessons to catch contradictions.

## Session: 2026-02-23 — Chase NPC Smooth Pursuit & SimplePath Patterns

- **[Pathfinding]** Don't use sequential compute-traverse-wait loops for chase behavior. The pattern `_computePath() → _traverseWaypointsNonBlocking(0.4s) → task.wait(0.5s)` creates ~50% idle time where no MoveTo is active. Use a continuous 0.1s tick loop that always has an active MoveTo and recomputes on a timer without stopping movement.

- **[Pathfinding]** Don't poll waypoint distance for advancement in a chase loop. `Humanoid.MoveToFinished` fires the instant the Humanoid reaches its MoveTo target — zero latency. Distance polling at 0.1s intervals can miss or overshoot waypoints at WalkSpeed 24 (2.4 studs/tick). Use MoveToFinished for waypoint-to-waypoint progression, keep the tick loop for recomputation and zone management.

- **[Pathfinding]** Don't call `MoveTo(self._rootPart.Position)` as an arrival stop. It fires a stale `MoveToFinished(true)` signal and makes the NPC visibly freeze. Use `MoveTo(targetPos)` at arrival distance so the NPC keeps facing and drifting toward the target.

- **[Pathfinding]** Don't rely only on path recomputation when `Path.Blocked` fires. Try `Humanoid.Jump = true` first — it's cheaper and often clears small dynamic obstacles without needing a full `ComputeAsync` cycle.

- **[Roblox]** Don't forget stuck detection in `followTarget`. The `_lastProgressPosition`/`_lastProgressTime` fields existed but were only used by `_traverseWaypoints` (blocking patrol). Chase loops need their own stuck check with a shorter threshold (2s vs 8s) since chase demands responsiveness.

## Session: 2026-02-23 — Detection Disc & NPC Orientation Fix

- **[Roblox]** Don't weld large Parts to a Humanoid's RootPart without `Massless = true`. A 100-stud diameter cylinder has ~1,100 mass units vs the Humanoid's ~25. The massive inertia prevents `MoveTo()` from rotating the assembly (NPC faces sideways) and can destabilize physics rendering (disc invisible). Always set `Massless = true` on debug/visual Parts welded to characters.

- **[Roblox]** Don't use WeldConstraint for debug visualizations that need to follow an NPC. Welds add physics complexity (mass, inertia, activation timing). Use an anchored Part and explicitly update its CFrame in the PostSimulation tick instead — simpler, more predictable, no physics edge cases.

- **[Luau]** Don't use Python-style format specifiers (`:.1f`) in Luau interpolated strings. Luau string interpolation only supports raw expressions inside `{}`. Use `math.floor()` or `string.format()` for number formatting.

- **[Roblox]** Don't forget `CastShadow = false` on debug visualization Parts. Large transparent debug discs/markers cast visible shadows that confuse the scene. Always disable shadow casting on non-gameplay visual elements.

## Session: 2026-02-23 — Guard NPC (Patrol + Chase Hybrid)

- **[Roblox]** Don't use `hasLineOfSight` raycast without excluding the target player's character model. The ray from NPC root to player HumanoidRootPart position hits the player's own body parts (legs, torso) first, making LOS always return false. Pass the target model in `FilterDescendantsInstances` alongside the NPC model.

- **[Architecture]** Don't require LOS to _maintain_ a chase — only require it to _initiate_ a chase. Using LOS for Chasing→Returning transitions causes flicker at wall edges where the player model partially peeks out frame-to-frame. Use distance-only for disengage, LOS+distance for engage.

- **[Architecture]** Don't add random waypoint selection to a generic patrol method. Use the existing `moveTo` in a spawned thread loop with random index selection — same pattern as the Wander NPC. Keeps the pathfinder module simple and behavior logic in the state machine where it belongs.

## Session: 2026-02-23 — Debug Panel MVP

- **[Roblox]** Don't bind debug panel toggle to F9. F9 opens the Roblox Developer Console in Studio play mode. Use F8 or another unoccupied key.

- **[Architecture]** Don't use `Remotes.onInvoke` with a validator for RemoteFunctions that take no client arguments. The validator pattern expects data to validate — use `Remotes.getFunction().OnServerInvoke` directly when the client sends nothing.

- **[Architecture]** Don't assume a single `onStateChanged` callback can serve both the in-world state label and external listeners. Modify the callback factory (`makeStateLabelUpdater`) to accept and chain an additional callback rather than replacing it.

- **[Roblox]** Don't assume wander beam/marker toggle state persists across state cycles. Wander's `onEnter` recreates visuals each cycle, ignoring the debug toggle. Store a `_wanderBeamVisible` flag on the NPC entry and check it before creating visuals.

- **[UX]** Don't let NPC states transition faster than the UI can display them. Guard's Returning state completed in 1-2 frames when near a waypoint, making it invisible in the debug panel. Add a minimum dwell time (`RETURN_DWELL`) so transient states are observable.

## Session: 2026-02-24 — Refactor & Debug Panel Enhancements

- **[Architecture]** Don't let a single module define both orchestration logic and behavior state definitions. NPCManager at 1,147 lines mixed spawning, state defs, debug visuals, and public API. Extract state definitions into per-behavior modules (`behaviors/ChaseStates.luau`, etc.) so adding a new NPC type doesn't require understanding the entire file.

- **[Architecture]** Don't duplicate factory functions that differ only in config values. `createWaypointMarkers` and `createGuardWaypointMarkers` were 90% identical (different color and line-drawing). Parameterize with a config object (`color`, `showLines`) instead of copy-pasting.

- **[Luau]** Don't access private fields (`ctx.pathfinder._isMoving = true`) from outside the owning module. It bypasses state tracking and breaks if internals change. In this case the write was redundant — `moveTo` already calls `_resetMovement()` which sets the flag. Trace the call graph before assuming you need to set internal state.

- **[Architecture]** Don't let behavior defaults overwrite debug panel overrides on state transitions. `followTarget` was called on every new chase and reset `_visualizeEnabled = options.visualize`, clobbering the panel's toggle. Use a `_visualizeOverride` field (nil = use behavior default, boolean = panel override) so the debug toggle persists across state re-entries. Other visual types (discs, labels, markers) didn't have this problem because they're created once and never recreated.

- **[Luau]** Don't use `any` for typed fields when `typeof()` works. Luau's `typeof(Module.new(nil :: any))` captures the full metatable type without needing explicit export types, providing autocomplete and type checking on fields like `pathfinder` and `stateMachine`.

## Session: 2026-02-24 — SimplePath Comparison & Skill Rewrite

- **[Pathfinding]** Don't recompute paths while the humanoid is in `Freefall` state. The NPC's position mid-air is unreliable, causing `ComputeAsync` to use a bad start position and produce erratic paths on landing. Check `self._humanoid:GetState() == Enum.HumanoidStateType.Freefall` at the top of `_computePath` and return the existing waypoints instead. Found by comparing against SimplePath's approach — one of very few things it handled that we didn't.

- **[Docs]** Don't ship skill assets as a single condensed "reference" file that simplifies the production module. It drifts silently as production code evolves — this session found the asset was missing freefall rejection, `_visualizeOverride`, stuck detection, collision group setup, and the full `_resetMovement`/`stop` separation. Ship assets as separate files matching production's module structure (one per module) so diffs between asset and production are meaningful. Extends the earlier "audit skill docs against lessons" rule with a structural fix.

## Session: 2026-02-24 — Suburban House Construction (MCP)

- **[MCP]** Don't try to build complex multi-part geometry through MapSetup/GameConfig when iterating on layout. Use `run_code` to execute a self-contained Luau construction script directly in Studio — it's faster to iterate (edit script, re-run), idempotent (destroy + recreate), and doesn't bloat source files. Move to config-driven only once the layout is finalized and needs to persist across sessions.

- **[MCP]** Don't build multi-story geometry in a single monolithic script. Split into per-floor scripts that modify the same Model — each stays under token limits and is independently re-runnable. The second script can reference parts created by the first.

## Session: 2026-02-25 — LOS Detection & Memory Timer

- **[Architecture]** Don't gate initial detection on LOS without also adding a memory timer for chase maintenance. Distance-only chase maintenance creates a broken mental model: walls matter for detection but not escape. Use `LOS_MEMORY` (configurable seconds) so NPCs give up after losing sight, completing the stealth loop (Alert → Pursuit → Memory → Disengage).

- **[Architecture]** Don't add visual debug state by creating new systems. Annotate the existing state label in the PostSimulation tick — the state machine's `onStateChanged` callback naturally restores it on the next transition, so no cleanup is needed.

## Session: 2026-02-25 — Separation of Concerns Audit & DebugVisuals Extraction

- **[Luau]** Don't mix different table shapes in a frozen array under `--!strict`. Luau infers the array type from all elements and flags mismatches. Add dummy fields to variant entries (e.g., `size = Vector3.zero` for staircases) so all elements share the same base shape.

- **[Architecture]** Don't pass a module-level variable's current value when extracting a closure to another module. The extracted closure captures the value at call time (nil), not the variable. Use a getter function (`function() return variable end`) to preserve late-binding across module boundaries.
