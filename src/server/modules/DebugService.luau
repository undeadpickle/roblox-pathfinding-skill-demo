--!strict
--[[
	DebugService - Server-side handler for debug panel remotes.

	Bridges client debug panel requests into NPCManager methods.
	Handles: NPC spawning/despawning, status polling, visual toggling,
	teleport, behavior swap, state change push.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugRemotes = require(Shared.DebugRemotes)
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)

local log = Logger.new("DebugService")

-- Lazy require to avoid circular dependency (NPCManager is a sibling module)
local NPCManager: any = nil

local DebugService = {}

-- ═══════════════════════════════════════════════════════════
-- SPAWN HELPERS
-- ═══════════════════════════════════════════════════════════

-- Default behavior configs from GameConfig (used for spawning and behavior swaps).
-- Each behavior type needs specific config fields — reusing an incompatible config
-- causes nil field crashes (e.g., guard needs DETECT_INTERVAL).
local defaultBehaviorConfigs: { [string]: { [string]: any } } = {
	chase = GameConfig.NPC.CHASE,
	patrol = GameConfig.NPC.PATROL,
	wander = GameConfig.NPC.WANDER,
	guard = GameConfig.NPC.GUARD,
}

-- Auto-naming: monotonic counter per behavior type. Never resets within a session.
local spawnCounters: { [string]: number } = {}

local function generateDisplayName(behaviorType: string): string
	spawnCounters[behaviorType] = (spawnCounters[behaviorType] or 0) + 1
	local count = spawnCounters[behaviorType]
	local label = behaviorType:sub(1, 1):upper() .. behaviorType:sub(2)
	return `{label} NPC {count}`
end

--- Shallow-copy a frozen GameConfig table and override position-dependent fields
--- so waypoints/center are relative to the spawn position, not hard-coded map coords.
local function generateSpawnConfig(
	behaviorType: string,
	baseConfig: { [string]: any },
	spawnPos: Vector3
): { [string]: any }
	-- Chase has no position-dependent fields
	if behaviorType == "chase" then
		return baseConfig
	end

	-- Clone (frozen tables can't be mutated)
	local config = table.clone(baseConfig)

	if behaviorType == "patrol" then
		-- 20x20 rectangular route around spawn point
		local half = 10
		config.WAYPOINTS = {
			spawnPos + Vector3.new(-half, 0, -half),
			spawnPos + Vector3.new(half, 0, -half),
			spawnPos + Vector3.new(half, 0, half),
			spawnPos + Vector3.new(-half, 0, half),
		}
	elseif behaviorType == "wander" then
		config.CENTER = spawnPos
	elseif behaviorType == "guard" then
		-- 5-point pentagon around spawn point (radius 15)
		local radius = 15
		local waypoints = {}
		for i = 0, 4 do
			local angle = (i / 5) * math.pi * 2 - math.pi / 2 -- start north
			table.insert(
				waypoints,
				Vector3.new(spawnPos.X + math.cos(angle) * radius, spawnPos.Y, spawnPos.Z + math.sin(angle) * radius)
			)
		end
		config.WAYPOINTS = waypoints
	end

	return config
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DebugService.initialize(): ()
	NPCManager = require(script.Parent.NPCManager)

	-- GET_NPC_STATUS: returns all NPC status data for requesting player
	local statusFunc = Remotes.getFunction(DebugRemotes.GET_NPC_STATUS)
	statusFunc.OnServerInvoke = function(player: Player): { [string]: any }
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local playerPos = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else Vector3.zero
		local status = NPCManager.getAllNPCStatus(playerPos)
		-- Embed metadata for the client to build dynamic UI
		status._meta = {
			availableBehaviors = NPCManager.getAvailableBehaviors(),
		}
		return status
	end

	-- SPAWN_NPC: spawn an NPC near the requesting player
	Remotes.getEvent(DebugRemotes.SPAWN_NPC).OnServerEvent:Connect(function(player: Player, behaviorType: unknown)
		if typeof(behaviorType) ~= "string" then
			log:warn(`Invalid SPAWN_NPC args from {player.Name}`)
			return
		end

		local baseConfig = defaultBehaviorConfigs[behaviorType]
		if not baseConfig then
			log:warn(`Unknown behavior type: {behaviorType}`)
			return
		end

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart or not rootPart:IsA("BasePart") then
			log:warn(`No character for spawn from {player.Name}`)
			return
		end

		-- Spawn 10 studs in front of player
		local spawnPos = rootPart.Position + rootPart.CFrame.LookVector * 10
		local displayName = generateDisplayName(behaviorType)
		local spawnConfig = generateSpawnConfig(behaviorType, baseConfig, spawnPos)

		local npcId = NPCManager.spawnNPC({
			displayName = displayName,
			behaviorType = behaviorType,
			spawnPosition = spawnPos,
			behavior = spawnConfig,
		})

		if npcId then
			log:info(`{player.Name} spawned {displayName} ({behaviorType})`)
		else
			log:warn(`Failed to spawn {behaviorType} NPC for {player.Name}`)
		end
	end)

	-- DESPAWN_NPC: despawn a specific NPC
	Remotes.getEvent(DebugRemotes.DESPAWN_NPC).OnServerEvent:Connect(function(player: Player, npcDisplayName: unknown)
		if typeof(npcDisplayName) ~= "string" then
			log:warn(`Invalid DESPAWN_NPC args from {player.Name}`)
			return
		end

		local success = NPCManager.despawnNPC(npcDisplayName)
		if success then
			log:info(`{player.Name} despawned {npcDisplayName}`)
		else
			log:warn(`Failed to despawn NPC: {npcDisplayName}`)
		end
	end)

	-- CLEAR_ALL_NPCS: tear down all NPCs
	Remotes.getEvent(DebugRemotes.CLEAR_ALL_NPCS).OnServerEvent:Connect(function(player: Player)
		NPCManager.cleanup()
		log:info(`{player.Name} cleared all NPCs`)
	end)

	-- TOGGLE_VISUAL: toggle a debug visual on/off for a specific NPC
	Remotes.getEvent(DebugRemotes.TOGGLE_VISUAL).OnServerEvent
		:Connect(function(player: Player, npcName: unknown, visualType: unknown, enabled: unknown)
			if typeof(npcName) ~= "string" or typeof(visualType) ~= "string" or typeof(enabled) ~= "boolean" then
				log:warn(`Invalid TOGGLE_VISUAL args from {player.Name}`)
				return
			end
			NPCManager.setDebugVisualEnabled(npcName, visualType, enabled)
		end)

	-- TELEPORT_TO_NPC_CURRENT: move player near an NPC's current position
	Remotes.getEvent(DebugRemotes.TELEPORT_TO_NPC_CURRENT).OnServerEvent
		:Connect(function(player: Player, npcDisplayName: unknown)
			if typeof(npcDisplayName) ~= "string" then
				log:warn(`Invalid TELEPORT_TO_NPC_CURRENT args from {player.Name}`)
				return
			end

			local npcPos = NPCManager.getNPCPosition(npcDisplayName)
			if not npcPos then
				log:warn(`NPC not found for teleport: {npcDisplayName}`)
				return
			end

			local character = player.Character
			if character then
				character:PivotTo(CFrame.new(npcPos + Vector3.new(5, 0, 5)))
				log:debug(`Teleported {player.Name} to {npcDisplayName} current pos`)
			end
		end)

	-- TELEPORT_NPC_TO_PLAYER: move an NPC near the player's current position
	Remotes.getEvent(DebugRemotes.TELEPORT_NPC_TO_PLAYER).OnServerEvent
		:Connect(function(player: Player, npcDisplayName: unknown)
			if typeof(npcDisplayName) ~= "string" then
				log:warn(`Invalid TELEPORT_NPC_TO_PLAYER args from {player.Name}`)
				return
			end

			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or not rootPart:IsA("BasePart") then
				log:warn(`No character for teleport from {player.Name}`)
				return
			end

			local playerPos = rootPart.Position
			local success = NPCManager.teleportNPC(npcDisplayName, playerPos + Vector3.new(5, 0, 5))
			if success then
				log:debug(`Teleported {npcDisplayName} to {player.Name}`)
			else
				log:warn(`Failed to teleport NPC: {npcDisplayName}`)
			end
		end)

	-- SET_BEHAVIOR: swap an NPC's behavior at runtime
	Remotes.getEvent(DebugRemotes.SET_BEHAVIOR).OnServerEvent
		:Connect(function(player: Player, npcDisplayName: unknown, behaviorType: unknown)
			if typeof(npcDisplayName) ~= "string" or typeof(behaviorType) ~= "string" then
				log:warn(`Invalid SET_BEHAVIOR args from {player.Name}`)
				return
			end

			local baseConfig = defaultBehaviorConfigs[behaviorType]
			if not baseConfig then
				log:warn(`Unknown behavior type for swap: {behaviorType}`)
				return
			end

			-- Generate position-relative config around NPC's current location
			-- so patrol waypoints / guard zones aren't stuck at map origin
			local npcPos = NPCManager.getNPCPosition(npcDisplayName)
			local config = if npcPos then generateSpawnConfig(behaviorType, baseConfig, npcPos) else baseConfig

			local success = NPCManager.setBehavior(npcDisplayName, behaviorType, config)
			if success then
				log:info(`{player.Name} swapped {npcDisplayName} to {behaviorType}`)
			else
				log:warn(`Failed to swap {npcDisplayName} to {behaviorType}`)
			end
		end)

	-- Push state changes to all connected clients
	local stateChangedEvent = Remotes.getEvent(DebugRemotes.NPC_STATE_CHANGED)
	NPCManager.setDebugStateCallback(function(npcName: string, newState: string, previousState: string?)
		stateChangedEvent:FireAllClients(npcName, newState, previousState)
	end)

	log:info("Debug remotes registered")
end

return DebugService
