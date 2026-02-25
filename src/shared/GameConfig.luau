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

-- Map geometry
GameConfig.MAP = table.freeze({
	OBSTACLES = table.freeze({
		-- Center wall: forces Chase NPC to path around when pursuing players
		table.freeze({
			name = "CenterWall",
			position = Vector3.new(0, 4, 0),
			size = Vector3.new(20, 8, 2),
			color = Color3.fromRGB(86, 91, 99),
		}),
		-- Patrol south leg: crosses Z=-20 path between waypoints 1→2
		table.freeze({
			name = "PatrolSouthWall",
			position = Vector3.new(-40, 3, -20),
			size = Vector3.new(2, 6, 10),
			color = Color3.fromRGB(108, 113, 120),
		}),
		-- Patrol west leg: crosses X=-50 path between waypoints 2→3
		table.freeze({
			name = "PatrolWestWall",
			position = Vector3.new(-50, 3, 0),
			size = Vector3.new(10, 6, 2),
			color = Color3.fromRGB(100, 105, 112),
		}),
		-- Patrol north leg: crosses Z=20 path between waypoints 3→4
		table.freeze({
			name = "PatrolNorthWall",
			position = Vector3.new(-42, 3, 20),
			size = Vector3.new(2, 6, 10),
			color = Color3.fromRGB(108, 113, 120),
		}),
		-- L-barrier horizontal segment: corner obstacle near Chase spawn
		table.freeze({
			name = "LBarrierH",
			position = Vector3.new(15, 3, -15),
			size = Vector3.new(10, 6, 2),
			color = Color3.fromRGB(72, 77, 84),
		}),
		-- L-barrier vertical segment: completes the corner
		table.freeze({
			name = "LBarrierV",
			position = Vector3.new(21, 3, -10),
			size = Vector3.new(2, 6, 10),
			color = Color3.fromRGB(72, 77, 84),
		}),
		-- Wander zone obstacles (center: 0, -30, radius: 25)
		table.freeze({
			name = "WanderBlock1",
			position = Vector3.new(-8, 2, -25),
			size = Vector3.new(4, 4, 4),
			color = Color3.fromRGB(130, 135, 140),
		}),
		table.freeze({
			name = "WanderBlock2",
			position = Vector3.new(5, 2, -35),
			size = Vector3.new(4, 4, 4),
			color = Color3.fromRGB(120, 125, 130),
		}),
		table.freeze({
			name = "WanderBlock3",
			position = Vector3.new(-3, 2, -40),
			size = Vector3.new(4, 4, 4),
			color = Color3.fromRGB(140, 145, 150),
		}),
		table.freeze({
			name = "WanderWall1",
			position = Vector3.new(10, 3, -28),
			size = Vector3.new(2, 6, 8),
			color = Color3.fromRGB(115, 120, 128),
		}),
		table.freeze({
			name = "WanderBlock4",
			position = Vector3.new(-12, 2, -34),
			size = Vector3.new(5, 4, 3),
			color = Color3.fromRGB(125, 130, 135),
		}),
		table.freeze({
			name = "WanderWall2",
			position = Vector3.new(0, 3, -18),
			size = Vector3.new(8, 6, 2),
			color = Color3.fromRGB(105, 110, 118),
		}),
		table.freeze({
			name = "WanderBlock5",
			position = Vector3.new(-15, 2, -22),
			size = Vector3.new(3, 4, 5),
			color = Color3.fromRGB(135, 140, 145),
		}),
		table.freeze({
			name = "WanderBlock6",
			position = Vector3.new(8, 2, -44),
			size = Vector3.new(4, 4, 4),
			color = Color3.fromRGB(118, 123, 130),
		}),
		-- Guard zone walls — create LOS-breaking corridors between patrol waypoints
		table.freeze({
			name = "GuardWall1",
			position = Vector3.new(5, 3, 35),
			size = Vector3.new(2, 6, 10),
			color = Color3.fromRGB(95, 100, 107),
		}),
		table.freeze({
			name = "GuardWall2",
			position = Vector3.new(-5, 3, 35),
			size = Vector3.new(2, 6, 10),
			color = Color3.fromRGB(95, 100, 107),
		}),
		-- Staircase near chase spawn — tests NPC elevation pathfinding
		table.freeze({
			name = "ChaseStairs",
			type = "staircase",
			position = Vector3.new(45, 0, 10),
			size = Vector3.zero, -- unused for staircases; satisfies array type inference
			steps = 8,
			stepSize = Vector3.new(6, 1, 2),
			color = Color3.fromRGB(90, 95, 102),
		}),
	}),
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
		GUARD = Vector3.new(0, 5, 30),
	}),

	-- Chase NPC: pursues nearest player
	CHASE = table.freeze({
		DISPLAY_NAME = "Chase NPC",
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

	-- Guard NPC: random patrol with LOS-triggered chase
	GUARD = table.freeze({
		DISPLAY_NAME = "Guard NPC",
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
		DISPLAY_NAME = "Wander NPC",
		CENTER = Vector3.new(0, 5, -30),
		RADIUS = 25,
		PAUSE_MIN = 1,
		PAUSE_MAX = 3,
	}),

	-- Debug state labels above NPC heads (gated by GAME.DEBUG)
	STATE_LABEL = table.freeze({
		SIZE = UDim2.fromOffset(200, 30),
		STUDS_OFFSET = Vector3.new(0, 4.5, 0),
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
