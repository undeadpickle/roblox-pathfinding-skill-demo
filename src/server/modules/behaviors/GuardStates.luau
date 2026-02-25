--!strict
--[[
	GuardStates - State definitions for the Guard NPC behavior.

	States: Guarding (random patrol) -> Chasing (LOS-triggered pursuit) -> Returning (back to post)
	Detection: distance + LOS raycast to initiate chase, distance-only to maintain chase
	(prevents LOS flicker at wall edges). Returns to nearest waypoint when target lost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCStateMachine = require(Shared.NPCStateMachine)

local BehaviorHelpers = require(script.Parent.BehaviorHelpers)

local log = Logger.new("GuardStates")

local GUARD_COLOR = Color3.fromRGB(255, 139, 0) -- Orange

local GuardStates: NPCStateMachine.StateMap = {
	Guarding = {
		onEnter = function(ctx: any)
			local config = GameConfig.NPC.GUARD

			if GameConfig.GAME.DEBUG and not ctx.debugFolder then
				ctx.debugFolder = BehaviorHelpers.createWaypointMarkers(config.WAYPOINTS, GUARD_COLOR, false)
			end

			local lastIndex = ctx.guardLastWaypointIndex or 0
			ctx.guardPatrolThread = task.spawn(function()
				while ctx.model and ctx.model:IsDescendantOf(game) do
					-- Pick random waypoint, excluding the last one visited
					local candidates = {}
					for i = 1, #config.WAYPOINTS do
						if i ~= lastIndex then
							table.insert(candidates, i)
						end
					end
					local nextIndex = candidates[math.random(1, #candidates)]
					lastIndex = nextIndex
					ctx.guardLastWaypointIndex = nextIndex

					log:debug(`Guard NPC: heading to waypoint {nextIndex}`)
					ctx.pathfinder:moveTo(config.WAYPOINTS[nextIndex])

					task.wait(config.PATROL_PAUSE)
				end
			end)
		end,

		onUpdate = function(ctx: any, dt: number): string?
			-- Throttle detection (no need to raycast every frame)
			ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
			if ctx.guardDetectTimer < GameConfig.NPC.GUARD.DETECT_INTERVAL then
				return nil
			end
			ctx.guardDetectTimer = 0

			return BehaviorHelpers.detectNearestPlayerInRange(ctx, GameConfig.NPC.GUARD, "guardTarget", "Chasing")
		end,

		onExit = function(ctx: any)
			if ctx.guardPatrolThread then
				task.cancel(ctx.guardPatrolThread)
				ctx.guardPatrolThread = nil
			end
			ctx.guardDetectTimer = nil
			ctx.pathfinder:stop()
		end,
	},

	Chasing = {
		onEnter = function(ctx: any)
			local target = ctx.guardTarget
			if not target then
				return
			end

			local config = GameConfig.NPC.GUARD
			ctx.pathfinder:followTarget(target, {
				recomputeInterval = config.RECOMPUTE_INTERVAL,
				arrivalDistance = config.ARRIVAL_DISTANCE,
				visualize = GameConfig.GAME.DEBUG,
				onTargetLost = function()
					log:debug("Guard NPC: target lost (callback)")
				end,
			})
		end,

		onUpdate = function(ctx: any, dt: number): string?
			-- Throttle re-evaluation
			ctx.guardReevalTimer = (ctx.guardReevalTimer or 0) + dt
			if ctx.guardReevalTimer < GameConfig.NPC.GUARD.REEVALUATE_INTERVAL then
				return nil
			end
			ctx.guardReevalTimer = 0

			-- Distance-only check to maintain chase (no LOS flicker at wall edges)
			-- LOS required to switch to a closer target
			return BehaviorHelpers.evaluateChaseTarget(ctx, GameConfig.NPC.GUARD, "guardTarget", "Returning", true)
		end,

		onExit = function(ctx: any)
			ctx.pathfinder:stop()
			ctx.guardReevalTimer = nil
		end,
	},

	Returning = {
		onEnter = function(ctx: any)
			ctx.guardReachedWaypoint = false

			local rootPart = ctx.model.PrimaryPart
			if not rootPart then
				ctx.guardReachedWaypoint = true
				return
			end

			-- Find nearest waypoint
			local waypoints = GameConfig.NPC.GUARD.WAYPOINTS
			local nearestIndex = 1
			local nearestDist = math.huge
			for i, wp in waypoints do
				local dist = (wp - rootPart.Position).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestIndex = i
				end
			end

			ctx.guardLastWaypointIndex = nearestIndex
			log:debug(`Guard NPC: returning to waypoint {nearestIndex}`)

			ctx.guardPatrolThread = task.spawn(function()
				ctx.pathfinder:moveTo(waypoints[nearestIndex])
				ctx.guardReachedWaypoint = true
			end)
		end,

		onUpdate = function(ctx: any, dt: number): string?
			if ctx.guardReachedWaypoint then
				-- Minimum dwell so "Returning" is observable in debug panel
				ctx.guardReturnDwell = (ctx.guardReturnDwell or 0) + dt
				if ctx.guardReturnDwell >= GameConfig.NPC.GUARD.RETURN_DWELL then
					return "Guarding"
				end
				return nil
			end

			-- Throttle detection during return (can interrupt to chase)
			ctx.guardDetectTimer = (ctx.guardDetectTimer or 0) + dt
			if ctx.guardDetectTimer < GameConfig.NPC.GUARD.DETECT_INTERVAL then
				return nil
			end
			ctx.guardDetectTimer = 0

			return BehaviorHelpers.detectNearestPlayerInRange(ctx, GameConfig.NPC.GUARD, "guardTarget", "Chasing")
		end,

		onExit = function(ctx: any)
			if ctx.guardPatrolThread then
				task.cancel(ctx.guardPatrolThread)
				ctx.guardPatrolThread = nil
			end
			ctx.guardDetectTimer = nil
			ctx.guardReachedWaypoint = nil
			ctx.guardReturnDwell = nil
			ctx.pathfinder:stop()
		end,
	},
}

return GuardStates
