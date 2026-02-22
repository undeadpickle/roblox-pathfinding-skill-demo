--!strict
--[[
	Remotes: Helper module for RemoteEvent/RemoteFunction management.
	
	Centralizes remote creation and access. Define your event names as
	constants here, then use getEvent() or getFunction() to access them.
	
	Usage:
		-- Define event names
		Remotes.PLAYER_READY = "PlayerReady"
		
		-- Server: Connect
		Remotes.getEvent(Remotes.PLAYER_READY).OnServerEvent:Connect(handler)
		
		-- Client: Fire
		Remotes.getEvent(Remotes.PLAYER_READY):FireServer()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

-- Define your remote event names here:
-- Remotes.PLAYER_READY = "PlayerReady"
-- Remotes.DATA_LOADED = "DataLoaded"
-- Remotes.ACTION_REQUEST = "ActionRequest"

local remotesFolder: Folder? = nil

local function getRemotesFolder(): Folder
	local cached = remotesFolder
	if cached then
		return cached
	end

	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		remotesFolder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	remotesFolder = folder
	return folder
end

--- Get or create a RemoteEvent by name
function Remotes.getEvent(name: string): RemoteEvent
	local folder = getRemotesFolder()
	local event = folder:FindFirstChild(name)

	if event and event:IsA("RemoteEvent") then
		return event
	end

	local newEvent = Instance.new("RemoteEvent")
	newEvent.Name = name
	newEvent.Parent = folder
	return newEvent
end

--- Get or create a RemoteFunction by name
function Remotes.getFunction(name: string): RemoteFunction
	local folder = getRemotesFolder()
	local func = folder:FindFirstChild(name)

	if func and func:IsA("RemoteFunction") then
		return func
	end

	local newFunc = Instance.new("RemoteFunction")
	newFunc.Name = name
	newFunc.Parent = folder
	return newFunc
end

--[[
	OPTIONAL: Type-safe event handling with validation (server-side only)

	Usage:
		Remotes.onEvent("Purchase", function(player, data)
			-- data is validated, safe to use
			processPurchase(player, data.itemId, data.quantity)
		end, function(args)
			-- Validator: return typed data or nil to reject
			if typeof(args[1]) ~= "string" then return nil end
			if typeof(args[2]) ~= "number" then return nil end
			if args[2] < 1 or args[2] > 100 then return nil end -- sanity check
			return { itemId = args[1], quantity = args[2] }
		end)
]]

--- Connect to a RemoteEvent with validation (server-side)
--- Invalid requests are silently ignored to avoid giving exploiters feedback
function Remotes.onEvent<T>(name: string, handler: (player: Player, data: T) -> (), validator: (args: { any }) -> T?)
	local event = Remotes.getEvent(name)
	event.OnServerEvent:Connect(function(player, ...)
		local data = validator({ ... })
		if data == nil then
			return -- Invalid args, silently ignore
		end
		handler(player, data)
	end)
end

--- Connect to a RemoteFunction with validation (server-side)
--- Returns nil to client on validation failure
function Remotes.onInvoke<T, R>(name: string, handler: (player: Player, data: T) -> R, validator: (args: { any }) -> T?)
	local func = Remotes.getFunction(name)
	func.OnServerInvoke = function(player, ...): R?
		local data = validator({ ... })
		if data == nil then
			return nil -- Invalid args
		end
		return handler(player, data)
	end
end

return Remotes
