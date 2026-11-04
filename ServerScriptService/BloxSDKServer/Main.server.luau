--!optimize 2
--[[
	BloxSDK server (Script)
	ServerScriptService.BloxSDKServer.Main

	Boots the entity system:
	  1. every instance in Workspace with a "classname" Attribute becomes an entity
	     (CreateEntityByName -> keyvalues from Attributes -> Spawn), then all Activate
	  2. each Heartbeat: g_EventQueue, thinks, movers/rotators, touch
	Entities added to Workspace later (e.g. cloned in) spawn on the fly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- don't run from wherever the .rbxm was dropped; it has to live in ServerScriptService
if not script:IsDescendantOf(ServerScriptService) then
	warn("[BloxSDK] Main must be inside ServerScriptService - move BloxSDKServer there")
	return
end

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local Cvar = require(Shared:WaitForChild("ConVar"))
local Net = require(Shared:WaitForChild("Net"))
require(Shared:WaitForChild("GameMovement")) -- registers the movement convars on the server

Net.Init()

local Game = script.Parent:WaitForChild("Game")
local EntityList = require(Game:WaitForChild("EntityList"))
local EntityIO = require(Game:WaitForChild("EntityIO"))
local BaseToggle = require(Game:WaitForChild("BaseToggle"))
local TouchSystem = require(Game:WaitForChild("TouchSystem"))
local PlayerManager = require(Game:WaitForChild("PlayerManager"))
local ConVarServer = require(Game:WaitForChild("ConVarServer"))
local EntityCommands = require(Game:WaitForChild("EntityCommands"))

-- entity classes register themselves with the factory when required
local entitiesFolder = Game:WaitForChild("Entities")
local Doors = nil
for _, module in entitiesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if not ok then
			warn("[BloxSDK] failed to load entity module " .. module.Name .. ": " .. tostring(result))
		elseif module.Name == "Doors" then
			Doors = result
		end
	end
end

-- brush volumes handled entirely on the client by GameMovement
local CLIENT_ONLY = { func_water = true, func_ladder = true }

-- point entity prefixes: their marker part is hidden at spawn
local POINT_PREFIXES = { "logic_", "math_", "filter_", "info_", "point_", "game_", "ambient_", "env_" }

local function isPointClass(classname: string): boolean
	for _, prefix in POINT_PREFIXES do
		if classname:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local spawned: { [Instance]: boolean } = {}

local function readClassname(inst: Instance): string?
	local cls = inst:GetAttribute("classname")
	if type(cls) ~= "string" or cls == "" then
		return nil
	end
	return string.lower(cls)
end

-- DispatchSpawn without Activate
local function createFromInstance(inst: Instance): any?
	if spawned[inst] then
		return nil
	end
	local classname = readClassname(inst)
	if not classname or CLIENT_ONLY[classname] then
		return nil
	end
	-- a part inside a Model entity belongs to that model
	local parent = inst.Parent
	while parent and parent ~= Workspace do
		if spawned[parent] then
			return nil
		end
		parent = parent.Parent
	end

	local ent = EntityList.CreateEntityByName(classname, inst)
	if not ent then
		Cvar.Warning(string.format("Can't create entity of class \"%s\" (%s)", classname, inst:GetFullName()))
		return nil
	end

	spawned[inst] = true
	ent:ReadAttributes()
	EntityList.Add(ent)

	local ok, err = pcall(function()
		ent:Precache()
		ent:Spawn()
		if isPointClass(classname) then
			ent:HideBrush()
		end
	end)
	if not ok then
		Cvar.Warning(string.format("%s(%s) Spawn error: %s", classname, ent.targetname, tostring(err)))
	end

	inst.Destroying:Connect(function()
		spawned[inst] = nil
		if not ent.removed then
			ent.destroyInstance = false
			ent:Remove()
		end
	end)
	return ent
end

local function activate(ent: any)
	local ok, err = pcall(ent.Activate, ent)
	if not ok then
		Cvar.Warning(string.format("%s(%s) Activate error: %s", ent.classname, ent.targetname, tostring(err)))
	end
end

------------------------------------------------------------------------
-- boot
------------------------------------------------------------------------

ConVarServer.Init()
EntityCommands.Init()
PlayerManager.Init()
BaseToggle.GetLivingPlayers = PlayerManager.GetLivingPlayers

-- sort so Models spawn before their descendant parts get a chance to (createFromInstance skips them)
local candidates = {}
for _, inst in Workspace:GetDescendants() do
	if readClassname(inst) then
		table.insert(candidates, inst)
	end
end
table.sort(candidates, function(a, b)
	local da, db = 0, 0
	local p = a.Parent
	while p do
		da += 1
		p = p.Parent
	end
	p = b.Parent
	while p do
		db += 1
		p = p.Parent
	end
	return da < db
end)

local created = {}
for _, inst in candidates do
	local ent = createFromInstance(inst)
	if ent then
		table.insert(created, ent)
	end
end
for _, ent in created do
	activate(ent)
end

Cvar.Msg(string.format("BloxSDK: spawned %d entities", #created))

-- late additions (clones, streamed-in models, etc.)
Workspace.DescendantAdded:Connect(function(inst)
	task.defer(function()
		if inst.Parent and readClassname(inst) then
			local ent = createFromInstance(inst)
			if ent then
				activate(ent)
			end
		end
	end)
end)

------------------------------------------------------------------------
-- frame loop
------------------------------------------------------------------------

local TOUCH_INTERVAL = 1 / 30
local touchAccumulator = 0

RunService.Heartbeat:Connect(function(dt)
	local now = EntityIO.CurTime()

	-- g_EventQueue.ServiceEvents()
	EntityIO.ServiceEvents()

	-- thinks
	for _, ent in table.clone(EntityList.All()) do
		if not ent.removed and ent.nextThink and ent.nextThink <= now then
			local ok, err = pcall(ent.RunThink, ent, now)
			if not ok then
				Cvar.Warning(string.format("%s(%s) think error: %s", ent.classname, ent.targetname, tostring(err)))
			end
		end
	end

	-- moving brushes
	BaseToggle.ServiceMovers(dt)
	if Doors and Doors.FuncRotating then
		Doors.FuncRotating.ServiceRotators(dt)
	end

	-- touch
	touchAccumulator += dt
	if touchAccumulator >= TOUCH_INTERVAL then
		touchAccumulator = 0
		TouchSystem.Service(PlayerManager.GetLivingPlayers())
	end
end)
