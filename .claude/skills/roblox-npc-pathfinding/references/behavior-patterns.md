# NPC Behavior Patterns (State Machine Architecture)

These patterns layer on top of the base `NPCPathfinder` module. Each assumes you have a working `NPCPathfinder` instance and uses `NPCStateMachine` to drive behavior through declarative state definitions.

## 1. Architecture Overview

- Behavior is driven by **state machines**, not ad-hoc controller classes
- `NPCStateMachine` ticks externally from a single `PostSimulation` connection -- it does NOT tick itself
- State definitions are plain tables with optional `onEnter` / `onUpdate` / `onExit` hooks
- A **context object** (typically the NPC entry table containing `model`, `pathfinder`, etc.) carries shared mutable state between hooks
- Behavior state modules live in separate files under a `behaviors/` folder, each exporting a `StateMap` table
- One state machine per NPC; one `PostSimulation` connection drives all machines

## 2. How It Works

### Construction

```lua
local sm = NPCStateMachine.new(initialState, stateMap, context, onStateChanged?)
```

- `initialState` -- string name of the starting state (must exist in `stateMap`)
- `stateMap` -- `{ [string]: StateDefinition }` table of all states
- `context` -- any table passed through to all hooks (shared mutable state)
- `onStateChanged` -- optional callback `(newState, previousState?) -> ()`, fires on initial state (previous = nil) and every transition

### State Definition

```lua
type StateDefinition = {
    onEnter: ((context) -> ())?,      -- fires immediately on entering state (including initial)
    onUpdate: ((context, dt) -> string?)?,  -- fires every tick; return state name to transition, nil to stay
    onExit: ((context) -> ())?,       -- fires before leaving state; cleanup threads, stop pathfinder
}
```

### Rules

- `onEnter` fires immediately on construction for the initial state
- `onUpdate` returns a state name to trigger a transition, or `nil` to stay in the current state
- Only **one transition per tick** (prevents infinite loops)
- Self-transitions are allowed (e.g., Chasing -> Chasing to switch targets) -- `onExit` then `onEnter` both fire
- Context is a shared mutable table -- states store behavior-specific fields (timers, targets, threads) directly on it
- `destroy()` calls `onExit` on the current state, then marks the machine as dead

### External Tick

```lua
-- Single PostSimulation connection drives all NPC state machines
RunService.PostSimulation:Connect(function(dt)
    for _, entry in npcEntries do
        entry.stateMachine:update(dt)
    end
end)
```

## 3. Pattern: Chase (Idle <-> Chasing)

The simplest two-state behavior. NPC scans for players while idle, follows the nearest one when detected, returns to idle when the target escapes.

```lua
local ChaseStates = {
    Idle = {
        onEnter = function(ctx)
            ctx.pathfinder:stop()
        end,

        onUpdate = function(ctx, _dt)
            local rootPart = ctx.model.PrimaryPart
            if not rootPart then return nil end

            local target = BehaviorHelpers.findNearestPlayer(rootPart.Position)
            if not target then return nil end

            local targetRoot = target:FindFirstChild("HumanoidRootPart")
            if not targetRoot then return nil end

            local distance = (targetRoot.Position - rootPart.Position).Magnitude
            if distance <= DETECTION_RADIUS then
                ctx.chaseTarget = target
                return "Chasing"
            end

            return nil
        end,
    },

    Chasing = {
        onEnter = function(ctx)
            ctx.pathfinder:followTarget(ctx.chaseTarget, {
                recomputeInterval = RECOMPUTE_INTERVAL,
                arrivalDistance = ARRIVAL_DISTANCE,
                onTargetLost = function() end,
            })
        end,

        onUpdate = function(ctx, dt)
            -- Throttle re-evaluation (no need to check every frame)
            ctx.chaseReevalTimer = (ctx.chaseReevalTimer or 0) + dt
            if ctx.chaseReevalTimer < REEVALUATE_INTERVAL then return nil end
            ctx.chaseReevalTimer = 0

            return BehaviorHelpers.evaluateChaseTarget(
                ctx, config, "chaseTarget", "Idle", false
            )
        end,

        onExit = function(ctx)
            ctx.pathfinder:stop()
            ctx.chaseReevalTimer = nil
        end,
    },
}
```

**Key points:**

- `followTarget` uses event-driven `MoveToFinished:Connect()` internally -- continuous fluid motion, not polled
- `evaluateChaseTarget` with `requireLOS = false`: once detected, no LOS check needed to maintain chase (distance-only)
- Timer-based re-evaluation avoids per-frame distance/player iteration
- Always `stop()` pathfinder in `onExit` of **both** states -- guarantees clean handoff regardless of which direction the transition goes
- `onTargetLost` callback is provided but intentionally empty here; the state machine handles target-lost transitions via `evaluateChaseTarget`

## 4. Pattern: Patrol (Patrolling)

Minimal single-state behavior. NPC loops through fixed waypoints. Extensible for Alert/Chase variants later.

```lua
local PatrolStates = {
    Patrolling = {
        onEnter = function(ctx)
            ctx.pathfinder:patrol(WAYPOINTS, {
                loopMode = "loop", -- or "pingpong"
                waitTime = WAIT_TIME,
                onWaypoint = function(index) end,
            })
        end,

        onExit = function(ctx)
            ctx.pathfinder:stop()
        end,
    },
}
```

**Key points:**

- `patrol()` handles loop/pingpong logic internally -- the state definition just configures and starts it
- No `onUpdate` needed when patrol is the only state. Add `onUpdate` when you need detection (scan for player -> transition to a Chase state)
- Debug markers created via `BehaviorHelpers.createWaypointMarkers()` with `showLines = true` for sequential route visualization
- To compose with chase: add an `Alert` or `Chasing` state, use `onUpdate` in Patrolling to scan for players, transition on detection

## 5. Pattern: Wander (Wandering)

NPC roams randomly within a radius. Uses its own spawned thread (not `patrol()`) because targets are random, not fixed waypoints.

```lua
local WanderStates = {
    Wandering = {
        onEnter = function(ctx)
            ctx.wanderThread = task.spawn(function()
                while ctx.model and ctx.model:IsDescendantOf(game) do
                    local target = BehaviorHelpers.getRandomPointInRadius(CENTER, RADIUS)
                    ctx.pathfinder:moveTo(target)

                    local pause = PAUSE_MIN + math.random() * (PAUSE_MAX - PAUSE_MIN)
                    task.wait(pause)
                end
            end)
        end,

        onExit = function(ctx)
            if ctx.wanderThread then
                task.cancel(ctx.wanderThread)
                ctx.wanderThread = nil
            end
            ctx.pathfinder:stop()
        end,
    },
}
```

**Key points:**

- Spawns its own thread because movement is a loop of `moveTo` -> pause -> pick new target. This is fundamentally different from `patrol()` which manages its own internal loop
- `getRandomPointInRadius` raycasts down to validate ground and rejects points that land on obstacle geometry
- **Thread cancellation in `onExit` is critical** -- without it, the spawned thread continues running after the state machine transitions away, causing the NPC to fight between two movement systems
- Always check `ctx.model:IsDescendantOf(game)` after `task.wait()` in the loop -- the model may have been destroyed during the pause
- MAX_ATTEMPTS (10) with fallback to center position prevents infinite loops when the radius is heavily obstructed

## 6. Pattern: Guard (Guarding <-> Chasing <-> Returning)

The most complex production behavior -- three states with a shared detection helper. Combines random patrol, LOS-triggered pursuit, and return-to-post.

### Shared Detection Helper

```lua
local function detectPlayerWithLOS(ctx)
    local rootPart = ctx.model.PrimaryPart
    if not rootPart then return nil end

    local target = BehaviorHelpers.findNearestPlayer(rootPart.Position)
    if not target then return nil end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return nil end

    local distance = (targetRoot.Position - rootPart.Position).Magnitude
    if distance <= DETECTION_RADIUS then
        if ctx.pathfinder:hasLineOfSight(targetRoot.Position, { target }) then
            ctx.guardTarget = target
            return "Chasing"
        end
    end

    return nil
end
```

### State Definitions

```lua
local GuardStates = {
    Guarding = {
        onEnter = function(ctx)
            local lastIndex = ctx.guardLastWaypointIndex or 0
            ctx.guardPatrolThread = task.spawn(function()
                while ctx.model and ctx.model:IsDescendantOf(game) do
                    -- Pick random waypoint, excluding the last one visited
                    local candidates = {}
                    for i = 1, #WAYPOINTS do
                        if i ~= lastIndex then
                            table.insert(candidates, i)
                        end
                    end
                    local nextIndex = candidates[math.random(1, #candidates)]
                    lastIndex = nextIndex
                    ctx.guardLastWaypointIndex = nextIndex

                    ctx.pathfinder:moveTo(WAYPOINTS[nextIndex])
                    task.wait(PATROL_PAUSE)
                end
            end)
        end,

        onUpdate = function(ctx, dt)
            -- Throttle detection (no need to raycast every frame)
            ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
            if ctx.guardDetectTimer < DETECT_INTERVAL then return nil end
            ctx.guardDetectTimer = 0

            return detectPlayerWithLOS(ctx)
        end,

        onExit = function(ctx)
            if ctx.guardPatrolThread then
                task.cancel(ctx.guardPatrolThread)
                ctx.guardPatrolThread = nil
            end
            ctx.guardDetectTimer = nil
            ctx.pathfinder:stop()
        end,
    },

    Chasing = {
        onEnter = function(ctx)
            ctx.pathfinder:followTarget(ctx.guardTarget, {
                recomputeInterval = RECOMPUTE_INTERVAL,
                arrivalDistance = ARRIVAL_DISTANCE,
            })
        end,

        onUpdate = function(ctx, dt)
            ctx.guardReevalTimer = (ctx.guardReevalTimer or 0) + dt
            if ctx.guardReevalTimer < REEVALUATE_INTERVAL then return nil end
            ctx.guardReevalTimer = 0

            -- Distance-only to maintain chase (no LOS -- prevents flicker at wall edges)
            -- LOS required only to SWITCH to a closer target
            return BehaviorHelpers.evaluateChaseTarget(
                ctx, config, "guardTarget", "Returning", true
            )
        end,

        onExit = function(ctx)
            ctx.pathfinder:stop()
            ctx.guardReevalTimer = nil
        end,
    },

    Returning = {
        onEnter = function(ctx)
            ctx.guardReachedWaypoint = false

            local rootPart = ctx.model.PrimaryPart
            if not rootPart then
                ctx.guardReachedWaypoint = true
                return
            end

            -- Find nearest waypoint to return to
            local nearestIndex = 1
            local nearestDist = math.huge
            for i, wp in WAYPOINTS do
                local dist = (wp - rootPart.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearestIndex = i
                end
            end

            ctx.guardLastWaypointIndex = nearestIndex

            ctx.guardPatrolThread = task.spawn(function()
                ctx.pathfinder:moveTo(WAYPOINTS[nearestIndex])
                ctx.guardReachedWaypoint = true
            end)
        end,

        onUpdate = function(ctx, dt)
            if ctx.guardReachedWaypoint then
                -- Minimum dwell so "Returning" is observable in debug panel
                ctx.guardReturnDwell = (ctx.guardReturnDwell or 0) + dt
                if ctx.guardReturnDwell >= RETURN_DWELL then
                    return "Guarding"
                end
                return nil
            end

            -- Can detect and chase during return
            ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
            if ctx.guardDetectTimer < DETECT_INTERVAL then return nil end
            ctx.guardDetectTimer = 0

            return detectPlayerWithLOS(ctx)
        end,

        onExit = function(ctx)
            if ctx.guardPatrolThread then
                task.cancel(ctx.guardPatrolThread)
                ctx.guardPatrolThread = nil
            end
            ctx.guardDetectTimer = nil
            ctx.guardReachedWaypoint = nil
            ctx.guardReturnDwell = nil
            ctx.pathfinder:stop()
        end,
    },
}
```

**Key points:**

- **LOS detection strategy:** Use LOS to *initiate* chase (Guarding/Returning -> Chasing), but distance-only to *maintain* chase (Chasing `onUpdate`). LOS flickers at wall edges because the player model partially peeks out frame-to-frame. Distance is stable once chase has begun.
- **`hasLineOfSight(targetPos, { target })`** -- the second argument excludes the target player's character from the raycast. Without this, the ray hits the target's own body parts (legs, torso) before reaching `HumanoidRootPart` position.
- **Guard returns to nearest waypoint**, not a fixed home position. This prevents the guard from awkwardly running across its entire patrol zone after a chase.
- **`RETURN_DWELL` minimum time** -- without this, the Returning state completes in 1-2 frames and is invisible in debug panels. The dwell makes the state observable.
- **Detection during return** -- the guard can interrupt its return path to chase a newly detected player, making it feel reactive rather than robotic.
- **Random waypoint selection excludes last visited** -- prevents the guard from immediately turning around, which looks unnatural.
- **Guarding uses a spawned thread** (like Wander), not `patrol()` -- random order between fixed waypoints is a different movement pattern than sequential patrol.

## 7. BehaviorHelpers API

Shared utility functions used by all behavior state modules.

### findNearestPlayer(position: Vector3): Model?

Iterates all players via `Players:GetPlayers()`, returns the nearest character model by distance from the given position. Returns `nil` if no players exist or no player has a spawned character.

```lua
local target = BehaviorHelpers.findNearestPlayer(rootPart.Position)
if not target then return nil end
```

### getRandomPointInRadius(center: Vector3, radius: number): Vector3

Generates a random point within a circular radius on the XZ plane, validates it with a downward raycast.

- Random angle + random distance within radius
- Raycasts down from 20 studs above to find ground
- Rejects points where the ray hits obstacle geometry (checks `IsDescendantOf(Workspace.Obstacles)`)
- MAX_ATTEMPTS = 10, falls back to center position if all attempts hit obstacles
- Caches the `Workspace.Obstacles` folder reference for performance (avoids `FindFirstChild` every call)

```lua
local target = BehaviorHelpers.getRandomPointInRadius(CENTER, RADIUS)
ctx.pathfinder:moveTo(target)
```

### createWaypointMarkers(waypoints: {Vector3}, color: Color3, showLines: boolean): Folder

Creates debug visualization for a set of waypoints.

- Sphere marker (`Part`, `Enum.PartType.Ball`) at each waypoint position
- Numbered label above each sphere via `BillboardGui` with `AlwaysOnTop = true`
- Optional connecting lines between sequential waypoints (thin neon `Part` oriented via `CFrame.lookAt`)
- Returns a `Folder` parented to `Workspace` -- caller is responsible for cleanup (destroy in `onExit` or store on context)
- **Patrol uses `showLines = true`** (fixed sequential route); **Guard uses `showLines = false`** (random order, lines would be misleading)

```lua
-- In onEnter, create markers (guarded by debug flag)
if DEBUG and not ctx.debugFolder then
    ctx.debugFolder = BehaviorHelpers.createWaypointMarkers(WAYPOINTS, color, true)
end
```

### evaluateChaseTarget(ctx, config, targetField, lostState, requireLOS?): string?

Core re-evaluation logic shared by all chase-capable behaviors. Call from `onUpdate` of a Chasing state.

**Parameters:**
- `ctx` -- the shared context table
- `config` -- table with `DETECTION_RADIUS` field (used for range check)
- `targetField` -- string key on ctx where the current target is stored (e.g., `"chaseTarget"`, `"guardTarget"`)
- `lostState` -- state name to transition to when the target is lost (e.g., `"Idle"`, `"Returning"`)
- `requireLOS` -- if true, only switches to a closer target when LOS check passes

**Returns:**
- `nil` -- current target is still the best, stay in Chasing
- `lostState` -- current target invalid (left game, out of range), clears `ctx[targetField]`
- `"Chasing"` -- switching to a closer player (self-transition: triggers `onExit` then `onEnter` with new target)

**Logic flow:**
1. Validate current target: still in game? Still within `DETECTION_RADIUS`?
2. If invalid -> return `lostState`, set `ctx[targetField] = nil`
3. Find nearest player. If a different, closer player exists within range:
   - If `requireLOS` is true, check LOS before switching
   - If check passes, set `ctx[targetField]` to new target, return `"Chasing"` (self-transition)
4. Otherwise return `nil` (keep chasing current target)

```lua
-- Chase NPC: no LOS needed to maintain chase
return BehaviorHelpers.evaluateChaseTarget(ctx, config, "chaseTarget", "Idle", false)

-- Guard NPC: LOS required to switch targets (distance-only to maintain current)
return BehaviorHelpers.evaluateChaseTarget(ctx, config, "guardTarget", "Returning", true)
```

### clearCache(): ()

Clears the cached `Workspace.Obstacles` folder reference. Call during map reinitialization if obstacles are rebuilt at runtime.

```lua
BehaviorHelpers.clearCache()
```

## 8. Composing Behaviors

These patterns are building blocks. The base `NPCPathfinder` provides movement primitives (`moveTo`, `patrol`, `followTarget`, `stop`). Behavior states manage *when* and *where* to use them. Keep these concerns separate.

### Composition Examples

**1. Wander + Chase + Attack (combat NPC)**
- Wander (idle) -> detect player -> Chase -> at attack range -> Attack (game-specific) -> player escapes -> Wander

Add an `onUpdate` to the Wandering state that scans for players. On detection, transition to Chasing. Add an Attack state that triggers at close range. When the target is lost, return to Wandering instead of Idle.

**2. Patrol + Chase + Return (sentry NPC)**
- Patrol -> spot player -> Chase -> player escapes range -> Return to nearest patrol point -> Patrol

Start with the Patrol pattern, add Chasing and Returning states from the Guard pattern. The key difference from pure Guard: use `patrol()` for sequential movement instead of random waypoint selection.

**3. Guard (self-contained composite)**
- Guarding (random patrol) -> LOS detection -> Chasing -> target lost -> Returning (nearest waypoint) -> Guarding

Already a complete composite. The Guard pattern demonstrates all the techniques: thread management, LOS detection, `evaluateChaseTarget` with `requireLOS`, return-to-post with nearest waypoint, and dwell timing.

### Pattern for Adding Detection to Any State

Any single-state behavior (Patrol, Wander) can gain detection by adding `onUpdate`:

```lua
Patrolling = {
    onEnter = function(ctx)
        ctx.pathfinder:patrol(WAYPOINTS, { loopMode = "loop", waitTime = WAIT_TIME })
    end,

    onUpdate = function(ctx, dt)
        ctx.detectTimer = (ctx.detectTimer or 0) + dt
        if ctx.detectTimer < DETECT_INTERVAL then return nil end
        ctx.detectTimer = 0

        local rootPart = ctx.model.PrimaryPart
        if not rootPart then return nil end

        local target = BehaviorHelpers.findNearestPlayer(rootPart.Position)
        if not target then return nil end

        local targetRoot = target:FindFirstChild("HumanoidRootPart")
        if not targetRoot then return nil end

        if (targetRoot.Position - rootPart.Position).Magnitude <= DETECTION_RADIUS then
            ctx.chaseTarget = target
            return "Chasing"
        end

        return nil
    end,

    onExit = function(ctx)
        ctx.detectTimer = nil
        ctx.pathfinder:stop()
    end,
}
```

The state machine handles the rest -- `onExit` stops the patrol, Chasing `onEnter` starts following, and the lost state returns to Patrolling.
