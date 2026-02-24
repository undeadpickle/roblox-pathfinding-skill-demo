--!strict
--[[
	Server entry point.

	Wrapped in pcall to catch initialization errors early.
	If this script fails, check Studio Output for [CRITICAL] errors.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Error boundary: Catch require/init failures
local success, err = pcall(function()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Logger = require(Shared.Logger)

	local log = Logger.new("Server")

	local function onPlayerAdded(player: Player): ()
		log:info("Player joined:", player.Name)
	end

	local function onPlayerRemoving(player: Player): ()
		log:info("Player leaving:", player.Name)
	end

	local function initialize(): ()
		log:info("Initializing...")

		-- Connect player events
		Players.PlayerAdded:Connect(onPlayerAdded)
		Players.PlayerRemoving:Connect(onPlayerRemoving)

		-- Handle players already in game (Studio testing)
		for _, player in Players:GetPlayers() do
			task.spawn(onPlayerAdded, player)
		end

		-- Build map geometry before NPCs so navmesh includes obstacles
		local MapSetup = require(script.modules.MapSetup)
		MapSetup.initialize()

		-- Initialize NPC pathfinding system
		local NPCManager = require(script.modules.NPCManager)
		NPCManager.initialize()

		-- Initialize debug panel server-side handlers
		local DebugService = require(script.modules.DebugService)
		DebugService.initialize()

		-- Clean up NPC threads and instances on server shutdown
		game:BindToClose(function()
			NPCManager.cleanup()
			MapSetup.cleanup()
		end)
	end

	initialize()
	log:info("Ready")
end)

if not success then
	warn("[CRITICAL] Server initialization failed:", err)
	-- In production, you might want to shut down the server
	-- or alert monitoring systems here
end
