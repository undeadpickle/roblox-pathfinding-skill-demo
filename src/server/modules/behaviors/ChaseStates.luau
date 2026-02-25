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
			return BehaviorHelpers.detectNearestPlayerInRange(ctx, GameConfig.NPC.CHASE, "chaseTarget", "Chasing")
		end,
	},

	Chasing = {
		onEnter = function(ctx: any)
			local target = ctx.chaseTarget
			if not target then
				return
			end

			local config = GameConfig.NPC.CHASE
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
			ctx.chaseReevalTimer = (ctx.chaseReevalTimer or 0) + dt
			if ctx.chaseReevalTimer < GameConfig.NPC.CHASE.REEVALUATE_INTERVAL then
				return nil
			end
			ctx.chaseReevalTimer = 0

			return BehaviorHelpers.evaluateChaseTarget(ctx, GameConfig.NPC.CHASE, "chaseTarget", "Idle", false)
		end,

		onExit = function(ctx: any)
			ctx.pathfinder:stop()
			ctx.chaseReevalTimer = nil
		end,
	},
}

return ChaseStates
