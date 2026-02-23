# Game-Specific AI Behavior Patterns

These patterns layer on top of the base pathfinding module. Each assumes you have a working `NPCPathfinder` instance that can move an NPC between points.

## Pattern: Chase

**Use when:** NPC pursues a moving target (enemy chasing player, zombie horde, guard alerted to intruder).

**Key decisions:**
- How often to recompute the path (balance responsiveness vs. performance)
- When to switch from pathfinding to direct MoveTo (short range, line of sight)
- What happens when the target is unreachable
- Attack range / stopping distance

```lua
local CHASE_RECOMPUTE_INTERVAL = 0.5     -- seconds
local DIRECT_CHASE_DISTANCE = 15          -- switch to direct MoveTo
local ATTACK_RANGE = 5                    -- stop pathfinding, start attacking
local GIVE_UP_DISTANCE = 150              -- stop chasing if target is too far
local GIVE_UP_TIME = 10                   -- stop chasing if no progress for this long

function ChaseController:start(npc, pathfinder, target)
    self.active = true
    self.lastProgressTime = tick()
    self.lastNPCPosition = npc.PrimaryPart.Position

    task.spawn(function()
        while self.active do
            local targetRoot = target.Character
                and target.Character:FindFirstChild("HumanoidRootPart")
            if not targetRoot then
                self:onTargetLost(npc, pathfinder)
                break
            end

            local distance = (targetRoot.Position - npc.PrimaryPart.Position).Magnitude

            -- Give up if too far
            if distance > GIVE_UP_DISTANCE then
                self:onTargetLost(npc, pathfinder)
                break
            end

            -- In attack range — stop moving, start combat
            if distance <= ATTACK_RANGE then
                pathfinder:stop()
                self:onAttackRange(npc, target)
            -- Close + line of sight — direct chase (cheaper than pathfinding)
            elseif distance <= DIRECT_CHASE_DISTANCE and self:hasLineOfSight(npc, targetRoot) then
                pathfinder:stop()
                npc:FindFirstChild("Humanoid"):MoveTo(targetRoot.Position)
            -- Far or obstructed — use pathfinding
            else
                pathfinder:moveTo(targetRoot.Position)
            end

            -- Stuck detection
            local moved = (npc.PrimaryPart.Position - self.lastNPCPosition).Magnitude
            if moved > 2 then
                self.lastProgressTime = tick()
                self.lastNPCPosition = npc.PrimaryPart.Position
            elseif tick() - self.lastProgressTime > GIVE_UP_TIME then
                self:onStuck(npc, pathfinder)
                break
            end

            task.wait(CHASE_RECOMPUTE_INTERVAL)
        end
    end)
end

function ChaseController:hasLineOfSight(npc, targetPart)
    local origin = npc.PrimaryPart.Position
    local direction = targetPart.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {npc, targetPart.Parent}
    local result = workspace:Raycast(origin, direction, params)
    return result == nil
end

function ChaseController:onTargetLost(npc, pathfinder)
    pathfinder:stop()
    -- Options: return to spawn, wander, idle, alert nearby NPCs
end

function ChaseController:onStuck(npc, pathfinder)
    pathfinder:stop()
    -- Options: teleport to nearest walkable point, try alternate path, give up
end

function ChaseController:onAttackRange(npc, target)
    -- Trigger attack behavior (game-specific)
end

function ChaseController:stop()
    self.active = false
end
```

### Chase Variants
- **Persistent chase** — Never gives up. Recompute interval stays constant. (Horror games)
- **Alert-based chase** — Chases while target is in detection range. Returns to post if target escapes. (Stealth games)
- **Pack chase** — Multiple NPCs coordinate. One pathfinds, others follow with offset. (Zombie hordes)
- **Predictive chase** — Pathfind to where the target will be, not where they are. Extrapolate position from velocity.

## Pattern: Patrol

**Use when:** NPC follows a set route and repeats it (guards, townspeople, ambient creatures).

**Key decisions:**
- Loop vs. ping-pong (A→B→C→A vs. A→B→C→B→A)
- Wait time at each point
- What interrupts patrol (spotting player, taking damage, scripted event)
- Resume behavior after interruption

```lua
function PatrolController:start(npc, pathfinder, waypoints, config)
    config = config or {}
    local loopMode = config.loopMode or "loop"        -- "loop" or "pingpong"
    local waitTime = config.waitTime or 2              -- seconds at each waypoint
    local onArrival = config.onArrival or function() end  -- callback at each point

    self.active = true
    self.currentIndex = 1
    self.direction = 1  -- 1 = forward, -1 = backward (for pingpong)

    task.spawn(function()
        while self.active do
            local target = waypoints[self.currentIndex]
            local targetPos = typeof(target) == "Vector3" and target
                or target.Position  -- Support both Vector3 and BasePart

            local reached = pathfinder:moveTo(targetPos)

            if reached then
                onArrival(self.currentIndex, target)
                task.wait(waitTime)
            end

            -- Advance to next waypoint
            if loopMode == "loop" then
                self.currentIndex = (self.currentIndex % #waypoints) + 1
            elseif loopMode == "pingpong" then
                self.currentIndex = self.currentIndex + self.direction
                if self.currentIndex > #waypoints then
                    self.direction = -1
                    self.currentIndex = #waypoints - 1
                elseif self.currentIndex < 1 then
                    self.direction = 1
                    self.currentIndex = 2
                end
            end
        end
    end)
end

function PatrolController:interrupt()
    self.active = false
    -- currentIndex preserved — can resume from where they left off
end

function PatrolController:resume(npc, pathfinder, waypoints, config)
    -- Resume from current index
    self:start(npc, pathfinder, waypoints, config)
end

function PatrolController:stop()
    self.active = false
    self.currentIndex = 1
end
```

### Patrol Tips
- Pre-compute and cache patrol paths if the environment is static. No need to recompute every loop.
- Use Parts or Attachments in Workspace as waypoints (easy to visualize and adjust in Studio).
- Add `waitTime` variation (randomize ±1 second) so multiple patrolling NPCs don't feel synchronized.

## Pattern: Flee

**Use when:** NPC runs away from a threat (civilians fleeing combat, cowardly enemies, escort targets).

**Key decisions:**
- Where to flee TO (away from threat, toward safe zone, random direction)
- When to stop fleeing (distance threshold, safe zone reached, timer)
- Speed boost during flee?

```lua
local FLEE_DISTANCE = 50            -- how far to run from threat
local SAFE_DISTANCE = 60            -- stop fleeing when this far away
local MAX_FLEE_ATTEMPTS = 5         -- tries to find a valid flee point

function FleeController:start(npc, pathfinder, threatPosition)
    self.active = true

    task.spawn(function()
        local fleePoint = self:findFleePoint(npc, threatPosition)

        if fleePoint then
            pathfinder:moveTo(fleePoint)
        else
            -- Couldn't find valid flee point — cower in place or try random directions
            self:onFleeBlocked(npc)
        end
    end)
end

function FleeController:findFleePoint(npc, threatPosition)
    local origin = npc.PrimaryPart.Position
    local awayDirection = (origin - threatPosition).Unit

    for attempt = 1, MAX_FLEE_ATTEMPTS do
        -- Add randomness to avoid all NPCs fleeing to the same spot
        local angle = math.rad(math.random(-45, 45))
        local rotatedDir = CFrame.Angles(0, angle, 0) * Vector3.new(awayDirection.X, 0, awayDirection.Z)
        local candidatePos = origin + rotatedDir * FLEE_DISTANCE

        -- Validate: raycast down to find ground
        local groundCheck = workspace:Raycast(
            candidatePos + Vector3.new(0, 10, 0),
            Vector3.new(0, -50, 0)
        )

        if groundCheck then
            return groundCheck.Position
        end
    end

    return nil  -- No valid flee point found
end
```

### Flee Variants
- **Flee to safe zone** — Instead of fleeing a fixed distance, pathfind to a designated safe area (building, spawn point).
- **Scatter** — Each NPC picks a random direction. Good for civilian panic.
- **Flee then hide** — Run to a safe distance, then find nearest cover point (raycast for walls/objects).

## Pattern: Wander

**Use when:** NPC moves randomly within an area (ambient creatures, idle townspeople, exploration behavior).

```lua
local WANDER_RADIUS = 30       -- max distance from home point
local WANDER_IDLE_MIN = 3      -- min seconds between wanders
local WANDER_IDLE_MAX = 8      -- max seconds between wanders
local MAX_WANDER_ATTEMPTS = 10 -- attempts to find valid random point

function WanderController:start(npc, pathfinder, homePosition, radius)
    radius = radius or WANDER_RADIUS
    self.active = true

    task.spawn(function()
        while self.active do
            local wanderPoint = self:findRandomPoint(homePosition, radius)

            if wanderPoint then
                pathfinder:moveTo(wanderPoint)
            end

            -- Random idle time
            local idleTime = math.random(WANDER_IDLE_MIN, WANDER_IDLE_MAX)
            task.wait(idleTime)
        end
    end)
end

function WanderController:findRandomPoint(center, radius)
    for _ = 1, MAX_WANDER_ATTEMPTS do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius
        local candidate = center + Vector3.new(
            math.cos(angle) * dist,
            0,
            math.sin(angle) * dist
        )

        -- Raycast down to validate ground exists AND reject points inside obstacles.
        -- Without this, random points can land on top of or inside obstacle geometry,
        -- causing pathfinding failures or NPCs trying to walk through walls.
        -- The hit position also provides accurate Y-snapping to ground level.
        local groundCheck = workspace:Raycast(
            candidate + Vector3.new(0, 10, 0),
            Vector3.new(0, -50, 0)
        )

        if groundCheck then
            -- Reject if the hit is an obstacle (not the baseplate/terrain)
            -- Adapt this check to your game's ground detection strategy
            local hitPart = groundCheck.Instance
            if hitPart and hitPart.Name ~= "Baseplate" and hitPart.Parent
                and hitPart.Parent.Name == "Obstacles" then
                continue
            end
            return groundCheck.Position
        end
    end
    return nil
end
```

## Pattern: Guard

**Use when:** NPC patrols a zone and chases intruders, then returns to post (security guards, sentries, base defenders).

This is a composite pattern: Patrol + Chase + Return.

```lua
local DETECTION_RADIUS = 40
local CHASE_GIVE_UP_RADIUS = 60   -- return to post if target escapes this far from guard post
local RETURN_THRESHOLD = 3        -- close enough to post to resume patrol

function GuardController:start(npc, pathfinder, patrolPoints, guardCenter)
    self.state = "patrol"
    self.active = true

    local patrolCtrl = PatrolController.new()
    local chaseCtrl = ChaseController.new()

    task.spawn(function()
        patrolCtrl:start(npc, pathfinder, patrolPoints, { waitTime = 3 })

        while self.active do
            if self.state == "patrol" then
                -- Check for targets in detection radius
                local target = self:findNearestTarget(npc, DETECTION_RADIUS)
                if target then
                    self.state = "chase"
                    patrolCtrl:interrupt()
                    chaseCtrl:start(npc, pathfinder, target)
                end

            elseif self.state == "chase" then
                -- Check if target escaped beyond give-up range from guard post
                local targetRoot = self.currentTarget
                    and self.currentTarget.Character
                    and self.currentTarget.Character:FindFirstChild("HumanoidRootPart")

                local distFromPost = targetRoot
                    and (targetRoot.Position - guardCenter).Magnitude
                    or math.huge

                if distFromPost > CHASE_GIVE_UP_RADIUS or not targetRoot then
                    self.state = "return"
                    chaseCtrl:stop()
                end

            elseif self.state == "return" then
                pathfinder:moveTo(guardCenter)
                local distToPost = (npc.PrimaryPart.Position - guardCenter).Magnitude
                if distToPost <= RETURN_THRESHOLD then
                    self.state = "patrol"
                    patrolCtrl:resume(npc, pathfinder, patrolPoints, { waitTime = 3 })
                end
            end

            task.wait(0.5)
        end
    end)
end
```

## Pattern: Formation Movement

**Use when:** Multiple NPCs move together maintaining relative positions (squad, convoy, army units).

```lua
function FormationController:start(leader, followers, pathfinder, destination, offsets)
    -- Leader pathfinds normally
    pathfinder:moveTo(destination)

    -- Followers maintain offset from leader
    for i, follower in followers do
        local offset = offsets[i] or Vector3.new(i * 4, 0, -4)

        task.spawn(function()
            while self.active do
                local leaderPos = leader.PrimaryPart.Position
                local leaderCF = leader.PrimaryPart.CFrame
                local targetPos = leaderCF:PointToWorldSpace(offset)

                -- Followers use direct MoveTo if close, pathfinding if obstructed
                local distance = (follower.PrimaryPart.Position - targetPos).Magnitude
                if distance > 5 then
                    follower:FindFirstChild("Humanoid"):MoveTo(targetPos)
                end

                task.wait(0.3)
            end
        end)
    end
end
```

### Formation Tips
- Adjust offset positions based on terrain width (tighten in corridors, spread in open areas)
- If a follower falls too far behind, have them pathfind to catch up rather than MoveTo through walls
- Leader speed may need to slow down to keep formation coherent

## Composing Behaviors

These patterns are designed to be composed. A typical NPC might cycle through:

1. **Wander** (idle state) → detects player → **Chase** → reaches attack range → **Attack** (game-specific) → player escapes → **Return** to home → **Wander**

2. **Patrol** → takes damage → **Flee** → reaches safe distance → **Patrol** (from nearest patrol point)

3. **Guard** (patrol + chase + return) as a self-contained composite

The base `NPCPathfinder` module provides the movement primitives. These behavior controllers manage *when* and *where* to call those primitives. Keep them separate — movement and decision-making are different concerns.
