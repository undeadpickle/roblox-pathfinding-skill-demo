--!strict
--[[
	DebugPanelUI - Factory functions for debug panel UI elements.

	Creates raw Roblox UI instances (no framework). All properties set
	before Parent per project conventions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)

local UI = GameConfig.UI
local COLORS = UI.COLORS
local FONTS = UI.FONTS

-- Panel constants
local PANEL_WIDTH = 280
local PANEL_BG = Color3.fromRGB(25, 25, 30)
local PANEL_BG_TRANSPARENCY = 0.08
local SECTION_BG = Color3.fromRGB(35, 35, 42)
local ROW_HEIGHT = 28
local PADDING = 8
local TEXT_SIZE = 13
local HEADING_TEXT_SIZE = 14

local DebugPanelUI = {}

--- Create the root ScreenGui and main panel frame.
function DebugPanelUI.createPanel(): (ScreenGui, Frame)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DebugPanel"
	screenGui.DisplayOrder = 100
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.Enabled = false -- starts hidden

	local panel = Instance.new("Frame")
	panel.Name = "PanelFrame"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -10, 0, 10)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0.9, 0)
	panel.BackgroundColor3 = PANEL_BG
	panel.BackgroundTransparency = PANEL_BG_TRANSPARENCY
	panel.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 60, 70)
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = panel

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundTransparency = 1

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.fromOffset(PADDING, 0)
	title.BackgroundTransparency = 1
	title.Text = "NPC Sandbox"
	title.TextColor3 = COLORS.PRIMARY
	title.Font = FONTS.HEADING
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -4, 0, 4)
	closeBtn.Size = UDim2.fromOffset(28, 28)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Text = "X"
	closeBtn.TextColor3 = COLORS.SECONDARY
	closeBtn.Font = FONTS.HEADING
	closeBtn.TextSize = 14
	closeBtn.Parent = header

	header.Parent = panel

	-- Scrolling content area below header
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(0, 36)
	content.Size = UDim2.new(1, 0, 1, -36)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = COLORS.SECONDARY
	content.CanvasSize = UDim2.new(0, 0, 0, 0) -- auto-sized by UIListLayout
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingLeft = UDim.new(0, PADDING)
	contentPad.PaddingRight = UDim.new(0, PADDING)
	contentPad.PaddingTop = UDim.new(0, 4)
	contentPad.PaddingBottom = UDim.new(0, PADDING)
	contentPad.Parent = content

	content.Parent = panel
	panel.Parent = screenGui

	return screenGui, panel
end

--- Create a collapsible section with a title header.
function DebugPanelUI.createSection(title: string, layoutOrder: number): Frame
	local section = Instance.new("Frame")
	section.Name = title .. "Section"
	section.Size = UDim2.fromScale(1, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundColor3 = SECTION_BG
	section.BackgroundTransparency = 0.3
	section.BorderSizePixel = 0
	section.LayoutOrder = layoutOrder

	local sectionCorner = Instance.new("UICorner")
	sectionCorner.CornerRadius = UDim.new(0, 6)
	sectionCorner.Parent = section

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding = UDim.new(0, 2)
	sectionLayout.Parent = section

	local sectionPad = Instance.new("UIPadding")
	sectionPad.PaddingLeft = UDim.new(0, PADDING)
	sectionPad.PaddingRight = UDim.new(0, PADDING)
	sectionPad.PaddingTop = UDim.new(0, 6)
	sectionPad.PaddingBottom = UDim.new(0, 6)
	sectionPad.Parent = section

	local header = Instance.new("TextLabel")
	header.Name = "SectionHeader"
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.Text = title
	header.TextColor3 = COLORS.PRIMARY
	header.Font = FONTS.HEADING
	header.TextSize = HEADING_TEXT_SIZE
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	header.Parent = section

	return section
end

--- Create a toggle row with label and clickable toggle indicator.
--- Returns the row Frame and a function to update the visual state externally.
function DebugPanelUI.createToggleRow(
	label: string,
	initial: boolean,
	layoutOrder: number,
	onChange: (enabled: boolean) -> ()
): (Frame, (enabled: boolean) -> ())
	local enabled = initial

	local row = Instance.new("Frame")
	row.Name = label .. "Toggle"
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder

	local indicator = Instance.new("TextButton")
	indicator.Name = "Indicator"
	indicator.Size = UDim2.fromOffset(18, 18)
	indicator.Position = UDim2.fromOffset(0, 5)
	indicator.BackgroundColor3 = if enabled then COLORS.SUCCESS else COLORS.SECONDARY
	indicator.BorderSizePixel = 0
	indicator.Text = ""
	indicator.AutoButtonColor = false

	local indicatorCorner = Instance.new("UICorner")
	indicatorCorner.CornerRadius = UDim.new(0, 4)
	indicatorCorner.Parent = indicator

	indicator.Parent = row

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Label"
	textLabel.Size = UDim2.new(1, -26, 1, 0)
	textLabel.Position = UDim2.fromOffset(26, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = label
	textLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
	textLabel.Font = FONTS.BODY
	textLabel.TextSize = TEXT_SIZE
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Parent = row

	local function updateVisual(newEnabled: boolean)
		enabled = newEnabled
		indicator.BackgroundColor3 = if enabled then COLORS.SUCCESS else COLORS.SECONDARY
	end

	indicator.MouseButton1Click:Connect(function()
		enabled = not enabled
		updateVisual(enabled)
		onChange(enabled)
	end)

	return row, updateVisual
end

--- Create a status row for one NPC. Returns the row Frame plus refs to update.
function DebugPanelUI.createStatusRow(npcName: string, layoutOrder: number): (Frame, TextLabel, TextLabel)
	local row = Instance.new("Frame")
	row.Name = npcName .. "Status"
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder

	local stateLabel = Instance.new("TextLabel")
	stateLabel.Name = "StateLabel"
	stateLabel.Size = UDim2.new(1, 0, 0, 18)
	stateLabel.BackgroundTransparency = 1
	stateLabel.Text = npcName .. ": --"
	stateLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
	stateLabel.Font = FONTS.HEADING
	stateLabel.TextSize = TEXT_SIZE
	stateLabel.TextXAlignment = Enum.TextXAlignment.Left
	stateLabel.Parent = row

	local metricsLabel = Instance.new("TextLabel")
	metricsLabel.Name = "MetricsLabel"
	metricsLabel.Size = UDim2.new(1, 0, 0, 16)
	metricsLabel.Position = UDim2.fromOffset(0, 20)
	metricsLabel.BackgroundTransparency = 1
	metricsLabel.Text = "..."
	metricsLabel.TextColor3 = COLORS.SECONDARY
	metricsLabel.Font = FONTS.BODY
	metricsLabel.TextSize = 11
	metricsLabel.TextXAlignment = Enum.TextXAlignment.Left
	metricsLabel.Parent = row

	return row, stateLabel, metricsLabel
end

--- Create a small sub-section label (used within sections to label groups).
function DebugPanelUI.createSubLabel(text: string, layoutOrder: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = text .. "SubLabel"
	label.Size = UDim2.new(1, 0, 0, 18)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = COLORS.SECONDARY
	label.Font = FONTS.BODY
	label.TextSize = 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = layoutOrder
	return label
end

--- Create a styled button.
function DebugPanelUI.createButton(text: string, color: Color3, layoutOrder: number, onClick: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = text .. "Button"
	btn.Size = UDim2.new(0.48, 0, 0, ROW_HEIGHT)
	btn.BackgroundColor3 = color
	btn.BackgroundTransparency = 0.7
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(220, 220, 225)
	btn.Font = FONTS.HEADING
	btn.TextSize = TEXT_SIZE
	btn.AutoButtonColor = true
	btn.LayoutOrder = layoutOrder

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = btn

	btn.MouseButton1Click:Connect(onClick)

	return btn
end

--- Create an always-visible performance strip (FPS, frame time, instance count).
--- Returns the ScreenGui and label refs for updating each frame.
function DebugPanelUI.createPerfStrip(): (ScreenGui, TextLabel, TextLabel, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "PerfStrip"
	gui.DisplayOrder = 101
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0, 0)
	strip.Position = UDim2.fromOffset(10, 10)
	strip.Size = UDim2.fromOffset(260, 22)
	strip.BackgroundColor3 = PANEL_BG
	strip.BackgroundTransparency = 0.3
	strip.BorderSizePixel = 0

	local stripCorner = Instance.new("UICorner")
	stripCorner.CornerRadius = UDim.new(0, 4)
	stripCorner.Parent = strip

	local stripPad = Instance.new("UIPadding")
	stripPad.PaddingLeft = UDim.new(0, 8)
	stripPad.PaddingRight = UDim.new(0, 8)
	stripPad.Parent = strip

	local stripLayout = Instance.new("UIListLayout")
	stripLayout.FillDirection = Enum.FillDirection.Horizontal
	stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stripLayout.Padding = UDim.new(0, 12)
	stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	stripLayout.Parent = strip

	local function makeLabel(name: string, order: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.Size = UDim2.new(0, 70, 1, 0)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.BackgroundTransparency = 1
		label.Text = "--"
		label.TextColor3 = COLORS.SUCCESS
		label.Font = FONTS.BODY
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = order
		label.Parent = strip
		return label
	end

	local fpsLabel = makeLabel("FPS", 1)
	local frameTimeLabel = makeLabel("FrameTime", 2)
	local instanceLabel = makeLabel("Instances", 3)

	strip.Parent = gui

	return gui, fpsLabel, frameTimeLabel, instanceLabel
end

--- Create a row of teleport buttons in a 2x2 grid.
function DebugPanelUI.createTeleportGrid(
	npcKeys: { { key: string, label: string } },
	layoutOrder: number,
	onTeleport: (key: string) -> ()
): Frame
	local grid = Instance.new("Frame")
	grid.Name = "TeleportGrid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = layoutOrder

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.48, 0, 0, ROW_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0.04, 0, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for i, entry in npcKeys do
		local btn = Instance.new("TextButton")
		btn.Name = entry.key .. "Teleport"
		btn.BackgroundColor3 = COLORS.SECONDARY
		btn.BackgroundTransparency = 0.6
		btn.BorderSizePixel = 0
		btn.Text = entry.label
		btn.TextColor3 = Color3.fromRGB(220, 220, 225)
		btn.Font = FONTS.BODY
		btn.TextSize = TEXT_SIZE
		btn.AutoButtonColor = true
		btn.LayoutOrder = i

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onTeleport(entry.key)
		end)

		btn.Parent = grid
	end

	return grid
end

--- Create a row of behavior swap buttons for one NPC.
--- Returns the row Frame and an update function to change the active highlight.
function DebugPanelUI.createBehaviorRow(
	npcDisplayName: string,
	currentBehavior: string,
	availableBehaviors: { string },
	layoutOrder: number,
	onSwap: (npcDisplayName: string, behaviorType: string) -> ()
): (Frame, (newBehavior: string) -> ())
	local activeBehavior = currentBehavior

	local row = Instance.new("Frame")
	row.Name = npcDisplayName .. "Behavior"
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 2)
	rowLayout.Parent = row

	-- NPC name label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NPCName"
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = npcDisplayName
	nameLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
	nameLabel.Font = FONTS.HEADING
	nameLabel.TextSize = TEXT_SIZE
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = row

	-- Button container
	local btnContainer = Instance.new("Frame")
	btnContainer.Name = "Buttons"
	btnContainer.Size = UDim2.fromScale(1, 0)
	btnContainer.AutomaticSize = Enum.AutomaticSize.Y
	btnContainer.BackgroundTransparency = 1
	btnContainer.LayoutOrder = 2

	local btnGrid = Instance.new("UIGridLayout")
	btnGrid.CellSize = UDim2.new(0.48, 0, 0, ROW_HEIGHT)
	btnGrid.CellPadding = UDim2.new(0.04, 0, 0, 4)
	btnGrid.SortOrder = Enum.SortOrder.LayoutOrder
	btnGrid.Parent = btnContainer

	local buttons: { [string]: TextButton } = {}

	for i, behavior in availableBehaviors do
		local isActive = behavior == activeBehavior
		local btn = Instance.new("TextButton")
		btn.Name = behavior .. "Btn"
		btn.Text = behavior:sub(1, 1):upper() .. behavior:sub(2)
		btn.BackgroundColor3 = if isActive then COLORS.PRIMARY else COLORS.SECONDARY
		btn.BackgroundTransparency = if isActive then 0.3 else 0.7
		btn.BorderSizePixel = 0
		btn.TextColor3 = Color3.fromRGB(220, 220, 225)
		btn.Font = FONTS.BODY
		btn.TextSize = TEXT_SIZE
		btn.AutoButtonColor = not isActive
		btn.LayoutOrder = i

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if behavior ~= activeBehavior then
				onSwap(npcDisplayName, behavior)
			end
		end)

		buttons[behavior] = btn
		btn.Parent = btnContainer
	end

	btnContainer.Parent = row

	-- Update function: highlights the new active behavior
	local function updateActive(newBehavior: string)
		activeBehavior = newBehavior
		for bType, btn in buttons do
			local isActive = bType == newBehavior
			btn.BackgroundColor3 = if isActive then COLORS.PRIMARY else COLORS.SECONDARY
			btn.BackgroundTransparency = if isActive then 0.3 else 0.7
			btn.AutoButtonColor = not isActive
		end
	end

	return row, updateActive
end

--- Create the spawn section with behavior type buttons and a Clear All button.
function DebugPanelUI.createSpawnSection(
	behaviors: { string },
	layoutOrder: number,
	onSpawn: (behaviorType: string) -> (),
	onClearAll: () -> ()
): Frame
	local section = DebugPanelUI.createSection("Spawn", layoutOrder)

	-- Behavior type button grid
	local grid = Instance.new("Frame")
	grid.Name = "SpawnGrid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = 1

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.48, 0, 0, ROW_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0.04, 0, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for i, behavior in behaviors do
		local label = behavior:sub(1, 1):upper() .. behavior:sub(2)
		local btn = Instance.new("TextButton")
		btn.Name = behavior .. "SpawnBtn"
		btn.BackgroundColor3 = COLORS.SUCCESS
		btn.BackgroundTransparency = 0.5
		btn.BorderSizePixel = 0
		btn.Text = label
		btn.TextColor3 = Color3.fromRGB(220, 220, 225)
		btn.Font = FONTS.HEADING
		btn.TextSize = TEXT_SIZE
		btn.AutoButtonColor = true
		btn.LayoutOrder = i

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onSpawn(behavior)
		end)

		btn.Parent = grid
	end

	grid.Parent = section

	-- Clear All button (full width, red)
	local clearBtn = Instance.new("TextButton")
	clearBtn.Name = "ClearAllBtn"
	clearBtn.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	clearBtn.BackgroundColor3 = COLORS.ERROR
	clearBtn.BackgroundTransparency = 0.5
	clearBtn.BorderSizePixel = 0
	clearBtn.Text = "Clear All"
	clearBtn.TextColor3 = Color3.fromRGB(220, 220, 225)
	clearBtn.Font = FONTS.HEADING
	clearBtn.TextSize = TEXT_SIZE
	clearBtn.AutoButtonColor = true
	clearBtn.LayoutOrder = 2

	local clearCorner = Instance.new("UICorner")
	clearCorner.CornerRadius = UDim.new(0, 4)
	clearCorner.Parent = clearBtn

	clearBtn.MouseButton1Click:Connect(onClearAll)
	clearBtn.Parent = section

	return section
end

--- Create a grid of despawn buttons, one per NPC.
function DebugPanelUI.createDespawnGrid(
	npcKeys: { { key: string, label: string } },
	layoutOrder: number,
	onDespawn: (key: string) -> ()
): Frame
	local grid = Instance.new("Frame")
	grid.Name = "DespawnGrid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = layoutOrder

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.48, 0, 0, ROW_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0.04, 0, 0, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	for i, entry in npcKeys do
		local btn = Instance.new("TextButton")
		btn.Name = entry.key .. "Despawn"
		btn.BackgroundColor3 = COLORS.ERROR
		btn.BackgroundTransparency = 0.6
		btn.BorderSizePixel = 0
		btn.Text = entry.label
		btn.TextColor3 = Color3.fromRGB(220, 220, 225)
		btn.Font = FONTS.BODY
		btn.TextSize = TEXT_SIZE
		btn.AutoButtonColor = true
		btn.LayoutOrder = i

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			onDespawn(entry.key)
		end)

		btn.Parent = grid
	end

	return grid
end

return DebugPanelUI
