# Roblox PathfindingService API Quick Reference

Last verified: February 2025. Always cross-check with https://create.roblox.com/docs/reference/engine/classes/PathfindingService for changes.

## Core Workflow

```lua
local PathfindingService = game:GetService("PathfindingService")

-- 1. Create a Path object with agent configuration
local path = PathfindingService:CreatePath({
    AgentRadius = 2,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentCanClimb = false,
    WaypointSpacing = 4,
    Costs = {},
    PathSettings = {
        SupportPartialPath = false,
    },
})

-- 2. Compute the path (ALWAYS wrap in pcall — this can error)
local success, errorMessage = pcall(function()
    path:ComputeAsync(startPosition, finishPosition)
end)

-- 3. Check result status
if success and path.Status == Enum.PathStatus.Success then
    local waypoints = path:GetWaypoints()
    -- traverse waypoints
end

-- 4. Handle partial paths (requires PathfindingUseImprovedSearch = Enabled)
if success and path.Status == Enum.PathStatus.ClosestNoPath then
    -- partial path returned — NPC can get closer but not all the way
    local waypoints = path:GetWaypoints()
end
```

## CreatePath Agent Parameters

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `AgentRadius` | integer | `2` | Agent radius in studs. Determines minimum clearance from obstacles. |
| `AgentHeight` | integer | `5` | Agent height in studs. Spaces shorter than this are non-traversable. |
| `AgentCanJump` | boolean | `true` | Whether jumping is allowed during pathfinding. |
| `AgentCanClimb` | boolean | `false` | Whether climbing TrussParts is allowed. |
| `WaypointSpacing` | number | `4` | Studs between intermediate waypoints. Set to `math.huge` for no intermediates. |
| `Costs` | table | `{}` | Material names or PathfindingModifier labels mapped to numeric costs. |
| `PathSettings` | table | `nil` | Additional settings. Currently supports `SupportPartialPath` (boolean). |

### Agent Parameter Tips
- `AgentRadius` and `AgentHeight` should match your NPC's actual collision size, not the visual size
- Larger `AgentRadius` = safer paths (more wall clearance) but may fail in tight spaces
- Set `AgentCanJump = false` if your NPCs shouldn't jump (cleaner movement)
- `WaypointSpacing` of 4 is fine for most cases. Increase for smoother movement on open terrain. Decrease for tight corridors.

## Path Object

### Properties
- `path.Status` → `Enum.PathStatus`
  - `Success` — Full path found
  - `NoPath` — No path exists to destination
  - `ClosestNoPath` — Partial path returned (only with `SupportPartialPath = true` and `PathfindingUseImprovedSearch = Enabled`)
  - `ClosestOutOfRange` — Destination too far from nav mesh

### Methods
- `path:GetWaypoints()` → Returns array of `PathWaypoint` objects
- `path:ComputeAsync(startPos: Vector3, endPos: Vector3)` → Yields, computes the path

### Events
- `path.Blocked(blockedWaypointIndex: number)` — Fires when a previously computed path is blocked by an obstacle. Use this to trigger recomputation.

## Humanoid Movement Reference

### Humanoid:MoveTo(position: Vector3)
Moves the Humanoid toward `position`. The Humanoid will pathfind around small obstacles but NOT around walls — use PathfindingService for that.

### Humanoid.MoveToFinished(reached: boolean)
Fires when `MoveTo` completes. The `reached` parameter is CRITICAL:
- `true` — NPC arrived at the target position
- `false` — The engine's hard 8-second safety timeout fired (NPC got stuck, blocked, or the point was unreachable)

**Always check `reached`.** Ignoring it is the primary cause of NPC loops freezing in production games.

```lua
local reached = humanoid.MoveToFinished:Wait()
if not reached then
    -- Handle stuck/timeout: recompute path, skip waypoint, or abort
end
```

## PathWaypoint

Each waypoint returned by `GetWaypoints()` has:
- `.Position` → `Vector3` — World position of this waypoint
- `.Action` → `Enum.PathWaypointAction`
  - `Walk` — Normal movement
  - `Jump` — NPC should jump at this waypoint
  - `Custom` — Custom action (used with PathfindingLinks)
- `.Label` → `string` — The label from a PathfindingModifier or PathfindingLink. Empty string if none.

## Enum.PathStatus Values

| Value | Meaning |
|-------|---------|
| `Success` | Path computed successfully to destination |
| `ClosestNoPath` | Partial path returned (closest reachable point). Requires `SupportPartialPath = true`. |
| `ClosestOutOfRange` | Goal is outside the nav mesh computed area |
| `NoPath` | No path exists between start and finish |

## Workspace Property

`Workspace.PathfindingUseImprovedSearch`
- `Default` — Uses production algorithm (will become the improved one in 2025)
- `Enabled` — Opt in to improved pathfinding algorithm (recommended)
- `Disabled` — Force legacy algorithm

**Always set to Enabled for new projects.**

## Vertical Limits

PathfindingService has hard boundaries:
- Parts with bottom Y coordinate below `-65,536` studs are ignored
- Parts with top Y coordinate above `65,536` studs are ignored
- Total vertical span of all parts must not exceed `65,536` studs

## Deprecated APIs — Do NOT Use

| Deprecated | Replacement |
|-----------|-------------|
| `PathfindingService:ComputeSmoothPathAsync()` | `CreatePath()` → `ComputeAsync()` |
| `PathfindingService:ComputeRawPathAsync()` | `CreatePath()` → `ComputeAsync()` |
| `PathfindingService:FindPathAsync()` | `CreatePath()` → `ComputeAsync()` |
