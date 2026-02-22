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

--[[
	Registry Pattern Example:
	
	Use string attributes on instances to drive behavior.
	Set an attribute like "InteractionType" = "collect" on a Part,
	then look up the config here.
	
	Example usage in code:
		local config = GameConfig.getInteractionConfig(part:GetAttribute("InteractionType"))
		if config then
			-- use config.points, config.sound, etc.
		end
]]
GameConfig.INTERACTIONS = table.freeze({
	-- Example entries - customize for your game:
	-- button = table.freeze({ sound = "Click", cooldown = 0.5 }),
	-- portal = table.freeze({ destination = "Spawn" }),
})

--- Get interaction config by type name
function GameConfig.getInteractionConfig(typeName: string): { [string]: any }?
	return GameConfig.INTERACTIONS[typeName]
end

return GameConfig
