--!strict
--[[
	NPCManager - Registry-based NPC manager for pathfinding behaviors.

	Public API:
	  - spawnNPC(config)       — create a runtime rig and register it
	  - registerNPC(model, config) — adopt a pre-placed model
	  - despawnNPC(npcId)      — individual teardown
	  - setBehavior(npcId, behaviorType, behaviorConfig?) — swap behavior at runtime
	  - cleanup()              — tear down all NPCs

	Each NPC is driven by a state machine (NPCStateMachine) that manages behavior
	transitions. The state machine ticks via a single RunService.PostSimulation
	connection — states call into NPCPathfinder methods for actual movement.

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

local DebugVisuals = require(script.Parent.DebugVisuals)

-- Behavior state maps
local BehaviorHelpers = require(script.Parent.behaviors.BehaviorHelpers)
local ChaseStates = require(script.Parent.behaviors.ChaseStates)
local GuardStates = require(script.Parent.behaviors.GuardStates)
local PatrolStates = require(script.Parent.behaviors.PatrolStates)
local WanderStates = require(script.Parent.behaviors.WanderStates)

local log = Logger.new("NPCManager")

local NPCManager = {}

-- ═══════════════════════════════════════════════════════════
-- TYPES
-- ═══════════════════════════════════════════════════════════

type NPCEntry = {
	model: Model,
	pathfinder: typeof(NPCPathfinder.new(nil :: any)),
	stateMachine: typeof(NPCStateMachine.new("" :: any, {} :: any, {} :: any)),
	behaviorType: string,
	behaviorConfig: { [string]: any },
	debugFolder: Folder?,
	debugDisc: Part?,
	stateLabel: TextLabel?,
	-- Standardized target field (used by chase-capable behaviors: chase, guard)
	activeTarget: Model?,
	-- LOS memory timer (shared by chase/guard, managed by evaluateChaseTarget)
	losLostTimer: number?,
	-- Re-evaluation timer (shared by chase-capable behaviors)
	reevalTimer: number?,
	-- Wander state fields (populated by state hooks)
	wanderThread: thread?,
	wanderTargetMarker: Part?,
	wanderNpcAttachment: Attachment?,
	-- Wander debug visual toggle (pre-mortem fix: onEnter recreates each cycle)
	_wanderBeamVisible: boolean?,
	-- Guard state fields (populated by state hooks)
	guardPatrolThread: thread?,
	guardReevalTimer: number?,
	guardDetectTimer: number?,
	guardLastWaypointIndex: number?,
	guardReachedWaypoint: boolean?,
	guardReturnDwell: number?,
}

-- ═══════════════════════════════════════════════════════════
-- INTERNAL STATE
-- ═══════════════════════════════════════════════════════════

local activeNPCs: { [string]: NPCEntry } = {}
local moduleConnections: { RBXScriptConnection } = {}
local debugStateCallback: ((npcName: string, newState: string, previousState: string?) -> ())? = nil
local tickRunning = false

-- ═══════════════════════════════════════════════════════════
-- BEHAVIOR REGISTRY
-- ═══════════════════════════════════════════════════════════

local BehaviorRegistry: { [string]: { states: NPCStateMachine.StateMap, initialState: string } } = {
	chase = { states = ChaseStates, initialState = "Idle" },
	patrol = { states = PatrolStates, initialState = "Patrolling" },
	wander = { states = WanderStates, initialState = "Wandering" },
	guard = { states = GuardStates, initialState = "Guarding" },
}

-- Detection disc colors (only behaviors with DETECTION_RADIUS get a disc)
local DISC_COLORS: { [string]: Color3 } = {
	chase = Color3.fromRGB(239, 68, 68), -- Red
	guard = Color3.fromRGB(255, 139, 0), -- Orange
}

-- ═══════════════════════════════════════════════════════════
-- NPC CREATION (rig factory — unchanged)
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
-- INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════

--- Late-binding getter for the debug state callback (DebugService sets it after NPCs spawn)
local function getDebugCallback()
	return debugStateCallback
end

--- Start the PostSimulation tick loop if not already running.
local function ensureTickRunning(): ()
	if tickRunning then
		return
	end
	tickRunning = true

	table.insert(
		moduleConnections,
		RunService.PostSimulation:Connect(function(dt: number)
			for _, entry in activeNPCs do
				if entry.stateMachine then
					entry.stateMachine:update(dt)
				end
				DebugVisuals.updateTick(entry)
			end
		end)
	)
end

--- Nil all behavior-specific fields on an NPCEntry.
--- Called after stateMachine:destroy() (which runs onExit cleanup) as a safety net
--- to catch any fields that onExit didn't nil (e.g., timers only cleared in one exit path).
local function scrubBehaviorFields(entry: NPCEntry): ()
	-- Chase/Guard shared
	entry.activeTarget = nil
	entry.losLostTimer = nil
	entry.reevalTimer = nil
	-- Wander-specific (Instances should be destroyed by onExit already)
	entry.wanderThread = nil
	entry.wanderTargetMarker = nil
	entry.wanderNpcAttachment = nil
	entry._wanderBeamVisible = nil
	-- Guard-specific
	entry.guardPatrolThread = nil
	entry.guardReevalTimer = nil
	entry.guardDetectTimer = nil
	entry.guardLastWaypointIndex = nil
	entry.guardReachedWaypoint = nil
	entry.guardReturnDwell = nil
end

--- Wire a behavior (state machine + debug visuals) onto an NPCEntry.
local function wireBehavior(entry: NPCEntry): ()
	local behaviorDef = BehaviorRegistry[entry.behaviorType]
	if not behaviorDef then
		log:error(`Unknown behavior type: {entry.behaviorType}`)
		return
	end

	-- Set walk speed from behavior config (if specified)
	local humanoid = entry.model:FindFirstChildOfClass("Humanoid")
	if humanoid and entry.behaviorConfig.WALK_SPEED then
		humanoid.WalkSpeed = entry.behaviorConfig.WALK_SPEED
	end

	-- Debug visuals: state label (all behaviors, persists across behavior swaps)
	if not entry.stateLabel then
		entry.stateLabel = DebugVisuals.createStateLabel(entry.model)
	end

	-- Debug visuals: detection radius disc (only behaviors with DETECTION_RADIUS)
	local discColor = DISC_COLORS[entry.behaviorType]
	if discColor and entry.behaviorConfig.DETECTION_RADIUS then
		entry.debugDisc =
			DebugVisuals.createDetectionRadiusCircle(entry.model, entry.behaviorConfig.DETECTION_RADIUS, discColor)
	end

	-- Create state machine
	entry.stateMachine = NPCStateMachine.new(
		behaviorDef.initialState,
		behaviorDef.states,
		entry,
		DebugVisuals.makeStateLabelUpdater(entry.model.Name, entry.stateLabel, getDebugCallback)
	)
end

--- Register a model+config into the active NPC registry.
local function registerEntry(model: Model, config: { [string]: any }): string?
	local displayName = config.displayName :: string

	-- Enforce unique IDs
	if activeNPCs[displayName] then
		log:error(`NPC with name "{displayName}" already registered`)
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
		behaviorType = config.behaviorType :: string,
		behaviorConfig = config.behavior :: { [string]: any },
	}

	activeNPCs[displayName] = entry
	log:info(`Registered {displayName} ({config.behaviorType})`)

	wireBehavior(entry)
	ensureTickRunning()

	return displayName
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════

--- Spawn a new NPC by creating a runtime rig and registering it.
--- config.spawnPosition is required. Returns npcId (displayName) on success, nil on failure.
function NPCManager.spawnNPC(config: { [string]: any }): string?
	local spawnPosition = config.spawnPosition :: Vector3?
	if not spawnPosition then
		log:error(`spawnNPC requires config.spawnPosition for "{config.displayName}"`)
		return nil
	end

	local model = createNPCModel(config.displayName :: string, spawnPosition)
	if not model then
		log:error(`Failed to spawn {config.displayName}`)
		return nil
	end

	return registerEntry(model, config)
end

--- Register an existing model as an NPC (no rig creation).
--- Returns npcId (displayName) on success, nil on failure.
function NPCManager.registerNPC(model: Model, config: { [string]: any }): string?
	-- Validate model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:error(`registerNPC: model "{model.Name}" has no Humanoid`)
		return nil
	end
	if not model.PrimaryPart then
		log:error(`registerNPC: model "{model.Name}" has no PrimaryPart`)
		return nil
	end

	-- Use model name as display name if not provided
	if not config.displayName then
		config.displayName = model.Name
	end

	-- Name the model to match displayName for debug panel consistency
	model.Name = config.displayName :: string

	return registerEntry(model, config)
end

--- Despawn a single NPC by its ID (displayName). Returns true if found and removed.
function NPCManager.despawnNPC(npcId: string): boolean
	local entry = activeNPCs[npcId]
	if not entry then
		log:warn(`despawnNPC: NPC "{npcId}" not found`)
		return false
	end

	-- Destroy state machine first (onExit stops threads and pathfinder movement)
	if entry.stateMachine then
		entry.stateMachine:destroy()
	end
	-- Then destroy the pathfinder (disconnects Path.Blocked, Humanoid.Died, etc.)
	entry.pathfinder:destroy()
	DebugVisuals.cleanupEntry(entry)
	if entry.model then
		entry.model:Destroy()
	end

	activeNPCs[npcId] = nil
	log:debug(`Despawned {npcId}`)
	return true
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

		-- Detection radius (nil-safe read from behavior config)
		local detectionRadius: number? = entry.behaviorConfig.DETECTION_RADIUS

		-- LOS check (using standardized activeTarget field)
		local hasLOS: boolean? = nil
		local losTarget = entry.activeTarget
		if losTarget then
			local targetRoot = losTarget:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				hasLOS = entry.pathfinder:hasLineOfSight(targetRoot.Position, { losTarget })
			end
		end

		-- LOS memory countdown (when NPC has lost sight but is still pursuing)
		local losCountdown: number? = nil
		if entry.losLostTimer then
			local memoryConfig: number? = entry.behaviorConfig.LOS_MEMORY
			if memoryConfig then
				losCountdown = math.floor(math.max(0, memoryConfig - entry.losLostTimer) * 10) / 10
			end
		end

		result[name] = {
			state = state,
			position = npcPos,
			distanceToPlayer = math.floor(distance * 10) / 10,
			hasLOS = hasLOS,
			losCountdown = losCountdown,
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
	DebugVisuals.setVisualEnabled(entry, visualType, enabled)
end

--- Get an NPC's current world position (or nil if not found).
function NPCManager.getNPCPosition(displayName: string): Vector3?
	local entry = activeNPCs[displayName]
	if not entry then
		return nil
	end
	local rootPart = entry.model and entry.model.PrimaryPart
	if not rootPart then
		return nil
	end
	return rootPart.Position
end

--- Get the list of registered behavior type keys (sorted for stable order).
function NPCManager.getAvailableBehaviors(): { string }
	local result = {}
	for key in BehaviorRegistry do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

--- Teleport an NPC to a world position. Stops current movement first.
function NPCManager.teleportNPC(displayName: string, position: Vector3): boolean
	local entry = activeNPCs[displayName]
	if not entry then
		return false
	end
	-- Stop pathfinder movement so it doesn't fight the teleport
	entry.pathfinder:stop()
	entry.model:PivotTo(CFrame.new(position))
	log:debug(
		`Teleported NPC "{displayName}" to ({math.floor(position.X)}, {math.floor(position.Y)}, {math.floor(position.Z)})`
	)
	return true
end

--- Swap a running NPC's behavior at runtime.
--- Tears down the old state machine and debug visuals, scrubs behavior-specific
--- context fields, then wires the new behavior. Model and pathfinder persist.
--- If behaviorConfig is nil, the existing config is reused — caller must ensure
--- the config is compatible with the new behavior type (e.g., patrol needs WAYPOINTS).
--- Returns true on success, false if NPC not found or behavior type unknown.
function NPCManager.setBehavior(npcId: string, behaviorType: string, behaviorConfig: { [string]: any }?): boolean
	local entry = activeNPCs[npcId]
	if not entry then
		log:warn(`setBehavior: NPC "{npcId}" not found`)
		return false
	end

	if not BehaviorRegistry[behaviorType] then
		log:error(`setBehavior: unknown behavior type "{behaviorType}"`)
		return false
	end

	local newConfig = behaviorConfig or entry.behaviorConfig
	if not newConfig then
		log:error(`setBehavior: no config provided and NPC "{npcId}" has no existing config`)
		return false
	end

	local oldBehavior = entry.behaviorType
	log:info(`Swapping {npcId}: {oldBehavior} -> {behaviorType}`)

	-- 1. Destroy old state machine (triggers current state's onExit → stops threads, pathfinder)
	if entry.stateMachine then
		entry.stateMachine:destroy()
	end

	-- 2. Scrub behavior-specific fields (safety net after onExit)
	scrubBehaviorFields(entry)

	-- 3. Clean up behavior-specific debug visuals (disc + waypoint markers)
	DebugVisuals.cleanupEntry(entry)

	-- 4. Update entry with new behavior identity
	entry.behaviorType = behaviorType
	entry.behaviorConfig = newConfig

	-- 5. Wire new behavior (state machine, disc, walkspeed — state label persists)
	wireBehavior(entry)

	log:info(`{npcId} now running "{behaviorType}"`)
	return true
end

function NPCManager.cleanup(): ()
	-- Disconnect module-level connections (includes PostSimulation tick)
	for _, connection in moduleConnections do
		connection:Disconnect()
	end
	table.clear(moduleConnections)
	tickRunning = false

	for name, entry in activeNPCs do
		-- Destroy state machine first (onExit stops threads and pathfinder movement)
		if entry.stateMachine then
			entry.stateMachine:destroy()
		end
		-- Then destroy the pathfinder (disconnects Path.Blocked, Humanoid.Died, etc.)
		entry.pathfinder:destroy()
		DebugVisuals.cleanupEntry(entry)
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
