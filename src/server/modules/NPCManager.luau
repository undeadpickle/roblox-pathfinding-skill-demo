--!strict
--[[
	NPCManager - Spawns and manages demo NPCs with different pathfinding behaviors.

	Spawns 3 NPCs:
	  - Chase NPC: pursues the nearest player
	  - Patrol NPC: walks a rectangular loop
	  - Wander NPC: roams randomly within a radius

	Each NPC is driven by a state machine (NPCStateMachine) that manages behavior
	transitions. The state machine ticks via a single RunService.PostSimulation
	connection — states call into NPCPathfinder methods for actual movement.

	NPCs are created as R15 rigs via Players:CreateHumanoidModelFromDescription().
	Falls back to simple Part+Humanoid if R15 creation fails.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCPathfinder = require(script.Parent.NPCPathfinder)
local NPCStateMachine = require(Shared.NPCStateMachine)

local log = Logger.new("NPCManager")

local NPCManager = {}

type NPCEntry = {
	model: Model,
	pathfinder: any,
	stateMachine: any,
	behaviorType: string,
	debugFolder: Folder?,
	stateLabel: TextLabel?,
	-- Chase state fields (populated by state hooks)
	chaseTarget: Model?,
	chaseReevalTimer: number?,
	-- Wander state fields (populated by state hooks)
	wanderThread: thread?,
}

local activeNPCs: { [string]: NPCEntry } = {}
local moduleConnections: { RBXScriptConnection } = {}

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
-- DEBUG STATE LABELS
-- ═══════════════════════════════════════════════════════════

local function createStateLabel(model: Model): TextLabel?
	if not GameConfig.GAME.DEBUG then
		return nil
	end

	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local config = GameConfig.NPC.STATE_LABEL

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StateLabelGui"
	billboard.Size = config.SIZE
	billboard.StudsOffset = config.STUDS_OFFSET
	billboard.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Name = "StateLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = config.DEFAULT_COLOR
	label.TextStrokeTransparency = config.STROKE_TRANSPARENCY
	label.Font = config.FONT
	label.TextSize = config.TEXT_SIZE
	label.Parent = billboard

	billboard.Parent = head

	return label
end

local function makeStateLabelUpdater(stateLabel: TextLabel?): ((newState: string, previousState: string?) -> ())?
	if not stateLabel then
		return nil
	end
	local colors = GameConfig.NPC.STATE_LABEL.COLORS
	local defaultColor = GameConfig.NPC.STATE_LABEL.DEFAULT_COLOR
	return function(newState: string, _previousState: string?)
		stateLabel.Text = newState
		stateLabel.TextColor3 = colors[newState] or defaultColor
	end
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
		stateMachine = nil :: any,
		behaviorType = behaviorType,
	}

	activeNPCs[displayName] = entry
	log:info(`Spawned {displayName} ({behaviorType})`)
	return entry
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS
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

local function createWaypointMarkers(waypoints: { Vector3 }): Folder
	local folder = Instance.new("Folder")
	folder.Name = "PatrolWaypointMarkers"

	for i, wp in waypoints do
		-- Marker sphere at each waypoint
		local marker = Instance.new("Part")
		marker.Name = `Waypoint_{i}`
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(2, 2, 2)
		marker.Position = wp
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(250, 204, 21) -- Yellow
		marker.Transparency = 0.5

		-- Number label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(40, 40)
		billboard.StudsOffset = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = tostring(i)
		label.TextColor3 = Color3.fromRGB(250, 204, 21)
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = billboard

		billboard.Parent = marker
		marker.Parent = folder

		-- Line to next waypoint
		local nextIndex = (i % #waypoints) + 1
		local nextWp = waypoints[nextIndex]
		local midpoint = (wp + nextWp) / 2
		local direction = nextWp - wp

		local line = Instance.new("Part")
		line.Name = `Line_{i}_to_{nextIndex}`
		line.Size = Vector3.new(0.2, 0.2, direction.Magnitude)
		line.CFrame = CFrame.lookAt(midpoint, nextWp)
		line.Anchored = true
		line.CanCollide = false
		line.CanTouch = false
		line.CanQuery = false
		line.Material = Enum.Material.Neon
		line.Color = Color3.fromRGB(250, 204, 21)
		line.Transparency = 0.7
		line.Parent = folder
	end

	folder.Parent = Workspace
	return folder
end

local cachedObstacleFolder: Folder? = nil

local function getObstacleFolder(): Folder?
	if not cachedObstacleFolder then
		cachedObstacleFolder = Workspace:FindFirstChild("Obstacles") :: Folder?
	end
	return cachedObstacleFolder
end

local function getRandomPointInRadius(center: Vector3, radius: number): Vector3
	local MAX_ATTEMPTS = 10
	local obstacleFolder = getObstacleFolder()

	for _ = 1, MAX_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local dist = math.random() * radius
		local candidate = Vector3.new(center.X + math.cos(angle) * dist, center.Y, center.Z + math.sin(angle) * dist)

		-- Raycast down from above to check for obstacle geometry at this XZ
		local rayOrigin = Vector3.new(candidate.X, candidate.Y + 20, candidate.Z)
		local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -40, 0))

		if rayResult then
			local hitPart = rayResult.Instance
			-- Accept only if we hit the baseplate (ground), not an obstacle
			if not obstacleFolder or not hitPart:IsDescendantOf(obstacleFolder) then
				return Vector3.new(candidate.X, rayResult.Position.Y + 3, candidate.Z)
			end
		else
			return candidate
		end
	end

	-- Fallback: return center if all attempts hit obstacles
	return center
end

-- ═══════════════════════════════════════════════════════════
-- STATE DEFINITIONS
--
-- Each NPC type has a state map: { [stateName] = { onEnter, onUpdate, onExit } }
-- onUpdate returns a state name to transition, or nil to stay in the current state.
-- The "context" passed to each hook is the NPCEntry table for that NPC.
-- ═══════════════════════════════════════════════════════════

-- Chase NPC: Idle (scanning for players) → Chasing (following target)
local CHASE_STATES: NPCStateMachine.StateMap = {
	Idle = {
		onEnter = function(ctx: NPCEntry)
			ctx.pathfinder:stop()
		end,

		onUpdate = function(ctx: NPCEntry, _dt: number): string?
			local rootPart = ctx.model.PrimaryPart
			if not rootPart then
				return nil
			end

			local target = findNearestPlayer(rootPart.Position)
			if not target then
				return nil
			end

			local targetRoot = target:FindFirstChild("HumanoidRootPart")
			if not targetRoot then
				return nil
			end

			local distance = ((targetRoot :: BasePart).Position - rootPart.Position).Magnitude
			if distance <= GameConfig.NPC.CHASE.DETECTION_RADIUS then
				-- Stash target so Chasing.onEnter can use it
				ctx.chaseTarget = target
				return "Chasing"
			end

			return nil
		end,
	},

	Chasing = {
		onEnter = function(ctx: NPCEntry)
			local target = ctx.chaseTarget
			if not target then
				return
			end

			local config = GameConfig.NPC.CHASE
			ctx.pathfinder:followTarget(target, {
				recomputeInterval = config.RECOMPUTE_INTERVAL,
				arrivalDistance = config.ARRIVAL_DISTANCE,
				onTargetLost = function()
					log:debug("Chase NPC: target lost (callback)")
				end,
			})
		end,

		onUpdate = function(ctx: NPCEntry, dt: number): string?
			local rootPart = ctx.model.PrimaryPart
			if not rootPart then
				return nil
			end

			-- Throttle re-evaluation (no need to check every frame)
			ctx.chaseReevalTimer = (ctx.chaseReevalTimer or 0) + dt
			if ctx.chaseReevalTimer < GameConfig.NPC.CHASE.REEVALUATE_INTERVAL then
				return nil
			end
			ctx.chaseReevalTimer = 0

			-- Is current target still valid and in range?
			local currentTarget = ctx.chaseTarget
			local currentTargetValid = false

			if currentTarget and currentTarget:IsDescendantOf(game) then
				local targetRoot = currentTarget:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					local distance = ((targetRoot :: BasePart).Position - rootPart.Position).Magnitude
					if distance <= GameConfig.NPC.CHASE.DETECTION_RADIUS then
						currentTargetValid = true
					end
				end
			end

			if not currentTargetValid then
				ctx.chaseTarget = nil
				return "Idle"
			end

			-- Check if a closer player is now the better target
			local nearest = findNearestPlayer(rootPart.Position)
			if nearest and nearest ~= currentTarget then
				local nearestRoot = nearest:FindFirstChild("HumanoidRootPart")
				if nearestRoot then
					local dist = ((nearestRoot :: BasePart).Position - rootPart.Position).Magnitude
					if dist <= GameConfig.NPC.CHASE.DETECTION_RADIUS then
						-- Self-transition: onExit stops old follow, onEnter starts new follow
						ctx.chaseTarget = nearest
						return "Chasing"
					end
				end
			end

			return nil
		end,

		onExit = function(ctx: NPCEntry)
			ctx.pathfinder:stop()
			ctx.chaseReevalTimer = nil
		end,
	},
}

-- Patrol NPC: single state (extensible — add Alert/Chase states later)
local PATROL_STATES: NPCStateMachine.StateMap = {
	Patrolling = {
		onEnter = function(ctx: NPCEntry)
			local config = GameConfig.NPC.PATROL

			if GameConfig.GAME.DEBUG and not ctx.debugFolder then
				ctx.debugFolder = createWaypointMarkers(config.WAYPOINTS)
			end

			ctx.pathfinder:patrol(config.WAYPOINTS, {
				loopMode = config.LOOP_MODE,
				waitTime = config.WAIT_TIME,
				onWaypoint = function(index: number)
					log:debug(`Patrol NPC: reached waypoint {index}`)
				end,
			})
			log:info("Patrol behavior started")
		end,

		onExit = function(ctx: NPCEntry)
			ctx.pathfinder:stop()
		end,
	},
}

-- Wander NPC: single state (extensible — add Flee/Curious states later)
local WANDER_STATES: NPCStateMachine.StateMap = {
	Wandering = {
		onEnter = function(ctx: NPCEntry)
			local config = GameConfig.NPC.WANDER

			ctx.wanderThread = task.spawn(function()
				while ctx.model and ctx.model:IsDescendantOf(game) do
					local target = getRandomPointInRadius(config.CENTER, config.RADIUS)
					local reached = ctx.pathfinder:moveTo(target)

					if reached then
						log:debug("Wander NPC: reached point, pausing")
					end

					local pause = config.PAUSE_MIN + math.random() * (config.PAUSE_MAX - config.PAUSE_MIN)
					task.wait(pause)
				end
			end)
		end,

		onExit = function(ctx: NPCEntry)
			if ctx.wanderThread then
				task.cancel(ctx.wanderThread)
				ctx.wanderThread = nil
			end
			ctx.pathfinder:stop()
		end,
	},
}

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

function NPCManager.initialize(): ()
	log:info("Initializing NPC system...")

	-- Spawn all demo NPCs
	local positions = GameConfig.NPC.SPAWN_POSITIONS

	local patrolEntry = spawnNPC("patrol", GameConfig.NPC.PATROL.DISPLAY_NAME, positions.PATROL)
	local wanderEntry = spawnNPC("wander", GameConfig.NPC.WANDER.DISPLAY_NAME, positions.WANDER)
	local chaseEntry = spawnNPC("chase", GameConfig.NPC.CHASE.DISPLAY_NAME, positions.CHASE)

	-- Attach state machines — each starts in its initial state (onEnter fires immediately)
	if patrolEntry then
		patrolEntry.stateLabel = createStateLabel(patrolEntry.model)
		patrolEntry.stateMachine =
			NPCStateMachine.new("Patrolling", PATROL_STATES, patrolEntry, makeStateLabelUpdater(patrolEntry.stateLabel))
	end

	if wanderEntry then
		wanderEntry.stateLabel = createStateLabel(wanderEntry.model)
		wanderEntry.stateMachine =
			NPCStateMachine.new("Wandering", WANDER_STATES, wanderEntry, makeStateLabelUpdater(wanderEntry.stateLabel))
	end

	if chaseEntry then
		local humanoid = chaseEntry.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.NPC.CHASE.WALK_SPEED
		end
		-- Chase starts Idle — transitions to Chasing when a player enters detection radius
		chaseEntry.stateLabel = createStateLabel(chaseEntry.model)
		chaseEntry.stateMachine =
			NPCStateMachine.new("Idle", CHASE_STATES, chaseEntry, makeStateLabelUpdater(chaseEntry.stateLabel))
	end

	-- Single tick loop for all state machines
	table.insert(
		moduleConnections,
		RunService.PostSimulation:Connect(function(dt: number)
			for _, entry in activeNPCs do
				if entry.stateMachine then
					entry.stateMachine:update(dt)
				end
			end
		end)
	)

	log:info("NPC system ready")
end

function NPCManager.cleanup(): ()
	-- Disconnect module-level connections (includes PostSimulation tick)
	for _, connection in moduleConnections do
		connection:Disconnect()
	end
	table.clear(moduleConnections)

	for name, entry in activeNPCs do
		-- Destroy state machine first (onExit stops threads and pathfinder movement)
		if entry.stateMachine then
			entry.stateMachine:destroy()
		end
		-- Then destroy the pathfinder (disconnects Path.Blocked, Humanoid.Died, etc.)
		entry.pathfinder:destroy()
		if entry.debugFolder then
			entry.debugFolder:Destroy()
		end
		if entry.model then
			entry.model:Destroy()
		end
		log:debug(`Cleaned up {name}`)
	end
	table.clear(activeNPCs)
	cachedObstacleFolder = nil
	log:info("All NPCs cleaned up")
end

return NPCManager
