--!strict
--[[
	PatrolStates - State definitions for the Patrol NPC behavior.

	States: Patrolling (loops waypoints in sequence)
	Single state — extensible for future Alert/Chase states.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local NPCStateMachine = require(Shared.NPCStateMachine)

local BehaviorHelpers = require(script.Parent.BehaviorHelpers)

local log = Logger.new("PatrolStates")

local PATROL_COLOR = Color3.fromRGB(250, 204, 21) -- Yellow

local PatrolStates: NPCStateMachine.StateMap = {
	Patrolling = {
		onEnter = function(ctx: any)
			local config = GameConfig.NPC.PATROL

			if GameConfig.GAME.DEBUG and not ctx.debugFolder then
				ctx.debugFolder = BehaviorHelpers.createWaypointMarkers(config.WAYPOINTS, PATROL_COLOR, true)
			end

			ctx.pathfinder:patrol(config.WAYPOINTS, {
				loopMode = config.LOOP_MODE,
				waitTime = config.WAIT_TIME,
				onWaypoint = function(index: number)
					log:debug(`Patrol NPC: reached waypoint {index}`)
				end,
			})
			log:info("Patrol behavior started")
		end,

		onExit = function(ctx: any)
			ctx.pathfinder:stop()
		end,
	},
}

return PatrolStates
