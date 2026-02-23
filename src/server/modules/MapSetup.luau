--!strict
--[[
	MapSetup - Creates obstacle geometry from GameConfig.

	Spawns anchored Parts in a Workspace folder so PathfindingService
	includes them in the navmesh. Call initialize() before NPCManager
	so paths are correct from the first computation.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)

local log = Logger.new("MapSetup")

local MapSetup = {}

local obstacleFolder: Folder? = nil

function MapSetup.initialize(): ()
	if obstacleFolder then
		log:info("Already initialized")
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Obstacles"

	for _, config in GameConfig.MAP.OBSTACLES do
		local part = Instance.new("Part")
		part.Name = config.name
		part.Size = config.size
		part.Position = config.position
		part.Color = config.color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = true
		part.Parent = folder
	end

	folder.Parent = Workspace
	obstacleFolder = folder

	log:info(`Created {#GameConfig.MAP.OBSTACLES} obstacles`)
end

function MapSetup.cleanup(): ()
	if obstacleFolder then
		obstacleFolder:Destroy()
		obstacleFolder = nil
	end
end

return MapSetup
