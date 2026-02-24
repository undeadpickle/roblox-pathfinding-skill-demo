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
	local partCount = 0

	for _, config in GameConfig.MAP.OBSTACLES do
		if config.type == "staircase" then
			-- Generate ascending steps from base position (+Z direction)
			local stepSize = config.stepSize
			for i = 0, config.steps - 1 do
				local step = Instance.new("Part")
				step.Name = `{config.name}_Step{i + 1}`
				step.Size = stepSize
				step.Position = config.position
					+ Vector3.new(0, i * stepSize.Y + stepSize.Y / 2, i * stepSize.Z + stepSize.Z / 2)
				step.Color = config.color
				step.Material = Enum.Material.SmoothPlastic
				step.Anchored = true
				step.CanCollide = true
				step.Parent = folder
				partCount += 1
			end
		else
			local part = Instance.new("Part")
			part.Name = config.name
			part.Size = config.size
			part.Position = config.position
			part.Color = config.color
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = true
			part.Parent = folder
			partCount += 1
		end
	end

	folder.Parent = Workspace
	obstacleFolder = folder

	log:info(`Created {partCount} obstacle parts from {#GameConfig.MAP.OBSTACLES} entries`)
end

function MapSetup.cleanup(): ()
	if obstacleFolder then
		obstacleFolder:Destroy()
		obstacleFolder = nil
	end
end

return MapSetup
