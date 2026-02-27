--!strict
--[[
	DebugPanel - Client-side debug panel for NPC sandbox.

	Toggle: F8 key (or close button)
	Polls NPC status every 0.5s, listens for state change pushes.
	NPC list is server-driven — dynamically rebuilds when NPCs are added/removed.
	Sends spawn, despawn, visual toggle, teleport, and behavior swap commands to server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

-- Toggle key (F9 conflicts with Roblox Developer Console — using F8 instead)
local TOGGLE_KEY = Enum.KeyCode.F8

local DebugPanel = {}

-- Dynamic NPC list (populated from server status polls)
local knownNPCs: { { displayName: string, behaviorType: string } } = {}

-- UI references (populated during initialize)
local screenGui: ScreenGui? = nil
local contentFrame: ScrollingFrame? = nil
local statusLabels: { [string]: { state: TextLabel, metrics: TextLabel } } = {}
local isPolling = false

-- Section references for rebuild
local spawnSection: Frame? = nil
local statusSection: Frame? = nil
local teleportSection: Frame? = nil
local behaviorSection: Frame? = nil
local despawnSection: Frame? = nil
local behaviorUpdaters: { [string]: (newBehavior: string) -> () } = {}
local availableBehaviors: { string } = {}

-- Visual toggle state (persists across NPC list rebuilds)
local toggleDefs = {
	{ label = "Detection Discs", visualType = "disc", order = 2 },
	{ label = "State Labels", visualType = "stateLabel", order = 3 },
	{ label = "Chase Path Dots", visualType = "chasePath", order = 4 },
	{ label = "Waypoint Markers", visualType = "waypoints", order = 5 },
	{ label = "Waypoint Numbers", visualType = "waypointNumbers", order = 6 },
	{ label = "Name Labels", visualType = "nameLabel", order = 7 },
	{ label = "Wander Beam", visualType = "wanderBeam", order = 8 },
}
local visualToggleStates: { [string]: boolean } = {}
-- Initialize all toggles to on
for _, def in toggleDefs do
	visualToggleStates[def.visualType] = true
end

--- Format metrics line for a given NPC status entry.
local function formatMetrics(data: { [string]: any }): string
	local parts = {}
	table.insert(parts, `Dist: {data.distanceToPlayer}`)

	if data.hasLOS ~= nil then
		if data.losCountdown then
			table.insert(parts, `LOS: No ({data.losCountdown}s)`)
		else
			table.insert(parts, `LOS: {if data.hasLOS then "Yes" else "No"}`)
		end
	end

	table.insert(parts, `Moving: {if data.isMoving then "Yes" else "No"}`)

	return table.concat(parts, "  |  ")
end

-- ═══════════════════════════════════════════════════════════
-- DYNAMIC SECTION BUILDERS
-- ═══════════════════════════════════════════════════════════

--- Build the NPC status section from the current NPC list.
local function buildStatusSection(npcList: { { displayName: string, behaviorType: string } }): Frame
	local section = DebugPanelUI.createSection("NPC Status", 3)

	if #npcList == 0 then
		local emptyLabel = DebugPanelUI.createSubLabel("No NPCs spawned", 1)
		emptyLabel.Parent = section
		return section
	end

	for i, npcInfo in npcList do
		local row, stateLabel, metricsLabel = DebugPanelUI.createStatusRow(npcInfo.displayName, i)
		statusLabels[npcInfo.displayName] = {
			state = stateLabel,
			metrics = metricsLabel,
		}
		row.Parent = section
	end

	return section
end

--- Build the teleport section from the current NPC list.
local function buildTeleportSection(npcList: { { displayName: string, behaviorType: string } }): Frame
	local section = DebugPanelUI.createSection("Teleport", 4)

	if #npcList == 0 then
		local emptyLabel = DebugPanelUI.createSubLabel("No NPCs to teleport to", 1)
		emptyLabel.Parent = section
		return section
	end

	-- Build NPC key arrays (shared format for all grids)
	local npcKeys: { { key: string, label: string } } = {}
	for _, npc in npcList do
		table.insert(npcKeys, { key = npc.displayName, label = npc.displayName })
	end

	-- Subsection: To NPC (Current Pos)
	local goToLabel = DebugPanelUI.createSubLabel("To NPC (Current Pos)", 1)
	goToLabel.Parent = section

	local goToEvent = Remotes.getEvent(DebugRemotes.TELEPORT_TO_NPC_CURRENT)
	local goToGrid = DebugPanelUI.createTeleportGrid(npcKeys, 2, function(displayName: string)
		goToEvent:FireServer(displayName)
		log:debug(`Teleporting to {displayName} current pos`)
	end)
	goToGrid.Parent = section

	-- Subsection: Summon NPC to Me
	local summonLabel = DebugPanelUI.createSubLabel("Summon NPC to Me", 3)
	summonLabel.Parent = section

	local summonEvent = Remotes.getEvent(DebugRemotes.TELEPORT_NPC_TO_PLAYER)
	local summonGrid = DebugPanelUI.createTeleportGrid(npcKeys, 4, function(displayName: string)
		summonEvent:FireServer(displayName)
		log:debug(`Summoning {displayName} to player`)
	end)
	summonGrid.Parent = section

	return section
end

--- Build the behavior swap section from the current NPC list.
local function buildBehaviorSection(
	npcList: { { displayName: string, behaviorType: string } },
	behaviors: { string }
): Frame
	local section = DebugPanelUI.createSection("Behavior", 5)
	table.clear(behaviorUpdaters)

	if #npcList == 0 or #behaviors == 0 then
		local emptyLabel = DebugPanelUI.createSubLabel("No NPCs available", 1)
		emptyLabel.Parent = section
		return section
	end

	local setBehaviorEvent = Remotes.getEvent(DebugRemotes.SET_BEHAVIOR)

	for i, npc in npcList do
		local row, updateFn = DebugPanelUI.createBehaviorRow(
			npc.displayName,
			npc.behaviorType,
			behaviors,
			i,
			function(displayName: string, behaviorType: string)
				setBehaviorEvent:FireServer(displayName, behaviorType)
				log:debug(`Requesting behavior swap: {displayName} -> {behaviorType}`)
			end
		)
		behaviorUpdaters[npc.displayName] = updateFn
		row.Parent = section
	end

	return section
end

--- Build the despawn section from the current NPC list.
local function buildDespawnSection(npcList: { { displayName: string, behaviorType: string } }): Frame
	local section = DebugPanelUI.createSection("Despawn", 6)

	if #npcList == 0 then
		local emptyLabel = DebugPanelUI.createSubLabel("No NPCs to despawn", 1)
		emptyLabel.Parent = section
		return section
	end

	local npcKeys: { { key: string, label: string } } = {}
	for _, npc in npcList do
		table.insert(npcKeys, { key = npc.displayName, label = npc.displayName })
	end

	local despawnEvent = Remotes.getEvent(DebugRemotes.DESPAWN_NPC)
	local grid = DebugPanelUI.createDespawnGrid(npcKeys, 1, function(displayName: string)
		despawnEvent:FireServer(displayName)
		log:debug(`Requesting despawn: {displayName}`)
	end)
	grid.Parent = section

	return section
end

-- ═══════════════════════════════════════════════════════════
-- DIFF + REBUILD
-- ═══════════════════════════════════════════════════════════

--- Check if the NPC list from the server differs from our known list.
--- Returns the sorted list if different, nil if same.
local function diffNPCList(statusData: { [string]: any }): { { displayName: string, behaviorType: string } }?
	local serverList: { { displayName: string, behaviorType: string } } = {}
	for name, data in statusData do
		if name == "_meta" then
			continue
		end
		table.insert(serverList, { displayName = name, behaviorType = data.behaviorType })
	end
	table.sort(serverList, function(a, b)
		return a.displayName < b.displayName
	end)

	-- Quick check: same count?
	if #serverList ~= #knownNPCs then
		return serverList
	end
	-- Check each entry by name (behavior changes don't trigger rebuild)
	for i, entry in serverList do
		if knownNPCs[i].displayName ~= entry.displayName then
			return serverList
		end
	end
	return nil
end

--- Sync visual toggle states to all known NPCs (called after rebuild).
local function syncToggleStatesToNPCs(): ()
	local toggleEvent = Remotes.getEvent(DebugRemotes.TOGGLE_VISUAL)
	for _, def in toggleDefs do
		local enabled = visualToggleStates[def.visualType]
		if enabled ~= nil then
			for _, npcInfo in knownNPCs do
				toggleEvent:FireServer(npcInfo.displayName, def.visualType, enabled)
			end
		end
	end
end

--- Rebuild dynamic sections (status + teleport + behavior + despawn) when NPC list changes.
local function rebuildDynamicSections(newList: { { displayName: string, behaviorType: string } }): ()
	knownNPCs = newList

	-- Clear old status label refs
	table.clear(statusLabels)

	local content = contentFrame
	if not content then
		return
	end

	-- Destroy old sections
	if statusSection then
		statusSection:Destroy()
	end
	if teleportSection then
		teleportSection:Destroy()
	end
	if behaviorSection then
		behaviorSection:Destroy()
	end
	if despawnSection then
		despawnSection:Destroy()
	end

	-- Rebuild
	statusSection = buildStatusSection(newList)
	statusSection.Parent = content

	teleportSection = buildTeleportSection(newList)
	teleportSection.Parent = content

	behaviorSection = buildBehaviorSection(newList, availableBehaviors)
	behaviorSection.Parent = content

	despawnSection = buildDespawnSection(newList)
	despawnSection.Parent = content

	-- Sync visual toggle states to any new NPCs
	syncToggleStatesToNPCs()

	log:debug(`Rebuilt panel for {#newList} NPCs`)
end

-- ═══════════════════════════════════════════════════════════
-- STATUS UPDATE + POLLING
-- ═══════════════════════════════════════════════════════════

--- Update status rows with fresh data from server.
local function updateStatusDisplay(statusData: { [string]: any }): ()
	for _, npcInfo in knownNPCs do
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
			labels.metrics.Text = "Despawned"
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
				-- Extract metadata
				local meta = result._meta
				if meta and meta.availableBehaviors then
					availableBehaviors = meta.availableBehaviors

					-- Build spawn section on first poll (deferred — needs availableBehaviors)
					if not spawnSection and contentFrame then
						local spawnEvent = Remotes.getEvent(DebugRemotes.SPAWN_NPC)
						local clearEvent = Remotes.getEvent(DebugRemotes.CLEAR_ALL_NPCS)
						spawnSection = DebugPanelUI.createSpawnSection(
							availableBehaviors,
							1,
							function(behaviorType: string)
								spawnEvent:FireServer(behaviorType)
								log:debug(`Requesting spawn: {behaviorType}`)
							end,
							function()
								clearEvent:FireServer()
								log:debug("Requesting clear all NPCs")
							end
						)
						spawnSection.Parent = contentFrame
					end
				end

				-- Check if NPC list changed -> rebuild UI
				local newList = diffNPCList(result)
				if newList then
					rebuildDynamicSections(newList)
				end
				updateStatusDisplay(result)

				-- Sync behavior highlights (catches changes from MCP/other tools)
				for name, data in result do
					if name == "_meta" then
						continue
					end
					local updater = behaviorUpdaters[name]
					if updater then
						updater(data.behaviorType)
					end
				end
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

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DebugPanel.initialize(): ()
	-- Build UI
	local gui, _panel = DebugPanelUI.createPanel()
	screenGui = gui

	contentFrame = _panel:FindFirstChild("Content") :: ScrollingFrame

	-- Section 1: Spawn — built on first poll (deferred, needs availableBehaviors from server)

	-- Section 2: Visual Toggles (static — doesn't depend on NPC list)
	local visualSection = DebugPanelUI.createSection("Visual Toggles", 2)

	local toggleEvent = Remotes.getEvent(DebugRemotes.TOGGLE_VISUAL)

	-- Track update functions so Toggle All can sync them
	local toggleUpdaters: { (enabled: boolean) -> () } = {}

	for _, def in toggleDefs do
		local row, updateFn = DebugPanelUI.createToggleRow(def.label, true, def.order, function(enabled: boolean)
			visualToggleStates[def.visualType] = enabled
			-- Fire for all known NPCs
			for _, npcInfo in knownNPCs do
				toggleEvent:FireServer(npcInfo.displayName, def.visualType, enabled)
			end
		end)
		table.insert(toggleUpdaters, updateFn)
		row.Parent = visualSection
	end

	-- Toggle All: master on/off that syncs all individual toggles
	local toggleAllRow, _toggleAllUpdate = DebugPanelUI.createToggleRow(
		"Toggle All",
		true,
		1,
		function(enabled: boolean)
			-- Sync all individual toggle visuals + state
			for _, updater in toggleUpdaters do
				updater(enabled)
			end
			-- Fire remotes for every visual type on every NPC
			for _, def in toggleDefs do
				visualToggleStates[def.visualType] = enabled
				for _, npcInfo in knownNPCs do
					toggleEvent:FireServer(npcInfo.displayName, def.visualType, enabled)
				end
			end
		end
	)
	toggleAllRow.Parent = visualSection

	visualSection.Parent = contentFrame

	-- Sections 3-6 (Status + Teleport + Behavior + Despawn) built dynamically on first poll

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

	-- Performance strip (always visible, independent of panel toggle)
	local perfGui, fpsLabel, frameTimeLabel, instanceLabel = DebugPanelUI.createPerfStrip()

	-- FPS / frame time: update every render frame
	RunService.RenderStepped:Connect(function(dt: number)
		local fps = math.floor(1 / dt)
		local ftMs = dt * 1000

		fpsLabel.Text = `{fps} fps`
		frameTimeLabel.Text = string.format("%.1f ms", ftMs)

		-- Color code by frame time: green < 16ms, yellow 16-33ms, red > 33ms
		local color = if ftMs < 16
			then GameConfig.UI.COLORS.SUCCESS
			elseif ftMs < 33 then GameConfig.UI.COLORS.WARNING
			else GameConfig.UI.COLORS.ERROR
		fpsLabel.TextColor3 = color
		frameTimeLabel.TextColor3 = color
	end)

	-- Instance count: update on a slow timer (every 3s) to avoid overhead
	task.spawn(function()
		while true do
			local count = #Workspace:GetDescendants()
			instanceLabel.Text = `{count} inst`
			task.wait(3)
		end
	end)

	perfGui.Parent = playerGui

	log:info(`Debug panel ready (toggle: {TOGGLE_KEY.Name})`)
end

return DebugPanel
