--!strict
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
			CollisionGroup = "NPCs",
			DisableUnusedStates = true,
		})

		pf:moveTo(targetPosition)
		pf:followTarget(playerCharacter, { recomputeInterval = 0.5 })
		pf:patrol(waypointList, { loopMode = "loop", waitTime = 2 })
		pf:stop()
		pf:destroy()

	Adapted from roblox-npc-pathfinding skill asset.
	Handles: Path computation, waypoint traversal, jump/climb, blocked paths,
	         stuck detection, NPC collision groups, Humanoid optimization, connection cleanup.
]]

local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Logger = require(ReplicatedStorage:WaitForChild("Shared").Logger)
local log = Logger.new("NPCPathfinder")

local NPCPathfinder = {}
NPCPathfinder.__index = NPCPathfinder

-- Template part for waypoint visualization (cloned per waypoint)
local waypointTemplate = Instance.new("Part")
waypointTemplate.Size = Vector3.new(0.6, 0.6, 0.6)
waypointTemplate.Shape = Enum.PartType.Ball
waypointTemplate.Anchored = true
waypointTemplate.CanCollide = false
waypointTemplate.CanTouch = false
waypointTemplate.CanQuery = false
waypointTemplate.Material = Enum.Material.Neon
waypointTemplate.Transparency = 0.3

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
	RecomputeInterval = 1.0,
	StuckTimeout = 8.0,
	StuckDistanceThreshold = 1.5,
	WaypointReachDistance = 3.0,
	MoveToTimeout = 8.0,
	DirectMoveDistance = 12.0,

	-- Physics and performance
	CollisionGroup = "NPCs",
	DisableUnusedStates = true,
}

function NPCPathfinder.new(npcModel: Model, config: { [string]: any }?)
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
	self._lastArrivalTime = nil :: number?
	self._visualWaypoints = {} :: { Part }
	self._visualizeEnabled = false
	self._visualizeOverride = nil :: boolean? -- debug panel override (nil = use default)

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

function NPCPathfinder:moveTo(targetPosition: Vector3): boolean
	if self._isDestroyed then
		return false
	end

	-- Lightweight reset: clear waypoints without cancelling orchestrating threads
	-- (patrol/follow) and without issuing a stale MoveTo that poisons MoveToFinished.
	self:_resetMovement()

	-- Check if close enough for direct movement
	local distance = (targetPosition - self._rootPart.Position).Magnitude
	if distance <= self._config.DirectMoveDistance and self:hasLineOfSight(targetPosition) then
		local reached = self:_directMoveTo(targetPosition)
		self._isMoving = false
		return reached
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

function NPCPathfinder:followTarget(target: Model, options: { [string]: any }?)
	if self._isDestroyed then
		return
	end

	options = options or {}
	local recomputeInterval = options.recomputeInterval or self._config.RecomputeInterval
	local arrivalDistance = options.arrivalDistance or 5
	local onArrival = options.onArrival
	local onTargetLost = options.onTargetLost
	-- Debug panel override wins over behavior default
	if self._visualizeOverride ~= nil then
		self._visualizeEnabled = self._visualizeOverride
	else
		self._visualizeEnabled = options.visualize or false
	end
	local tickRate = 0.1
	local stuckCheckInterval = 2.0

	self:stop()
	self._isMoving = true

	local lastZoneLogTime = 0

	-- Event-driven waypoint advancement: MoveToFinished advances the index
	-- and issues the next MoveTo, so the NPC never pauses between waypoints.
	local moveConnection = self._humanoid.MoveToFinished:Connect(function(reached)
		if not self._isMoving or self._isDestroyed then
			return
		end
		-- Only advance during pathfinding (not arrival/direct chase which issue their own MoveTo)
		if #self._waypoints == 0 or self._currentWaypointIndex < 1 then
			return
		end
		if reached and self._currentWaypointIndex < #self._waypoints then
			self._currentWaypointIndex += 1
			local nextWaypoint = self._waypoints[self._currentWaypointIndex]
			if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
				self._humanoid.Jump = true
			end
			if nextWaypoint.Action == Enum.PathWaypointAction.Custom then
				self:_handleCustomWaypoint(nextWaypoint)
			else
				self._humanoid:MoveTo(nextWaypoint.Position)
			end
		end
	end)

	self._followThread = task.spawn(function()
		-- Start at recomputeInterval to force immediate first path computation
		local timeSinceRecompute = recomputeInterval

		-- Stuck detection state
		self._lastProgressPosition = self._rootPart.Position
		self._lastProgressTime = tick()

		while self._isMoving and not self._isDestroyed do
			-- Validate target
			local targetRoot = target and target:FindFirstChild("HumanoidRootPart") or target and target.PrimaryPart
			if not targetRoot then
				if onTargetLost then
					onTargetLost()
				end
				break
			end

			local targetPos = targetRoot.Position
			local distance = (targetPos - self._rootPart.Position).Magnitude

			-- ARRIVAL: keep moving toward target instead of stopping dead
			if distance <= arrivalDistance then
				self._humanoid:MoveTo(targetPos)
				do
					local now = tick()
					if now - lastZoneLogTime >= 2.0 then
						lastZoneLogTime = now
						log:debug(`followTarget zone=Arrival dist={math.floor(distance)}`)
					end
				end
				if onArrival then
					local now = tick()
					if not self._lastArrivalTime or now - self._lastArrivalTime >= 0.5 then
						self._lastArrivalTime = now
						onArrival(target)
					end
				end
				-- Recompute immediately when target moves out of arrival range
				timeSinceRecompute = recomputeInterval
				-- Reset stuck tracking (arrival is intentional non-progress)
				self._lastProgressPosition = self._rootPart.Position
				self._lastProgressTime = tick()
				task.wait(tickRate)
				continue
			end

			-- DIRECT CHASE: close + line of sight, skip pathfinding entirely
			if distance <= self._config.DirectMoveDistance and self:hasLineOfSight(targetPos) then
				self._humanoid:MoveTo(targetPos)
				do
					local now = tick()
					if now - lastZoneLogTime >= 2.0 then
						lastZoneLogTime = now
						log:debug(`followTarget zone=DirectChase dist={math.floor(distance)}`)
					end
				end
				-- Clear stale waypoints so we recompute fresh when LoS breaks
				self._waypoints = {}
				self._currentWaypointIndex = 0
				timeSinceRecompute = 0
				-- Reset stuck tracking (direct chase = different movement mode)
				self._lastProgressPosition = self._rootPart.Position
				self._lastProgressTime = tick()
				task.wait(tickRate)
				continue
			end

			-- PATHFINDING: recompute on timer, event-driven waypoint advancement
			timeSinceRecompute += tickRate
			if timeSinceRecompute >= recomputeInterval then
				timeSinceRecompute = 0
				local pathFound = self:_computePath(targetPos)
				if pathFound and self._visualizeEnabled then
					self:_createVisualWaypoints()
				end
			end

			-- Issue MoveTo for current waypoint (MoveToFinished handles advancement)
			if
				#self._waypoints > 0
				and self._currentWaypointIndex >= 1
				and self._currentWaypointIndex <= #self._waypoints
			then
				local waypoint = self._waypoints[self._currentWaypointIndex]

				if waypoint.Action == Enum.PathWaypointAction.Jump then
					self._humanoid.Jump = true
				end

				if waypoint.Action == Enum.PathWaypointAction.Custom then
					self:_handleCustomWaypoint(waypoint)
				else
					self._humanoid:MoveTo(waypoint.Position)
				end
			else
				-- No waypoints (path failed or pending) — best-effort direct move
				self._humanoid:MoveTo(targetPos)
			end

			do
				local now = tick()
				if now - lastZoneLogTime >= 2.0 then
					lastZoneLogTime = now
					log:debug(`followTarget zone=Pathfinding dist={math.floor(distance)} waypoints={#self._waypoints}`)
				end
			end

			-- Stuck detection: if no progress for stuckCheckInterval, jump + recompute
			local moved = (self._rootPart.Position - self._lastProgressPosition).Magnitude
			if moved >= self._config.StuckDistanceThreshold then
				self._lastProgressPosition = self._rootPart.Position
				self._lastProgressTime = tick()
			elseif tick() - self._lastProgressTime > stuckCheckInterval then
				log:debug("Chase NPC stuck — jumping and recomputing path")
				self._humanoid.Jump = true
				self:_computePath(targetPos)
				if self._visualizeEnabled then
					self:_createVisualWaypoints()
				end
				self._lastProgressPosition = self._rootPart.Position
				self._lastProgressTime = tick()
			end

			task.wait(tickRate)

			-- Model may have been destroyed during the wait
			if not self._rootPart or not self._model or not self._model:IsDescendantOf(game) then
				break
			end
		end

		-- Cleanup: disconnect event, destroy visuals
		if moveConnection then
			moveConnection:Disconnect()
		end
		self:_destroyVisualWaypoints()
		self._isMoving = false
	end)
end

function NPCPathfinder:patrol(waypoints: { any }, options: { [string]: any }?)
	if self._isDestroyed then
		return
	end
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
		-- Loop until destroyed. Thread cancellation (via stop()) is the exit mechanism,
		-- not _isMoving — moveTo resets _isMoving internally during traversal.
		while not self._isDestroyed do
			local wp = waypoints[index]
			local pos = if typeof(wp) == "Vector3"
				then wp
				elseif typeof(wp) == "Instance" and wp:IsA("BasePart") then wp.Position
				else error("Patrol waypoint must be Vector3 or BasePart")

			self._isMoving = true
			local reached = self:moveTo(pos)

			if self._isDestroyed then
				break
			end

			if reached and onWaypoint then
				onWaypoint(index, wp)
			end

			if reached and waitTime > 0 then
				task.wait(waitTime)
			end

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

function NPCPathfinder:stop()
	self._isMoving = false
	self._waypoints = {}
	self._currentWaypointIndex = 0
	self._lastArrivalTime = nil
	self:_destroyVisualWaypoints()

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

function NPCPathfinder:isMoving(): boolean
	return self._isMoving
end

--- Toggle chase path dot visualization at runtime (used by debug panel).
--- Sets a persistent override that survives followTarget restarts.
--- When disabled, immediately destroys existing dots and suppresses future creation.
--- When re-enabled, dots appear on the next path recomputation.
function NPCPathfinder:setVisualizeEnabled(enabled: boolean): ()
	self._visualizeOverride = enabled
	self._visualizeEnabled = enabled
	if not enabled then
		self:_destroyVisualWaypoints()
	end
end

function NPCPathfinder:getConfig(): { [string]: any }
	return table.clone(self._config)
end

function NPCPathfinder:setConfig(key: string, value: any)
	self._config[key] = value

	-- If agent params changed, recreate the Path object
	local agentParams = {
		"AgentRadius",
		"AgentHeight",
		"AgentCanJump",
		"AgentCanClimb",
		"WaypointSpacing",
		"Costs",
		"SupportPartialPath",
	}
	if table.find(agentParams, key) then
		self:_recreatePath()
	end
end

function NPCPathfinder:destroy()
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true

	self:stop()

	-- Disconnect all events
	for _, connection in self._connections do
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

-- Lightweight movement reset for use within moveTo. Unlike stop(), this does NOT:
--   1. Cancel _followThread or _patrolThread (avoids self-cancellation)
--   2. Issue MoveTo(currentPosition) (avoids stale MoveToFinished signals)
function NPCPathfinder:_resetMovement()
	self._waypoints = {}
	self._currentWaypointIndex = 0
	self._isMoving = true
end

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
	-- Keep FallingDown, GettingUp, Freefall, Landed enabled — NPCs need the
	-- physics recovery cycle when colliding with obstacle geometry.
	local unusedStates = {
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Flying,
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
	-- Skip recompute while airborne — start position is unreliable mid-air
	if self._humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		return #self._waypoints > 0
	end

	-- Throttle recomputation
	local now = tick()
	if now - self._lastComputeTime < self._config.RecomputeInterval * 0.5 then
		return #self._waypoints > 0
	end

	local success, errorMessage = pcall(function()
		self._path:ComputeAsync(self._rootPart.Position, targetPosition)
	end)

	if not success then
		log:warn(`ComputeAsync error: {errorMessage}`)
		return false
	end

	self._lastComputeTime = now

	if self._path.Status == Enum.PathStatus.Success or self._path.Status == Enum.PathStatus.ClosestNoPath then
		self._waypoints = self._path:GetWaypoints()
		-- Skip waypoint 1 (start position) — it's always at the NPC's current XZ,
		-- and the Y mismatch (navmesh vs HumanoidRootPart hip height) causes
		-- distance checks to get stuck.
		self._currentWaypointIndex = if #self._waypoints >= 2 then 2 else 1
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
			return false
		end

		-- Stuck detection (overall progress)
		local moved = (self._rootPart.Position - self._lastProgressPosition).Magnitude
		if moved >= self._config.StuckDistanceThreshold then
			self._lastProgressPosition = self._rootPart.Position
			self._lastProgressTime = tick()
		elseif tick() - self._lastProgressTime > self._config.StuckTimeout then
			log:warn("NPC appears stuck. Aborting traversal.")
			return false
		end
	end

	return true
end

function NPCPathfinder:_waitForMoveComplete(targetPosition: Vector3): boolean
	local startTime = tick()

	repeat
		local reached = self._humanoid.MoveToFinished:Wait()

		if reached then
			return true
		end

		local distance = (self._rootPart.Position - targetPosition).Magnitude
		if distance <= self._config.WaypointReachDistance then
			return true
		end

		if tick() - startTime > self._config.MoveToTimeout then
			return false
		end

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

function NPCPathfinder:_destroyVisualWaypoints()
	for _, part in self._visualWaypoints do
		part:Destroy()
	end
	table.clear(self._visualWaypoints)
end

function NPCPathfinder:_createVisualWaypoints()
	self:_destroyVisualWaypoints()
	for i, waypoint in self._waypoints do
		local marker = waypointTemplate:Clone()
		marker.Position = waypoint.Position
		-- Color coding: green=destination, red=jump, orange=normal
		if i == #self._waypoints then
			marker.Color = Color3.fromRGB(34, 197, 94) -- Green (destination)
		elseif waypoint.Action == Enum.PathWaypointAction.Jump then
			marker.Color = Color3.fromRGB(239, 68, 68) -- Red (jump)
		else
			marker.Color = Color3.fromRGB(255, 139, 0) -- Orange (normal)
		end
		marker.Parent = Workspace
		table.insert(self._visualWaypoints, marker)
	end
end

function NPCPathfinder:hasLineOfSight(targetPosition: Vector3, excludeModels: { Model }?): boolean
	local origin = self._rootPart.Position
	local direction = targetPosition - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions: { Instance } = { self._model }
	if excludeModels then
		for _, model in excludeModels do
			table.insert(exclusions, model)
		end
	end
	params.FilterDescendantsInstances = exclusions

	local result = Workspace:Raycast(origin, direction, params)
	return result == nil
end

function NPCPathfinder:_onPathBlocked(blockedWaypointIndex: number)
	if blockedWaypointIndex >= self._currentWaypointIndex and self._isMoving then
		-- Try jumping over the obstruction first (cheaper than full recompute)
		self._humanoid.Jump = true
		task.defer(function()
			if self._isMoving and not self._isDestroyed and #self._waypoints > 0 then
				local lastWaypoint = self._waypoints[#self._waypoints]
				self:_computePath(lastWaypoint.Position)
			end
		end)
	end
end

function NPCPathfinder:_handleCustomWaypoint(waypoint)
	self._humanoid:MoveTo(waypoint.Position)
	self._humanoid.MoveToFinished:Wait()
end

return NPCPathfinder
