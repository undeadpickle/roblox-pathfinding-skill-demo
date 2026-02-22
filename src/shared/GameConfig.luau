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

	-- Spawn positions on the default baseplate
	SPAWN_POSITIONS = table.freeze({
		CHASE = Vector3.new(30, 5, 0),
		PATROL = Vector3.new(-30, 5, 0),
		WANDER = Vector3.new(0, 5, -30),
	}),

	-- Chase NPC: pursues nearest player
	CHASE = table.freeze({
		DISPLAY_NAME = "Chase NPC",
		DETECTION_RADIUS = 50,
		RECOMPUTE_INTERVAL = 0.5,
		ARRIVAL_DISTANCE = 5,
		REEVALUATE_INTERVAL = 3,
	}),

	-- Patrol NPC: walks a rectangular route
	PATROL = table.freeze({
		DISPLAY_NAME = "Patrol NPC",
		WAIT_TIME = 2,
		LOOP_MODE = "loop",
		WAYPOINTS = table.freeze({
			Vector3.new(-30, 5, -20),
			Vector3.new(-50, 5, -20),
			Vector3.new(-50, 5, 20),
			Vector3.new(-30, 5, 20),
		}),
	}),

	-- Wander NPC: roams randomly within a radius
	WANDER = table.freeze({
		DISPLAY_NAME = "Wander NPC",
		CENTER = Vector3.new(0, 5, -30),
		RADIUS = 25,
		PAUSE_MIN = 1,
		PAUSE_MAX = 3,
	}),
})

return GameConfig
