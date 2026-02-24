--!strict
--[[
	NPCManager - Spawns and manages demo NPCs with different pathfinding behaviors.

	Spawns 4 NPCs:
	  - Chase NPC: pursues the nearest player
	  - Patrol NPC: walks a rectangular loop
	  - Wander NPC: roams randomly within a radius
	  - Guard NPC: random patrol with LOS-triggered chase and return-to-post

	Each NPC is driven by a state machine (NPCStateMachine) that manages behavior
	transitions. The state machine ticks via a single RunService.PostSimulation
	connection — states call into NPCPathfinder methods for actual movement.

	NPCs are created as R15 rigs via Players:CreateHumanoidModelFromDescription().
	Falls back to simple Part+Humanoid if R15 creation fails.

	Behavior state definitions live in src/server/modules/behaviors/.
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

-- Behavior state maps
local BehaviorHelpers = require(script.Parent.behaviors.BehaviorHelpers)
local ChaseStates = require(script.Parent.behaviors.ChaseStates)
local GuardStates = require(script.Parent.behaviors.GuardStates)
local PatrolStates = require(script.Parent.behaviors.PatrolStates)
local WanderStates = require(script.Parent.behaviors.WanderStates)

local log = Logger.new("NPCManager")

local NPCManager = {}

type NPCEntry = {
	model: Model,
	pathfinder: typeof(NPCPathfinder.new(nil :: any)),
	stateMachine: typeof(NPCStateMachine.new("" :: any, {} :: any, {} :: any)),
	behaviorType: string,
	debugFolder: Folder?,
	debugDisc: Part?,
	stateLabel: TextLabel?,
	-- Chase state fields (populated by state hooks)
	chaseTarget: Model?,
	chaseReevalTimer: number?,
	-- Wander state fields (populated by state hooks)
	wanderThread: thread?,
	wanderTargetMarker: Part?,
	wanderNpcAttachment: Attachment?,
	-- Wander debug visual toggle (pre-mortem fix: onEnter recreates each cycle)
	_wanderBeamVisible: boolean?,
	-- Guard state fields (populated by state hooks)
	guardPatrolThread: thread?,
	guardTarget: Model?,
	guardReevalTimer: number?,
	guardDetectTimer: number?,
	guardLastWaypointIndex: number?,
	guardReachedWaypoint: boolean?,
	guardReturnDwell: number?,
}

local activeNPCs: { [string]: NPCEntry } = {}
local moduleConnections: { RBXScriptConnection } = {}
local debugStateCallback: ((npcName: string, newState: string, previousState: string?) -> ())? = nil

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

local function makeStateLabelUpdater(
	npcName: string,
	stateLabel: TextLabel?
): ((newState: string, previousState: string?) -> ())?
	if not stateLabel then
		return nil
	end
	local colors = GameConfig.NPC.STATE_LABEL.COLORS
	local defaultColor = GameConfig.NPC.STATE_LABEL.DEFAULT_COLOR
	return function(newState: string, _previousState: string?)
		stateLabel.Text = newState
		stateLabel.TextColor3 = colors[newState] or defaultColor
		log:debug(`State changed: {_previousState or "init"} -> {newState}`)
		if debugStateCallback then
			debugStateCallback(npcName, newState, _previousState)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- DEBUG VISUALS
-- ═══════════════════════════════════════════════════════════

local function createDetectionRadiusCircle(model: Model, radius: number, color: Color3): Part?
	if not GameConfig.GAME.DEBUG then
		return nil
	end

	local rootPart = model.PrimaryPart
	if not rootPart then
		return nil
	end

	local diameter = radius * 2
	local disc = Instance.new("Part")
	disc.Name = "DetectionRadiusDisc"
	disc.Shape = Enum.PartType.Cylinder
	-- Cylinder axis is along X, so X = thickness, Y/Z = diameter
	disc.Size = Vector3.new(0.2, diameter, diameter)
	-- Lay flat at ground level. Anchored + explicit CFrame update in PostSimulation tick.
	disc.CFrame = CFrame.new(rootPart.Position.X, 0.15, rootPart.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanTouch = false
	disc.CanQuery = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = 0.85

	disc.Parent = Workspace

	log:debug(
		`Detection disc created: diameter={diameter}, pos=({disc.Position.X}, {disc.Position.Y}, {disc.Position.Z})`
	)

	return disc
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
		patrolEntry.stateMachine = NPCStateMachine.new(
			"Patrolling",
			PatrolStates,
			patrolEntry,
			makeStateLabelUpdater(GameConfig.NPC.PATROL.DISPLAY_NAME, patrolEntry.stateLabel)
		)
	end

	if wanderEntry then
		wanderEntry.stateLabel = createStateLabel(wanderEntry.model)
		wanderEntry.stateMachine = NPCStateMachine.new(
			"Wandering",
			WanderStates,
			wanderEntry,
			makeStateLabelUpdater(GameConfig.NPC.WANDER.DISPLAY_NAME, wanderEntry.stateLabel)
		)
	end

	if chaseEntry then
		local humanoid = chaseEntry.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.NPC.CHASE.WALK_SPEED
		end
		-- Chase starts Idle — transitions to Chasing when a player enters detection radius
		chaseEntry.stateLabel = createStateLabel(chaseEntry.model)
		chaseEntry.debugDisc = createDetectionRadiusCircle(
			chaseEntry.model,
			GameConfig.NPC.CHASE.DETECTION_RADIUS,
			Color3.fromRGB(239, 68, 68)
		)
		chaseEntry.stateMachine = NPCStateMachine.new(
			"Idle",
			ChaseStates,
			chaseEntry,
			makeStateLabelUpdater(GameConfig.NPC.CHASE.DISPLAY_NAME, chaseEntry.stateLabel)
		)
	end

	local guardEntry = spawnNPC("guard", GameConfig.NPC.GUARD.DISPLAY_NAME, positions.GUARD)
	if guardEntry then
		local humanoid = guardEntry.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = GameConfig.NPC.GUARD.WALK_SPEED
		end
		-- Guard starts Guarding — LOS+distance triggers Chasing, then Returning to post
		guardEntry.stateLabel = createStateLabel(guardEntry.model)
		guardEntry.debugDisc = createDetectionRadiusCircle(
			guardEntry.model,
			GameConfig.NPC.GUARD.DETECTION_RADIUS,
			Color3.fromRGB(255, 139, 0)
		)
		guardEntry.stateMachine = NPCStateMachine.new(
			"Guarding",
			GuardStates,
			guardEntry,
			makeStateLabelUpdater(GameConfig.NPC.GUARD.DISPLAY_NAME, guardEntry.stateLabel)
		)
	end

	-- Single tick loop for all state machines
	table.insert(
		moduleConnections,
		RunService.PostSimulation:Connect(function(dt: number)
			for _, entry in activeNPCs do
				if entry.stateMachine then
					entry.stateMachine:update(dt)
				end
				-- Update anchored debug disc to follow NPC position
				if entry.debugDisc then
					local rootPart = entry.model.PrimaryPart
					if rootPart then
						entry.debugDisc.CFrame = CFrame.new(rootPart.Position.X, 0.15, rootPart.Position.Z)
							* CFrame.Angles(0, 0, math.rad(90))
					end
				end
			end
		end)
	)

	log:info("NPC system ready")
end

--- Register a callback that fires on every NPC state transition.
--- Used by DebugService to push state changes to clients.
function NPCManager.setDebugStateCallback(
	callback: (npcName: string, newState: string, previousState: string?) -> ()
): ()
	debugStateCallback = callback
end

--- Assemble status data for all NPCs relative to a player position.
function NPCManager.getAllNPCStatus(playerPosition: Vector3): { [string]: any }
	local result = {}
	for name, entry in activeNPCs do
		local rootPart = entry.model and entry.model.PrimaryPart
		if not rootPart then
			continue
		end

		local npcPos = rootPart.Position
		local distance = (npcPos - playerPosition).Magnitude

		local state = if entry.stateMachine then entry.stateMachine:getCurrentState() else "Unknown"
		local humanoid = entry.model:FindFirstChildOfClass("Humanoid")
		local walkSpeed = if humanoid then humanoid.WalkSpeed else 0
		local isMoving = entry.pathfinder:isMoving()

		-- Detection radius (Chase and Guard only)
		local detectionRadius: number? = nil
		if entry.behaviorType == "chase" then
			detectionRadius = GameConfig.NPC.CHASE.DETECTION_RADIUS
		elseif entry.behaviorType == "guard" then
			detectionRadius = GameConfig.NPC.GUARD.DETECTION_RADIUS
		end

		-- LOS check (Guard only, when chasing a target)
		local hasLOS: boolean? = nil
		if entry.behaviorType == "guard" and entry.guardTarget then
			local targetRoot = entry.guardTarget:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				hasLOS = entry.pathfinder:hasLineOfSight(targetRoot.Position, { entry.guardTarget })
			end
		end

		result[name] = {
			state = state,
			position = npcPos,
			distanceToPlayer = math.floor(distance * 10) / 10,
			hasLOS = hasLOS,
			isMoving = isMoving,
			walkSpeed = walkSpeed,
			detectionRadius = detectionRadius,
			behaviorType = entry.behaviorType,
		}
	end
	return result
end

--- Toggle visibility of a specific debug visual type for an NPC.
function NPCManager.setDebugVisualEnabled(npcName: string, visualType: string, enabled: boolean): ()
	local entry = activeNPCs[npcName]
	if not entry then
		log:warn(`setDebugVisualEnabled: NPC "{npcName}" not found`)
		return
	end

	if visualType == "disc" then
		if entry.debugDisc then
			entry.debugDisc.Transparency = if enabled then 0.85 else 1
		end
	elseif visualType == "stateLabel" then
		local head = entry.model:FindFirstChild("Head")
		if head then
			local billboard = head:FindFirstChild("StateLabelGui")
			if billboard and billboard:IsA("BillboardGui") then
				billboard.Enabled = enabled
			end
		end
	elseif visualType == "waypoints" then
		if entry.debugFolder then
			for _, child in entry.debugFolder:GetChildren() do
				if child:IsA("BasePart") then
					child.Transparency = if enabled then 0.5 else 1
				elseif child:IsA("BillboardGui") then
					child.Enabled = enabled
				end
			end
		end
	elseif visualType == "wanderBeam" then
		entry._wanderBeamVisible = enabled
		-- Toggle existing instances if they exist right now
		if entry.wanderTargetMarker then
			entry.wanderTargetMarker.Transparency = if enabled then 0.3 else 1
		end
		if entry.wanderNpcAttachment then
			local beam = entry.wanderNpcAttachment:FindFirstChildOfClass("Beam")
			if beam then
				beam.Transparency = NumberSequence.new(if enabled then 0.5 else 1)
			end
		end
	elseif visualType == "chasePath" then
		-- Toggle chase/guard path dots (the small spheres along computed path)
		entry.pathfinder:setVisualizeEnabled(enabled)
	elseif visualType == "nameLabel" then
		-- Toggle the NPC display name BillboardGui above head
		local head = entry.model:FindFirstChild("Head")
		if head then
			-- Name label is a BillboardGui that is NOT named "StateLabelGui"
			for _, child in head:GetChildren() do
				if child:IsA("BillboardGui") and child.Name ~= "StateLabelGui" then
					child.Enabled = enabled
				end
			end
		end
	elseif visualType == "waypointNumbers" then
		-- Toggle just the number BillboardGuis on waypoint markers (not the spheres)
		if entry.debugFolder then
			for _, child in entry.debugFolder:GetChildren() do
				if child:IsA("BasePart") then
					local billboard = child:FindFirstChildOfClass("BillboardGui")
					if billboard then
						billboard.Enabled = enabled
					end
				end
			end
		end
	else
		log:warn(`setDebugVisualEnabled: unknown visualType "{visualType}"`)
	end
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
		if entry.debugDisc then
			entry.debugDisc:Destroy()
		end
		if entry.model then
			entry.model:Destroy()
		end
		log:debug(`Cleaned up {name}`)
	end
	table.clear(activeNPCs)
	BehaviorHelpers.clearCache()
	log:info("All NPCs cleaned up")
end

return NPCManager
