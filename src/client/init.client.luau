--!strict
--[[
	Client entry point.

	Wrapped in pcall to catch initialization errors early.
	If this script fails, check Studio Output for [CRITICAL] errors.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Error boundary: Catch require/init failures
local success, err = pcall(function()
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Logger = require(Shared.Logger)

	local log = Logger.new("Client")

	local function initialize(): ()
		log:info("Initializing...")

		local DebugPanel = require(script.modules.DebugPanel)
		DebugPanel.initialize()
	end

	local function onCharacterAdded(_character: Model): ()
		log:debug("Character spawned")
	end

	-- Connect character events
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	initialize()
	log:info("Ready")
end)

if not success then
	warn("[CRITICAL] Client initialization failed:", err)
end
