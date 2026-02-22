--!strict
--[[
	Logger: Simple logging utility with log levels.
	
	Automatically prefixes with [Server] or [Client] based on context.
	Use minLevel to filter logs in production.
	
	Usage:
		local log = Logger.new("MyModule")
		log:debug("Detailed info")  -- Only shows if minLevel <= DEBUG
		log:info("Normal info")
		log:warn("Something wrong")
		log:error("Something failed")
		
		-- Production (only warnings and errors)
		local log = Logger.new("MyModule", "WARN")
]]

local RunService = game:GetService("RunService")

local Logger = {}
Logger.__index = Logger

export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR"
export type Logger = typeof(setmetatable(
	{} :: {
		prefix: string,
		minLevel: number,
	},
	Logger
))

local IS_SERVER = RunService:IsServer()
local CONTEXT = IS_SERVER and "Server" or "Client"

local LEVELS = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
}

--- Create a logger for a specific module
function Logger.new(moduleName: string, minLevel: LogLevel?): Logger
	local self = setmetatable({}, Logger)
	self.prefix = `[{CONTEXT}][{moduleName}]`
	self.minLevel = LEVELS[minLevel or "DEBUG"] or 1
	return self
end

function Logger:debug(...: any): ()
	if self.minLevel <= LEVELS.DEBUG then
		print(self.prefix, "[DEBUG]", ...)
	end
end

function Logger:info(...: any): ()
	if self.minLevel <= LEVELS.INFO then
		print(self.prefix, ...)
	end
end

function Logger:warn(...: any): ()
	if self.minLevel <= LEVELS.WARN then
		warn(self.prefix, ...)
	end
end

function Logger:error(...: any): ()
	warn(self.prefix, "[ERROR]", ...)
end

return Logger
