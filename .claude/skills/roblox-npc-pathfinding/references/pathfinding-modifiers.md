# Pathfinding Modifiers and Links

## PathfindingModifier

PathfindingModifiers let you define custom regions that affect pathfinding behavior beyond just material costs.

### Use Cases
- Danger zones NPCs should avoid (lava, traps, enemy territory)
- Preferred corridors NPCs should favor (lit paths, safe zones)
- Doors or barriers that NPCs can pass through (PassThrough)
- Areas with custom traversal cost regardless of material

### Setup

1. Create an **Anchored** part covering the region
2. Set `CanCollide = false` on the part (it's a zone, not a wall)
3. Insert a `PathfindingModifier` instance as a child of the part
4. Set the modifier's `Label` property to a meaningful name

```
Part (Anchored, CanCollide = false)
  └── PathfindingModifier
        Label = "DangerZone"
```

5. Reference the label in `Costs`:

```lua
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    Costs = {
        DangerZone = math.huge,  -- Never enter this zone
    },
})
```

### Cost Examples for Modifiers

```lua
Costs = {
    DangerZone = math.huge,   -- Impassable
    SlowZone = 10,            -- Avoid if possible
    PreferredPath = 0.5,      -- Prefer this route
    EnemyTerritory = 15,      -- Strongly avoid
    Water = 20,               -- Material cost (works alongside modifier labels)
}
```

### PassThrough Property

`PathfindingModifier.PassThrough = true` makes the enclosed parts traversable even if they normally have collision.

Use case: Doors that NPCs can open.

```
DoorPart (Anchored, CanCollide = true)  -- Blocks players physically
  └── PathfindingModifier
        PassThrough = true  -- But pathfinding treats it as walkable
```

The path will route through the door. In your traversal code, when the NPC reaches a waypoint near a PassThrough door, trigger the door-open logic.

### Detecting Modifier Labels During Traversal

Waypoints carry the label of any modifier they pass through:

```lua
for _, waypoint in waypoints do
    if waypoint.Label == "DangerZone" then
        -- NPC is about to enter a danger zone — maybe add caution behavior
    elseif waypoint.Label == "Door" then
        -- Trigger door open animation/logic before proceeding
    end

    humanoid:MoveTo(waypoint.Position)
    humanoid.MoveToFinished:Wait()
end
```

## PathfindingLink

PathfindingLinks connect two otherwise disconnected locations. They allow NPCs to pathfind across gaps, through teleporters, up ladders, or via vehicles — anything that requires a custom traversal action.

### When to Use PathfindingLinks
- Jumping across a chasm
- Using a boat, elevator, or vehicle
- Teleporter pads
- Climbing a non-TrussPart ladder
- Ziplines, grapple points
- Any traversal that isn't standard walking/jumping/climbing

### Setup

1. Create two `Attachment` instances at the start and end of the custom traversal
2. Create a `PathfindingLink` instance anywhere in Workspace
3. Set `PathfindingLink.Attachment0` to the start attachment
4. Set `PathfindingLink.Attachment1` to the end attachment
5. Set `PathfindingLink.Label` to a descriptive name (e.g., "BoatRide", "Teleporter")
6. Reference the label in `Costs` with appropriate cost

```lua
-- Setup in Studio or via script:
local link = Instance.new("PathfindingLink")
link.Attachment0 = startAttachment  -- Attachment at dock A
link.Attachment1 = endAttachment    -- Attachment at dock B
link.Label = "BoatRide"
link.IsBidirectional = true         -- Can traverse both ways
link.Parent = workspace

-- In CreatePath:
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    Costs = {
        Water = math.huge,    -- Block normal water traversal
        BoatRide = 1,         -- But allow the boat link (cheaper than swimming)
    },
})
```

### Handling Link Waypoints During Traversal

Link waypoints have `Action = Enum.PathWaypointAction.Custom` and carry the link's label:

```lua
for _, waypoint in waypoints do
    if waypoint.Action == Enum.PathWaypointAction.Custom then
        if waypoint.Label == "BoatRide" then
            -- Execute custom boat traversal logic
            seatNPCInBoat(npc)
            moveBoatToDestination()
            unseatNPC(npc)
        elseif waypoint.Label == "Teleporter" then
            -- Teleport the NPC
            npc:PivotTo(CFrame.new(waypoint.Position))
        elseif waypoint.Label == "Ladder" then
            -- Play climb animation, move NPC up
            playClimbAnimation(npc)
            moveNPCVertically(npc, waypoint.Position)
        end
    else
        humanoid:MoveTo(waypoint.Position)
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        humanoid.MoveToFinished:Wait()
    end
end
```

### PathfindingLink Properties

| Property | Type | Description |
|----------|------|-------------|
| `Attachment0` | Attachment | Start point of the link |
| `Attachment1` | Attachment | End point of the link |
| `Label` | string | Identifier used in Costs and waypoint.Label |
| `IsBidirectional` | boolean | Whether the link can be traversed both ways |

### Visualization and Debugging

Toggle **Pathfinding links** in View → Visualization Options to see link connections in Studio. Toggle **Navigation mesh** to verify the nav mesh includes your link endpoints.

## Combining Modifiers and Links

Complex environments often use both:

```lua
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,
    Costs = {
        -- Materials
        Water = math.huge,
        Mud = 5,

        -- Modifier labels (from PathfindingModifier instances)
        DangerZone = math.huge,
        SlowCorridor = 8,

        -- Link labels (from PathfindingLink instances)
        BoatRide = 2,
        Ladder = 3,
        Teleporter = 0.5,  -- Prefer teleporters
    },
})
```

The pathfinding system evaluates all costs together and finds the cheapest total path considering materials, modifier zones, and link traversals.

## Common Gotchas

- Modifier labels and link labels are case-sensitive. "dangerzone" ≠ "DangerZone".
- If you set a cost for a label but no modifier/link has that label, nothing happens (no error).
- If a modifier/link has a label but it's not in `Costs`, the default cost of `1` is used.
- PassThrough only affects pathfinding computation. You still need to handle the physical collision in your game logic (open the door, remove the barrier, etc.).
- PathfindingLink endpoints must be on or very near the nav mesh. If an attachment is floating in mid-air, the link won't connect.
