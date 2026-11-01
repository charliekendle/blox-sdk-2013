--!optimize 2
--[[
	PlayerMovement (LocalScript)
	StarterPlayer.StarterPlayerScripts.BloxSDKClient.PlayerMovement

	Drives the local character with BloxSDK GameMovement (Source SDK 2013 CGameMovement port).
	Fixed 66-tick simulation, interpolated first-person camera, Source-style mouse look.

	Controls:
	  WASD        move
	  Space       jump (noclip: up)
	  Ctrl / C    duck (noclip: down)
	  Shift       sprint (+speed, 320)
	  Alt         walk (+walk, 150)
	  `           console (DevConsole) - V/M are console binds: noclip, toggle cl_mouselock

	Console:
	  convars  sensitivity, m_yaw, m_pitch, fov_desired, cl_forwardspeed, cl_sidespeed, cl_upspeed,
	           hl2_normspeed, hl2_sprintspeed, hl2_walkspeed, smoothstairs, sv_falldamage,
	           cl_mouselock, cl_drawhud, cl_showspeed, cl_showpos, cl_showfps
	  commands noclip, kill, getpos, setpos, setang
	  Positions are Source units on Roblox axes (Y up).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local Cvar = require(Shared:WaitForChild("ConVar"))
local GameMovement = require(Shared:WaitForChild("GameMovement"))
local ConVars = GameMovement.ConVars

local player = Players.LocalPlayer

local TICK_INTERVAL = 0.015 -- Source default 66.67 tick
local MAX_TICKS_PER_FRAME = 8
local RENDER_STEP_NAME = "BloxSDK_PlayerMovement"

------------------------------------------------------------------------
-- ConVars
------------------------------------------------------------------------

local ARCHIVE = Cvar.FCVAR_ARCHIVE
local CHEAT = Cvar.FCVAR_CHEAT

local sensitivity = Cvar.ConVar("sensitivity", 3, ARCHIVE, "Mouse sensitivity.", 0.0001, 10000)
local m_yaw = Cvar.ConVar("m_yaw", 0.022, ARCHIVE, "Mouse yaw factor.")
local m_pitch = Cvar.ConVar("m_pitch", 0.022, ARCHIVE, "Mouse pitch factor.")
local fov_desired = Cvar.ConVar("fov_desired", 90, ARCHIVE, "Sets the base field-of-view (horizontal, 4:3).", 20, 130)
local cl_forwardspeed = Cvar.ConVar("cl_forwardspeed", 450, CHEAT, "")
local cl_sidespeed = Cvar.ConVar("cl_sidespeed", 450, CHEAT, "")
local cl_upspeed = Cvar.ConVar("cl_upspeed", 320, CHEAT, "")
local hl2_normspeed = Cvar.ConVar("hl2_normspeed", 190, 0, "Normal run speed.")
local hl2_sprintspeed = Cvar.ConVar("hl2_sprintspeed", 320, 0, "Sprint speed.")
local hl2_walkspeed = Cvar.ConVar("hl2_walkspeed", 150, 0, "Walk speed.")
local smoothstairs = Cvar.ConVar("smoothstairs", 1, 0, "Smooth player eye z coordinate when traversing stairs.", 0, 1)
local sv_falldamage = Cvar.ConVar("sv_falldamage", 1, Cvar.FCVAR_NOTIFY, "Apply HL2 fall damage.", 0, 1)
local cl_mouselock = Cvar.ConVar("cl_mouselock", 1, 0, "Lock the mouse to the centre for mouse look.", 0, 1)
local cl_drawhud = Cvar.ConVar("cl_drawhud", 1, CHEAT, "Enable the rendering of the hud.", 0, 1)
local cl_showspeed = Cvar.ConVar("cl_showspeed", 1, 0, "Show horizontal speed meter.", 0, 1)
local cl_showpos = Cvar.ConVar("cl_showpos", 0, 0, "Draw current position at top of screen.", 0, 2)
local cl_showfps = Cvar.ConVar("cl_showfps", 0, 0, "Draw fps meter at top of screen.", 0, 1)

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local movement = nil
local humanoid: Humanoid? = nil
local root: BasePart? = nil
local rootOffsetStuds = 3
local connections = {}
local hiddenParts = {}

local pitch, yaw = 0, 0
local accumulator = 0
local prevOrigin, currOrigin = Vector3.zero, Vector3.zero
local prevView, currView = GameMovement.VEC_VIEW, GameMovement.VEC_VIEW
local jumpQueued = false
local punchPitch = 0
local fpsSmoothed = 60

local smoothZ = 0
local smoothViewOffset = GameMovement.VEC_VIEW

local KEYS_FORWARD = { Enum.KeyCode.W }
local KEYS_BACK = { Enum.KeyCode.S }
local KEYS_LEFT = { Enum.KeyCode.A }
local KEYS_RIGHT = { Enum.KeyCode.D }
local KEYS_JUMP = { Enum.KeyCode.Space }
local KEYS_DUCK = { Enum.KeyCode.LeftControl, Enum.KeyCode.C }
local KEYS_SPEED = { Enum.KeyCode.LeftShift }
local KEYS_WALK = { Enum.KeyCode.LeftAlt }

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "BloxSDK_HUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 10

local function makeLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	for k, v in props do
		(label :: any)[k] = v
	end
	label.Parent = hud
	return label
end

local speedLabel = makeLabel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -64),
	Size = UDim2.fromOffset(300, 28),
	TextSize = 24,
})

local infoLabel = makeLabel({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -40),
	Size = UDim2.fromOffset(500, 20),
	TextSize = 16,
	TextColor3 = Color3.fromRGB(200, 200, 200),
})

local posLabel = makeLabel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 40),
	Size = UDim2.fromOffset(420, 80),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
})

local fpsLabel = makeLabel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 16),
	Size = UDim2.fromOffset(200, 20),
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Right,
})

local crosshair = Instance.new("Frame")
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Position = UDim2.fromScale(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(4, 4)
crosshair.BackgroundColor3 = Color3.new(1, 1, 1)
crosshair.BorderSizePixel = 0
crosshair.Parent = hud

hud.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function isDown(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function inputBlocked(): boolean
	return Cvar.consoleVisible or UserInputService:GetFocusedTextBox() ~= nil
end

local function getControls()
	local ok, controls = pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any)
		return playerModule:GetControls()
	end)
	return if ok then controls else nil
end

local function verticalFov(horizontalDeg: number): number
	-- Source fov is horizontal at 4:3, Roblox FieldOfView is vertical
	return math.deg(2 * math.atan(math.tan(math.rad(horizontalDeg) / 2) * 3 / 4))
end

local function refreshIgnoreList()
	if not movement then
		return
	end
	local list = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	movement:SetIgnoreList(list)
end

local function cacheHiddenParts(char: Model)
	table.clear(hiddenParts)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(hiddenParts, d)
		end
	end
end

local function snapInterpolation()
	if not movement then
		return
	end
	prevOrigin, currOrigin = movement.origin, movement.origin
	prevView, currView = movement.viewOffset, movement.viewOffset
	smoothZ = movement.origin.Y
	smoothViewOffset = movement.viewOffset
	accumulator = 0
end

local function buildCmd()
	local f, s, u = 0, 0, 0
	local blocked = inputBlocked()
	local noclip = movement and movement.noclip

	if not blocked then
		if isDown(KEYS_FORWARD) then f += cl_forwardspeed:GetFloat() end
		if isDown(KEYS_BACK) then f -= cl_forwardspeed:GetFloat() end
		if isDown(KEYS_RIGHT) then s += cl_sidespeed:GetFloat() end
		if isDown(KEYS_LEFT) then s -= cl_sidespeed:GetFloat() end
		if noclip then
			if isDown(KEYS_JUMP) then u += cl_upspeed:GetFloat() end
			if isDown(KEYS_DUCK) then u -= cl_upspeed:GetFloat() end
		end
	end

	local sprint = not blocked and isDown(KEYS_SPEED)
	local walk = not blocked and isDown(KEYS_WALK)
	local maxspeed = if sprint
		then hl2_sprintspeed:GetFloat()
		elseif walk then hl2_walkspeed:GetFloat()
		else hl2_normspeed:GetFloat()

	local cmd = {
		forwardmove = f,
		sidemove = s,
		upmove = u,
		jump = not blocked and not noclip and (jumpQueued or isDown(KEYS_JUMP)),
		duck = not blocked and not noclip and isDown(KEYS_DUCK),
		sprint = sprint,
		maxspeed = maxspeed,
		pitch = pitch,
		yaw = yaw,
	}
	jumpQueued = false
	return cmd
end

------------------------------------------------------------------------
-- Simulation + render
------------------------------------------------------------------------

local function runTick()
	local cmd = buildCmd()

	prevOrigin = currOrigin
	prevView = currView

	movement:ProcessMovement(cmd, TICK_INTERVAL)

	if movement.carryYaw ~= 0 then
		yaw += movement.carryYaw
	end

	currOrigin = movement.origin
	currView = movement.viewOffset

	local ups = ConVars.units_per_stud
	if humanoid and humanoid.Health > 0 and currOrigin.Y / ups < Workspace.FallenPartsDestroyHeight then
		humanoid.Health = 0
	end
end

local function updateHud(dt: number)
	local drawHud = cl_drawhud:GetBool()
	hud.Enabled = drawHud
	if not drawHud then
		return
	end

	local v = movement.velocity
	local showSpeed = cl_showspeed:GetBool()
	speedLabel.Visible = showSpeed
	infoLabel.Visible = showSpeed
	if showSpeed then
		speedLabel.Text = string.format("%d u/s", math.floor(math.sqrt(v.X * v.X + v.Z * v.Z) + 0.5))
		infoLabel.Text = string.format(
			"%s  %s  vz %d",
			if movement.noclip then "NOCLIP" elseif movement.onGround then "GROUND" else "AIR",
			if movement.ducked then "DUCKED" elseif movement.duckAmount > 0 then "DUCKING" else "STAND",
			math.floor(v.Y + 0.5)
		)
	end

	local showPos = cl_showpos:GetInt()
	posLabel.Visible = showPos ~= 0
	if showPos ~= 0 then
		local o = if showPos == 2 then movement.origin + Vector3.new(0, movement.viewOffset, 0) else movement.origin
		posLabel.Text = string.format(
			"name: %s\npos:  %.2f %.2f %.2f\nang:  %.2f %.2f %.2f\nvel:  %.2f",
			player.Name,
			o.X, o.Y, o.Z,
			pitch, yaw, 0,
			v.Magnitude
		)
	end

	local showFps = cl_showfps:GetBool()
	fpsLabel.Visible = showFps
	if showFps then
		fpsSmoothed += ((1 / math.max(dt, 1e-4)) - fpsSmoothed) * 0.1
		fpsLabel.Text = string.format("%d fps", math.floor(fpsSmoothed + 0.5))
	end
end

local function render(dt: number)
	if not movement or not root then
		return
	end

	local ups = ConVars.units_per_stud
	local camera = Workspace.CurrentCamera

	-- mouse look
	if cl_mouselock:GetBool() and not inputBlocked() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
		local sens = sensitivity:GetFloat()
		yaw -= delta.X * sens * m_yaw:GetFloat()
		pitch = math.clamp(pitch - delta.Y * sens * m_pitch:GetFloat(), -89, 89)
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	yaw %= 360

	-- fixed tick
	accumulator = math.min(accumulator + dt, TICK_INTERVAL * MAX_TICKS_PER_FRAME)
	while accumulator >= TICK_INTERVAL do
		accumulator -= TICK_INTERVAL
		runTick()
		if not movement then
			return
		end
	end

	local alpha = accumulator / TICK_INTERVAL
	local origin = prevOrigin:Lerp(currOrigin, alpha)
	local viewOffset = prevView + (currView - prevView) * alpha

	-- C_BasePlayer::SmoothViewOnStairs
	local z = origin.Y
	local groundStatic = movement.platformVelocity.Magnitude < 1
	if smoothstairs:GetBool() and movement.onGround and groundStatic and z ~= smoothZ and viewOffset == smoothViewOffset then
		local dir = if z > smoothZ then 1 else -1
		local stepSize = ConVars.sv_stepsize
		smoothZ += dt * 150 * dir
		if dir > 0 then
			if smoothZ > z then smoothZ = z end
			if z - smoothZ > stepSize then smoothZ = z - stepSize end
		else
			if smoothZ < z then smoothZ = z end
			if smoothZ - z > stepSize then smoothZ = z + stepSize end
		end
	else
		smoothZ = z
		smoothViewOffset = viewOffset
	end

	-- punch decay
	punchPitch *= math.exp(-dt * 8)
	if math.abs(punchPitch) < 0.01 then
		punchPitch = 0
	end

	local eye = Vector3.new(origin.X, smoothZ + viewOffset, origin.Z) / ups
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = verticalFov(fov_desired:GetFloat())
	camera.CFrame = CFrame.new(eye) * CFrame.fromOrientation(math.rad(pitch + punchPitch), math.rad(yaw), 0)

	-- body follows feet + view yaw
	root.CFrame = CFrame.new(origin / ups + Vector3.new(0, rootOffsetStuds, 0)) * CFrame.Angles(0, math.rad(yaw), 0)

	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 1
	end

	updateHud(dt)
end

------------------------------------------------------------------------
-- Character lifecycle
------------------------------------------------------------------------

local function teardown()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if movement then
		movement:Destroy()
		movement = nil
	end
	table.clear(hiddenParts)
	humanoid, root = nil, nil
end

local function onDied()
	local deadRoot = root
	teardown()
	if deadRoot then
		deadRoot.Anchored = false
	end
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

local function onCharacterAdded(char: Model)
	teardown()

	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	-- let the spawn location settle
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	if char.Parent == nil or hum.Health <= 0 then
		return
	end

	humanoid, root = hum, hrp

	rootOffsetStuds = if hum.RigType == Enum.HumanoidRigType.R15 then hum.HipHeight + hrp.Size.Y / 2 else 3

	local controls = getControls()
	if controls then
		controls:Disable()
	end

	hum.AutoRotate = false
	hum:ChangeState(Enum.HumanoidStateType.Physics)
	hrp.Anchored = true
	hrp.AssemblyLinearVelocity = Vector3.zero

	movement = GameMovement.new()
	refreshIgnoreList()

	movement.OnLand = function(fallSpeed: number)
		punchPitch = -math.min(fallSpeed / 100, 8)
		if sv_falldamage:GetBool() and humanoid then
			local dmg = GameMovement.GetFallDamage(fallSpeed)
			if dmg > 0 then
				humanoid:TakeDamage(dmg)
			end
		end
	end

	local ups = ConVars.units_per_stud
	local feet = hrp.Position - Vector3.new(0, rootOffsetStuds, 0)
	local _, ry = hrp.CFrame:ToOrientation()
	yaw = math.deg(ry)
	pitch = 0
	punchPitch = 0

	movement:Teleport(feet * ups + Vector3.new(0, 1, 0))
	snapInterpolation()

	cacheHiddenParts(char)
	table.insert(connections, char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(hiddenParts, d)
		end
	end))
	table.insert(connections, hum.Died:Connect(onDied))

	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, render)
end

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------

Cvar.ConCommand("noclip", function()
	if not movement then
		return
	end
	movement:SetNoclip(not movement.noclip)
	snapInterpolation()
	Cvar.Msg(if movement.noclip then "noclip ON" else "noclip OFF")
end, "Toggle. Player becomes non-solid and flies.", CHEAT)

Cvar.ConCommand("kill", function()
	if humanoid then
		humanoid.Health = 0
	end
end, "Kills the player with generic damage")

Cvar.ConCommand("getpos", function()
	if not movement then
		return
	end
	local o = movement.origin
	Cvar.Msg(string.format("setpos %.6f %.6f %.6f;setang %.6f %.6f %.6f", o.X, o.Y, o.Z, pitch, yaw, 0))
end, "dump position and angles to the console")

Cvar.ConCommand("setpos", function(args)
	if not movement then
		return
	end
	if args:ArgC() < 3 then
		Cvar.Msg("Usage:  setpos x y <z optional>")
		return
	end
	local o = movement.origin
	local x = tonumber(args:Arg(1)) or o.X
	local y = tonumber(args:Arg(2)) or o.Y
	local z = if args:ArgC() >= 4 then tonumber(args:Arg(3)) or o.Z else o.Z
	if movement.noclip then
		movement.origin = Vector3.new(x, y, z)
		movement.velocity = Vector3.zero
	else
		movement:Teleport(Vector3.new(x, y, z))
	end
	snapInterpolation()
end, "Move player to specified origin (must have sv_cheats).", CHEAT)

Cvar.ConCommand("setang", function(args)
	if args:ArgC() < 3 then
		Cvar.Msg("Usage:  setang pitch yaw <roll optional>")
		return
	end
	pitch = math.clamp(tonumber(args:Arg(1)) or pitch, -89, 89)
	yaw = tonumber(args:Arg(2)) or yaw
end, "Snap player eyes to specified pitch yaw <roll:optional> (must have sv_cheats).", CHEAT)

------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or inputBlocked() then
		return
	end
	if table.find(KEYS_JUMP, input.KeyCode) then
		jumpQueued = true
	end
end)

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------

local function watchPlayer(plr: Player)
	plr.CharacterAdded:Connect(function()
		task.defer(refreshIgnoreList)
	end)
end
for _, plr in Players:GetPlayers() do
	watchPlayer(plr)
end
Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshIgnoreList)
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
