--!strict
--[[
	NPCManager - Spawns and manages demo NPCs with different pathfinding behaviors.

	Spawns 3 NPCs:
	  - Chase NPC: pursues the nearest player
	  - Patrol NPC: walks a rectangular loop
	  - Wander NPC: roams randomly within a radius

	NPCs are created as R15 rigs via Players:CreateHumanoidModelFromDescription().
	Falls back to simple Part+Humanoid if R15 creation fails.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCPathfinder = require(script.Parent.NPCPathfinder)

local log = Logger.new("NPCManager")

local NPCManager = {}

type NPCEntry = {
	model: Model,
	pathfinder: any,
	behaviorThread: thread?,
	behaviorType: string,
}

local activeNPCs: { [string]: NPCEntry } = {}

-- ═══════════════════════════════════════════════════════════
-- NPC CREATION
-- ═══════════════════════════════════════════════════════════

local function createSimpleNPCModel(): Model
	local model = Instance.new("Model")

	-- Torso (serves as HumanoidRootPart)
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Anchored = false
	rootPart.CanCollide = true
	rootPart.Parent = model

	-- Head (for BillboardGui attachment)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Anchored = false
	head.CanCollide = false

	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = rootPart
	headWeld.Part1 = head
	headWeld.Parent = head

	head.CFrame = rootPart.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = rootPart
	return model
end

local function createNPCModel(displayName: string, spawnPosition: Vector3): Model?
	local model: Model? = nil

	-- Try creating a full R15 rig
	local description = Instance.new("HumanoidDescription")
	local success, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()

	if success and result then
		model = result :: Model
	else
		log:warn(`Failed to create R15 model for {displayName}, using simple model`)
		model = createSimpleNPCModel()
	end

	if not model then
		return nil
	end

	model.Name = displayName

	-- Add name label above head
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(200, 50)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = true

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = displayName
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.5
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = billboard

		billboard.Parent = head
	end

	-- Position and parent (properties before Parent per conventions)
	model:PivotTo(CFrame.new(spawnPosition))
	model.Parent = Workspace

	return model
end

-- ═══════════════════════════════════════════════════════════
-- SPAWNING
-- ═══════════════════════════════════════════════════════════

local function spawnNPC(behaviorType: string, displayName: string, spawnPosition: Vector3): NPCEntry?
	local model = createNPCModel(displayName, spawnPosition)
	if not model then
		log:error(`Failed to spawn {displayName}`)
		return nil
	end

	local npcConfig = GameConfig.NPC
	local pathfinder = NPCPathfinder.new(model, {
		AgentRadius = npcConfig.AGENT.AgentRadius,
		AgentHeight = npcConfig.AGENT.AgentHeight,
		AgentCanJump = npcConfig.AGENT.AgentCanJump,
		WaypointSpacing = npcConfig.AGENT.WaypointSpacing,
		CollisionGroup = npcConfig.COLLISION_GROUP,
	})

	local entry: NPCEntry = {
		model = model,
		pathfinder = pathfinder,
		behaviorThread = nil,
		behaviorType = behaviorType,
	}

	activeNPCs[displayName] = entry
	log:info(`Spawned {displayName} ({behaviorType})`)
	return entry
end

-- ═══════════════════════════════════════════════════════════
-- BEHAVIORS
-- ═══════════════════════════════════════════════════════════

local function findNearestPlayer(position: Vector3): Model?
	local nearest: Model? = nil
	local nearestDist = math.huge

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			continue
		end

		local dist = ((root :: BasePart).Position - position).Magnitude
		if dist < nearestDist then
			nearest = character
			nearestDist = dist
		end
	end

	return nearest
end

local function startChaseBehavior(entry: NPCEntry): ()
	local config = GameConfig.NPC.CHASE

	entry.behaviorThread = task.spawn(function()
		while entry.model and entry.model:IsDescendantOf(game) do
			local rootPart = entry.model.PrimaryPart
			if not rootPart then
				break
			end

			local target = findNearestPlayer(rootPart.Position)

			if target then
				local targetRoot = target:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					local distance = ((targetRoot :: BasePart).Position - rootPart.Position).Magnitude
					if distance <= config.DETECTION_RADIUS then
						entry.pathfinder:followTarget(target, {
							recomputeInterval = config.RECOMPUTE_INTERVAL,
							arrivalDistance = config.ARRIVAL_DISTANCE,
							onTargetLost = function()
								log:debug("Chase NPC: target lost")
							end,
						})
						-- followTarget is non-blocking; wait then re-evaluate for target switching
						task.wait(config.REEVALUATE_INTERVAL)
						continue
					end
				end
			end

			-- No target in range, idle
			task.wait(1)
		end
	end)
end

local function startPatrolBehavior(entry: NPCEntry): ()
	local config = GameConfig.NPC.PATROL

	entry.pathfinder:patrol(config.WAYPOINTS, {
		loopMode = config.LOOP_MODE,
		waitTime = config.WAIT_TIME,
		onWaypoint = function(index: number)
			log:debug(`Patrol NPC: reached waypoint {index}`)
		end,
	})

	log:info("Patrol behavior started")
end

local function getRandomPointInRadius(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return Vector3.new(center.X + math.cos(angle) * dist, center.Y, center.Z + math.sin(angle) * dist)
end

local function startWanderBehavior(entry: NPCEntry): ()
	local config = GameConfig.NPC.WANDER

	entry.behaviorThread = task.spawn(function()
		while entry.model and entry.model:IsDescendantOf(game) do
			local target = getRandomPointInRadius(config.CENTER, config.RADIUS)

			-- moveTo is blocking — returns when NPC arrives or fails
			local reached = entry.pathfinder:moveTo(target)

			if reached then
				log:debug("Wander NPC: reached point, pausing")
			end

			-- Random pause between moves
			local pause = config.PAUSE_MIN + math.random() * (config.PAUSE_MAX - config.PAUSE_MIN)
			task.wait(pause)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function NPCManager.initialize(): ()
	log:info("Initializing NPC system...")

	-- Enable improved pathfinding algorithm (fixes zig-zagging and wall-hugging)
	local pathfindingEnabled = pcall(function()
		(Workspace :: any).PathfindingUseImprovedSearch = true
	end)
	if not pathfindingEnabled then
		log:warn(
			"Could not enable PathfindingUseImprovedSearch via script. Enable it manually in Studio: Workspace > Properties > PathfindingUseImprovedSearch"
		)
	end

	-- Spawn all demo NPCs
	local positions = GameConfig.NPC.SPAWN_POSITIONS

	local patrolEntry = spawnNPC("patrol", GameConfig.NPC.PATROL.DISPLAY_NAME, positions.PATROL)
	local wanderEntry = spawnNPC("wander", GameConfig.NPC.WANDER.DISPLAY_NAME, positions.WANDER)
	local chaseEntry = spawnNPC("chase", GameConfig.NPC.CHASE.DISPLAY_NAME, positions.CHASE)

	-- Start non-player-dependent behaviors immediately
	if patrolEntry then
		startPatrolBehavior(patrolEntry)
	end

	if wanderEntry then
		startWanderBehavior(wanderEntry)
	end

	-- Chase behavior needs a player target
	if chaseEntry then
		local chaseStarted = false

		local function tryStartChase(): ()
			if chaseStarted then
				return
			end
			if #Players:GetPlayers() > 0 then
				chaseStarted = true
				startChaseBehavior(chaseEntry)
				log:info("Chase behavior activated (player detected)")
			end
		end

		Players.PlayerAdded:Connect(function()
			tryStartChase()
		end)

		-- Handle players already in-game (Studio testing)
		tryStartChase()
	end

	local playerStatus = if #Players:GetPlayers() > 0 then "chase active" else "chase waiting for player"
	log:info(`NPC system ready — {playerStatus}`)
end

function NPCManager.cleanup(): ()
	for name, entry in activeNPCs do
		if entry.behaviorThread then
			task.cancel(entry.behaviorThread)
		end
		entry.pathfinder:destroy()
		if entry.model then
			entry.model:Destroy()
		end
		log:debug(`Cleaned up {name}`)
	end
	table.clear(activeNPCs)
	log:info("All NPCs cleaned up")
end

return NPCManager
