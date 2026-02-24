--!strict
--[[
	BehaviorHelpers - Shared utility functions for NPC behavior state definitions.

	Extracted from NPCManager to keep behavior modules focused on state logic.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BehaviorHelpers = {}

-- ═══════════════════════════════════════════════════════════
-- PLAYER DETECTION
-- ═══════════════════════════════════════════════════════════

function BehaviorHelpers.findNearestPlayer(position: Vector3): Model?
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

-- ═══════════════════════════════════════════════════════════
-- RANDOM POINT GENERATION
-- ═══════════════════════════════════════════════════════════

local cachedObstacleFolder: Folder? = nil

local function getObstacleFolder(): Folder?
	if not cachedObstacleFolder then
		cachedObstacleFolder = Workspace:FindFirstChild("Obstacles") :: Folder?
	end
	return cachedObstacleFolder
end

function BehaviorHelpers.getRandomPointInRadius(center: Vector3, radius: number): Vector3
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
-- DEBUG WAYPOINT MARKERS
-- ═══════════════════════════════════════════════════════════

function BehaviorHelpers.createWaypointMarkers(waypoints: { Vector3 }, color: Color3, showLines: boolean): Folder
	local folder = Instance.new("Folder")
	folder.Name = "WaypointMarkers"

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
		marker.Color = color
		marker.Transparency = 0.5
		marker.CastShadow = false

		-- Number label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(40, 40)
		billboard.StudsOffset = Vector3.new(0, 2, 0)
		billboard.AlwaysOnTop = true

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = tostring(i)
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = billboard

		billboard.Parent = marker
		marker.Parent = folder

		-- Connecting lines between sequential waypoints
		if showLines then
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
			line.Color = color
			line.Transparency = 0.7
			line.Parent = folder
		end
	end

	folder.Parent = Workspace
	return folder
end

-- ═══════════════════════════════════════════════════════════
-- CHASE TARGET RE-EVALUATION
-- ═══════════════════════════════════════════════════════════

--- Evaluates whether the current chase target is still valid, and whether
--- a closer player should be targeted instead.
--- Returns: nextState (string?) — nil to stay in Chasing, "Idle"/"Returning" if target lost,
---          "Chasing" if switching to a closer target.
--- Also updates ctx[targetField] when switching or clearing targets.
function BehaviorHelpers.evaluateChaseTarget(
	ctx: any,
	config: { DETECTION_RADIUS: number, REEVALUATE_INTERVAL: number },
	targetField: string,
	lostState: string,
	requireLOS: boolean?
): string?
	local rootPart = ctx.model.PrimaryPart
	if not rootPart then
		return nil
	end

	-- Is current target still valid and in range?
	local currentTarget = ctx[targetField]
	local currentTargetValid = false

	if currentTarget and currentTarget:IsDescendantOf(game) then
		local targetRoot = currentTarget:FindFirstChild("HumanoidRootPart")
		if targetRoot then
			local distance = ((targetRoot :: BasePart).Position - rootPart.Position).Magnitude
			if distance <= config.DETECTION_RADIUS then
				currentTargetValid = true
			end
		end
	end

	if not currentTargetValid then
		ctx[targetField] = nil
		return lostState
	end

	-- Check if a closer player is now the better target
	local nearest = BehaviorHelpers.findNearestPlayer(rootPart.Position)
	if nearest and nearest ~= currentTarget then
		local nearestRoot = nearest:FindFirstChild("HumanoidRootPart")
		if nearestRoot then
			local dist = ((nearestRoot :: BasePart).Position - rootPart.Position).Magnitude
			if dist <= config.DETECTION_RADIUS then
				if requireLOS then
					if ctx.pathfinder:hasLineOfSight((nearestRoot :: BasePart).Position, { nearest }) then
						ctx[targetField] = nearest
						return "Chasing"
					end
				else
					ctx[targetField] = nearest
					return "Chasing"
				end
			end
		end
	end

	return nil
end

--- Clears the obstacle folder cache. Call during cleanup if map may reinitialize.
function BehaviorHelpers.clearCache(): ()
	cachedObstacleFolder = nil
end

return BehaviorHelpers
