--!strict
--[[
	ChaseStates - State definitions for the Chase NPC behavior.

	States: Idle (scanning for players) -> Chasing (following target)
	Transitions back to Idle when target moves out of detection radius.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCStateMachine = require(Shared.NPCStateMachine)

local BehaviorHelpers = require(script.Parent.BehaviorHelpers)

local log = Logger.new("ChaseStates")

local ChaseStates: NPCStateMachine.StateMap = {
	Idle = {
		onEnter = function(ctx: any)
			ctx.pathfinder:stop()
		end,

		onUpdate = function(ctx: any, _dt: number): string?
			return BehaviorHelpers.detectNearestPlayerInRange(ctx, ctx.behaviorConfig, "activeTarget", "Chasing")
		end,
	},

	Chasing = {
		onEnter = function(ctx: any)
			local target = ctx.activeTarget
			if not target then
				return
			end

			local config = ctx.behaviorConfig
			ctx.pathfinder:followTarget(target, {
				recomputeInterval = config.RECOMPUTE_INTERVAL,
				arrivalDistance = config.ARRIVAL_DISTANCE,
				visualize = GameConfig.GAME.DEBUG,
				onTargetLost = function()
					log:debug("Chase NPC: target lost (callback)")
				end,
			})
		end,

		onUpdate = function(ctx: any, dt: number): string?
			-- Throttle re-evaluation (no need to check every frame)
			ctx.reevalTimer = (ctx.reevalTimer or 0) + dt
			if ctx.reevalTimer < ctx.behaviorConfig.REEVALUATE_INTERVAL then
				return nil
			end
			ctx.reevalTimer = 0

			return BehaviorHelpers.evaluateChaseTarget(ctx, ctx.behaviorConfig, "activeTarget", "Idle", false)
		end,

		onExit = function(ctx: any)
			ctx.pathfinder:stop()
			ctx.reevalTimer = nil
			ctx.losLostTimer = nil
		end,
	},
}

return ChaseStates
