--[[
    NPCPathfinder - Production-ready NPC pathfinding module for Roblox
    
    Usage:
        local NPCPathfinder = require(path.to.NPCPathfinder)
        
        local pf = NPCPathfinder.new(npcModel, {
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = false,
            WaypointSpacing = 4,
            Costs = {},
            SupportPartialPath = false,
            CollisionGroup = "NPCs",       -- prevents NPC-to-NPC physics jitter
            DisableUnusedStates = true,     -- disable expensive Humanoid states
        })
        
        pf:moveTo(targetPosition)
        pf:followTarget(playerCharacter, { recomputeInterval = 0.5 })
        pf:patrol(waypointList, { loopMode = "loop", waitTime = 2 })
        pf:stop()
        pf:destroy()
    
    Requires: Server-side execution. NPC model with Humanoid and HumanoidRootPart.
    Place in ServerScriptService or ServerStorage (not ReplicatedStorage — see note below).
    
    Handles: Path computation, waypoint traversal, jump/climb, blocked paths,
             stuck detection, NPC collision groups, Humanoid optimization, connection cleanup.
    
    NOTE: This module contains server-authoritative AI logic. Keep it in ServerScriptService
    or ServerStorage so it is not replicated to clients. ReplicatedStorage exposes your NPC
    behavior logic (aggro ranges, timing, decision patterns) to exploiters.
]]

local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local NPCPathfinder = {}
NPCPathfinder.__index = NPCPathfinder

-- Default configuration
local DEFAULTS = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	AgentCanClimb = false,
	WaypointSpacing = 4,
	Costs = {},
	SupportPartialPath = false,

	-- Behavior tuning
	RecomputeInterval = 1.0,         -- min seconds between path recomputes
	StuckTimeout = 8.0,              -- seconds without progress before stuck recovery
	StuckDistanceThreshold = 1.5,    -- must move this far to count as progress
	WaypointReachDistance = 3.0,     -- close enough to a waypoint to consider it reached
	MoveToTimeout = 8.0,             -- max seconds to wait for MoveToFinished per waypoint
	DirectMoveDistance = 12.0,       -- use direct MoveTo instead of pathfinding within this range

	-- Physics and performance
	CollisionGroup = "NPCs",         -- collision group name; NPCs in same group won't collide
	DisableUnusedStates = true,      -- disable expensive Humanoid states NPCs don't need
}

--[[ 
    Constructor
    @param npcModel: Model — The NPC model (must have Humanoid and HumanoidRootPart)
    @param config: table? — Override defaults. Keys match DEFAULTS above.
    @return NPCPathfinder instance
]]
function NPCPathfinder.new(npcModel: Model, config: {[string]: any}?)
	assert(npcModel, "NPCPathfinder: npcModel is required")
	assert(npcModel:FindFirstChild("Humanoid"), "NPCPathfinder: NPC model must have a Humanoid")
	assert(npcModel.PrimaryPart, "NPCPathfinder: NPC model must have PrimaryPart set")

	config = config or {}

	local self = setmetatable({}, NPCPathfinder)

	-- Model references
	self._model = npcModel
	self._humanoid = npcModel:FindFirstChild("Humanoid")
	self._rootPart = npcModel.PrimaryPart

	-- Configuration (merge with defaults)
	self._config = {}
	for key, default in DEFAULTS do
		self._config[key] = if config[key] ~= nil then config[key] else default
	end

	-- Create the Path object (reused across computations)
	self._path = PathfindingService:CreatePath({
		AgentRadius = self._config.AgentRadius,
		AgentHeight = self._config.AgentHeight,
		AgentCanJump = self._config.AgentCanJump,
		AgentCanClimb = self._config.AgentCanClimb,
		WaypointSpacing = self._config.WaypointSpacing,
		Costs = self._config.Costs,
		PathSettings = {
			SupportPartialPath = self._config.SupportPartialPath,
		},
	})

	-- State
	self._waypoints = {}
	self._currentWaypointIndex = 0
	self._isMoving = false
	self._isDestroyed = false
	self._lastComputeTime = 0
	self._lastProgressPosition = self._rootPart.Position
	self._lastProgressTime = tick()

	-- Connections (tracked for cleanup)
	self._connections = {}

	-- Lock network ownership to server
	pcall(function()
		self._rootPart:SetNetworkOwner(nil)
	end)

	-- Set up collision group so NPCs don't collide with each other
	if self._config.CollisionGroup then
		self:_setupCollisionGroup(self._config.CollisionGroup)
	end

	-- Disable expensive Humanoid states that NPCs don't need
	if self._config.DisableUnusedStates then
		self:_disableUnusedStates()
	end

	-- Connect Path.Blocked
	self:_connect("PathBlocked", self._path.Blocked, function(blockedIndex)
		self:_onPathBlocked(blockedIndex)
	end)

	-- Connect Humanoid.Died for cleanup
	self:_connect("HumanoidDied", self._humanoid.Died, function()
		self:stop()
	end)

	return self
end

--[[ 
    Move to a specific position.
    Computes a path and traverses it. Returns true if destination reached.
    @param targetPosition: Vector3
    @return boolean — true if NPC reached the destination
]]
function NPCPathfinder:moveTo(targetPosition: Vector3): boolean
	if self._isDestroyed then return false end

	self:stop()
	self._isMoving = true

	-- Check if close enough for direct movement
	local distance = (targetPosition - self._rootPart.Position).Magnitude
	if distance <= self._config.DirectMoveDistance and self:_hasLineOfSight(targetPosition) then
		return self:_directMoveTo(targetPosition)
	end

	-- Compute path
	local pathFound = self:_computePath(targetPosition)
	if not pathFound then
		self._isMoving = false
		return false
	end

	-- Traverse waypoints
	local reached = self:_traverseWaypoints()
	self._isMoving = false
	return reached
end

--[[
    Follow a moving target continuously.
    Recomputes path at intervals. Runs until stopped or target is lost.
    @param target: Model — Target model (must have PrimaryPart)
    @param options: table? — { recomputeInterval, arrivalDistance, onArrival, onTargetLost }
]]
function NPCPathfinder:followTarget(target: Model, options: {[string]: any}?)
	if self._isDestroyed then return end

	options = options or {}
	local recomputeInterval = options.recomputeInterval or self._config.RecomputeInterval
	local arrivalDistance = options.arrivalDistance or 5
	local onArrival = options.onArrival
	local onTargetLost = options.onTargetLost

	self:stop()
	self._isMoving = true

	self._followThread = task.spawn(function()
		while self._isMoving and not self._isDestroyed do
			-- Validate target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
				or target and target.PrimaryPart
			if not targetRoot then
				if onTargetLost then onTargetLost() end
				break
			end

			local distance = (targetRoot.Position - self._rootPart.Position).Magnitude

			-- At arrival distance
			if distance <= arrivalDistance then
				self._humanoid:MoveTo(self._rootPart.Position) -- stop movement
				if onArrival then onArrival(target) end
				task.wait(0.2)
				continue
			end

			-- Close + line of sight = direct chase
			if distance <= self._config.DirectMoveDistance and self:_hasLineOfSight(targetRoot.Position) then
				self._humanoid:MoveTo(targetRoot.Position)
			else
				-- Compute and start following path (non-blocking)
				local pathFound = self:_computePath(targetRoot.Position)
				if pathFound then
					self:_traverseWaypointsNonBlocking(recomputeInterval)
				end
			end

			task.wait(recomputeInterval)
		end

		self._isMoving = false
	end)
end

--[[
    Patrol a list of waypoints.
    @param waypoints: {Vector3 | BasePart} — List of positions or parts
    @param options: table? — { loopMode = "loop"|"pingpong", waitTime = number, onWaypoint = function }
]]
function NPCPathfinder:patrol(waypoints: {any}, options: {[string]: any}?)
	if self._isDestroyed then return end
	assert(#waypoints >= 2, "NPCPathfinder:patrol requires at least 2 waypoints")

	options = options or {}
	local loopMode = options.loopMode or "loop"
	local waitTime = options.waitTime or 2
	local onWaypoint = options.onWaypoint

	self:stop()
	self._isMoving = true

	local index = 1
	local direction = 1

	self._patrolThread = task.spawn(function()
		while self._isMoving and not self._isDestroyed do
			local wp = waypoints[index]
			local pos = if typeof(wp) == "Vector3" then wp
				elseif typeof(wp) == "Instance" and wp:IsA("BasePart") then wp.Position
				else error("Patrol waypoint must be Vector3 or BasePart")

			local reached = self:moveTo(pos)

			if reached and onWaypoint then
				onWaypoint(index, wp)
			end

			if reached and waitTime > 0 then
				task.wait(waitTime)
			end

			-- Advance index
			if not self._isMoving then break end

			if loopMode == "loop" then
				index = (index % #waypoints) + 1
			elseif loopMode == "pingpong" then
				index += direction
				if index > #waypoints then
					direction = -1
					index = #waypoints - 1
				elseif index < 1 then
					direction = 1
					index = 2
				end
			end
		end
	end)
end

--[[
    Stop all movement immediately.
]]
function NPCPathfinder:stop()
	self._isMoving = false
	self._waypoints = {}
	self._currentWaypointIndex = 0

	-- Cancel follow/patrol threads
	if self._followThread then
		task.cancel(self._followThread)
		self._followThread = nil
	end
	if self._patrolThread then
		task.cancel(self._patrolThread)
		self._patrolThread = nil
	end

	-- Stop humanoid movement
	if self._humanoid and self._humanoid.Health > 0 then
		pcall(function()
			self._humanoid:MoveTo(self._rootPart.Position)
		end)
	end
end

--[[
    Check if the NPC is currently moving.
    @return boolean
]]
function NPCPathfinder:isMoving(): boolean
	return self._isMoving
end

--[[
    Get the current config (read-only copy).
    @return table
]]
function NPCPathfinder:getConfig(): {[string]: any}
	return table.clone(self._config)
end

--[[
    Update a config value at runtime (e.g., changing costs).
    Recreates the Path object if agent params changed.
    @param key: string
    @param value: any
]]
function NPCPathfinder:setConfig(key: string, value: any)
	self._config[key] = value

	-- If agent params changed, recreate the Path object
	local agentParams = {
		"AgentRadius", "AgentHeight", "AgentCanJump",
		"AgentCanClimb", "WaypointSpacing", "Costs", "SupportPartialPath"
	}
	if table.find(agentParams, key) then
		self:_recreatePath()
	end
end

--[[
    Clean up all connections and state. Call when NPC is removed from the game.
]]
function NPCPathfinder:destroy()
	if self._isDestroyed then return end
	self._isDestroyed = true

	self:stop()

	-- Disconnect all events
	for name, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}

	-- Clear references
	self._model = nil
	self._humanoid = nil
	self._rootPart = nil
	self._path = nil
end


-- ═══════════════════════════════════════════════════════════
-- PRIVATE METHODS
-- ═══════════════════════════════════════════════════════════

function NPCPathfinder:_setupCollisionGroup(groupName: string)
	-- Register the group if it doesn't exist yet (safe to call multiple times)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)

	-- Disable NPC-to-NPC collisions within this group
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupName, groupName, false)
	end)

	-- Assign all BaseParts in the NPC to this group
	for _, part in self._model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

function NPCPathfinder:_disableUnusedStates()
	-- Disable Humanoid states that server-side NPCs never use.
	-- Saves CPU by skipping the engine's per-frame state transition checks.
	local unusedStates = {
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Flying,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.Landed,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.StrafingNoPhysics,
		Enum.HumanoidStateType.Swimming,
	}

	for _, state in unusedStates do
		self._humanoid:SetStateEnabled(state, false)
	end
end

function NPCPathfinder:_connect(name: string, signal: RBXScriptSignal, callback: (...any) -> ())
	if self._connections[name] then
		self._connections[name]:Disconnect()
	end
	self._connections[name] = signal:Connect(callback)
end

function NPCPathfinder:_recreatePath()
	-- Disconnect old blocked handler
	if self._connections["PathBlocked"] then
		self._connections["PathBlocked"]:Disconnect()
	end

	self._path = PathfindingService:CreatePath({
		AgentRadius = self._config.AgentRadius,
		AgentHeight = self._config.AgentHeight,
		AgentCanJump = self._config.AgentCanJump,
		AgentCanClimb = self._config.AgentCanClimb,
		WaypointSpacing = self._config.WaypointSpacing,
		Costs = self._config.Costs,
		PathSettings = {
			SupportPartialPath = self._config.SupportPartialPath,
		},
	})

	self:_connect("PathBlocked", self._path.Blocked, function(blockedIndex)
		self:_onPathBlocked(blockedIndex)
	end)
end

function NPCPathfinder:_computePath(targetPosition: Vector3): boolean
	-- Throttle recomputation
	local now = tick()
	if now - self._lastComputeTime < self._config.RecomputeInterval * 0.5 then
		return #self._waypoints > 0  -- return whether we have an existing path
	end

	local success, errorMessage = pcall(function()
		self._path:ComputeAsync(self._rootPart.Position, targetPosition)
	end)

	if not success then
		warn("[NPCPathfinder] ComputeAsync error:", errorMessage)
		return false
	end

	self._lastComputeTime = now

	if self._path.Status == Enum.PathStatus.Success
		or self._path.Status == Enum.PathStatus.ClosestNoPath then
		self._waypoints = self._path:GetWaypoints()
		self._currentWaypointIndex = 1
		return true
	end

	-- Path failed
	self._waypoints = {}
	self._currentWaypointIndex = 0
	return false
end

function NPCPathfinder:_traverseWaypoints(): boolean
	self._lastProgressPosition = self._rootPart.Position
	self._lastProgressTime = tick()

	for i = self._currentWaypointIndex, #self._waypoints do
		if not self._isMoving or self._isDestroyed then
			return false
		end

		self._currentWaypointIndex = i
		local waypoint = self._waypoints[i]

		-- Handle custom waypoints (PathfindingLinks)
		if waypoint.Action == Enum.PathWaypointAction.Custom then
			self:_handleCustomWaypoint(waypoint)
			continue
		end

		-- Move to waypoint
		self._humanoid:MoveTo(waypoint.Position)

		-- Handle jump
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self._humanoid.Jump = true
		end

		-- Wait for arrival with timeout
		local arrived = self:_waitForMoveComplete(waypoint.Position)

		if not arrived then
			-- Stuck at this waypoint — abort traversal
			return false
		end

		-- Stuck detection (overall progress)
		local moved = (self._rootPart.Position - self._lastProgressPosition).Magnitude
		if moved >= self._config.StuckDistanceThreshold then
			self._lastProgressPosition = self._rootPart.Position
			self._lastProgressTime = tick()
		elseif tick() - self._lastProgressTime > self._config.StuckTimeout then
			warn("[NPCPathfinder] NPC appears stuck. Aborting traversal.")
			return false
		end
	end

	return true  -- All waypoints reached
end

function NPCPathfinder:_traverseWaypointsNonBlocking(duration: number)
	-- Traverse as many waypoints as possible within the given duration
	-- Used by followTarget to avoid blocking the recompute loop
	local startTime = tick()

	for i = self._currentWaypointIndex, #self._waypoints do
		if not self._isMoving or self._isDestroyed then break end
		if tick() - startTime > duration * 0.8 then break end  -- leave time for recompute

		self._currentWaypointIndex = i
		local waypoint = self._waypoints[i]

		if waypoint.Action == Enum.PathWaypointAction.Custom then
			self:_handleCustomWaypoint(waypoint)
			continue
		end

		self._humanoid:MoveTo(waypoint.Position)

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self._humanoid.Jump = true
		end

		-- Brief wait for movement
		local waitStart = tick()
		repeat
			task.wait(0.1)
			local dist = (self._rootPart.Position - waypoint.Position).Magnitude
		until dist <= self._config.WaypointReachDistance
			or tick() - waitStart > 2
			or not self._isMoving
	end
end

function NPCPathfinder:_waitForMoveComplete(targetPosition: Vector3): boolean
	local startTime = tick()

	repeat
		local reached = self._humanoid.MoveToFinished:Wait()

		-- MoveToFinished passes a boolean: true if NPC arrived, false if the
		-- engine's hard 8-second timeout fired. Check it first.
		if reached then
			return true
		end

		-- reached == false means the 8s timeout fired. Check if we're close
		-- enough anyway (can happen with tight waypoint spacing).
		local distance = (self._rootPart.Position - targetPosition).Magnitude
		if distance <= self._config.WaypointReachDistance then
			return true
		end

		-- Not close enough and timed out — give up if we've exceeded our own timeout
		if tick() - startTime > self._config.MoveToTimeout then
			return false
		end

		-- Retry MoveTo if still active
		if self._isMoving then
			self._humanoid:MoveTo(targetPosition)
		end
	until not self._isMoving or self._isDestroyed

	return false
end

function NPCPathfinder:_directMoveTo(targetPosition: Vector3): boolean
	self._humanoid:MoveTo(targetPosition)
	local result = self._humanoid.MoveToFinished:Wait()
	return result
end

function NPCPathfinder:_hasLineOfSight(targetPosition: Vector3): boolean
	local origin = self._rootPart.Position
	local direction = targetPosition - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self._model }

	local result = workspace:Raycast(origin, direction, params)
	return result == nil
end

function NPCPathfinder:_onPathBlocked(blockedWaypointIndex: number)
	-- Only care if the blockage is ahead of us
	if blockedWaypointIndex >= self._currentWaypointIndex and self._isMoving then
		-- Recompute on next update cycle — don't compute inside the event handler
		task.defer(function()
			if self._isMoving and not self._isDestroyed and #self._waypoints > 0 then
				local lastWaypoint = self._waypoints[#self._waypoints]
				self:_computePath(lastWaypoint.Position)
			end
		end)
	end
end

function NPCPathfinder:_handleCustomWaypoint(waypoint)
	-- Override this method in subclasses for custom PathfindingLink handling.
	-- Default: just move to the waypoint position.
	--
	-- Example override:
	-- function MyPathfinder:_handleCustomWaypoint(waypoint)
	--     if waypoint.Label == "BoatRide" then
	--         self:_rideBoat(waypoint)
	--     elseif waypoint.Label == "Teleporter" then
	--         self._model:PivotTo(CFrame.new(waypoint.Position))
	--     else
	--         self._humanoid:MoveTo(waypoint.Position)
	--         self._humanoid.MoveToFinished:Wait()
	--     end
	-- end

	self._humanoid:MoveTo(waypoint.Position)
	self._humanoid.MoveToFinished:Wait()
end

return NPCPathfinder
