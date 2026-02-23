# Agent Configuration Guide

## Sizing Your Agent

The most common pathfinding failure is agent size not matching the actual NPC model. The pathfinding system uses `AgentRadius` and `AgentHeight` to determine what spaces the NPC can fit through.

### How to Measure Your NPC

```lua
-- Get the bounding box of the NPC model
local npc = workspace.MyNPC
local cframe, size = npc:GetBoundingBox()

-- AgentRadius = half the widest horizontal dimension
local agentRadius = math.ceil(math.max(size.X, size.Z) / 2)

-- AgentHeight = total height
local agentHeight = math.ceil(size.Y)

print("AgentRadius:", agentRadius, "AgentHeight:", agentHeight)
```

### Common Agent Sizes

| NPC Type | AgentRadius | AgentHeight | Notes |
|----------|-------------|-------------|-------|
| Standard R15 character | 2 | 5 | Default values, works for most humanoids |
| Child/small character | 1 | 3 | Fits through smaller gaps |
| Large enemy/boss | 4–6 | 8–10 | Needs wider corridors. Test carefully. |
| Thin NPC (e.g., skeleton) | 1 | 5 | Can fit through tighter spaces |
| Wide NPC (e.g., mech) | 5–8 | 8–12 | May fail in indoor environments |

### Rules of Thumb
- Round UP, not down. A slightly too-large agent avoids wall clipping. A too-small agent walks through geometry.
- If your NPC is getting stuck on corners, increase `AgentRadius` by 1.
- If paths fail in spaces the NPC should fit through, decrease `AgentRadius` by 1.
- Test with nav mesh visualization ON (View → Visualization Options → Navigation Mesh).

## Material Costs

The `Costs` table in `CreatePath()` controls material preference. Higher cost = path avoids that material. Default cost for all materials is `1`.

```lua
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    Costs = {
        Water = 20,        -- Strongly avoid water
        Mud = 5,           -- Mildly avoid mud
        Neon = math.huge,  -- Never traverse neon (treated as impassable)
        Grass = 0.5,       -- Prefer grass over default
    },
})
```

### Cost Values Guide
| Cost | Effect |
|------|--------|
| `0.5` or lower | Agent prefers this material (will detour to use it) |
| `1` | Default — no preference |
| `5–20` | Agent avoids but will use if no alternative |
| `math.huge` | Completely impassable — agent will never cross this |

### Material Names (Case-Sensitive)
Use the exact Enum.Material name: `Plastic`, `Wood`, `Slate`, `Concrete`, `CorrodedMetal`, `DiamondPlate`, `Foil`, `Grass`, `Ice`, `Marble`, `Granite`, `Brick`, `Pebble`, `Sand`, `Fabric`, `SmoothPlastic`, `Metal`, `WoodPlanks`, `Cobblestone`, `Neon`, `Glass`, `ForceField`, `Water`, `Snow`, `Mud`, `Basalt`, `Rock`, `CrackedLava`, `Limestone`, `Asphalt`, `LeafyGrass`, `Salt`, `Sandstone`, `Pavement`, `Ground`, `Glacier`

### Terrain Materials
Terrain materials use the same names. If you set `Water = math.huge`, both Part materials and Terrain water become impassable.

## Climb Configuration

TrussParts are the only built-in climbable surface. Enable with:

```lua
local path = PathfindingService:CreatePath({
    AgentCanClimb = true,
    Costs = {
        Climb = 2,  -- Optional: make climbing cost more than walking (default is 1)
    },
})
```

Climbing waypoints have the `label` "Climb". Check for them in traversal if you need custom climb animation.

## Jump Configuration

When `AgentCanJump = true`, the pathfinding system generates Jump waypoints where the agent needs to jump to reach the next area (small ledges, gaps). Handle them during traversal:

```lua
if waypoint.Action == Enum.PathWaypointAction.Jump then
    humanoid.Jump = true
end
```

Set `AgentCanJump = false` if:
- Your NPC should never jump (cleaner, more predictable movement)
- Your environment has no jumpable gaps
- You want NPCs to only use ramps and stairs

## WaypointSpacing

Controls density of intermediate waypoints between path nodes.

| Value | Use Case |
|-------|----------|
| `2–3` | Tight indoor environments, precision needed |
| `4` | Default, good for most cases |
| `8–12` | Open outdoor areas, performance optimization |
| `math.huge` | No intermediate waypoints — only path turns and actions |

Smaller spacing = smoother-looking movement but more waypoints to process. Larger spacing = fewer computations but NPC may cut corners visually.

## Partial Path Support

Requires `PathfindingUseImprovedSearch = Enabled` in Workspace.

```lua
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    PathSettings = {
        SupportPartialPath = true,
    },
})

path:ComputeAsync(startPos, endPos)

if path.Status == Enum.PathStatus.Success then
    -- Full path found
elseif path.Status == Enum.PathStatus.ClosestNoPath then
    -- Partial path — NPC can get closer but can't reach destination
    -- Useful for: approaching locked doors, getting near unreachable targets,
    -- moving toward a goal even if the direct path is blocked
end
```

### When to Use Partial Paths
- Chase AI where you want the NPC to get as close as possible even if blocked
- NPCs reacting to sounds/alerts behind closed doors
- Fallback behavior when full path fails
- Dynamic environments where paths may become partially blocked

### When NOT to Use Partial Paths
- Patrol routes that must complete (NPC would stop mid-patrol)
- Precision navigation where arriving at the wrong spot causes bugs
- When you need to guarantee the NPC reaches the exact destination
