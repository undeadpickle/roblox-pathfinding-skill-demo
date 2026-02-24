--!strict
--[[
	WanderStates - State definitions for the Wander NPC behavior.

	States: Wandering (roams randomly within a radius)
	Single state — extensible for future Flee/Curious states.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCStateMachine = require(Shared.NPCStateMachine)

local BehaviorHelpers = require(script.Parent.BehaviorHelpers)

local log = Logger.new("WanderStates")

local WANDER_COLOR = Color3.fromRGB(34, 197, 94) -- Green (Wandering state color)

local WanderStates: NPCStateMachine.StateMap = {
	Wandering = {
		onEnter = function(ctx: any)
			local config = GameConfig.NPC.WANDER

			-- Debug: beam from NPC to current wander target + marker sphere
			local targetMarker: Part? = nil
			local beamHidden = ctx._wanderBeamVisible == false -- respect debug panel toggle
			if GameConfig.GAME.DEBUG then
				local rootPart = ctx.model.PrimaryPart
				if rootPart then
					-- Attachment on NPC root (beam start)
					local npcAttachment = Instance.new("Attachment")
					npcAttachment.Parent = rootPart
					ctx.wanderNpcAttachment = npcAttachment

					-- Target marker sphere
					targetMarker = Instance.new("Part")
					targetMarker.Name = "WanderTargetMarker"
					targetMarker.Shape = Enum.PartType.Ball
					targetMarker.Size = Vector3.new(1, 1, 1)
					targetMarker.Anchored = true
					targetMarker.CanCollide = false
					targetMarker.CanTouch = false
					targetMarker.CanQuery = false
					targetMarker.CastShadow = false
					targetMarker.Material = Enum.Material.Neon
					targetMarker.Color = WANDER_COLOR
					targetMarker.Transparency = if beamHidden then 1 else 0.3
					targetMarker.Parent = Workspace
					ctx.wanderTargetMarker = targetMarker

					-- Attachment on target marker (beam end)
					local targetAttachment = Instance.new("Attachment")
					targetAttachment.Parent = targetMarker

					-- Beam connecting NPC to target
					local beam = Instance.new("Beam")
					beam.Attachment0 = npcAttachment
					beam.Attachment1 = targetAttachment
					beam.Width0 = 0.2
					beam.Width1 = 0.2
					beam.Color = ColorSequence.new(WANDER_COLOR)
					beam.Transparency = NumberSequence.new(if beamHidden then 1 else 0.5)
					beam.FaceCamera = true
					beam.Parent = npcAttachment
				end
			end

			ctx.wanderThread = task.spawn(function()
				while ctx.model and ctx.model:IsDescendantOf(game) do
					local target = BehaviorHelpers.getRandomPointInRadius(config.CENTER, config.RADIUS)

					-- Update debug marker position
					if targetMarker then
						targetMarker.Position = target
					end

					local reached = ctx.pathfinder:moveTo(target)

					if reached then
						log:debug("Wander NPC: reached point, pausing")
					end

					local pause = config.PAUSE_MIN + math.random() * (config.PAUSE_MAX - config.PAUSE_MIN)
					task.wait(pause)
				end
			end)
		end,

		onExit = function(ctx: any)
			if ctx.wanderThread then
				task.cancel(ctx.wanderThread)
				ctx.wanderThread = nil
			end
			-- Clean up debug visualization (beam destroyed with npcAttachment)
			if ctx.wanderNpcAttachment then
				ctx.wanderNpcAttachment:Destroy()
				ctx.wanderNpcAttachment = nil
			end
			if ctx.wanderTargetMarker then
				ctx.wanderTargetMarker:Destroy()
				ctx.wanderTargetMarker = nil
			end
			ctx.pathfinder:stop()
		end,
	},
}

return WanderStates
