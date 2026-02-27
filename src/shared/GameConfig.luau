--!strict
--[[
	GameConfig: Centralized configuration for your game.

	Keep all tunable values here so they're easy to find and adjust.
	Use nested tables to organize by system/feature.

	Why table.freeze()?
	Config tables are frozen to prevent accidental mutation. If you
	later write `GameConfig.PLAYER.WALK_SPEED = 30`, you'll get an
	error instead of silently changing the value. This catches typos
	and unintended side effects early.
]]

local GameConfig = {}

-- Game metadata
GameConfig.GAME = table.freeze({
	NAME = "RobloxPathfindingSkillDemo",
	VERSION = "0.1.0",
	DEBUG = true, -- Set false for production
})

-- Player settings (customize per game)
GameConfig.PLAYER = table.freeze({
	WALK_SPEED = 16,
	JUMP_POWER = 50,
	-- Add game-specific player config here
})

-- UI theme colors
GameConfig.UI = table.freeze({
	COLORS = table.freeze({
		PRIMARY = Color3.fromRGB(59, 130, 246), -- Blue
		SECONDARY = Color3.fromRGB(100, 116, 139), -- Slate
		SUCCESS = Color3.fromRGB(34, 197, 94), -- Green
		WARNING = Color3.fromRGB(250, 204, 21), -- Yellow
		ERROR = Color3.fromRGB(239, 68, 68), -- Red
	}),
	FONTS = table.freeze({
		HEADING = Enum.Font.GothamBold,
		BODY = Enum.Font.Gotham,
	}),
})

-- Sound asset IDs (populate as needed)
GameConfig.SOUNDS = table.freeze({
	-- UI_CLICK = "rbxassetid://0",
	-- UI_HOVER = "rbxassetid://0",
})

-- NPC pathfinding configuration
GameConfig.NPC = table.freeze({
	COLLISION_GROUP = "NPCs",

	-- PathfindingService agent parameters (R15 humanoid)
	AGENT = table.freeze({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
	}),

	-- Chase NPC: pursues nearest player
	CHASE = table.freeze({
		WALK_SPEED = 4,
		DETECTION_RADIUS = 20,
		RECOMPUTE_INTERVAL = 0.5,
		ARRIVAL_DISTANCE = 5,
		REEVALUATE_INTERVAL = 3,
		REQUIRE_LOS = true, -- Walls block detection; set false to see through walls
		LOS_MEMORY = 3, -- Seconds to chase after losing sight (nil = omniscient)
	}),

	-- Patrol NPC: walks a rectangular route
	PATROL = table.freeze({
		WAIT_TIME = 2,
		LOOP_MODE = "loop",
		WAYPOINTS = table.freeze({
			Vector3.new(-30, 5, -20),
			Vector3.new(-50, 5, -20),
			Vector3.new(-50, 5, 20),
			Vector3.new(-30, 5, 20),
		}),
	}),

	-- Guard NPC: random patrol with LOS-triggered chase
	GUARD = table.freeze({
		WALK_SPEED = 10,
		DETECTION_RADIUS = 18,
		RECOMPUTE_INTERVAL = 0.5,
		ARRIVAL_DISTANCE = 5,
		REEVALUATE_INTERVAL = 1,
		DETECT_INTERVAL = 0.2,
		PATROL_PAUSE = 1.5,
		RETURN_DWELL = 0.8,
		REQUIRE_LOS = true, -- Walls block detection; set false to see through walls
		LOS_MEMORY = 5, -- Seconds to chase after losing sight (nil = omniscient); guards are more persistent
		WAYPOINTS = table.freeze({
			Vector3.new(10, 5, 25),
			Vector3.new(15, 5, 45),
			Vector3.new(0, 5, 50),
			Vector3.new(-15, 5, 45),
			Vector3.new(-10, 5, 25),
		}),
	}),

	-- Wander NPC: roams randomly within a radius
	WANDER = table.freeze({
		CENTER = Vector3.new(0, 5, -30),
		RADIUS = 25,
		PAUSE_MIN = 1,
		PAUSE_MAX = 3,
	}),

	-- Debug state labels above NPC heads (gated by GAME.DEBUG)
	STATE_LABEL = table.freeze({
		SIZE = UDim2.fromOffset(220, 56),
		STUDS_OFFSET = Vector3.new(0, 3.5, 0),
		TEXT_SIZE = 14,
		FONT = Enum.Font.GothamBold,
		STROKE_TRANSPARENCY = 0,
		COLORS = table.freeze({
			Idle = Color3.fromRGB(250, 204, 21), -- Yellow (passive)
			Chasing = Color3.fromRGB(239, 68, 68), -- Red (active pursuit)
			Patrolling = Color3.fromRGB(59, 130, 246), -- Blue (routine)
			Wandering = Color3.fromRGB(34, 197, 94), -- Green (exploratory)
			Guarding = Color3.fromRGB(255, 139, 0), -- Orange (guard patrol)
			Returning = Color3.fromRGB(0, 200, 255), -- Cyan (returning to post)
		}),
		DEFAULT_COLOR = Color3.fromRGB(200, 200, 200),
	}),
})

return GameConfig
