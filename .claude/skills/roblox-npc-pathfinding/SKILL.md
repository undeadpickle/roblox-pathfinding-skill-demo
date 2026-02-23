---
name: roblox-npc-pathfinding
description: >
  Production-grade NPC pathfinding for Roblox games using PathfindingService.
  Covers architecture, implementation, debugging, and game-specific AI behaviors
  (chase, patrol, flee, formations). Use when user asks to add NPC pathfinding,
  fix NPC movement, make enemies chase players, create patrol routes, debug
  stuck NPCs, audit pathfinding code, integrate pathfinding into a Roblox game,
  improve NPC AI navigation, or build AI behavior on top of pathfinding.
  Applies to humanoid character models. Supports Luau.
metadata:
  author: custom
  version: 1.0.0
  category: game-development
  tags: [roblox, luau, npc, pathfinding, ai, game-dev]
---

# Roblox NPC Pathfinding

## How to Use This Skill

Before writing any code, determine which scenario matches the user's situation:

| Scenario | Signal | Action |
|----------|--------|--------|
| **Build from scratch** | No game yet, greenfield NPC system | Full architecture walkthrough, generate base module, set up project structure |
| **Integrate into existing game** | Has a game with folder structure, no pathfinding yet | Ask about their project structure first, adapt module to fit, provide integration glue |
| **Audit and improve** | Has working pathfinding, wants it reviewed | Run the audit checklist against their code, prioritize fixes |
| **Debug specific issue** | Something is broken right now (stuck, zig-zag, errors) | Jump to common-pitfalls.md, diagnose systematically |
| **Add game-specific AI behavior** | Base movement works, needs chase/patrol/flee/formations | Consult behavior-patterns.md, layer behavior on top of existing pathfinding |

Ask the user which scenario applies. If unclear from context, ask:

> Are you starting fresh, adding pathfinding to an existing game, improving what you have, fixing a bug, or layering on AI behaviors like chasing or patrolling?

## Critical: Before Any Implementation

These apply to ALL scenarios. Verify or set these before writing pathfinding code:

### 1. Enable Improved Pathfinding Algorithm
In Roblox Studio: Workspace → Properties → `PathfindingUseImprovedSearch` → **Enabled**

This was released Nov 2024 / re-enabled March 2025. It fixes zig-zagging, wall-hugging, agent size being ignored, and terrain navmesh issues. There is no reason to leave this off for new work.

**⚠ This property is NOT scriptable.** You cannot enable it via code or MCP — it must be set manually in Studio.

### 2. NPC Model Requirements
Every pathfinding NPC needs:
- A `Model` with `PrimaryPart` set to `HumanoidRootPart`
- A `Humanoid` instance (for `MoveTo` and `MoveToFinished`)
- `HumanoidRootPart` must be an anchored-false part
- Model should be in `Workspace` (not ReplicatedStorage) when pathfinding

### 3. Network Ownership (Server-Side NPCs)
CRITICAL: Lock network ownership to the server immediately when the NPC spawns:

```lua
npcModel.PrimaryPart:SetNetworkOwner(nil)
```

Without this, `Humanoid:MoveTo()` and `MoveToFinished` have unpredictable latency as ownership bounces between server and nearest client. This is the #1 cause of jittery/laggy NPC movement.

### 4. NPC Collision Group
When multiple NPCs converge (chasing the same target, patrolling through a chokepoint), their HumanoidRootParts collide and cause physics jitter. Fix by putting all NPCs in a collision group with self-collisions disabled:

```lua
local PhysicsService = game:GetService("PhysicsService")
PhysicsService:RegisterCollisionGroup("NPCs")
PhysicsService:CollisionGroupSetCollidable("NPCs", "NPCs", false)
```

Then assign NPC parts: `part.CollisionGroup = "NPCs"`

The base module (`assets/npc-pathfinder-module.luau`) handles this automatically via the `CollisionGroup` config option.

### 5. Script Placement
- Pathfinding logic runs on the **server** (ServerScriptService or inside the NPC model)
- Place the pathfinding module in **ServerScriptService or ServerStorage**, NOT ReplicatedStorage — NPC AI logic in ReplicatedStorage is visible to exploiters who can decompile it and learn behavior patterns
- A centralized ModuleScript is preferred over script-per-NPC

## Scenario 1: Build From Scratch

1. Read `references/api-quick-reference.md` to understand the current API surface
2. Read `references/agent-configuration.md` to configure agent params for the NPC size
3. Use `assets/npc-pathfinder-module.luau` as the base — it is production-ready and extensible
4. Place the module in `ServerScriptService` or `ServerStorage` (NOT `ReplicatedStorage` — NPC AI logic should not be replicated to clients where exploiters can decompile it)
5. Create a server Script that requires the module and spawns NPCs
6. Test with nav mesh visualization enabled (View → Visualization Options → Navigation Mesh)

### Minimal Quick Start (before using the full module)

This is the absolute minimum to get an NPC walking to a point. Use this to verify your setup works, then switch to the full module:

```lua
-- Server Script in ServerScriptService
local PathfindingService = game:GetService("PathfindingService")

local npc = workspace:WaitForChild("TestNPC")
local humanoid = npc:WaitForChild("Humanoid")
npc.PrimaryPart:SetNetworkOwner(nil)

local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,
})

local destination = Vector3.new(50, 0, 50)

local success, err = pcall(function()
    path:ComputeAsync(npc.PrimaryPart.Position, destination)
end)

if success and path.Status == Enum.PathStatus.Success then
    local waypoints = path:GetWaypoints()
    -- Start from index 2: waypoint 1 is the NPC's current position.
    -- Its Y is at navmesh height (Y=0), not hip height, so 3D distance
    -- checks fail and MoveToFinished fires instantly on a stale position.
    for i = 2, #waypoints do
        local waypoint = waypoints[i]
        humanoid:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        local reached = humanoid.MoveToFinished:Wait()
        if not reached then
            break -- NPC got stuck (8s timeout) — recompute or abort
        end
    end
end
```

Once this works, move to the full module for production use.

## Scenario 2: Integrate Into Existing Game

Before generating any code, gather this context:

1. **Project structure** — Where are scripts? ServerScriptService? Per-model? ModuleScript pattern?
2. **Existing NPC setup** — Do NPCs exist already? How are they spawned? Is there a spawner/pool system?
3. **Existing movement** — Any `MoveTo` calls without pathfinding? State machine? Behavior system?
4. **Game type** — This determines which behaviors to wire up (see Scenario 5)
5. **NPC count** — Under 20 concurrent = straightforward. Over 20 = consult `references/performance-patterns.md`
6. **Environment** — Static map or dynamic (destructible, doors, moving platforms)?

Then: read `references/integration-guide.md` for the full decision tree on where to place the module and how to connect it to their existing systems.

Generate the module adapted to their naming conventions and import patterns. Provide one fully wired example NPC in their project structure.

## Scenario 3: Audit and Improve Existing Pathfinding

Read the user's code, then systematically run through `references/audit-checklist.md`.

Output format:
1. **Critical issues** — Will cause bugs or major performance problems. Fix immediately.
2. **Warnings** — Works but fragile or suboptimal. Fix when convenient.
3. **Suggestions** — Nice-to-have improvements and modern API features they're not using.
4. **Specific code patches** — For each issue, show the exact before/after fix.

## Scenario 4: Debug Specific Issue

Read `references/common-pitfalls.md` and match the user's symptom to known causes.

Common symptoms and first checks:
- **NPC stuck / not moving** → Network ownership, `MoveToFinished` timeout, waypoint unreachable, `SpawnLocation.CanCollide` blocking path
- **NPC stuck after being knocked over** → Humanoid physics recovery states (`FallingDown`, `GettingUp`, `Freefall`, `Landed`) were disabled. Only disable these on flat geometry with no collision risk.
- **NPC zig-zags** → `PathfindingUseImprovedSearch` not enabled, `AgentRadius` too small
- **NPC walks through walls** → `PathfindingUseImprovedSearch` not enabled, `AgentRadius` doesn't match model
- **Path returns NoPath** → Destination unreachable, nav mesh gap, agent too large for space
- **NPC jitters near waypoints** → `MoveToFinished` latency (network ownership), waypoint spacing too small
- **NPC recomputes path rapidly (dozens/sec)** → `MoveTo(currentPosition)` used as a "stop" mechanism fires a stale `MoveToFinished(true)` that subsequent `:Wait()` calls catch instantly. Clear waypoint state without issuing a MoveTo call.
- **Waypoint arrival detection fails on first waypoint** → `GetWaypoints()` index 1 is the start position at navmesh Y (≈0), not hip height. Skip index 1, start traversal from index 2.
- **`MoveToFinished` resolves but NPC hasn't visually arrived** → `MoveToFinished` checks XZ distance only (ignoring Y). Don't mix it with 3D `Vector3.Magnitude` distance checks — they'll disagree when Y differs.
- **`stop()` silently kills the calling thread** → If `stop()` calls `task.cancel()` on a thread that called `stop()`, the thread dies mid-execution. Use a separate reset method that clears state without cancelling the calling thread.
- **ComputeAsync errors** → Missing pcall, start/end position inside geometry

Always ask the user to enable nav mesh visualization and check if the destination is actually reachable on the mesh.

## Scenario 5: Add Game-Specific AI Behavior

Read `references/behavior-patterns.md` for detailed implementation patterns.

The base module provides movement primitives. Game behavior layers on top:

| Behavior | Key Pattern |
|----------|-------------|
| **Chase** | Recompute path every 0.5–1s toward target. Direct `MoveTo` when close + line-of-sight. Stop at attack range. |
| **Patrol** | Pre-defined waypoint list. Loop or ping-pong. Resume after interruption. |
| **Flee** | Compute path away from threat. Pick point in opposite direction at safe distance. |
| **Wander** | Random point within radius. Validate with `Workspace:Raycast` downward to reject points inside obstacles and Y-snap to ground. Idle between moves. |
| **Guard** | Patrol a zone. Chase if target enters radius. Return to post if target escapes. |
| **Formation** | Leader pathfinds. Followers offset from leader position. Adjust spacing dynamically. |

For any behavior pattern, the user should provide:
- What triggers the behavior (proximity, damage, event)
- What ends the behavior (target lost, timer, reaching destination)
- What happens on failure (can't reach target, path blocked)

## Deprecated APIs — Never Use These

- `PathfindingService:ComputeSmoothPathAsync()` → Use `CreatePath()` + `ComputeAsync()`
- `PathfindingService:ComputeRawPathAsync()` → Use `CreatePath()` + `ComputeAsync()`
- `PathfindingService:FindPathAsync()` → Use `CreatePath()` + `ComputeAsync()`

If you see these in existing code, flag for immediate replacement.

## Reference Files

Consult these as needed based on scenario:

- `references/api-quick-reference.md` — Full current API surface, enums, events, parameters
- `references/agent-configuration.md` — How to size agents, material costs, modifier setup
- `references/pathfinding-modifiers.md` — PathfindingModifier, PathfindingLink, custom traversals
- `references/performance-patterns.md` — Scaling 20+ NPCs, staggered recompute, rendering optimization
- `references/common-pitfalls.md` — Known bugs, debugging checklist, symptom-to-cause map
- `references/audit-checklist.md` — Structured code review framework for existing pathfinding
- `references/integration-guide.md` — How to assess a project and integrate pathfinding into it
- `references/behavior-patterns.md` — Chase, patrol, flee, wander, guard, formation implementations
