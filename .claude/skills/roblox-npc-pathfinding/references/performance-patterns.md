# Performance Patterns for NPC Pathfinding

## Scale Tiers

| NPC Count | Complexity | Key Concern |
|-----------|-----------|-------------|
| 1–10 | Low | Just make it correct. Performance isn't an issue. |
| 10–30 | Medium | Stagger recomputation. Watch for simultaneous ComputeAsync calls. |
| 30–100 | High | OOP required. Consider client-side rendering. Aggressive recompute throttling. |
| 100+ | Extreme | Custom movement (BulkMoveTo), simplified pathfinding, LOD system for distant NPCs. |

## Core Principle: Not Every NPC Needs a Path Every Frame

The single biggest performance mistake is recomputing paths too frequently. PathfindingService:ComputeAsync() is expensive. Budget your calls.

### Recomputation Strategies

**Time-based throttle:**
```lua
local RECOMPUTE_INTERVAL = 1.0  -- seconds between path recomputes
local lastComputeTime = 0

local function shouldRecompute()
    local now = tick()
    if now - lastComputeTime >= RECOMPUTE_INTERVAL then
        lastComputeTime = now
        return true
    end
    return false
end
```

**Distance-based threshold (for chase AI):**
```lua
local RECOMPUTE_DISTANCE = 10  -- only recompute if target moved this far
local lastTargetPosition = nil

local function shouldRecompute(currentTargetPos)
    if not lastTargetPosition then
        lastTargetPosition = currentTargetPos
        return true
    end
    if (currentTargetPos - lastTargetPosition).Magnitude >= RECOMPUTE_DISTANCE then
        lastTargetPosition = currentTargetPos
        return true
    end
    return false
end
```

**Event-based (Path.Blocked):**
Only recompute when the path is actually blocked, not on a timer:
```lua
path.Blocked:Connect(function(blockedWaypointIndex)
    if blockedWaypointIndex >= nextWaypointIndex then
        recomputePath()
    end
end)
```

Best practice: combine all three. Use the blocked event for reactive recompute, a distance threshold for chase targets, and a time-based minimum interval to prevent spam.

## Staggered Computation

When multiple NPCs need paths, don't compute them all on the same frame.

```lua
local NPC_UPDATE_BATCH_SIZE = 5
local currentBatchIndex = 0

function updateNPCBatch(npcs)
    local startIdx = currentBatchIndex * NPC_UPDATE_BATCH_SIZE + 1
    local endIdx = math.min(startIdx + NPC_UPDATE_BATCH_SIZE - 1, #npcs)

    for i = startIdx, endIdx do
        npcs[i]:recomputePathIfNeeded()
    end

    currentBatchIndex = (currentBatchIndex + 1) % math.ceil(#npcs / NPC_UPDATE_BATCH_SIZE)
end

-- Call on Heartbeat or at fixed interval
RunService.Heartbeat:Connect(function()
    updateNPCBatch(allNPCs)
end)
```

This distributes pathfinding load across frames instead of spiking on one frame.

## Direct MoveTo vs. Pathfinding

For short distances with line of sight, `Humanoid:MoveTo()` directly is far cheaper than computing a path. Use a distance + raycast check:

```lua
local MAX_DIRECT_DISTANCE = 15  -- studs

function canMoveDirect(npc, targetPos)
    local origin = npc.PrimaryPart.Position
    local distance = (targetPos - origin).Magnitude

    if distance > MAX_DIRECT_DISTANCE then
        return false
    end

    -- Raycast to check line of sight
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {npc}

    local result = workspace:Raycast(origin, (targetPos - origin), rayParams)
    return result == nil  -- no hit = clear line of sight
end
```

Use direct MoveTo when possible, fall back to pathfinding when obstructed.

## Network Ownership

Every NPC's `PrimaryPart` (HumanoidRootPart) should have network ownership locked to the server:

```lua
npc.PrimaryPart:SetNetworkOwner(nil)
```

Without this:
- Roblox auto-assigns ownership to the nearest player
- Ownership transfers cause physics stutter
- `MoveToFinished` has unpredictable latency (fires late on the server when client owns the NPC)
- NPCs jitter when multiple players are near them

Do this ONCE when the NPC spawns. Don't set it repeatedly.

## OOP Module Pattern

Script-per-NPC does not scale. Use a centralized module:

```lua
-- NPCManager (ServerScriptService)
local NPCPathfinder = require(path.to.NPCPathfinder)

local activeNPCs = {}

function spawnNPC(model, destination)
    local npc = NPCPathfinder.new(model, {
        AgentRadius = 2,
        AgentHeight = 5,
    })
    table.insert(activeNPCs, npc)
    npc:moveTo(destination)
end

function cleanupNPC(npc)
    npc:destroy()
    -- remove from activeNPCs table
end
```

All NPC logic lives in the module. The manager script just orchestrates spawning and lifecycle.

## Reducing Humanoid Cost (High NPC Counts)

Humanoid is expensive. For 50+ NPCs, consider:

**Disable unused Humanoid states:**
```lua
-- Safe to disable — NPCs never use these
humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)

-- WARNING: Do NOT disable these when obstacles exist in the environment.
-- FallingDown, GettingUp, Freefall, and Landed form the physics recovery cycle.
-- Without them, an NPC knocked over by an obstacle stays down permanently.
-- Only disable on flat geometry with zero collision risk.
-- humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
-- humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
-- humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
-- humanoid:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
```

**Disable collision on NPC parts that don't need it:**
```lua
for _, part in npc:GetDescendants() do
    if part:IsA("BasePart") and part ~= npc.PrimaryPart then
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
    end
end
```

## WaypointSpacing Optimization

Larger `WaypointSpacing` = fewer waypoints = fewer `MoveTo` calls = better performance:

- Indoor/tight: `WaypointSpacing = 4` (default)
- Outdoor/open: `WaypointSpacing = 8–12`
- Tower defense lanes: `WaypointSpacing = math.huge` (only turns and action points)

## Extreme Scale (100+ NPCs): BulkMoveTo

For very high NPC counts, bypass `Humanoid:MoveTo()` entirely and move parts directly using `Workspace:BulkMoveTo()`. This skips physics simulation and is dramatically faster.

```lua
local parts = {}  -- array of PrimaryParts
local cframes = {}  -- array of target CFrames

-- Compute target positions from waypoints, then:
workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
```

Trade-offs:
- No physics (NPCs float over gaps, walk through walls visually)
- No Humanoid animation states
- You handle collision/animation manually
- Use for distant NPCs or large hordes where precision doesn't matter

## LOD (Level of Detail) for NPC Behavior

Not every NPC needs full pathfinding at all times:

| Distance from Camera | Behavior |
|---------------------|----------|
| Close (0–50 studs) | Full pathfinding, animations, collision |
| Medium (50–150 studs) | Simplified pathfinding (longer recompute interval), basic animation |
| Far (150+ studs) | No pathfinding. Teleport between key positions. Minimal/no animation. |
| Out of streaming range | Despawn or freeze entirely |

Implement with a distance check on each update cycle and adjust the NPC's behavior tier accordingly.
