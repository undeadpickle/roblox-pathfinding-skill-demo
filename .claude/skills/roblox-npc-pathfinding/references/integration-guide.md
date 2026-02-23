# Integration Guide: Adding Pathfinding to an Existing Game

## Phase 1: Assess the Project

Before writing any pathfinding code, understand the existing project. Ask these questions:

### Script Architecture
- Where do server scripts live? (`ServerScriptService`, inside models, both?)
- Do they use ModuleScripts? Where are shared modules stored? (`ReplicatedStorage`, `ServerScriptService`, `ServerStorage`?)
- What's the require pattern? (direct path, or some kind of loader/framework?)
- Is there a game framework in use? (Knit, ProfileService patterns, custom?)

### Existing NPC Setup
- Do NPC models already exist in the game? Where? (`Workspace`, `ServerStorage`, `ReplicatedStorage`?)
- How are NPCs spawned? (placed in Studio, spawned from a template, object pool?)
- Do NPCs have Humanoids already?
- Is `PrimaryPart` set on NPC models?
- Any existing movement logic? (even basic `MoveTo` to fixed positions?)

### Game Context
- What should NPCs do? (chase, patrol, guard, wander, flee, stand still until triggered?)
- How many NPCs at once?
- Is the environment static or dynamic?
- Indoors, outdoors, or mixed?
- Are there obstacles NPCs need special handling for? (doors, elevators, bridges?)

## Phase 2: Workspace Setup

These changes apply regardless of game architecture:

1. **Enable improved pathfinding:**
   Workspace → Properties → `PathfindingUseImprovedSearch` → **Enabled**

2. **Verify NPC models have required components:**
   - `Humanoid` instance
   - `HumanoidRootPart` (set as `PrimaryPart`)
   - `HumanoidRootPart.Anchored = false`

3. **Enable nav mesh visualization** in Studio to verify your environment is walkable.

4. **Add PathfindingModifiers** for any areas that need special treatment:
   - Danger zones: Anchored CanCollide=false parts with PathfindingModifier (Label = "Danger")
   - Doors: PathfindingModifier with PassThrough = true
   - Preferred paths: PathfindingModifier with low-cost label

## Phase 3: Module Placement

Place `npc-pathfinder-module.luau` based on their existing architecture. **Default to server-side locations** — NPC AI logic should not be in ReplicatedStorage where clients can decompile it and learn behavior patterns (aggro ranges, timing, decision logic).

| Their Pattern | Place Module In | Require Pattern |
|--------------|-----------------|-----------------|
| Modules in ServerScriptService | `ServerScriptService.Modules` | `require(ServerScriptService.Modules.NPCPathfinder)` |
| Modules in ServerStorage | `ServerStorage.Modules` | `require(ServerStorage.Modules.NPCPathfinder)` |
| Modules in ReplicatedStorage | Move NPC module to `ServerScriptService.Modules` instead | `require(ServerScriptService.Modules.NPCPathfinder)` |
| No module pattern (scripts only) | `ServerScriptService.NPCPathfinder` | `require(script.Parent.NPCPathfinder)` or direct path |
| Framework (Knit, etc.) | Follow framework conventions for services (server-side) | Framework-specific require |

> **Why not ReplicatedStorage?** Everything in ReplicatedStorage is sent to every client. Exploiters can decompile ModuleScripts there. While they can't force the server NPC to do anything, they CAN read your aggro radius, recompute intervals, stuck detection thresholds, and decision logic — then exploit those patterns (kiting NPCs, abusing blind spots, timing invulnerability windows). Server-side AI logic should stay opaque.

Rename the module file to match their naming convention (PascalCase, camelCase, etc.).

## Phase 4: Connect to Existing NPC System

### If they have a spawner/pool system:

Hook into their existing spawn flow. After the NPC model is created/retrieved:

```lua
-- In their existing spawn function, add:
local NPCPathfinder = require(path.to.NPCPathfinder)

function spawnNPC(template, spawnPosition)
    -- Their existing spawn logic
    local npcModel = template:Clone()
    npcModel:PivotTo(CFrame.new(spawnPosition))
    npcModel.Parent = workspace

    -- ADD: Initialize pathfinding
    npcModel.PrimaryPart:SetNetworkOwner(nil)
    local pathfinder = NPCPathfinder.new(npcModel, {
        AgentRadius = 2,
        AgentHeight = 5,
    })

    -- Store reference for later use
    npcModel:SetAttribute("PathfinderActive", true)

    return npcModel, pathfinder
end
```

### If NPCs are pre-placed in Workspace:

Create an initialization script that finds and initializes all NPCs:

```lua
-- ServerScriptService/InitNPCPathfinding
local NPCPathfinder = require(path.to.NPCPathfinder)
local pathfinders = {}

for _, npc in workspace.NPCs:GetChildren() do
    if npc:FindFirstChild("Humanoid") then
        npc.PrimaryPart:SetNetworkOwner(nil)
        local pf = NPCPathfinder.new(npc, {
            AgentRadius = 2,
            AgentHeight = 5,
        })
        pathfinders[npc] = pf
    end
end
```

### If they have a state machine or behavior system:

The pathfinder module provides movement primitives. Wire them into the existing state system:

```lua
-- Example: existing state machine integration
function NPCStateMachine:enterState(state)
    if state == "Chase" then
        self.pathfinder:followTarget(self.target, {
            recomputeInterval = 0.5,
            arrivalDistance = 5,
        })
    elseif state == "Patrol" then
        self.pathfinder:patrol(self.patrolPoints)
    elseif state == "Idle" then
        self.pathfinder:stop()
    end
end
```

### If they have NO existing NPC management:

Create a simple manager:

```lua
-- ServerScriptService/NPCManager
local NPCPathfinder = require(path.to.NPCPathfinder)

local NPCManager = {}
NPCManager.npcs = {}

function NPCManager:register(npcModel, config)
    npcModel.PrimaryPart:SetNetworkOwner(nil)
    local entry = {
        model = npcModel,
        pathfinder = NPCPathfinder.new(npcModel, config or {}),
    }
    self.npcs[npcModel] = entry
    return entry
end

function NPCManager:remove(npcModel)
    local entry = self.npcs[npcModel]
    if entry then
        entry.pathfinder:destroy()
        self.npcs[npcModel] = nil
    end
end

function NPCManager:getPathfinder(npcModel)
    local entry = self.npcs[npcModel]
    return entry and entry.pathfinder
end

return NPCManager
```

## Phase 5: Wire Up One NPC End-to-End

Before scaling to all NPCs, get ONE working perfectly:

1. Pick the simplest NPC in the game
2. Initialize it with the pathfinder module
3. Give it a basic task (move to a fixed point)
4. Verify: nav mesh shows a path, NPC moves smoothly, no errors
5. Test: move an obstacle into the path — does the NPC recompute?
6. Test: destroy the NPC — does cleanup happen without errors?

Once this works, expand to all NPCs.

## Phase 6: Handle Cleanup

NPCs that are destroyed must clean up pathfinding connections:

```lua
npcModel.Destroying:Connect(function()
    local pathfinder = NPCManager:getPathfinder(npcModel)
    if pathfinder then
        NPCManager:remove(npcModel)
    end
end)
```

Or if using Humanoid.Died:

```lua
humanoid.Died:Connect(function()
    pathfinder:stop()
    -- Optional: delay before cleanup for death animation
    task.delay(3, function()
        pathfinder:destroy()
        npcModel:Destroy()
    end)
end)
```

## Common Integration Mistakes

1. **Forgetting to set network ownership** — The single most common integration bug. Always first.
2. **Running pathfinding on the client** — Unless you specifically need client-predicted NPCs, keep it server-side.
3. **Not testing with nav mesh visible** — Many integration issues are actually environment issues (gaps in nav mesh, walls not blocking correctly).
4. **Over-engineering from the start** — Get one NPC walking correctly before adding chase AI, state machines, and performance optimizations.
5. **Ignoring existing game loop timing** — If the game uses `RunService.Heartbeat` for updates, hook NPC updates into the same loop rather than creating separate `while` loops.
