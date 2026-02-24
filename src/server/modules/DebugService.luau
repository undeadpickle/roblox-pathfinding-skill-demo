--!strict
--[[
	DebugService - Server-side handler for debug panel remotes.

	Bridges client debug panel requests into NPCManager methods.
	Handles: NPC status polling, visual toggling, teleport, state change push.
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
		return NPCManager.getAllNPCStatus(playerPos)
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
	Remotes.getEvent(DebugRemotes.TELEPORT_TO_NPC).OnServerEvent:Connect(function(player: Player, npcKey: unknown)
		if typeof(npcKey) ~= "string" then
			log:warn(`Invalid TELEPORT_TO_NPC args from {player.Name}`)
			return
		end

		local spawnPositions = GameConfig.NPC.SPAWN_POSITIONS :: { [string]: Vector3 }
		local targetPos = spawnPositions[npcKey]
		if not targetPos then
			log:warn(`Unknown NPC key for teleport: {npcKey}`)
			return
		end

		local character = player.Character
		if character then
			-- Offset so we don't land on top of the NPC
			character:PivotTo(CFrame.new(targetPos + Vector3.new(5, 0, 5)))
			log:debug(`Teleported {player.Name} to {npcKey} zone`)
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
