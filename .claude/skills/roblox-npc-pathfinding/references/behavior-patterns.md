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

The simplest two-state behavior. NPC scans for players while idle, follows the nearest one when detected, returns to idle when the target escapes or LOS memory expires.

```lua
local ChaseStates = {
    Idle = {
        onEnter = function(ctx)
            ctx.pathfinder:stop()
        end,

        onUpdate = function(ctx, _dt)
            return BehaviorHelpers.detectNearestPlayerInRange(ctx, CONFIG, "chaseTarget", "Chasing")
        end,
    },

    Chasing = {
        onEnter = function(ctx)
            ctx.pathfinder:followTarget(ctx.chaseTarget, {
                recomputeInterval = CONFIG.RECOMPUTE_INTERVAL,
                arrivalDistance = CONFIG.ARRIVAL_DISTANCE,
            })
        end,

        onUpdate = function(ctx, dt)
            -- Throttle re-evaluation (no need to check every frame)
            ctx.chaseReevalTimer = (ctx.chaseReevalTimer or 0) + dt
            if ctx.chaseReevalTimer < CONFIG.REEVALUATE_INTERVAL then return nil end
            ctx.chaseReevalTimer = 0

            return BehaviorHelpers.evaluateChaseTarget(ctx, CONFIG, "chaseTarget", "Idle", false)
        end,

        onExit = function(ctx)
            ctx.pathfinder:stop()
            ctx.chaseReevalTimer = nil
            ctx.losLostTimer = nil
        end,
    },
}
```

**Key points:**

- `detectNearestPlayerInRange` handles distance + optional LOS check in one call -- replaces inline detection boilerplate
- `CONFIG.REQUIRE_LOS = true` blocks detection through walls; `CONFIG.LOS_MEMORY` adds a countdown when LOS is lost during chase
- `evaluateChaseTarget` checks LOS each reevaluation tick when `LOS_MEMORY` is configured, counting down via `ctx.losLostTimer` until the NPC gives up
- `followTarget` uses event-driven `MoveToFinished:Connect()` internally -- continuous fluid motion, not polled
- Timer-based re-evaluation avoids per-frame distance/player iteration
- Always `stop()` pathfinder and clear `losLostTimer` in `onExit`

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

The most complex production behavior -- three states using shared detection helpers. Combines random patrol, LOS-triggered pursuit with memory timer, and return-to-post.

```lua
local GuardStates = {
    Guarding = {
        onEnter = function(ctx)
            local lastIndex = ctx.guardLastWaypointIndex or 0
            ctx.guardPatrolThread = task.spawn(function()
                while ctx.model and ctx.model:IsDescendantOf(game) do
                    local candidates = {}
                    for i = 1, #CONFIG.WAYPOINTS do
                        if i ~= lastIndex then table.insert(candidates, i) end
                    end
                    local nextIndex = candidates[math.random(1, #candidates)]
                    lastIndex = nextIndex
                    ctx.guardLastWaypointIndex = nextIndex
                    ctx.pathfinder:moveTo(CONFIG.WAYPOINTS[nextIndex])
                    task.wait(CONFIG.PATROL_PAUSE)
                end
            end)
        end,

        onUpdate = function(ctx, dt)
            ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
            if ctx.guardDetectTimer < CONFIG.DETECT_INTERVAL then return nil end
            ctx.guardDetectTimer = 0
            return BehaviorHelpers.detectNearestPlayerInRange(ctx, CONFIG, "guardTarget", "Chasing")
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
                recomputeInterval = CONFIG.RECOMPUTE_INTERVAL,
                arrivalDistance = CONFIG.ARRIVAL_DISTANCE,
            })
        end,

        onUpdate = function(ctx, dt)
            ctx.guardReevalTimer = (ctx.guardReevalTimer or 0) + dt
            if ctx.guardReevalTimer < CONFIG.REEVALUATE_INTERVAL then return nil end
            ctx.guardReevalTimer = 0
            -- LOS_MEMORY provides countdown when sight is lost; requireLOS=true for target switching
            return BehaviorHelpers.evaluateChaseTarget(ctx, CONFIG, "guardTarget", "Returning", true)
        end,

        onExit = function(ctx)
            ctx.pathfinder:stop()
            ctx.guardReevalTimer = nil
            ctx.losLostTimer = nil
        end,
    },

    Returning = {
        onEnter = function(ctx)
            ctx.guardReachedWaypoint = false
            local rootPart = ctx.model.PrimaryPart
            if not rootPart then ctx.guardReachedWaypoint = true; return end

            local nearestIndex, nearestDist = 1, math.huge
            for i, wp in CONFIG.WAYPOINTS do
                local dist = (wp - rootPart.Position).Magnitude
                if dist < nearestDist then nearestDist = dist; nearestIndex = i end
            end
            ctx.guardLastWaypointIndex = nearestIndex

            ctx.guardPatrolThread = task.spawn(function()
                ctx.pathfinder:moveTo(CONFIG.WAYPOINTS[nearestIndex])
                ctx.guardReachedWaypoint = true
            end)
        end,

        onUpdate = function(ctx, dt)
            if ctx.guardReachedWaypoint then
                ctx.guardReturnDwell = (ctx.guardReturnDwell or 0) + dt
                if ctx.guardReturnDwell >= CONFIG.RETURN_DWELL then return "Guarding" end
                return nil
            end

            ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
            if ctx.guardDetectTimer < CONFIG.DETECT_INTERVAL then return nil end
            ctx.guardDetectTimer = 0
            return BehaviorHelpers.detectNearestPlayerInRange(ctx, CONFIG, "guardTarget", "Chasing")
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

- **`detectNearestPlayerInRange`** replaces the old local `detectPlayerWithLOS` helper — shared utility handles distance + `REQUIRE_LOS` check in one call. Used by both Guarding and Returning.
- **LOS memory strategy:** `REQUIRE_LOS = true` blocks initial detection through walls. `LOS_MEMORY` (seconds) lets `evaluateChaseTarget` count down via `ctx.losLostTimer` when sight is lost during chase — NPC gives up after N seconds without regaining LOS. This completes the stealth loop: walls block detection AND allow escape.
- **`hasLineOfSight(targetPos, { target })`** -- the second argument excludes the target player's character from the raycast. Without this, the ray hits the target's own body parts and LOS always returns false.
- **Guard returns to nearest waypoint**, not a fixed home. Prevents awkward cross-zone sprinting after a chase.
- **`RETURN_DWELL` minimum time** -- without this, Returning completes in 1-2 frames and is invisible in debug panels.
- **Detection during return** -- guard can interrupt its return to chase a newly detected player.
- **Random waypoint selection excludes last visited** -- prevents back-and-forth.
- **Always clear `losLostTimer` in Chasing `onExit`** -- timer lives on shared context, must be reset between chases.

## 7. BehaviorHelpers API

Shared utility functions used by all behavior state modules.

### findNearestPlayer(position: Vector3): Model?

Iterates all players via `Players:GetPlayers()`, returns the nearest character model by distance from the given position. Returns `nil` if no players exist or no player has a spawned character.

```lua
local target = BehaviorHelpers.findNearestPlayer(rootPart.Position)
if not target then return nil end
```

### detectNearestPlayerInRange(ctx, config, targetField, transitionState): string?

Combined detection helper — checks distance and optional LOS in one call. Use this for `onUpdate` in Idle/Guarding/Returning states instead of inline detection boilerplate.

- Finds nearest player via `findNearestPlayer`
- Checks distance against `config.DETECTION_RADIUS`
- If `config.REQUIRE_LOS ~= false`, raycasts via `ctx.pathfinder:hasLineOfSight()` (excludes target model)
- On success: sets `ctx[targetField] = target`, returns `transitionState`
- On fail: returns `nil`

```lua
-- In Idle onUpdate:
return BehaviorHelpers.detectNearestPlayerInRange(ctx, CONFIG, "chaseTarget", "Chasing")

-- CONFIG must have: DETECTION_RADIUS (number), REQUIRE_LOS (boolean?, default true)
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

Core re-evaluation logic shared by all chase-capable behaviors. Call from `onUpdate` of a Chasing state on a throttled timer (not every frame).

**Parameters:**
- `ctx` -- the shared context table
- `config` -- table with `DETECTION_RADIUS`, `REEVALUATE_INTERVAL`, and optionally `REQUIRE_LOS` + `LOS_MEMORY`
- `targetField` -- string key on ctx where the current target is stored (e.g., `"chaseTarget"`, `"guardTarget"`)
- `lostState` -- state name to transition to when the target is lost (e.g., `"Idle"`, `"Returning"`)
- `requireLOS` -- if true, only switches to a closer target when LOS check passes

**Returns:**
- `nil` -- current target is still valid, stay in Chasing
- `lostState` -- current target invalid (left game, out of range, or LOS memory expired), clears `ctx[targetField]`
- `"Chasing"` -- switching to a closer player (self-transition: triggers `onExit` then `onEnter` with new target)

**Logic flow:**
1. Validate current target: still in game? Still within `DETECTION_RADIUS`?
2. If invalid → return `lostState`, clear `ctx[targetField]` and `ctx.losLostTimer`
3. If `config.LOS_MEMORY` and `config.REQUIRE_LOS` are set: check LOS this tick
   - LOS regained → clear `ctx.losLostTimer`
   - LOS lost → increment `ctx.losLostTimer` by `REEVALUATE_INTERVAL`
   - Timer ≥ `LOS_MEMORY` → return `lostState` (NPC gives up)
4. Find nearest player. If a different, closer player exists within range:
   - If `requireLOS` is true, check LOS before switching
   - On success: clear `ctx.losLostTimer`, set new target, return `"Chasing"` (self-transition)
5. Otherwise return `nil` (keep chasing current target)

```lua
-- Chase NPC: LOS_MEMORY countdown, no LOS required for target switching
return BehaviorHelpers.evaluateChaseTarget(ctx, CONFIG, "chaseTarget", "Idle", false)

-- Guard NPC: LOS_MEMORY countdown, LOS required to switch to a new target
return BehaviorHelpers.evaluateChaseTarget(ctx, CONFIG, "guardTarget", "Returning", true)
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
