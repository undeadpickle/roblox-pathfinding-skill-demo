# Luau Code Patterns

Foundational, game-agnostic implementation patterns for Roblox development. For coding rules and style conventions, see [luau-conventions.md](luau-conventions.md). For game-specific patterns (AI, audio, camera, multiplayer), see [patterns/INDEX.md](patterns/INDEX.md).

Each pattern includes **when/why/related** metadata to help identify the right pattern for a given problem.

---

## Player Lifecycle Management

> **When:** Any game that tracks per-player state, data, connections, or UI. This is the backbone of nearly every Roblox game — reach for it first when the task involves player join, leave, character spawn, or per-player cleanup.
>
> **Why:** Without structured lifecycle management, player-scoped connections leak, state persists after disconnect, and Studio testing breaks when scripts load after players are already in-game.
>
> **Related:** Connection Management, Debounce (both need cleanup on PlayerRemoving)

```luau
local Players = game:GetService("Players")

type PlayerState = {
    connections: {RBXScriptConnection},
    -- Add per-player state: inventory, score, settings, etc.
}

local playerStates: {[Player]: PlayerState} = {}

local function setupCharacter(player: Player, character: Model): ()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    -- Character-specific setup (health, animations, hitboxes)
end

local function onPlayerAdded(player: Player): ()
    local state: PlayerState = {
        connections = {},
    }
    playerStates[player] = state

    local character = player.Character or player.CharacterAdded:Wait()
    setupCharacter(player, character)

    table.insert(state.connections, player.CharacterAdded:Connect(function(char)
        setupCharacter(player, char)
    end))
end

local function onPlayerRemoving(player: Player): ()
    local state = playerStates[player]
    if not state then return end

    for _, conn in state.connections do
        conn:Disconnect()
    end

    playerStates[player] = nil
end

-- Handle players already in-game (critical for Studio and late-loading scripts)
for _, player in Players:GetPlayers() do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
```

---

## Connection Management

> **When:** Any system that creates event connections with a limited lifetime — per-round systems, temporary UI, NPC behavior, zones. If the connections should stop when something ends or is destroyed, use this.
>
> **Why:** Undisconnected connections are the #1 source of memory leaks in Roblox. Connections on an instance's own events auto-clean on `:Destroy()`, but connections where the callback references *another* instance can prevent GC.
>
> **Related:** Player Lifecycle (for player-scoped connections), CollectionService Tags (for instance-scoped connections)

```luau
local connections: {RBXScriptConnection} = {}

local function setupConnections(): ()
    table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
    table.insert(connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

local function cleanup(): ()
    for _, connection in connections do
        connection:Disconnect()
    end
    table.clear(connections)
end
```

**Scoped variant** — wraps connections in an object for cleaner lifecycle:

```luau
local function createConnectionBag(): {
    add: (self: any, conn: RBXScriptConnection) -> (),
    cleanup: (self: any) -> (),
}
    local conns: {RBXScriptConnection} = {}
    return {
        add = function(_, conn: RBXScriptConnection)
            table.insert(conns, conn)
        end,
        cleanup = function(_)
            for _, c in conns do
                c:Disconnect()
            end
            table.clear(conns)
        end,
    }
end
```

---

## CollectionService Tag Pattern

> **When:** Applying shared behavior to multiple instances in the world — interactables, hazards, collectibles, spawn points, anything where multiple parts/models share the same logic. Prefer this over iterating workspace children or manually wiring scripts to each instance.
>
> **Why:** Tags decouple behavior from hierarchy. Add a tag in Studio, and the script finds it automatically. Handles streaming (instances loading/unloading) gracefully via the added/removed signals.
>
> **Related:** Attribute-Based Behavior (combine tags for "what type" with attributes for "what config"), Connection Management (store per-instance connections for cleanup)

```luau
local CollectionService = game:GetService("CollectionService")

local TAG = "Interactable"
local instanceConnections: {[Instance]: {RBXScriptConnection}} = {}

local function onTagAdded(instance: Instance): ()
    local part = instance :: BasePart
    local conns: {RBXScriptConnection} = {}

    table.insert(conns, part.Touched:Connect(function(hit)
        -- Handle touch
    end))

    instanceConnections[instance] = conns
end

local function onTagRemoved(instance: Instance): ()
    local conns = instanceConnections[instance]
    if not conns then return end

    for _, conn in conns do
        conn:Disconnect()
    end

    instanceConnections[instance] = nil
end

-- Process instances already in the world
for _, instance in CollectionService:GetTagged(TAG) do
    onTagAdded(instance)
end

-- Handle streaming / runtime additions
CollectionService:GetInstanceAddedSignal(TAG):Connect(onTagAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(onTagRemoved)
```

---

## Remote Event Validation (Server)

> **When:** Any `RemoteEvent` or `RemoteFunction` handler on the server. All client-sent data is untrusted — type check everything before use.
>
> **Why:** Exploiters can send arbitrary types and values through remotes. Without validation, a malicious client can crash server scripts, corrupt data, or trigger unintended behavior. See also `luau-conventions.md` → Server Authority.
>
> **Related:** Rate Limiting (pair with validation to prevent spam), Player Lifecycle (verify player state before processing)

Simple validation:

```luau
MyEvent.OnServerEvent:Connect(function(player: Player, data: unknown)
    if typeof(data) ~= "string" then return end

    local validData: string = data
    -- Safe to use
end)
```

Complex structured validation:

```luau
type ActionData = {
    action: string,
    targetId: number,
}

local function validateActionData(data: unknown): ActionData?
    if typeof(data) ~= "table" then return nil end

    -- Cast required because Luau can't narrow unknown through field access
    local t = data :: {[string]: unknown}
    if typeof(t.action) ~= "string" then return nil end
    if typeof(t.targetId) ~= "number" then return nil end

    return t :: ActionData
end

MyEvent.OnServerEvent:Connect(function(player: Player, data: unknown)
    local validated = validateActionData(data)
    if not validated then return end

    -- Safe to use validated.action and validated.targetId
end)
```

---

## Rate Limiting Remote Events

> **When:** Any server-side remote handler that should not be called faster than a reasonable rate — actions, requests, chat, purchases. Essential for any multiplayer game.
>
> **Why:** Without rate limiting, exploiters can spam remotes hundreds of times per second, causing server lag, duplicating actions, or overwhelming systems. Validation alone isn't enough — you also need throttling.
>
> **Related:** Remote Event Validation (always pair with this), Player Lifecycle (clean up rate limit state on PlayerRemoving)

```luau
local RATE_LIMIT = 10 -- max calls per second per player
local playerCalls: {[Player]: {count: number, resetTime: number}} = {}

local function isRateLimited(player: Player): boolean
    local now = os.clock()
    local data = playerCalls[player]

    if not data or now >= data.resetTime then
        playerCalls[player] = { count = 1, resetTime = now + 1 }
        return false
    end

    data.count += 1
    return data.count > RATE_LIMIT
end

-- Clean up on leave
Players.PlayerRemoving:Connect(function(player: Player)
    playerCalls[player] = nil
end)

-- Usage in any remote handler
MyRemote.OnServerEvent:Connect(function(player: Player, ...)
    if isRateLimited(player) then return end
    -- Process normally
end)
```

---

## Debounce Pattern

> **When:** Preventing rapid repeat triggers — touch events, button clicks, interaction prompts, ability usage. Anytime an action should have a cooldown per player or per instance.
>
> **Why:** `Touched` events fire multiple times per contact. UI buttons can be spammed. Without debounce, players trigger actions dozens of times unintentionally.
>
> **Related:** Player Lifecycle (clean up debounce state on PlayerRemoving), Rate Limiting (debounce is per-action cooldown, rate limiting is per-player throughput)

```luau
local debounces: {[Player]: boolean} = {}

local function onTouched(player: Player): ()
    if debounces[player] then return end
    debounces[player] = true

    -- Do action
    print("Touched by", player.Name)

    task.delay(1, function()
        debounces[player] = nil
    end)
end

-- Clean up on leave to avoid stale entries
Players.PlayerRemoving:Connect(function(player: Player)
    debounces[player] = nil
end)
```

---

## RunService Frame Loop Selection

> **When:** Any per-frame update — movement, camera, animations, visual effects, physics reactions. Choosing the wrong event causes jitter, input lag, or server errors.
>
> **Why:** Roblox's frame loop has distinct phases. Running camera code in PostSimulation instead of PreRender adds a frame of latency. Running render code on the server crashes. The event names were updated (old names still work but are deprecated).
>
> **Related:** Delta-Time Scaling (always multiply by deltaTime in frame loops)

```luau
local RunService = game:GetService("RunService")

-- CLIENT ONLY: Before rendering — camera, UI tracking cursor, visual interpolation
-- (Formerly: RenderStepped)
RunService.PreRender:Connect(function(deltaTime: number)
    -- Runs before the frame renders, client only
end)

-- CLIENT OR SERVER: Before physics — applying forces, movement input
-- (Formerly: Stepped)
RunService.PreSimulation:Connect(function(deltaTime: number)
    -- Runs before physics step
end)

-- CLIENT OR SERVER: After physics — reacting to physics results, general updates
-- (Formerly: Heartbeat — still the most commonly used)
RunService.PostSimulation:Connect(function(deltaTime: number)
    -- Runs after physics step
end)

-- CLIENT ONLY: Ordered render binding with explicit priority
RunService:BindToRenderStep("CameraUpdate", Enum.RenderPriority.Camera.Value - 1, function(deltaTime: number)
    -- Runs at specific priority before PreRender
end)

-- Don't forget to unbind when no longer needed
RunService:UnbindFromRenderStep("CameraUpdate")
```

**Quick reference:**

| Event | Runs on | Use for |
|---|---|---|
| `PreRender` | Client only | Camera, HUD, visual polish |
| `PreSimulation` | Client + Server | Movement, forces, input-driven physics |
| `PostSimulation` | Client + Server | React to physics, general game logic |
| `BindToRenderStep` | Client only | Ordered updates (camera priority) |

---

## Delta-Time Scaling

> **When:** Any value that changes per frame — movement speed, rotation, timer countdowns, interpolation progress. If it runs inside a RunService connection, it almost certainly needs deltaTime.
>
> **Why:** Without deltaTime scaling, behavior is framerate-dependent. A player at 30 FPS moves half as fast as one at 60 FPS. Mobile players get punished, high-refresh monitor players get an advantage.
>
> **Related:** RunService Frame Loop (deltaTime comes from the event callback)

```luau
local SPEED = 20 -- studs per second

RunService.PostSimulation:Connect(function(deltaTime: number)
    -- Framerate-independent movement
    local moveDistance = SPEED * deltaTime
    part.Position += part.CFrame.LookVector * moveDistance
end)

-- Framerate-independent timer
local elapsed = 0
local DURATION = 5

RunService.PostSimulation:Connect(function(deltaTime: number)
    elapsed += deltaTime
    if elapsed >= DURATION then
        -- Timer complete
    end
end)
```

---

## Instance Destruction Safety

> **When:** Any code that yields (task.wait, WaitForChild, async DataStore calls, etc.) and then acts on an instance afterward. Also relevant for deferred callbacks that might fire after an instance is destroyed.
>
> **Why:** During a yield, the instance may have been destroyed by another script, the player may have left, or the character may have respawned. Accessing properties of a destroyed instance errors silently or throws.
>
> **Related:** Player Lifecycle (player may leave during async operations), Safe Instance Access in conventions

```luau
local function doDelayedAction(part: BasePart): ()
    task.wait(2)

    -- Part may have been destroyed during the wait
    if not part:IsDescendantOf(game) then return end

    part.Color = Color3.new(1, 0, 0)
end

-- For player operations after a yield
local function grantRewardAsync(player: Player): ()
    local success, result = pcall(function()
        return DataStore:GetAsync(tostring(player.UserId))
    end)

    -- Player may have left during the DataStore call
    if not player:IsDescendantOf(game) then return end

    if success then
        -- Safe to modify player state
    end
end
```

---

## Model Animation (CFrameValue + PivotTo)

> **When:** Tweening an entire Model's position/rotation — doors opening, platforms moving, objects animating to a target position. TweenService cannot directly tween `Model:PivotTo()`.
>
> **Why:** TweenService only works on object properties. Since `PivotTo` is a method (not a property), you need an intermediary CFrameValue that the tween modifies, with a Changed listener that calls PivotTo each frame.
>
> **Related:** RunService Frame Loop (alternative: manual interpolation in PostSimulation for more control)

```luau
local TweenService = game:GetService("TweenService")

local function tweenModel(model: Model, targetCFrame: CFrame, duration: number): ()
    local cfValue = Instance.new("CFrameValue")
    cfValue.Value = model:GetPivot()

    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(cfValue, tweenInfo, { Value = targetCFrame })

    local connection = cfValue.Changed:Connect(function(newCFrame)
        model:PivotTo(newCFrame)
    end)

    tween.Completed:Once(function()
        connection:Disconnect()
        cfValue:Destroy()
    end)

    tween:Play()
end
```

---

## Attribute-Based Behavior (Registry Pattern)

> **When:** Multiple instances share behavior but with different configuration — doors with different speeds, pickups with different values, buttons with different actions. Use attributes for per-instance config, tags for shared behavior type.
>
> **Why:** Avoids creating separate scripts for each variation. Designers can configure behavior in Studio properties panel without touching code. Pairs naturally with CollectionService tags.
>
> **Related:** CollectionService Tags (tag = "what behavior", attribute = "what config"), Remote Event Validation (validate attribute types at runtime since they can be modified)

```luau
local INTERACTION_TYPES = {
    button = { sound = "Click", cooldown = 0.5 },
    portal = { sound = "Whoosh", destination = "Spawn" },
    pickup = { sound = "Grab", destroyOnUse = true },
}

local function handleInteraction(part: BasePart, player: Player): ()
    local interactionType = part:GetAttribute("InteractionType")
    if typeof(interactionType) ~= "string" then return end

    local config = INTERACTION_TYPES[interactionType]
    if not config then return end

    -- Use config to drive behavior
    -- e.g., play config.sound, apply config.cooldown
end
```

**Combining with tags:**

```luau
-- Tag: "Interactable" (handled by CollectionService pattern above)
-- Attribute: "InteractionType" = "portal"
-- Attribute: "Destination" = "Level2Spawn"
-- Result: CollectionService connects the touch event,
--         attribute registry drives what happens on touch
```
