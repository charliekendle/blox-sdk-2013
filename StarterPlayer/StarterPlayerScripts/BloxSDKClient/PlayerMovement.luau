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
	  V           toggle noclip
	  M           toggle mouse lock
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameMovement = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("GameMovement"))
local ConVars = GameMovement.ConVars

local player = Players.LocalPlayer

local TICK_INTERVAL = 0.015 -- Source default 66.67 tick
local MAX_TICKS_PER_FRAME = 8
local RENDER_STEP_NAME = "BloxSDK_PlayerMovement"

local cl = {
	sensitivity = 3,
	m_yaw = 0.022,
	m_pitch = 0.022,
	forwardspeed = 450,
	sidespeed = 450,
	upspeed = 320,
	fov = 90, -- horizontal FOV at 4:3, like Source's fov_desired
	normspeed = 190, -- hl2_normspeed
	sprintspeed = 320, -- hl2_sprintspeed
	walkspeed = 150, -- hl2_walkspeed
	smoothstairs = true,
	falldamage = true,
	showhud = true,
}

local Binds = {
	forward = { Enum.KeyCode.W },
	back = { Enum.KeyCode.S },
	moveleft = { Enum.KeyCode.A },
	moveright = { Enum.KeyCode.D },
	jump = { Enum.KeyCode.Space },
	duck = { Enum.KeyCode.LeftControl, Enum.KeyCode.C },
	speed = { Enum.KeyCode.LeftShift },
	walk = { Enum.KeyCode.LeftAlt },
	noclip = Enum.KeyCode.V,
	togglemouse = Enum.KeyCode.M,
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

local movement = nil
local character: Model? = nil
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
local mouseLocked = true
local punchPitch = 0

local smoothZ = 0
local smoothViewOffset = GameMovement.VEC_VIEW

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------

local hud = Instance.new("ScreenGui")
hud.Name = "BloxSDK_HUD"
hud.ResetOnSpawn = false
hud.IgnoreGuiInset = true
hud.DisplayOrder = 10

local speedLabel = Instance.new("TextLabel")
speedLabel.AnchorPoint = Vector2.new(0.5, 1)
speedLabel.Position = UDim2.new(0.5, 0, 1, -64)
speedLabel.Size = UDim2.fromOffset(300, 28)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.Code
speedLabel.TextSize = 24
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextStrokeTransparency = 0.4
speedLabel.Text = ""
speedLabel.Parent = hud

local infoLabel = Instance.new("TextLabel")
infoLabel.AnchorPoint = Vector2.new(0.5, 1)
infoLabel.Position = UDim2.new(0.5, 0, 1, -40)
infoLabel.Size = UDim2.fromOffset(500, 20)
infoLabel.BackgroundTransparency = 1
infoLabel.Font = Enum.Font.Code
infoLabel.TextSize = 16
infoLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
infoLabel.TextStrokeTransparency = 0.5
infoLabel.Text = ""
infoLabel.Parent = hud

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

local function buildCmd()
	local f, s, u = 0, 0, 0
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local noclip = movement and movement.noclip

	if not typing then
		if isDown(Binds.forward) then f += cl.forwardspeed end
		if isDown(Binds.back) then f -= cl.forwardspeed end
		if isDown(Binds.moveright) then s += cl.sidespeed end
		if isDown(Binds.moveleft) then s -= cl.sidespeed end
		if noclip then
			if isDown(Binds.jump) then u += cl.upspeed end
			if isDown(Binds.duck) then u -= cl.upspeed end
		end
	end

	local sprint = not typing and isDown(Binds.speed)
	local walk = not typing and isDown(Binds.walk)
	local maxspeed = if sprint then cl.sprintspeed elseif walk then cl.walkspeed else cl.normspeed

	local cmd = {
		forwardmove = f,
		sidemove = s,
		upmove = u,
		jump = not typing and not noclip and (jumpQueued or isDown(Binds.jump)),
		duck = not typing and not noclip and isDown(Binds.duck),
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

local function render(dt: number)
	if not movement or not root then
		return
	end

	local ups = ConVars.units_per_stud
	local camera = Workspace.CurrentCamera

	-- mouse look
	if mouseLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		local delta = UserInputService:GetMouseDelta()
		yaw -= delta.X * cl.sensitivity * cl.m_yaw
		pitch = math.clamp(pitch - delta.Y * cl.sensitivity * cl.m_pitch, -89, 89)
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
	if cl.smoothstairs and movement.onGround and groundStatic and z ~= smoothZ and viewOffset == smoothViewOffset then
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
	camera.FieldOfView = verticalFov(cl.fov)
	camera.CFrame = CFrame.new(eye) * CFrame.fromOrientation(math.rad(pitch + punchPitch), math.rad(yaw), 0)

	-- body follows feet + view yaw
	root.CFrame = CFrame.new(origin / ups + Vector3.new(0, rootOffsetStuds, 0)) * CFrame.Angles(0, math.rad(yaw), 0)

	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 1
	end

	-- HUD
	hud.Enabled = cl.showhud
	if cl.showhud then
		local v = movement.velocity
		speedLabel.Text = string.format("%d u/s", math.floor(math.sqrt(v.X * v.X + v.Z * v.Z) + 0.5))
		infoLabel.Text = string.format(
			"%s  %s  vz %d  %s",
			if movement.noclip then "NOCLIP" elseif movement.onGround then "GROUND" else "AIR",
			if movement.ducked then "DUCKED" elseif movement.duckAmount > 0 then "DUCKING" else "STAND",
			math.floor(v.Y + 0.5),
			if mouseLocked then "" else "[mouse free]"
		)
	end
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
	character, humanoid, root = nil, nil, nil
end

local function onDied()
	local deadRoot = root
	teardown()
	if deadRoot then
		deadRoot.Anchored = false
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
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

	character, humanoid, root = char, hum, hrp

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
		if cl.falldamage and humanoid then
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
	accumulator = 0

	movement:Teleport(feet * ups + Vector3.new(0, 1, 0))
	prevOrigin, currOrigin = movement.origin, movement.origin
	prevView, currView = movement.viewOffset, movement.viewOffset
	smoothZ = movement.origin.Y
	smoothViewOffset = movement.viewOffset

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
-- Input
------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end
	local key = input.KeyCode
	if table.find(Binds.jump, key) then
		jumpQueued = true
	elseif key == Binds.noclip then
		if movement then
			movement:SetNoclip(not movement.noclip)
			prevOrigin, currOrigin = movement.origin, movement.origin
		end
	elseif key == Binds.togglemouse then
		mouseLocked = not mouseLocked
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
