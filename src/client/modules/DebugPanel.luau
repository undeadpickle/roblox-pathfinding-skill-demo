--!strict
--[[
	DebugPanel - Client-side debug panel for NPC pathfinding demo.

	Toggle: F9 key (or close button)
	Polls NPC status every 0.5s, listens for state change pushes.
	Sends visual toggle and teleport commands to server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DebugPanelUI = require(script.Parent.DebugPanelUI)
local DebugRemotes = require(Shared.DebugRemotes)
local GameConfig = require(Shared.GameConfig)
local Logger = require(Shared.Logger)
local Remotes = require(Shared.Remotes)

local log = Logger.new("DebugPanel")

local player = Players.LocalPlayer

-- State label colors (reused from GameConfig for consistent coloring)
local STATE_COLORS = GameConfig.NPC.STATE_LABEL.COLORS
local STATE_DEFAULT_COLOR = GameConfig.NPC.STATE_LABEL.DEFAULT_COLOR

-- NPC display order and config
local NPC_ORDER = {
	{ key = "CHASE", displayName = GameConfig.NPC.CHASE.DISPLAY_NAME, behaviorType = "chase" },
	{ key = "PATROL", displayName = GameConfig.NPC.PATROL.DISPLAY_NAME, behaviorType = "patrol" },
	{ key = "WANDER", displayName = GameConfig.NPC.WANDER.DISPLAY_NAME, behaviorType = "wander" },
	{ key = "GUARD", displayName = GameConfig.NPC.GUARD.DISPLAY_NAME, behaviorType = "guard" },
}

-- Toggle key (F9 conflicts with Roblox Developer Console — using F8 instead)
local TOGGLE_KEY = Enum.KeyCode.F8

local DebugPanel = {}

-- UI references (populated during initialize)
local screenGui: ScreenGui? = nil
local statusLabels: { [string]: { state: TextLabel, metrics: TextLabel } } = {}
local isPolling = false

--- Format metrics line for a given NPC status entry.
local function formatMetrics(data: { [string]: any }): string
	local parts = {}
	table.insert(parts, `Dist: {data.distanceToPlayer}`)

	if data.hasLOS ~= nil then
		table.insert(parts, `LOS: {if data.hasLOS then "Yes" else "No"}`)
	end

	table.insert(parts, `Moving: {if data.isMoving then "Yes" else "No"}`)

	return table.concat(parts, "  |  ")
end

--- Update status rows with fresh data from server.
local function updateStatusDisplay(statusData: { [string]: any }): ()
	for _, npcInfo in NPC_ORDER do
		local labels = statusLabels[npcInfo.displayName]
		if not labels then
			continue
		end

		local data = statusData[npcInfo.displayName]
		if data then
			local stateColor = STATE_COLORS[data.state] or STATE_DEFAULT_COLOR
			labels.state.Text = `{npcInfo.displayName}: {data.state}`
			labels.state.TextColor3 = stateColor
			labels.metrics.Text = formatMetrics(data)
		else
			labels.state.Text = `{npcInfo.displayName}: --`
			labels.state.TextColor3 = STATE_DEFAULT_COLOR
			labels.metrics.Text = "Not spawned"
		end
	end
end

--- Start polling loop for NPC status.
local function startPolling(): ()
	if isPolling then
		return
	end
	isPolling = true

	local statusFunc = Remotes.getFunction(DebugRemotes.GET_NPC_STATUS)

	task.spawn(function()
		while isPolling do
			local ok, result = pcall(function()
				return statusFunc:InvokeServer()
			end)

			if ok and result then
				updateStatusDisplay(result)
			elseif not ok then
				log:warn(`Status poll failed: {result}`)
			end

			task.wait(0.5)
		end
	end)
end

--- Stop polling loop.
local function stopPolling(): ()
	isPolling = false
end

--- Toggle panel visibility.
local function togglePanel(): ()
	local gui = screenGui
	if not gui then
		return
	end

	gui.Enabled = not gui.Enabled

	if gui.Enabled then
		startPolling()
		log:debug("Debug panel opened")
	else
		stopPolling()
		log:debug("Debug panel closed")
	end
end

function DebugPanel.initialize(): ()
	-- Build UI
	local gui, _panel = DebugPanelUI.createPanel()
	screenGui = gui

	local content = _panel:FindFirstChild("Content") :: ScrollingFrame

	-- Section 1: Visual Toggles
	local visualSection = DebugPanelUI.createSection("Visual Toggles", 1)

	local toggleEvent = Remotes.getEvent(DebugRemotes.TOGGLE_VISUAL)

	-- Each toggle fires a remote for ALL NPCs with that visual type
	local toggleDefs = {
		{ label = "Detection Discs", visualType = "disc", order = 1 },
		{ label = "State Labels", visualType = "stateLabel", order = 2 },
		{ label = "Waypoint Markers", visualType = "waypoints", order = 3 },
		{ label = "Wander Beam", visualType = "wanderBeam", order = 4 },
	}

	for _, def in toggleDefs do
		local row, _updateFn = DebugPanelUI.createToggleRow(def.label, true, def.order, function(enabled: boolean)
			-- Fire for all NPCs
			for _, npcInfo in NPC_ORDER do
				toggleEvent:FireServer(npcInfo.displayName, def.visualType, enabled)
			end
		end)
		row.Parent = visualSection
	end

	visualSection.Parent = content

	-- Section 2: NPC Status
	local statusSection = DebugPanelUI.createSection("NPC Status", 2)

	for i, npcInfo in NPC_ORDER do
		local row, stateLabel, metricsLabel = DebugPanelUI.createStatusRow(npcInfo.displayName, i)
		statusLabels[npcInfo.displayName] = {
			state = stateLabel,
			metrics = metricsLabel,
		}
		row.Parent = statusSection
	end

	statusSection.Parent = content

	-- Section 3: Teleport
	local teleportSection = DebugPanelUI.createSection("Teleport", 3)

	local teleportEvent = Remotes.getEvent(DebugRemotes.TELEPORT_TO_NPC)
	local teleportKeys = {}
	for _, npcInfo in NPC_ORDER do
		table.insert(teleportKeys, { key = npcInfo.key, label = npcInfo.key:sub(1, 1) .. npcInfo.key:sub(2):lower() })
	end

	local teleportGrid = DebugPanelUI.createTeleportGrid(teleportKeys, 1, function(key: string)
		teleportEvent:FireServer(key)
		log:debug(`Teleporting to {key} zone`)
	end)
	teleportGrid.Parent = teleportSection

	teleportSection.Parent = content

	-- Listen for state change pushes (instant updates between polls)
	local stateChangedEvent = Remotes.getEvent(DebugRemotes.NPC_STATE_CHANGED)
	stateChangedEvent.OnClientEvent:Connect(function(npcName: string, newState: string, _previousState: string?)
		local labels = statusLabels[npcName]
		if labels then
			local stateColor = STATE_COLORS[newState] or STATE_DEFAULT_COLOR
			labels.state.Text = `{npcName}: {newState}`
			labels.state.TextColor3 = stateColor
		end
	end)

	-- Close button
	local closeBtn = _panel:FindFirstChild("Header") :: Frame
	local closeBtnInst = closeBtn and closeBtn:FindFirstChild("CloseButton") :: TextButton
	if closeBtnInst then
		closeBtnInst.MouseButton1Click:Connect(togglePanel)
	end

	-- Toggle key binding
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			togglePanel()
		end
	end)

	-- Parent to PlayerGui
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui

	log:info(`Debug panel ready (toggle: {TOGGLE_KEY.Name})`)
end

return DebugPanel
