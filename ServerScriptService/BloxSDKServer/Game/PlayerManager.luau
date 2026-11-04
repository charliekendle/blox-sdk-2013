--!optimize 2
--[[
	PlayerManager (ModuleScript)
	Wraps each Player as a "player" entity (CBasePlayer-lite) so they can be activators,
	touch triggers, be teleported/pushed/hurt, and +use things.

	Movement is client-side (GameMovement), so the client reports its hull every tick
	(PlayerState) and the server sends back movement effects (MovementEffect).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local MathLib = require(Shared:WaitForChild("MathLib"))
local GameMovement = require(Shared:WaitForChild("GameMovement"))

local Game = script.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local EntityList = require(Game:WaitForChild("EntityList"))

local PlayerManager = {}

local PLAYER_USE_RADIUS = 96 -- units
local MAX_EYE_ERROR_STUDS = 12

local byPlayer: { [Player]: any } = {}

------------------------------------------------------------------------
-- player entity
------------------------------------------------------------------------

local PlayerEntity = BaseEntity.extend("player")
PlayerManager.PlayerEntity = PlayerEntity

function PlayerEntity:Init(instance)
	PlayerEntity.super.Init(self, instance)
	self.destroyInstance = false
	self.player = nil :: Player?
	self.state = {
		origin = Vector3.zero,
		velocity = Vector3.zero,
		ducked = false,
		onGround = false,
		pitch = 0,
		yaw = 0,
	}
	self.hasState = false
	self.teleportSeq = 0
	self.pushes = {}
end

function PlayerEntity:IsPlayer(): boolean
	return true
end

function PlayerEntity:GetHumanoid(): Humanoid?
	local char = self.player and self.player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function PlayerEntity:IsAlive(): boolean
	local hum = self:GetHumanoid()
	return hum ~= nil and hum.Health > 0 and self.hasState
end

function PlayerEntity:GetAbsOrigin(): Vector3
	return self.state.origin
end

function PlayerEntity:GetPivot(): CFrame
	local ups = MathLib.UnitsPerStud()
	return CFrame.new(self.state.origin / ups) * CFrame.Angles(0, math.rad(self.state.yaw), 0)
end

function PlayerEntity:SetPivot(cf: CFrame)
	local _, ry = cf:ToOrientation()
	self:Teleport(cf.Position * MathLib.UnitsPerStud(), math.deg(ry), nil)
end

function PlayerEntity:WorldSpaceCenter(): Vector3
	local h = if self.state.ducked then GameMovement.VEC_DUCK_HULL_MAX.Y else GameMovement.VEC_HULL_MAX.Y
	return self.state.origin + Vector3.new(0, h / 2, 0)
end

function PlayerEntity:EyePosition(): Vector3
	local view = if self.state.ducked then GameMovement.VEC_DUCK_VIEW else GameMovement.VEC_VIEW
	return self.state.origin + Vector3.new(0, view, 0)
end

-- hull as an axis-aligned box in studs (centre, half size)
function PlayerEntity:GetHullBox(marginUnits: number?): (Vector3, Vector3)
	local ups = MathLib.UnitsPerStud()
	local maxs = if self.state.ducked then GameMovement.VEC_DUCK_HULL_MAX else GameMovement.VEC_HULL_MAX
	local mins = GameMovement.VEC_HULL_MIN
	local m = marginUnits or 0
	local center = (self.state.origin + (mins + maxs) * 0.5) / ups
	local half = ((maxs - mins) * 0.5 + Vector3.new(m, m, m)) / ups
	return center, half
end

-- Teleport( origin, yaw, velocity ). nil leaves that part alone, like CBaseEntity::Teleport
function PlayerEntity:Teleport(origin: Vector3?, yaw: number?, velocity: Vector3?)
	if not self.player then
		return
	end
	self.teleportSeq += 1
	if origin then
		self.state.origin = origin
	end
	if velocity then
		self.state.velocity = velocity
	end
	Net.Get("MovementEffect"):FireClient(self.player, "teleport", {
		seq = self.teleportSeq,
		origin = origin,
		yaw = yaw,
		velocity = velocity,
	})
end

-- trigger_push style base velocity; nil velocity clears that source
function PlayerEntity:SetPush(source: any, velocity: Vector3?)
	if not self.player then
		return
	end
	local key = source.entindex
	if self.pushes[key] == velocity then
		return
	end
	self.pushes[key] = velocity
	Net.Get("MovementEffect"):FireClient(self.player, "push", { id = key, velocity = velocity })
end

function PlayerEntity:ClearPushes()
	table.clear(self.pushes)
	if self.player then
		Net.Get("MovementEffect"):FireClient(self.player, "clearpush", {})
	end
end

function PlayerEntity:ApplyAbsVelocityImpulse(velocity: Vector3)
	if self.player then
		Net.Get("MovementEffect"):FireClient(self.player, "impulse", { velocity = velocity })
	end
end

function PlayerEntity:TakeDamage(info)
	local hum = self:GetHumanoid()
	if hum and hum.Health > 0 and info.damage > 0 then
		hum:TakeDamage(info.damage)
	end
end

function PlayerEntity:Remove()
	-- players are never removed by I/O
end

PlayerEntity.Inputs.kill = function(self)
	local hum = self:GetHumanoid()
	if hum then
		hum.Health = 0
	end
end

PlayerEntity.Inputs.sethealth = function(self, data)
	local hum = self:GetHumanoid()
	if hum then
		hum.Health = math.clamp(data.value:Float(), 0, hum.MaxHealth)
	end
end

PlayerEntity.Inputs.setmaxhealth = function(self, data)
	local hum = self:GetHumanoid()
	if hum then
		hum.MaxHealth = math.max(data.value:Float(), 1)
	end
end

------------------------------------------------------------------------
-- traces
------------------------------------------------------------------------

local function charactersFilter(): { Instance }
	local list = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	return list
end

-- first entity hit along a ray (skips non-entity non-collidable parts)
local function traceEntity(fromStuds: Vector3, dirStuds: Vector3, wantUsable: boolean): (any?, RaycastResult?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false
	local filter = charactersFilter()
	params.FilterDescendantsInstances = filter

	local origin = fromStuds
	local remaining = dirStuds
	for _ = 1, 8 do
		local result = Workspace:Raycast(origin, remaining, params)
		if not result then
			return nil, nil
		end
		local ent = EntityList.FromInstance(result.Instance)
		local part = result.Instance :: BasePart
		if ent and (not wantUsable or ent:IsUsable()) then
			return ent, result
		end
		if part.CanCollide and not ent then
			-- hit the world
			return nil, result
		end
		table.insert(filter, result.Instance)
		params.FilterDescendantsInstances = filter
	end
	return nil, nil
end

local function viewDirection(state): Vector3
	return CFrame.fromOrientation(math.rad(state.pitch), math.rad(state.yaw), 0).LookVector
end

function PlayerManager.FindUseEntity(playerEnt: any, eyeStuds: Vector3?, dir: Vector3?): any?
	local ups = MathLib.UnitsPerStud()
	local eye = eyeStuds or playerEnt:EyePosition() / ups
	local look = dir or viewDirection(playerEnt.state)
	return (traceEntity(eye, look.Unit * (PLAYER_USE_RADIUS / ups), true))
end

-- !picker: whatever is under the crosshair
EntityList.PickerResolver = function(activator: any): any?
	if not activator or not activator.IsPlayer or not activator:IsPlayer() then
		return nil
	end
	local ups = MathLib.UnitsPerStud()
	local eye = activator:EyePosition() / ups
	return (traceEntity(eye, viewDirection(activator.state) * 1024, false))
end

------------------------------------------------------------------------
-- spawning
------------------------------------------------------------------------

-- set by Points.luau to include info_player_deathmatch etc.
PlayerManager.SpawnPointProvider = nil :: (() -> { any })?

local function pickSpawnPoint(): any?
	local provider = PlayerManager.SpawnPointProvider
	local starts = if provider then provider() else EntityList.FindAllByClassname("info_player_start")
	if #starts == 0 then
		return nil
	end
	-- prefer the master spawn (spawnflag 1)
	for _, ent in starts do
		if ent:HasSpawnFlags(1) and not ent.disabled then
			return ent
		end
	end
	local enabled = {}
	for _, ent in starts do
		if not ent.disabled then
			table.insert(enabled, ent)
		end
	end
	if #enabled == 0 then
		return nil
	end
	return enabled[math.random(1, #enabled)]
end

local function onCharacterAdded(playerEnt: any, char: Model)
	playerEnt.hasState = false
	table.clear(playerEnt.pushes)

	local spawn = pickSpawnPoint()
	if spawn then
		local pivot = spawn:GetPivot()
		local _, ry = pivot:ToOrientation()
		task.defer(function()
			if char.Parent then
				char:PivotTo(CFrame.new(pivot.Position + Vector3.new(0, 3, 0)) * CFrame.Angles(0, ry, 0))
			end
		end)
		task.delay(0.3, function()
			if char.Parent and playerEnt.player and playerEnt.player.Character == char then
				playerEnt:Teleport(spawn:GetAbsOrigin() + Vector3.new(0, 1, 0), math.deg(ry), Vector3.zero)
			end
		end)
	end

	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root and not playerEnt.hasState then
		playerEnt.state.origin = (root.Position - Vector3.new(0, 3, 0)) * MathLib.UnitsPerStud()
	end
end

local function addPlayer(plr: Player)
	local ent = PlayerEntity.new(nil)
	ent.classname = "player"
	ent.player = plr
	EntityList.Add(ent)
	byPlayer[plr] = ent

	plr.CharacterAdded:Connect(function(char)
		onCharacterAdded(ent, char)
	end)
	if plr.Character then
		task.spawn(onCharacterAdded, ent, plr.Character)
	end
end

local function removePlayer(plr: Player)
	local ent = byPlayer[plr]
	if ent then
		byPlayer[plr] = nil
		ent.removed = true
		EntityList.Remove(ent)
	end
end

------------------------------------------------------------------------
-- API
------------------------------------------------------------------------

function PlayerManager.ForPlayer(plr: Player?): any?
	return plr and byPlayer[plr]
end

function PlayerManager.GetPlayerEntities(): { any }
	local list = {}
	for _, ent in byPlayer do
		table.insert(list, ent)
	end
	return list
end

function PlayerManager.GetLivingPlayers(): { any }
	local list = {}
	for _, ent in byPlayer do
		if ent:IsAlive() then
			table.insert(list, ent)
		end
	end
	return list
end

function PlayerManager.Init()
	Net.Get("PlayerState").OnServerEvent:Connect(function(plr, origin, velocity, ducked, onGround, pitch, yaw, seq)
		local ent = byPlayer[plr]
		if not ent then
			return
		end
		if typeof(origin) ~= "Vector3" or typeof(velocity) ~= "Vector3" then
			return
		end
		if type(seq) ~= "number" or seq < ent.teleportSeq then
			-- stale: sent before the client applied our last teleport
			return
		end
		local state = ent.state
		state.origin = origin
		state.velocity = velocity
		state.ducked = ducked == true
		state.onGround = onGround == true
		state.pitch = if type(pitch) == "number" then pitch else 0
		state.yaw = if type(yaw) == "number" then yaw else 0
		ent.hasState = true
	end)

	Net.Get("Use").OnServerEvent:Connect(function(plr, eye, dir)
		local ent = byPlayer[plr]
		if not ent or not ent:IsAlive() then
			return
		end
		if typeof(eye) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then
			return
		end
		local ups = MathLib.UnitsPerStud()
		local expectedEye = ent:EyePosition() / ups
		if (eye - expectedEye).Magnitude > MAX_EYE_ERROR_STUDS then
			eye = expectedEye
		end
		local target = PlayerManager.FindUseEntity(ent, eye, dir)
		if target then
			target:Use(ent, ent, 0, 0)
		end
	end)

	for _, plr in Players:GetPlayers() do
		addPlayer(plr)
	end
	Players.PlayerAdded:Connect(addPlayer)
	Players.PlayerRemoving:Connect(removePlayer)
end

return PlayerManager
