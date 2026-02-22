# Luau Coding Conventions

Style rules and principles for Roblox Luau development. For implementation recipes with code examples, see [luau-patterns.md](luau-patterns.md).

## Naming

| Style | Use For |
|-------|---------|
| `PascalCase` | Services, classes, modules, types, enums |
| `camelCase` | Variables, functions, parameters, member values |
| `SCREAMING_SNAKE_CASE` | Constants |
| `_camelCase` | Private members |

- Spell out words fully — no abbreviations
- Acronyms: `aJsonVariable`, `MakeHttpCall` (don't capitalize whole acronym)
- Exception: set abbreviations like `RGB`, `XYZ` stay uppercase
- File names match the exported object: `PlayerManager.lua` → exports `PlayerManager`

## File Structure Order

1. `--!strict` (and optionally `--!native` for compute-heavy modules)
2. Services via `game:GetService()`
3. Module imports via `require()` (sorted alphabetically)
4. Type definitions
5. Constants
6. Module-level variables
7. Private functions
8. Public functions / module methods
9. Return statement

## Task Library (Required)

| Use | Not |
|-----|-----|
| `task.wait(n)` | `wait(n)` |
| `task.spawn(fn)` | `spawn(fn)` |
| `task.delay(n, fn)` | `delay(n, fn)` |
| `task.defer(fn)` | — |
| `task.cancel(thread)` | — |

## Service Access

Always use `game:GetService()`:

```luau
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Never use globals: workspace, game.Players, etc.
```

## Strings

Prefer double quotes. Single quotes acceptable when the string contains double quotes.

```luau
local name = "Hello"
local dialogue = 'She said "run!"'
```

Prefer string interpolation over concatenation:

```luau
-- Preferred
local msg = `{player.Name} scored {score} points!`

-- Avoid
local msg = player.Name .. " scored " .. tostring(score) .. " points!"
```

Interpolation handles `tostring()` automatically, is more readable, and produces less garbage for the GC.

## Iteration

Use generalized iteration (no `pairs`/`ipairs`):

```luau
for key, value in dictionary do
for index, item in array do
```

> **Note:** The official Roblox style guide recommends `ipairs`/`pairs` to signal table type. We prefer generalized iteration for brevity and because it handles both cases correctly. This is an intentional deviation.

## Type Annotations

Annotate function parameters and returns. Use `typeof()` (not `type()`) for Roblox types.

```luau
local function calculateDamage(baseDamage: number, multiplier: number): number
    return baseDamage * multiplier
end

local function getPlayer(userId: number): Player?
    return Players:GetPlayerByUserId(userId)
end
```

## If-Then-Else Expressions

Prefer inline `if` expressions over the `and/or` hack:

```luau
-- Correct (safe)
local scale = if someCondition then 1 else 2

-- Avoid (breaks if truthy value is false or nil)
local scale = someCondition and 1 or 2
```

For multi-line conditions, put `then`/`else` on new lines. If it won't fit in three lines, use a regular `if` statement instead.

## Guard Clauses

Prefer early returns over deep nesting:

```luau
local function handleHit(hit: BasePart)
    local character = hit.Parent
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    if humanoid.Health <= 0 then return end

    applyDamage(humanoid)
end
```

## Module Pattern

```luau
--!strict
local MyModule = {}

function MyModule.doSomething(value: string): boolean
    return true
end

-- Private (not in module table)
local function helperFunction(): ()
    -- internal logic
end

return MyModule
```

## Error Handling

- Use `pcall`/`xpcall` for operations that can fail (DataStores, HTTP, etc.)
- Return `success, result` — don't throw for runtime conditions
- Reserve `assert` for validating correct *usage* of a function

```luau
local success, result = pcall(function()
    return dataStore:GetAsync(key)
end)

if not success then
    warn("DataStore read failed:", result)
    return nil
end
```

## Event Connections & Cleanup

Always store and disconnect connections that outlive their purpose. This is the #1 source of memory leaks. See [luau-patterns.md → Connection Management](luau-patterns.md#connection-management) for implementation patterns.

```luau
local connection = part.Touched:Connect(function(hit)
    -- handle
end)

-- Disconnect when done
connection:Disconnect()
```

- Connections on an instance's *own* events auto-clean when that instance is `Destroy()`ed
- Connections where the callback *references another instance* can prevent GC of that instance — disconnect these explicitly
- For player-scoped connections, clean up on `PlayerRemoving`

## Instance Creation Order

Set all properties **before** setting `Parent`. When you parent an instance, it replicates immediately — every subsequent property change sends a separate network update.

```luau
-- ✅ Properties first, parent last (one replication packet)
local part = Instance.new("Part")
part.Size = Vector3.new(10, 10, 10)
part.Anchored = true
part.Parent = workspace

-- ❌ Parent too early (each property change replicates separately)
local part = Instance.new("Part")
part.Parent = workspace
part.Size = Vector3.new(10, 10, 10)
part.Anchored = true
```

This also applies to the second argument of `Instance.new("Part", parent)` — it's discouraged for the same reason.

## WaitForChild

```luau
-- Client scripts: always WaitForChild for replicated content
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Server scripts: direct indexing is fine (content exists at startup)
local remotes = ReplicatedStorage.Remotes
```

Never use `WaitForChild` in loops or hot paths.

## Instance Safety After Yields

Any code that yields (`task.wait`, `WaitForChild`, async DataStore calls) must verify instances still exist before using them:

```luau
task.wait(2)
if not part:IsDescendantOf(game) then return end
-- Safe to use part
```

This applies to player references too — the player may have left during the yield. See [luau-patterns.md → Instance Destruction Safety](luau-patterns.md#instance-destruction-safety) for full examples.

## Yielding

Mark yielding functions with an `Async` suffix. Never yield on the main thread without wrapping.

```luau
local function loadDataAsync(player: Player): PlayerData?
    local success, data = pcall(function()
        return DataStoreService:GetAsync(tostring(player.UserId))
    end)
    return if success then data else nil
end
```

## Server Authority (Never Trust the Client)

- Client *requests*, server *decides*
- Always validate RemoteEvent args on the server: check types with `typeof()`, validate ranges, verify permissions
- Always rate limit remote handlers to prevent spam

```luau
remote.OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown)
    if typeof(action) ~= "string" then return end
    if typeof(value) ~= "number" then return end
    if value < 0 or value > MAX_VALUE then return end

    -- Safe to proceed
end)
```

For complex validation and rate limiting patterns, see [luau-patterns.md → Remote Event Validation](luau-patterns.md#remote-event-validation-server) and [luau-patterns.md → Rate Limiting](luau-patterns.md#rate-limiting-remote-events).

## RunService Events

The frame loop events were renamed. Prefer the new names (old names still work but are deprecated):

| Current Name | Deprecated Name | Runs On | Use For |
|---|---|---|---|
| `PreRender` | `RenderStepped` | Client only | Camera, HUD, visual updates |
| `PreSimulation` | `Stepped` | Client + Server | Movement, forces, input |
| `PostSimulation` | `Heartbeat` | Client + Server | React to physics, general logic |

Always use `deltaTime` from the callback for frame-rate independence. See [luau-patterns.md → RunService Frame Loop](luau-patterns.md#runservice-frame-loop-selection) and [Delta-Time Scaling](luau-patterns.md#delta-time-scaling).

## CollectionService Over Manual Iteration

Prefer CollectionService tags over iterating workspace children to find instances:

```luau
-- Prefer: tag instances in Studio, query by tag
local hazards = CollectionService:GetTagged("Hazard")

-- Avoid: manual search through hierarchy
for _, child in Workspace:GetDescendants() do
    if child.Name == "Hazard" then ...
```

Tags handle streaming (instances loading/unloading) gracefully via added/removed signals. See [luau-patterns.md → CollectionService Tag Pattern](luau-patterns.md#collectionservice-tag-pattern) for the full setup.

## Native Code Generation

For compute-heavy modules (math loops, array processing, procedural generation), add `--!native` at the top. Not beneficial for code that mostly calls Roblox APIs.

```luau
--!native
--!strict
```

## Avoid

| Avoid | Use Instead |
|-------|-------------|
| `workspace` global | `game:GetService("Workspace")` |
| `pairs()` / `ipairs()` | Generalized iteration |
| `_G` / shared globals | ModuleScripts for shared state |
| `type()` for Roblox types | `typeof()` |
| `x and y or z` ternary | `if x then y else z` |
| `UDim2.new(0, x, 0, y)` | `UDim2.fromOffset(x, y)` |
| `UDim2.new(x, 0, y, 0)` | `UDim2.fromScale(x, y)` |
| String concatenation with `..` | String interpolation with backticks |
| Complex metatables for simple classes | Typed tables + functions |
| Dynamic requires | Static paths via variables |
| `Instance.new("X", parent)` | Set all properties, then `.Parent` last |
| Iterating workspace descendants | CollectionService tags |
| Semicolons | — |
| Parentheses in `if`/`while`/`repeat` conditions | — |
