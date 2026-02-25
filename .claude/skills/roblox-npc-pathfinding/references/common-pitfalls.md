# Common Pitfalls and Debugging

## Debugging Setup

Before diagnosing any pathfinding issue, enable these visualizations in Roblox Studio:

1. **Navigation Mesh** — View → Visualization Options → Navigation Mesh
   - Colored areas = walkable
   - Non-colored areas = blocked
   - Small arrows = jumpable gaps
2. **Pathfinding Modifiers** — View → Visualization Options → Pathfinding Modifiers
   - Shows labels for modifier regions
3. **Pathfinding Links** — View → Visualization Options → Pathfinding Links
   - Shows link connections between attachments

## Symptom → Cause → Fix

### NPC doesn't move at all

**Causes (check in order):**
1. `ComputeAsync` errored silently — No `pcall` wrapper, error swallowed
   - **Fix:** Always wrap in pcall: `local success, err = pcall(function() path:ComputeAsync(...) end)`
2. `path.Status` is `NoPath` — Destination unreachable
   - **Fix:** Check nav mesh visualization. Is there a walkable path? Is the destination on the mesh?
3. NPC model has no Humanoid
   - **Fix:** Ensure the model has a `Humanoid` instance
4. `PrimaryPart` not set on the model
   - **Fix:** `npcModel.PrimaryPart = npcModel:FindFirstChild("HumanoidRootPart")`
5. NPC is anchored
   - **Fix:** `HumanoidRootPart.Anchored = false`
6. NPC is inside geometry — Start position is inside a wall/floor
   - **Fix:** Spawn NPC above ground with a small offset, or raycast down to find valid ground

### NPC moves but gets stuck

**Causes:**
1. **Network ownership not locked** — Movement is laggy, NPC oscillates
   - **Fix:** `npc.PrimaryPart:SetNetworkOwner(nil)` on spawn
2. **No Path.Blocked handler** — Obstacle moved into path, NPC walks into it forever
   - **Fix:** Connect `path.Blocked` event, recompute path when blocked ahead of current waypoint
3. **MoveToFinished never fires** — Waypoint is unreachable (e.g., inside a wall, too high)
   - **Fix:** Add a timeout: if `MoveToFinished` hasn't fired in 8+ seconds, skip waypoint or recompute
4. **AgentRadius too small** — Path goes too close to walls, NPC clips and gets stuck on corners
   - **Fix:** Increase `AgentRadius` to match NPC actual size. Enable `PathfindingUseImprovedSearch`.
5. **NPC collides with other NPCs** — Multiple NPCs blocking each other at bottlenecks
   - **Fix:** Disable NPC-to-NPC collision, or stagger movement timing
6. **SpawnLocation blocks path** — `SpawnLocation.CanCollide` defaults to `true`, making it a physical wall that NPCs can't pass through
   - **Fix:** Set `SpawnLocation.CanCollide = false`. Spawning uses the `Enabled` property, not collision.
7. **NPC stuck after being knocked over near obstacles** — Humanoid physics recovery states were disabled (`FallingDown`, `GettingUp`, `Freefall`, `Landed`). Without them, a knocked-over NPC stays down permanently.
   - **Fix:** Only disable these states on flat geometry with no collision risk. Keep them enabled when physical obstacles exist.
8. **First waypoint from GetWaypoints() causes instant stall** — Waypoint 1 is the NPC's current position at navmesh Y height (≈0), not hip height. 3D distance checks fail because Y mismatches.
   - **Fix:** Always skip index 1. Start waypoint traversal from index 2.

### NPC zig-zags

**Causes:**
1. **PathfindingUseImprovedSearch not enabled** — Legacy algorithm generates zig-zag paths
   - **Fix:** Workspace → Properties → `PathfindingUseImprovedSearch` → Enabled
2. **Path recomputing too frequently** — New path computed before NPC reaches first waypoint
   - **Fix:** Add minimum interval between recomputes (0.5–1 second)
3. **WaypointSpacing too small** — Lots of tiny waypoints causing micro-corrections
   - **Fix:** Increase `WaypointSpacing` to 6–8

### NPC walks through walls

**Causes:**
1. **PathfindingUseImprovedSearch not enabled** — Known bug in legacy algorithm
   - **Fix:** Enable improved search
2. **AgentRadius doesn't match NPC** — Path fits but NPC doesn't
   - **Fix:** Measure NPC bounding box, set AgentRadius accordingly
3. **Part has CanCollide = false** — Nav mesh treats it as empty space
   - **Fix:** Set `CanCollide = true` on walls/floors, or add a PathfindingModifier to explicitly block
4. **MeshPart collision fidelity** — Complex meshes may have gaps in collision
   - **Fix:** Use simpler collision boxes, or add invisible blocking parts

### Path returns NoPath when it should succeed

**Causes:**
1. **Destination not on nav mesh** — Goal is floating, inside geometry, or off the walkable area
   - **Fix:** Raycast down from destination to find the nearest ground point
2. **AgentRadius too large** — NPC is "too fat" for the corridor
   - **Fix:** Reduce AgentRadius or widen the corridor
3. **Nav mesh not generated** — New parts added without waiting for mesh update
   - **Fix:** In Studio, save and reopen. At runtime, wait a moment after changing geometry.
4. **Vertical limits exceeded** — Parts below -65536 or above 65536 studs
   - **Fix:** Keep your game world within bounds
5. **Path distance too long** — Very long paths may fail
   - **Fix:** Break into intermediate waypoints, pathfind in segments

### ComputeAsync throws an error

**Causes:**
1. **Start or end position is NaN/inf** — Destroyed NPC, nil HumanoidRootPart
   - **Fix:** Validate positions before computing: `if startPos ~= startPos then return end` (NaN check)
2. **Called from the wrong context** — Must be called from a server or client Script
   - **Fix:** Ensure it's in a Script or LocalScript, not a ModuleScript that's never required

### NPC jitters/stutters during movement

**Causes:**
1. **Network ownership bouncing** — Server/client fighting over physics
   - **Fix:** `SetNetworkOwner(nil)` immediately on spawn
2. **NPC-NPC collisions** — Multiple NPCs converging on the same target push each other, causing physics micro-stutters that interfere with MoveTo calculations. This is the #1 cause of group jitter.
   - **Fix:** Create a collision group for NPCs and disable self-collisions:
     ```lua
     local PhysicsService = game:GetService("PhysicsService")
     PhysicsService:RegisterCollisionGroup("NPCs")
     PhysicsService:CollisionGroupSetCollidable("NPCs", "NPCs", false)
     -- Then set each NPC part's CollisionGroup = "NPCs"
     ```
     The base module handles this automatically via the `CollisionGroup` config (defaults to `"NPCs"`). Set to `nil` to disable if you need NPC-NPC collision for gameplay reasons.
3. **MoveTo called with very close waypoints** — Humanoid oscillates between tiny positions
   - **Fix:** Skip waypoints that are very close to current position (< 2 studs)
4. **Multiple scripts controlling the same NPC** — Competing MoveTo calls
   - **Fix:** Audit for duplicate scripts. Use a single centralized controller.

### NPC recomputes path rapidly (dozens or hundreds per second)

**Causes:**
1. **`MoveTo(currentPosition)` used as a stop mechanism** — `Humanoid:MoveTo(npc.PrimaryPart.Position)` fires a stale `MoveToFinished(true)` signal. Any subsequent `MoveToFinished:Wait()` catches this stale signal instantly, causing the next path computation to start immediately. This creates a tight loop — observed as 77 path recomputes in 3.3 seconds.
   - **Fix:** Don't use `MoveTo` to stop movement. Instead, clear internal waypoint/movement state without issuing a `MoveTo` call. A separate `_resetMovement()` method that sets flags and clears state is the correct approach.

### stop() silently kills the calling thread

**Causes:**
1. **`stop()` calls `task.cancel()` on the movement thread, but was called FROM that thread** — `task.cancel` on the currently executing thread kills it mid-function. No error, no warning — execution just stops.
   - **Fix:** If `stop()` needs to cancel a movement thread, don't call it from within that thread. Use a separate `_resetMovement()` method for internal state clearing. Reserve `stop()` for external callers. Alternatively, use a flag (`_shouldStop = true`) that the movement loop checks on each iteration.

### MoveToFinished and distance checks disagree

**Causes:**
1. **Mixing `MoveToFinished:Wait()` with `Vector3.Magnitude` distance checks** — `MoveToFinished` resolves based on XZ distance only (ignoring Y). `Vector3.Magnitude` includes Y. A waypoint directly below the NPC (same XZ, different Y from navmesh height) passes `MoveToFinished` instantly but fails a 3D distance threshold.
   - **Fix:** Use one or the other consistently. If using `MoveToFinished`, trust its result. If using manual distance checks, use XZ-only distance: `(pos1 * Vector3.new(1, 0, 1) - pos2 * Vector3.new(1, 0, 1)).Magnitude`.

### MoveToFinished fires late or inconsistently

**Causes:**
1. **Network ownership on client** — MoveToFinished timing is unreliable when client owns NPC physics
   - **Fix:** `SetNetworkOwner(nil)`
2. **Humanoid.MoveToFinished timeout** — Built-in 8-second timeout fires even if NPC hasn't arrived. The event passes a `reached` boolean: `true` if the NPC arrived, `false` if the 8s timeout fired.
   - **Fix:** ALWAYS check the `reached` parameter. This is the #1 cause of NPC loops silently freezing in production — the timeout fires with `reached = false`, code doesn't check it, assumes the NPC arrived, and the loop stalls.
   ```lua
   local reached = humanoid.MoveToFinished:Wait()
   if reached then
       -- NPC actually arrived at the waypoint
   else
       -- 8s timeout fired — NPC is stuck. Recompute or skip.
   end
   ```

### ComputeAsync called while NPC is in freefall

**Causes:**
1. **Path computed while NPC is airborne** — If the NPC is mid-air (freefall after being knocked off a ledge, bumped by physics, etc.), `ComputeAsync` uses the airborne position as the start. The resulting path is invalid — it starts from a position the NPC won't be at when it lands.
   - **Fix:** Guard `_computePath` with a freefall state check at the top. Skip recomputation and keep the existing waypoints until the NPC lands:
   ```lua
   if self._humanoid:GetState() == Enum.HumanoidStateType.Freefall then
       return #self._waypoints > 0
   end
   ```

### hasLineOfSight always returns false

**Causes:**
1. **Raycast hits the target's own body** — When raycasting from NPC root to a player's HumanoidRootPart position, the ray intersects the player's legs, torso, or other body parts before reaching the target point. The raycast reports a "hit" (obstacle found), so LOS returns false even with a clear sightline.
   - **Fix:** Pass the target character model in `FilterDescendantsInstances` alongside the NPC model:
   ```lua
   local rayParams = RaycastParams.new()
   rayParams.FilterType = Enum.RaycastFilterType.Exclude
   rayParams.FilterDescendantsInstances = {self._model, targetCharacterModel}
   ```
   The `hasLineOfSight(targetPos, excludeModels?)` method in the asset module accepts an optional `excludeModels` array for this purpose.

### NPC chases forever after player hides behind a wall

**Causes:**
1. **`LOS_MEMORY` not configured** — Detection uses `REQUIRE_LOS = true` so walls block the initial spot, but chase maintenance has no LOS check. Once detected, the NPC chases regardless of walls until the player leaves the detection radius. This creates a broken mental model: walls matter for detection but not escape.
   - **Fix:** Add `LOS_MEMORY` to the NPC config (e.g., `LOS_MEMORY = 3` for chase, `LOS_MEMORY = 5` for guard). `evaluateChaseTarget` will count down `ctx.losLostTimer` each reevaluation tick when LOS is lost, and drop the target when the timer expires. This completes the stealth loop: detect → pursue → lose sight → countdown → disengage.
   ```lua
   -- In GameConfig or local CONFIG:
   LOS_MEMORY = 3,  -- seconds before giving up (nil = chase forever)
   REQUIRE_LOS = true,  -- must be true for LOS_MEMORY to activate
   ```

### Guard NPC flickers between chase and return states at wall edges

**Causes:**
1. **Using raw LOS per-frame to maintain chase** — When a player peeks around a wall corner, LOS alternates true/false each frame as the player model partially occludes. If the Chasing → Returning transition triggers on LOS loss, the NPC rapidly switches states (chase → return → chase → return).
   - **Fix:** Use `LOS_MEMORY` timer instead of raw LOS for chase maintenance. The timer accumulates only on throttled reevaluation ticks (not every frame), and the NPC only gives up after the full countdown expires — not on transient LOS breaks. Set `REQUIRE_LOS = true` for detection, and let `evaluateChaseTarget` manage the countdown.

### Debug visual toggles reset when NPC re-enters a state

**Causes:**
1. **Behavior state `onEnter` overwrites debug visual flag** — If `followTarget` is called on every Chasing `onEnter` and it resets `_visualizeEnabled = options.visualize`, the debug panel's toggle gets clobbered. The panel set `_visualizeEnabled = true`, but the next state transition sets it back to `false`.
   - **Fix:** Use a `_visualizeOverride` pattern. `nil` = use behavior default, `true`/`false` = debug panel override. Check `_visualizeOverride` first, fall back to the behavior option:
   ```lua
   function NPCPathfinder:setVisualizeEnabled(enabled: boolean)
       self._visualizeOverride = enabled
   end

   -- Inside followTarget / movement methods:
   local shouldVisualize = if self._visualizeOverride ~= nil
       then self._visualizeOverride
       else (options.visualize or false)
   ```

## Performance Debugging

### Detecting Pathfinding Bottlenecks
- Open Studio's **MicroProfiler** (Ctrl+F6) and look for `PathfindingService` spikes
- Check **Server Stats** for script activity percentage
- If pathfinding dominates server time, you're computing too many paths per frame

### Quick Health Check
```lua
-- Add to a test script temporarily
local startTime = tick()
path:ComputeAsync(startPos, endPos)
local elapsed = tick() - startTime
print("Path compute time:", elapsed, "seconds")
print("Path status:", path.Status)
print("Waypoint count:", #path:GetWaypoints())
```

Normal compute times:
- Simple path: 0.001–0.005 seconds
- Complex path (long, many obstacles): 0.01–0.05 seconds
- If consistently > 0.05 seconds: reduce path length or simplify environment

## Environment Issues

### Parts Not Affecting Nav Mesh
- Parts must have `CanCollide = true` to block the nav mesh (unless using PathfindingModifier)
- Parts in `nil` or outside Workspace don't affect nav mesh
- Very thin parts (< 0.2 studs) may not register

### Terrain Nav Mesh Gaps
- Terrain with steep slopes may create unwalkable zones
- Water terrain is walkable by default (set `Water = math.huge` in Costs to block)
- Terrain material boundaries can create nav mesh seams — check with visualization

### Dynamic Environment
- Moving or destroying parts at runtime updates the nav mesh, but not instantly
- After changing geometry, there's a brief delay before the nav mesh updates
- `Path.Blocked` event fires when a computed path is invalidated by geometry changes
- For doors/gates: use PathfindingModifier with PassThrough instead of destroying/moving parts
