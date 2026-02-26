--!strict
--[[
	DebugVisuals - Debug visualization functions for NPC pathfinding system.

	Extracted from NPCManager to separate debug presentation concerns from
	NPC lifecycle orchestration. All functions are gated by GameConfig.GAME.DEBUG.

	Owns: state labels, detection radius discs, visual toggling, per-frame
	debug updates (LOS countdown annotation, disc position following), cleanup.

	Does NOT own: behavior-created visuals (waypoint markers, wander beams) —
	those are created by behavior state modules and toggled here via shared
	NPCEntry fields.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)

local log = Logger.new("DebugVisuals")

local DebugVisuals = {}

-- ═══════════════════════════════════════════════════════════
-- STATE LABELS
-- ═══════════════════════════════════════════════════════════

--- Creates a BillboardGui + TextLabel above the NPC's Head for state display.
--- Returns nil if DEBUG is off or model has no Head.
function DebugVisuals.createStateLabel(model: Model): TextLabel?
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

--- Returns a callback that updates a state label's text/color and optionally
--- fires a debug state callback. Uses a GETTER function for the callback because
--- debugStateCallback is nil at NPC spawn time — DebugService sets it later
--- (init order: NPCManager.initialize → DebugService.initialize).
--- Both this callback and updateTick write to stateLabel.Text — updateTick
--- overwrites during LOS countdown (intentional, PostSim wins same frame).
function DebugVisuals.makeStateLabelUpdater(
	npcName: string,
	stateLabel: TextLabel?,
	getDebugCallback: ((
	) -> ((npcName: string, newState: string, previousState: string?) -> ())?)?
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
		if getDebugCallback then
			local callback = getDebugCallback()
			if callback then
				callback(npcName, newState, _previousState)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- DETECTION RADIUS DISC
-- ═══════════════════════════════════════════════════════════

--- Creates an anchored flat cylinder at ground level representing detection radius.
--- Returns nil if DEBUG is off or model has no PrimaryPart.
function DebugVisuals.createDetectionRadiusCircle(model: Model, radius: number, color: Color3): Part?
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
	-- Lay flat at ground level. Anchored + explicit CFrame update in updateTick.
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
-- VISUAL TOGGLING
-- ═══════════════════════════════════════════════════════════

--- Toggle visibility of a specific debug visual type on an NPC entry.
--- Entry is the NPCEntry table from NPCManager (typed as any to avoid circular dep).
function DebugVisuals.setVisualEnabled(entry: any, visualType: string, enabled: boolean): ()
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
		log:warn(`setVisualEnabled: unknown visualType "{visualType}"`)
	end
end

-- ═══════════════════════════════════════════════════════════
-- PER-FRAME UPDATES
-- ═══════════════════════════════════════════════════════════

--- Per-frame debug visual updates: LOS countdown annotation on state labels
--- and detection disc position following NPC movement.
--- Called from NPCManager's PostSimulation tick for each NPC entry.
function DebugVisuals.updateTick(entry: any): ()
	-- Annotate state label during LOS memory countdown
	if entry.stateLabel and entry.losLostTimer then
		local memoryConfig: number? = entry.behaviorConfig and entry.behaviorConfig.LOS_MEMORY
		if memoryConfig then
			local remaining = math.max(0, memoryConfig - entry.losLostTimer)
			entry.stateLabel.Text = string.format("Chasing (%.1fs)", remaining)
			entry.stateLabel.TextColor3 = GameConfig.NPC.STATE_LABEL.COLORS.Returning
				or GameConfig.NPC.STATE_LABEL.DEFAULT_COLOR
		end
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

-- ═══════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════

--- Destroys debug instances (debugFolder, debugDisc) on an NPC entry.
function DebugVisuals.cleanupEntry(entry: any): ()
	if entry.debugFolder then
		entry.debugFolder:Destroy()
	end
	if entry.debugDisc then
		entry.debugDisc:Destroy()
	end
end

return DebugVisuals
