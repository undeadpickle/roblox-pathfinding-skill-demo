--!strict
--[[
	DebugService - Server-side handler for debug panel remotes.

	Bridges client debug panel requests into NPCManager methods.
	Handles: NPC status polling, visual toggling, teleport, behavior swap, state change push.
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

	-- TOGGLE_VISUAL: toggle a debug visual on/off for a specific NPC
	Remotes.getEvent(DebugRemotes.TOGGLE_VISUAL).OnServerEvent
		:Connect(function(player: Player, npcName: unknown, visualType: unknown, enabled: unknown)
			if typeof(npcName) ~= "string" or typeof(visualType) ~= "string" or typeof(enabled) ~= "boolean" then
				log:warn(`Invalid TOGGLE_VISUAL args from {player.Name}`)
				return
			end
			NPCManager.setDebugVisualEnabled(npcName, visualType, enabled)
		end)

	-- TELEPORT_TO_NPC: move player's character near an NPC's spawn zone
	Remotes.getEvent(DebugRemotes.TELEPORT_TO_NPC).OnServerEvent
		:Connect(function(player: Player, npcDisplayName: unknown)
			if typeof(npcDisplayName) ~= "string" then
				log:warn(`Invalid TELEPORT_TO_NPC args from {player.Name}`)
				return
			end

			local spawnPos = NPCManager.getNPCSpawnPosition(npcDisplayName)
			if not spawnPos then
				log:warn(`No spawn position for NPC: {npcDisplayName}`)
				return
			end

			local character = player.Character
			if character then
				character:PivotTo(CFrame.new(spawnPos + Vector3.new(5, 0, 5)))
				log:debug(`Teleported {player.Name} to {npcDisplayName} spawn zone`)
			end
		end)

	-- TELEPORT_TO_NPC_CURRENT: move player near an NPC's current position (not spawn zone)
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

	-- Default behavior configs from GameConfig (used when debug panel swaps behaviors)
	-- Each behavior type needs specific config fields — reusing existing config from
	-- a different behavior type causes nil field crashes (e.g., guard needs DETECT_INTERVAL).
	local defaultBehaviorConfigs: { [string]: { [string]: any } } = {
		chase = GameConfig.NPC.CHASE,
		patrol = GameConfig.NPC.PATROL,
		wander = GameConfig.NPC.WANDER,
		guard = GameConfig.NPC.GUARD,
	}

	-- SET_BEHAVIOR: swap an NPC's behavior at runtime
	Remotes.getEvent(DebugRemotes.SET_BEHAVIOR).OnServerEvent
		:Connect(function(player: Player, npcDisplayName: unknown, behaviorType: unknown)
			if typeof(npcDisplayName) ~= "string" or typeof(behaviorType) ~= "string" then
				log:warn(`Invalid SET_BEHAVIOR args from {player.Name}`)
				return
			end

			-- Always supply the default config for the target behavior type
			-- to avoid nil field crashes from incompatible existing configs
			local config = defaultBehaviorConfigs[behaviorType]
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
