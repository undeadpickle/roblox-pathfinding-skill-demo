--!strict
--[[
	NPCAnimator - Loads and drives humanoid animations for NPC models.

	Signal-driven: Humanoid.Running controls idle/walk/run transitions,
	Humanoid.StateChanged handles jump/fall. No coupling to behavior
	state machines or NPCPathfinder.

	Usage:
		local cleanup = NPCAnimator.setup(npcModel)
		-- Later:
		cleanup() -- stops tracks, disconnects signals
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)

local log = Logger.new("NPCAnimator")

local NPCAnimator = {}

--- Load an AnimationTrack from an asset ID onto an Animator.
--- Returns the track configured with priority and looping, or nil on failure.
local function loadTrack(
	animator: Animator,
	name: string,
	assetId: string,
	priority: Enum.AnimationPriority,
	looped: boolean,
	modelName: string
): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy() -- Animation instance not needed after loading

	if not ok or not track then
		log:warn(`Failed to load animation "{name}" for {modelName}`)
		return nil
	end

	track.Priority = priority
	track.Looped = looped
	return track
end

--- Set up animations for an NPC model.
--- Returns a cleanup function that stops all tracks and disconnects signals,
--- or nil if the model has no Humanoid.
function NPCAnimator.setup(model: Model): (() -> ())?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log:warn(`NPCAnimator.setup: no Humanoid in {model.Name}`)
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Throttle animation updates for distant NPCs
	animator.PreferLodEnabled = true

	local animConfig = GameConfig.NPC.ANIMATIONS
	local FADE_TIME = animConfig.FADE_TIME
	local RUN_THRESHOLD = animConfig.RUN_SPEED_THRESHOLD

	-- Load all tracks
	local idleTrack = loadTrack(animator, "idle", animConfig.IDLE, Enum.AnimationPriority.Idle, true, model.Name)
	local walkTrack = loadTrack(animator, "walk", animConfig.WALK, Enum.AnimationPriority.Movement, true, model.Name)
	local runTrack = loadTrack(animator, "run", animConfig.RUN, Enum.AnimationPriority.Movement, true, model.Name)
	local jumpTrack = loadTrack(animator, "jump", animConfig.JUMP, Enum.AnimationPriority.Action, false, model.Name)
	local fallTrack = loadTrack(animator, "fall", animConfig.FALL, Enum.AnimationPriority.Action, true, model.Name)

	local connections: { RBXScriptConnection } = {}
	local currentMovementAnim: string? = nil

	--- Cross-fade to a movement animation (idle/walk/run), stopping the previous one.
	local function playMovementAnim(name: string, track: AnimationTrack?): ()
		if not track or currentMovementAnim == name then
			return
		end
		-- Stop previous movement/idle track
		if currentMovementAnim == "idle" and idleTrack then
			idleTrack:Stop(FADE_TIME)
		elseif currentMovementAnim == "walk" and walkTrack then
			walkTrack:Stop(FADE_TIME)
		elseif currentMovementAnim == "run" and runTrack then
			runTrack:Stop(FADE_TIME)
		end
		track:Play(FADE_TIME)
		currentMovementAnim = name
	end

	-- Start with idle
	if idleTrack then
		idleTrack:Play(0)
		currentMovementAnim = "idle"
	end

	-- Running signal: speed > 0 = moving, speed ~= 0 = stopped
	table.insert(
		connections,
		humanoid.Running:Connect(function(speed: number)
			if speed < 0.1 then
				playMovementAnim("idle", idleTrack)
			elseif speed >= RUN_THRESHOLD then
				playMovementAnim("run", runTrack)
			else
				playMovementAnim("walk", walkTrack)
			end
		end)
	)

	-- StateChanged: jump and fall (action priority overrides movement anims)
	table.insert(
		connections,
		humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if new == Enum.HumanoidStateType.Jumping then
				if jumpTrack then
					jumpTrack:Play(FADE_TIME)
				end
			elseif new == Enum.HumanoidStateType.Freefall then
				if fallTrack then
					fallTrack:Play(FADE_TIME)
				end
			elseif new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics then
				-- Landing: stop action-priority tracks; Running signal handles movement
				if jumpTrack then
					jumpTrack:Stop(FADE_TIME)
				end
				if fallTrack then
					fallTrack:Stop(FADE_TIME)
				end
			end
		end)
	)

	log:debug(`Animations loaded for {model.Name}`)

	-- Return cleanup closure
	return function()
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)

		-- Stop and destroy all tracks
		local allTracks = { idleTrack, walkTrack, runTrack, jumpTrack, fallTrack }
		for _, track in allTracks do
			if track then
				track:Stop(0)
				track:Destroy()
			end
		end

		currentMovementAnim = nil
		log:debug(`Animations cleaned up for {model.Name}`)
	end
end

return NPCAnimator
