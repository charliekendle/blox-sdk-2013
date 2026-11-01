--!optimize 2
--[[
	DevConsole (LocalScript)
	StarterPlayer.StarterPlayerScripts.BloxSDKClient.DevConsole

	Source-style developer console + key binds on top of BloxSDK ConVar.

	`            toggle console
	Tab          complete
	Up / Down    pick a completion, or walk command history
	Enter        run

	Commands: clear, toggleconsole, showconsole, hideconsole,
	          bind, unbind, unbindall, key_listboundkeys
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Cvar = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("ConVar"))

local player = Players.LocalPlayer

local MAX_LINES = 300
local MAX_COMPLETIONS = 10
local MAX_HISTORY = 50

-- SourceScheme / Steam 2013 colours
local COLOR_WINDOW = Color3.fromRGB(76, 88, 68)
local COLOR_PANEL = Color3.fromRGB(62, 70, 55)
local COLOR_BORDER_DARK = Color3.fromRGB(40, 46, 34)
local COLOR_BORDER_LIGHT = Color3.fromRGB(136, 145, 128)
local COLOR_TEXT = Color3.fromRGB(216, 222, 211)
local COLOR_TEXT_DIM = Color3.fromRGB(160, 170, 149)
local COLOR_SELECTED = Color3.fromRGB(149, 136, 49)

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BloxSDK_Console"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function stroke(parent: GuiObject, color: Color3)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local window = Instance.new("Frame")
window.Name = "Window"
window.Position = UDim2.fromOffset(40, 60)
window.Size = UDim2.fromOffset(680, 460)
window.BackgroundColor3 = COLOR_WINDOW
window.BorderSizePixel = 0
window.Parent = gui
stroke(window, COLOR_BORDER_LIGHT)

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(320, 200)
sizeLimit.Parent = window

local titleBar = Instance.new("TextLabel")
titleBar.Name = "Title"
titleBar.Size = UDim2.new(1, 0, 0, 28)
titleBar.BackgroundTransparency = 1
titleBar.Font = Enum.Font.SourceSansBold
titleBar.TextSize = 18
titleBar.TextColor3 = COLOR_TEXT
titleBar.TextXAlignment = Enum.TextXAlignment.Left
titleBar.Text = "   Console"
titleBar.Parent = window

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -6, 0, 5)
closeButton.Size = UDim2.fromOffset(18, 18)
closeButton.BackgroundColor3 = COLOR_WINDOW
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.SourceSansBold
closeButton.TextSize = 16
closeButton.TextColor3 = COLOR_TEXT
closeButton.Text = "x"
closeButton.AutoButtonColor = true
closeButton.Parent = window
stroke(closeButton, COLOR_BORDER_LIGHT)

local output = Instance.new("ScrollingFrame")
output.Name = "Output"
output.Position = UDim2.fromOffset(10, 30)
output.Size = UDim2.new(1, -20, 1, -72)
output.BackgroundColor3 = COLOR_PANEL
output.BorderSizePixel = 0
output.ScrollBarThickness = 10
output.ScrollBarImageColor3 = COLOR_BORDER_LIGHT
output.CanvasSize = UDim2.new()
output.AutomaticCanvasSize = Enum.AutomaticSize.Y
output.ScrollingDirection = Enum.ScrollingDirection.Y
output.Parent = window
stroke(output, COLOR_BORDER_DARK)

local outputPadding = Instance.new("UIPadding")
outputPadding.PaddingLeft = UDim.new(0, 6)
outputPadding.PaddingTop = UDim.new(0, 4)
outputPadding.PaddingRight = UDim.new(0, 14)
outputPadding.PaddingBottom = UDim.new(0, 4)
outputPadding.Parent = output

local outputLayout = Instance.new("UIListLayout")
outputLayout.SortOrder = Enum.SortOrder.LayoutOrder
outputLayout.Parent = output

local input = Instance.new("TextBox")
input.Name = "Input"
input.AnchorPoint = Vector2.new(0, 1)
input.Position = UDim2.new(0, 10, 1, -10)
input.Size = UDim2.new(1, -100, 0, 24)
input.BackgroundColor3 = COLOR_PANEL
input.BorderSizePixel = 0
input.ClearTextOnFocus = false
input.Font = Enum.Font.Code
input.TextSize = 15
input.TextColor3 = COLOR_TEXT
input.PlaceholderText = ""
input.TextXAlignment = Enum.TextXAlignment.Left
input.Text = ""
input.Parent = window
stroke(input, COLOR_BORDER_DARK)

local inputPadding = Instance.new("UIPadding")
inputPadding.PaddingLeft = UDim.new(0, 6)
inputPadding.Parent = input

local submit = Instance.new("TextButton")
submit.Name = "Submit"
submit.AnchorPoint = Vector2.new(1, 1)
submit.Position = UDim2.new(1, -10, 1, -10)
submit.Size = UDim2.fromOffset(76, 24)
submit.BackgroundColor3 = COLOR_WINDOW
submit.BorderSizePixel = 0
submit.Font = Enum.Font.SourceSans
submit.TextSize = 16
submit.TextColor3 = COLOR_TEXT
submit.Text = "Submit"
submit.Parent = window
stroke(submit, COLOR_BORDER_LIGHT)

local completionFrame = Instance.new("Frame")
completionFrame.Name = "Completions"
completionFrame.Position = UDim2.new(0, 10, 1, -8)
completionFrame.Size = UDim2.new(1, -100, 0, 0)
completionFrame.AutomaticSize = Enum.AutomaticSize.Y
completionFrame.BackgroundColor3 = COLOR_PANEL
completionFrame.BorderSizePixel = 0
completionFrame.Visible = false
completionFrame.ZIndex = 5
completionFrame.Parent = window
stroke(completionFrame, COLOR_BORDER_LIGHT)

local completionLayout = Instance.new("UIListLayout")
completionLayout.SortOrder = Enum.SortOrder.LayoutOrder
completionLayout.Parent = completionFrame

gui.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------

local lineCount = 0
local lines = {}
local stickToBottom = true

local function scrollToBottom()
	output.CanvasPosition = Vector2.new(0, math.max(0, output.AbsoluteCanvasSize.Y - output.AbsoluteWindowSize.Y))
end

local function addLine(text: string, color: Color3)
	lineCount += 1
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.RichText = false
	label.Text = if text == "" then " " else text
	label.LayoutOrder = lineCount
	label.Parent = output
	table.insert(lines, label)

	if #lines > MAX_LINES then
		table.remove(lines, 1):Destroy()
	end
end

output:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
	if stickToBottom then
		scrollToBottom()
	end
end)

output:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	local bottom = output.AbsoluteCanvasSize.Y - output.AbsoluteWindowSize.Y
	stickToBottom = output.CanvasPosition.Y >= bottom - 4
end)

for _, entry in Cvar.GetHistory() do
	addLine(entry.text, entry.color)
end
Cvar.OnPrint(addLine)

local function clearOutput()
	for _, label in lines do
		label:Destroy()
	end
	table.clear(lines)
	Cvar.ClearHistory()
	stickToBottom = true
end

------------------------------------------------------------------------
-- Completion + history
------------------------------------------------------------------------

local completions: { string } = {}
local completionIndex = 0
local commandHistory: { string } = {}
local historyIndex = 0
local suppressTextChange = false

local function setInputText(text: string)
	suppressTextChange = true
	input.Text = text
	input.CursorPosition = #text + 1
	suppressTextChange = false
end

local function renderCompletions()
	for _, child in completionFrame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	completionFrame.Visible = #completions > 0 and input:IsFocused()
	if not completionFrame.Visible then
		return
	end

	for i, item in completions do
		local base = Cvar.Find(item:match("^(%S+)") or item)
		local suffix = ""
		if base and not base.isCommand and not item:find(" ", 1, true) then
			suffix = "  " .. base:GetString()
		end

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 20)
		button.BackgroundColor3 = if i == completionIndex then COLOR_SELECTED else COLOR_PANEL
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = Enum.Font.Code
		button.TextSize = 14
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.TextColor3 = COLOR_TEXT
		button.RichText = true
		button.Text = string.format(
			'  %s<font color="#%s">%s</font>',
			item,
			COLOR_TEXT_DIM:ToHex(),
			suffix
		)
		button.LayoutOrder = i
		button.ZIndex = 6
		button.Parent = completionFrame

		button.MouseButton1Click:Connect(function()
			setInputText(if item:find(" ", 1, true) then item else item .. " ")
			completions = {}
			completionIndex = 0
			renderCompletions()
			input:CaptureFocus()
		end)
	end

	-- the list opens upward if it would fall off the bottom of the screen
	local below = window.AbsolutePosition.Y + window.AbsoluteSize.Y + completionFrame.AbsoluteSize.Y
	if below > gui.AbsoluteSize.Y then
		completionFrame.AnchorPoint = Vector2.new(0, 1)
		completionFrame.Position = UDim2.new(0, 10, 1, -36)
	else
		completionFrame.AnchorPoint = Vector2.new(0, 0)
		completionFrame.Position = UDim2.new(0, 10, 1, -8)
	end
end

local function refreshCompletions()
	local text = input.Text
	if text == "" then
		completions = {}
	else
		completions = Cvar.Complete(text, MAX_COMPLETIONS)
		-- hide an exact single match the user has already typed out
		if #completions == 1 and string.lower(completions[1]) == string.lower((text:gsub("%s+$", ""))) then
			completions = {}
		end
	end
	completionIndex = 0
	renderCompletions()
end

input:GetPropertyChangedSignal("Text"):Connect(function()
	if suppressTextChange then
		return
	end
	local cleaned = input.Text:gsub("[`\t]", "")
	if cleaned ~= input.Text then
		setInputText(cleaned)
	end
	historyIndex = 0
	refreshCompletions()
end)

local function acceptCompletion()
	if #completions == 0 then
		return
	end
	local item = completions[if completionIndex > 0 then completionIndex else 1]
	setInputText(if item:find(" ", 1, true) then item else item .. " ")
	refreshCompletions()
end

local function moveSelection(dir: number)
	if #completions > 0 then
		completionIndex += dir
		if completionIndex < 1 then
			completionIndex = #completions
		elseif completionIndex > #completions then
			completionIndex = 1
		end
		renderCompletions()
		return
	end

	if #commandHistory == 0 then
		return
	end
	-- dir -1 = older (Up), +1 = newer (Down)
	if dir < 0 then
		historyIndex = math.min(historyIndex + 1, #commandHistory)
	else
		historyIndex = math.max(historyIndex - 1, 0)
	end
	local text = if historyIndex == 0 then "" else commandHistory[#commandHistory - historyIndex + 1]
	setInputText(text)
end

------------------------------------------------------------------------
-- Show / hide / submit
------------------------------------------------------------------------

local function setVisible(visible: boolean)
	gui.Enabled = visible
	Cvar.consoleVisible = visible
	if visible then
		task.defer(function()
			input:CaptureFocus()
			setInputText((input.Text:gsub("`", "")))
		end)
		stickToBottom = true
		task.defer(scrollToBottom)
	else
		input:ReleaseFocus()
		completions = {}
		renderCompletions()
	end
end

local function submitInput()
	local text = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
	setInputText("")
	completions = {}
	completionIndex = 0
	historyIndex = 0
	renderCompletions()

	if text == "" then
		return
	end

	if commandHistory[#commandHistory] ~= text then
		table.insert(commandHistory, text)
		if #commandHistory > MAX_HISTORY then
			table.remove(commandHistory, 1)
		end
	end

	stickToBottom = true
	Cvar.ExecuteFromConsole(text)
end

input.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitInput()
		if gui.Enabled then
			task.defer(function()
				input:CaptureFocus()
			end)
		end
	else
		task.defer(renderCompletions)
	end
end)

input.Focused:Connect(renderCompletions)

submit.MouseButton1Click:Connect(function()
	submitInput()
	input:CaptureFocus()
end)

closeButton.MouseButton1Click:Connect(function()
	setVisible(false)
end)

------------------------------------------------------------------------
-- Dragging
------------------------------------------------------------------------

local dragging = false
local dragStart = Vector2.zero
local windowStart = Vector2.zero

titleBar.InputBegan:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragStart = Vector2.new(io.Position.X, io.Position.Y)
		windowStart = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
	end
end)

UserInputService.InputChanged:Connect(function(io)
	if dragging and io.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = Vector2.new(io.Position.X, io.Position.Y) - dragStart
		window.Position = UDim2.fromOffset(windowStart.X + delta.X, windowStart.Y + delta.Y)
	end
end)

UserInputService.InputEnded:Connect(function(io)
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

------------------------------------------------------------------------
-- Key binds
------------------------------------------------------------------------

local KEY_ALIASES: { [string]: string } = {
	["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
	["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
	ctrl = "LeftControl", rctrl = "RightControl",
	shift = "LeftShift", rshift = "RightShift",
	alt = "LeftAlt", ralt = "RightAlt",
	enter = "Return", space = "Space", tab = "Tab", backspace = "Backspace",
	uparrow = "Up", downarrow = "Down", leftarrow = "Left", rightarrow = "Right",
	ins = "Insert", del = "Delete", pgup = "PageUp", pgdn = "PageDown",
	capslock = "CapsLock", semicolon = "Semicolon",
	["`"] = "Backquote", ["-"] = "Minus", ["="] = "Equals",
	["["] = "LeftBracket", ["]"] = "RightBracket", [","] = "Comma",
	["."] = "Period", ["/"] = "Slash", ["\\"] = "BackSlash", ["'"] = "Quote",
}

local MOUSE_NAMES: { [Enum.UserInputType]: string } = {
	[Enum.UserInputType.MouseButton1] = "mouse1",
	[Enum.UserInputType.MouseButton2] = "mouse2",
	[Enum.UserInputType.MouseButton3] = "mouse3",
}

local keyCodeByLower: { [string]: Enum.KeyCode } = {}
local sourceNameByKeyCode: { [Enum.KeyCode]: string } = {}
for _, item in Enum.KeyCode:GetEnumItems() do
	keyCodeByLower[string.lower(item.Name)] = item
end
for sourceName, keyName in KEY_ALIASES do
	local item = keyCodeByLower[string.lower(keyName)]
	if item then
		sourceNameByKeyCode[item] = sourceName
	end
end

-- canonical key name for a typed name ("CTRL" -> "ctrl", "leftcontrol" -> "ctrl")
local function canonicalKeyName(name: string): string?
	local lower = string.lower(name)
	if lower == "mouse1" or lower == "mouse2" or lower == "mouse3" then
		return lower
	end
	local item = if KEY_ALIASES[lower] then keyCodeByLower[string.lower(KEY_ALIASES[lower])] else keyCodeByLower[lower]
	if not item then
		return nil
	end
	return sourceNameByKeyCode[item] or string.lower(item.Name)
end

local function keyNameFromInput(io: InputObject): string?
	local mouse = MOUSE_NAMES[io.UserInputType]
	if mouse then
		return mouse
	end
	if io.KeyCode == Enum.KeyCode.Unknown then
		return nil
	end
	return sourceNameByKeyCode[io.KeyCode] or string.lower(io.KeyCode.Name)
end

local binds: { [string]: string } = {}
local heldPlusCommands: { [string]: string } = {}

local function setBind(key: string, command: string?)
	binds[key] = command
end

local function runBind(key: string, pressed: boolean)
	local command = binds[key]
	if not command then
		return
	end

	if pressed then
		if command:sub(1, 1) == "+" then
			heldPlusCommands[key] = command
		end
		Cvar.Execute(command)
	else
		local held = heldPlusCommands[key]
		if held then
			heldPlusCommands[key] = nil
			Cvar.Execute("-" .. held:sub(2))
		end
	end
end

-- default binds
setBind("`", "toggleconsole")
setBind("v", "noclip")
setBind("m", "toggle cl_mouselock")

UserInputService.InputBegan:Connect(function(io, gameProcessed)
	local key = keyNameFromInput(io)
	if not key then
		return
	end

	if gui.Enabled then
		-- only the console toggle works while the console is open
		if binds[key] == "toggleconsole" then
			setVisible(false)
			return
		end
		if input:IsFocused() then
			if io.KeyCode == Enum.KeyCode.Tab then
				acceptCompletion()
			elseif io.KeyCode == Enum.KeyCode.Up then
				moveSelection(-1)
			elseif io.KeyCode == Enum.KeyCode.Down then
				moveSelection(1)
			end
		end
		return
	end

	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	runBind(key, true)
end)

UserInputService.InputEnded:Connect(function(io)
	local key = keyNameFromInput(io)
	if key then
		runBind(key, false)
	end
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

Cvar.ConCommand("clear", clearOutput, "Clear all console output.")

Cvar.ConCommand("toggleconsole", function()
	setVisible(not gui.Enabled)
end, "Show/hide the console.")

Cvar.ConCommand("showconsole", function()
	setVisible(true)
end, "Show the console.")

Cvar.ConCommand("hideconsole", function()
	setVisible(false)
end, "Hide the console.")

Cvar.ConCommand("bind", function(args)
	if args:ArgC() < 2 then
		Cvar.Msg("bind <key> [command] : attach a command to a key")
		return
	end
	local key = canonicalKeyName(args:Arg(1))
	if not key then
		Cvar.Msg(string.format('"%s" isn\'t a valid key', args:Arg(1)))
		return
	end
	if args:ArgC() == 2 then
		if binds[key] then
			Cvar.Msg(string.format('"%s" = "%s"', key, binds[key]))
		else
			Cvar.Msg(string.format('"%s" is not bound', key))
		end
		return
	end
	local parts = {}
	for i = 2, args:ArgC() - 1 do
		table.insert(parts, args:Arg(i))
	end
	setBind(key, table.concat(parts, " "))
end, "Bind a key.")

Cvar.ConCommand("unbind", function(args)
	if args:ArgC() ~= 2 then
		Cvar.Msg("unbind <key> : remove commands from a key")
		return
	end
	local key = canonicalKeyName(args:Arg(1))
	if not key then
		Cvar.Msg(string.format('"%s" isn\'t a valid key', args:Arg(1)))
		return
	end
	setBind(key, nil)
end, "Unbind a key.")

Cvar.ConCommand("unbindall", function()
	table.clear(binds)
	-- keep the console reachable
	setBind("`", "toggleconsole")
end, "Unbind all keys.")

Cvar.ConCommand("key_listboundkeys", function()
	local keys = {}
	for key in binds do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		Cvar.Msg(string.format('"%s" = "%s"', key, binds[key]))
	end
end, "List bound keys with bindings.")

Cvar.Msg("BloxSDK console. Type 'cvarlist' or 'find <text>' to see what's available.")
