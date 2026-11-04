--!optimize 2
--[[
	BaseEntity (ModuleScript) - port of CBaseEntity's I/O, keyvalue, think and lifecycle parts.

	Entities in Studio: any Part or Model with an Attribute  classname = "logic_relay" (etc).
	Every other Attribute is a keyvalue:  targetname, spawnflags, wait, speed, ...
	Outputs are Attributes named after the output, value "target,input,param,delay,times":
	    OnTrigger      = "door1,Open,,0,-1"
	    OnTrigger_2    = "relay2,Trigger"          (attribute names must be unique, so suffix _N)
	    or several in one attribute separated by "|"
	A Model entity = brush entity made of all its parts. A Part entity = brush made of that part,
	or a point entity (its position/rotation is the entity origin/angles).

	Subclassing:
	    local MyEnt = BaseEntity.extend("my_ent")      -- also registers the classname
	    MyEnt:DeclareOutputs({ "OnFoo" })
	    MyEnt.Inputs.dofoo = function(self, data) self:FireOutput("OnFoo", data.activator) end
	    function MyEnt:Spawn() MyEnt.super.Spawn(self) ... end
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local Cvar = require(Shared:WaitForChild("ConVar"))
local MathLib = require(Shared:WaitForChild("MathLib"))
local EntityList = require(script.Parent:WaitForChild("EntityList"))
local EntityIO = require(script.Parent:WaitForChild("EntityIO"))
local Variant = require(script.Parent:WaitForChild("Variant"))

local BaseEntity = {}
BaseEntity.__index = BaseEntity
BaseEntity.ClassName = "baseentity"
BaseEntity.Inputs = {}
BaseEntity.OutputNames = { "OnUser1", "OnUser2", "OnUser3", "OnUser4", "OnKilled" }

-- keys never treated as keyvalues
local IGNORED_ATTRIBUTES = { classname = true }

------------------------------------------------------------------------
-- Class plumbing
------------------------------------------------------------------------

function BaseEntity.extend(base: any, classname: string?)
	if type(base) == "string" then
		-- BaseEntity.extend("classname") shorthand
		classname = base
		base = BaseEntity
	end

	local class = setmetatable({}, { __index = base })
	class.__index = class
	class.super = base
	class.Inputs = setmetatable({}, { __index = base.Inputs })
	class.OutputNames = table.clone(base.OutputNames)

	function class.new(instance: Instance?)
		local self = setmetatable({}, class)
		self:Init(instance)
		return self
	end

	if classname then
		EntityList.LinkEntityToClass(classname, class)
	end
	return class
end

function BaseEntity:DeclareOutputs(names: { string })
	for _, name in names do
		if not table.find(self.OutputNames, name) then
			table.insert(self.OutputNames, name)
		end
	end
end

function BaseEntity.new(instance: Instance?)
	local self = setmetatable({}, BaseEntity)
	self:Init(instance)
	return self
end

function BaseEntity:Init(instance: Instance?)
	self.instance = instance
	self.classname = self.ClassName
	self.targetname = ""
	self.parentname = ""
	self.spawnflags = 0
	self.keyvalues = {}
	self.outputs = {}
	self.removed = false
	self.thinkFn = nil
	self.nextThink = nil
	self.children = {}
	self.moveParent = nil
	self.parentOffset = nil
	self.health = 0
	self.maxHealth = 0
	self.disabled = false
	self.parts = nil
	self.connections = {}

	for _, name in self.OutputNames do
		self.outputs[string.lower(name)] = EntityIO.NewOutput(name)
	end
end

------------------------------------------------------------------------
-- Keyvalues
------------------------------------------------------------------------

local function findOutputName(self, key: string): string?
	local lower = string.lower(key)
	if self.outputs[lower] then
		return lower
	end
	-- OnTrigger_2 / OnTrigger2 -> OnTrigger
	local stripped = lower:gsub("_?%d+$", "")
	if stripped ~= lower and self.outputs[stripped] then
		return stripped
	end
	return nil
end

-- returns true if handled
function BaseEntity:KeyValue(key: string, value: any): boolean
	local lower = string.lower(key)
	self.keyvalues[lower] = value

	if lower == "targetname" then
		self.targetname = tostring(value)
		return true
	elseif lower == "spawnflags" then
		self.spawnflags = tonumber(value) or 0
		return true
	elseif lower == "parentname" then
		self.parentname = tostring(value)
		return true
	elseif lower == "health" then
		self.health = tonumber(value) or 0
		self.maxHealth = self.health
		return true
	elseif lower == "startdisabled" then
		self.disabled = value == true or tonumber(value) == 1
		return true
	end

	local outputName = findOutputName(self, key)
	if outputName and type(value) == "string" then
		for connection in (value .. "|"):gmatch("(.-)[|\n]") do
			if connection:match("%S") then
				self.outputs[outputName]:ParseAndAdd(connection)
			end
		end
		return true
	end

	return false
end

function BaseEntity:ReadAttributes()
	local inst = self.instance
	if not inst then
		return
	end
	for key, value in inst:GetAttributes() do
		if not IGNORED_ATTRIBUTES[string.lower(key)] then
			self:KeyValue(key, value)
		end
	end
end

function BaseEntity:GetKey(key: string): any
	return self.keyvalues[string.lower(key)]
end

function BaseEntity:GetKeyString(key: string, default: string?): string
	local v = self.keyvalues[string.lower(key)]
	if v == nil then
		return default or ""
	end
	return tostring(v)
end

function BaseEntity:GetKeyFloat(key: string, default: number?): number
	local v = self.keyvalues[string.lower(key)]
	if type(v) == "boolean" then
		return if v then 1 else 0
	end
	return tonumber(v) or default or 0
end

function BaseEntity:GetKeyInt(key: string, default: number?): number
	return math.floor(self:GetKeyFloat(key, default))
end

function BaseEntity:GetKeyBool(key: string, default: boolean?): boolean
	local v = self.keyvalues[string.lower(key)]
	if v == nil then
		return default or false
	end
	if type(v) == "boolean" then
		return v
	end
	return (tonumber(v) or 0) ~= 0
end

function BaseEntity:HasSpawnFlags(flags: number): boolean
	return bit32.band(self.spawnflags, flags) ~= 0
end

function BaseEntity:AddSpawnFlags(flags: number)
	self.spawnflags = bit32.bor(self.spawnflags, flags)
end

function BaseEntity:RemoveSpawnFlags(flags: number)
	self.spawnflags = bit32.band(self.spawnflags, bit32.bnot(flags))
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function BaseEntity:Precache() end

-- after keyvalues, before Activate
function BaseEntity:Spawn() end

-- after every entity has spawned
function BaseEntity:Activate()
	if self.parentname ~= "" then
		local parent = EntityList.FindEntityByName(self.parentname, self)
		if parent then
			self:SetParent(parent)
		else
			Cvar.Warning(string.format("%s(%s) couldn't find parent %s", self.classname, self.targetname, self.parentname))
		end
	end
end

function BaseEntity:IsUsable(): boolean
	return false
end

function BaseEntity:Use(activator: any?, caller: any?, useType: number?, value: number?) end

function BaseEntity:IsPlayer(): boolean
	return false
end

function BaseEntity:IsTrigger(): boolean
	return false
end

-- UTIL_Remove
function BaseEntity:Remove()
	if self.removed then
		return
	end
	self.removed = true
	self.thinkFn = nil
	self.nextThink = nil

	if self.moveParent then
		local siblings = self.moveParent.children
		local i = table.find(siblings, self)
		if i then
			table.remove(siblings, i)
		end
		self.moveParent = nil
	end

	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)

	self:OnRemove()
	EntityList.Remove(self)

	if self.instance and self.destroyInstance ~= false then
		self.instance:Destroy()
	end
end

function BaseEntity:OnRemove() end

------------------------------------------------------------------------
-- Think
------------------------------------------------------------------------

function BaseEntity:SetThink(fn: ((any) -> ())?, delay: number?)
	self.thinkFn = fn
	if fn then
		self.nextThink = EntityIO.CurTime() + (delay or 0)
	else
		self.nextThink = nil
	end
end

function BaseEntity:SetNextThink(time: number?)
	self.nextThink = time
end

function BaseEntity:GetNextThink(): number?
	return self.nextThink
end

function BaseEntity:RunThink(now: number)
	local fn = self.thinkFn
	if fn and self.nextThink and self.nextThink <= now then
		self.nextThink = nil
		fn(self)
	end
end

------------------------------------------------------------------------
-- I/O
------------------------------------------------------------------------

function BaseEntity:GetOutput(name: string)
	return self.outputs[string.lower(name)]
end

function BaseEntity:FireOutput(name: string, activator: any?, value: any?, delay: number?)
	local output = self.outputs[string.lower(name)]
	if output then
		output:FireOutput(value, activator, self, delay)
	end
end

-- CBaseEntity::AcceptInput
function BaseEntity:AcceptInput(inputName: string, activator: any?, caller: any?, value: any?, outputId: number?): boolean
	if self.removed then
		return false
	end
	local handler = self.Inputs[string.lower(inputName)]
	if not handler then
		Cvar.DevMsg(2, string.format("Unhandled input: (%s) -> (%s,%s)", inputName, self.classname, self.targetname))
		return false
	end
	local variant = if type(value) == "table" and getmetatable(value) == Variant then value else Variant.new(value)
	local ok, err = pcall(handler, self, {
		activator = activator,
		caller = caller,
		value = variant,
		outputId = outputId or 0,
	})
	if not ok then
		Cvar.Warning(string.format("%s(%s).%s error: %s", self.classname, self.targetname, inputName, tostring(err)))
	end
	return true
end

-- Inputs available on every entity
BaseEntity.Inputs.kill = function(self)
	self:Remove()
end

BaseEntity.Inputs.killhierarchy = function(self)
	for _, child in table.clone(self.children) do
		child:AcceptInput("KillHierarchy", nil, self)
	end
	self:Remove()
end

for i = 1, 4 do
	BaseEntity.Inputs["fireuser" .. i] = function(self, data)
		self:FireOutput("OnUser" .. i, data.activator, data.value)
	end
end

BaseEntity.Inputs.use = function(self, data)
	self:Use(data.activator, data.caller, 0, 0)
end

-- AddOutput "keyname value" or "OnX target:input:param:delay:times"
BaseEntity.Inputs.addoutput = function(self, data)
	local text = data.value:String()
	local key, rest = text:match("^%s*(%S+)%s+(.*)$")
	if not key then
		return
	end
	if findOutputName(self, key) then
		rest = rest:gsub(":", ",")
	end
	self:KeyValue(key, rest)
	self:OnKeyValueChanged(string.lower(key))
end

BaseEntity.Inputs.setparent = function(self, data)
	local parent = EntityList.FindEntityByName(data.value:String(), self, data.activator, data.caller)
	if parent then
		self:SetParent(parent)
	end
end

BaseEntity.Inputs.clearparent = function(self)
	self:SetParent(nil)
end

BaseEntity.Inputs.color = function(self, data)
	local color = data.value:Color3()
	for _, part in self:GetParts() do
		part.Color = color
	end
end

BaseEntity.Inputs.alpha = function(self, data)
	local alpha = math.clamp(data.value:Float(), 0, 255)
	for _, part in self:GetParts() do
		part.Transparency = 1 - alpha / 255
	end
end

function BaseEntity:OnKeyValueChanged(key: string) end

------------------------------------------------------------------------
-- Geometry
------------------------------------------------------------------------

function BaseEntity:GetParts(): { BasePart }
	if self.parts then
		return self.parts
	end
	local parts = {}
	local inst = self.instance
	if inst then
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	self.parts = parts
	return parts
end

function BaseEntity:IsBrush(): boolean
	return #self:GetParts() > 0
end

function BaseEntity:GetPivot(): CFrame
	local inst = self.instance
	if inst and (inst:IsA("PVInstance")) then
		return (inst :: any):GetPivot()
	end
	return self.virtualPivot or CFrame.identity
end

-- moves the entity and anything parented to it
function BaseEntity:SetPivot(cf: CFrame)
	local inst = self.instance
	if inst and inst:IsA("PVInstance") then
		(inst :: any):PivotTo(cf)
	else
		self.virtualPivot = cf
	end
	for _, child in self.children do
		if child.parentOffset then
			child:SetPivot(cf * child.parentOffset)
		end
	end
end

function BaseEntity:SetParent(parent: any?)
	if self.moveParent then
		local siblings = self.moveParent.children
		local i = table.find(siblings, self)
		if i then
			table.remove(siblings, i)
		end
	end
	self.moveParent = parent
	if parent then
		table.insert(parent.children, self)
		self.parentOffset = parent:GetPivot():ToObjectSpace(self:GetPivot())
	else
		self.parentOffset = nil
	end
end

-- origin in Source units (Roblox axes), the same space GameMovement uses
function BaseEntity:GetAbsOrigin(): Vector3
	return self:GetPivot().Position * MathLib.UnitsPerStud()
end

function BaseEntity:WorldSpaceCenter(): Vector3
	local inst = self.instance
	if inst and inst:IsA("Model") then
		local cf = inst:GetBoundingBox()
		return cf.Position * MathLib.UnitsPerStud()
	end
	return self:GetAbsOrigin()
end

-- yaw in Roblox convention (degrees about +Y, 0 = facing -Z)
function BaseEntity:GetYaw(): number
	local _, ry = self:GetPivot():ToOrientation()
	return math.deg(ry)
end

-- size projected onto a direction (studs), for door/button travel distances
function BaseEntity:ExtentAlong(dir: Vector3): number
	local inst = self.instance
	local cf, size
	if inst and inst:IsA("Model") then
		cf, size = inst:GetBoundingBox()
	elseif inst and inst:IsA("BasePart") then
		cf, size = inst.CFrame, inst.Size
	else
		return 0
	end
	return math.abs(dir:Dot(cf.RightVector)) * size.X
		+ math.abs(dir:Dot(cf.UpVector)) * size.Y
		+ math.abs(dir:Dot(cf.LookVector)) * size.Z
end

-- box (studs) vs our parts
function BaseEntity:Overlaps(center: Vector3, half: Vector3): boolean
	for _, part in self:GetParts() do
		if part.Parent and MathLib.BoxOverlapsPart(center, half, part) then
			return true
		end
	end
	return false
end

-- touch callbacks (TouchSystem); entities register with TouchSystem.Register to get them
function BaseEntity:StartTouch(other: any) end
function BaseEntity:Touch(other: any) end
function BaseEntity:EndTouch(other: any) end

-- tools/toolstrigger: invisible, non-solid, not hit by use traces
function BaseEntity:HideBrush()
	for _, part in self:GetParts() do
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Anchored = true
	end
end

function BaseEntity:SetSolid(solid: boolean)
	for _, part in self:GetParts() do
		part.CanCollide = solid
		part.CanQuery = solid
	end
end

function BaseEntity:SetVisible(visible: boolean)
	for _, part in self:GetParts() do
		local original = part:GetAttribute("BSDK_Transparency")
		if original == nil then
			original = part.Transparency
			part:SetAttribute("BSDK_Transparency", original)
		end
		part.Transparency = if visible then original else 1
	end
end

------------------------------------------------------------------------
-- Sound (EmitSound for rbxassetid sounds; Source soundscript names are ignored)
------------------------------------------------------------------------

function BaseEntity.ResolveSoundId(sound: any): string?
	if sound == nil then
		return nil
	end
	local s = tostring(sound)
	if s == "" then
		return nil
	end
	if s:match("^rbxassetid://") or s:match("^rbxasset://") then
		return s
	end
	if s:match("^%d+$") then
		return "rbxassetid://" .. s
	end
	return nil
end

function BaseEntity:EmitSound(sound: any, volume: number?): Sound?
	local id = BaseEntity.ResolveSoundId(sound)
	if not id then
		return nil
	end
	local parent = self:GetParts()[1] or workspace
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.RollOffMaxDistance = 200
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 30)
	return s
end

------------------------------------------------------------------------
-- Damage (CTakeDamageInfo-lite)
------------------------------------------------------------------------

BaseEntity.DMG_GENERIC = 0
BaseEntity.DMG_CRUSH = 1
BaseEntity.DMG_BULLET = 2
BaseEntity.DMG_SLASH = 4
BaseEntity.DMG_BURN = 8
BaseEntity.DMG_VEHICLE = 16
BaseEntity.DMG_FALL = 32
BaseEntity.DMG_BLAST = 64
BaseEntity.DMG_CLUB = 128
BaseEntity.DMG_SHOCK = 256
BaseEntity.DMG_SONIC = 512
BaseEntity.DMG_ENERGYBEAM = 1024
BaseEntity.DMG_DROWN = 16384
BaseEntity.DMG_POISON = 131072
BaseEntity.DMG_RADIATION = 262144

export type TakeDamageInfo = {
	damage: number,
	damageType: number,
	attacker: any?,
	inflictor: any?,
}

function BaseEntity:TakeDamage(info: TakeDamageInfo)
	if self.removed or self.maxHealth <= 0 then
		return
	end
	self.health -= info.damage
	if self.health <= 0 then
		self:FireOutput("OnKilled", info.attacker)
		self:Remove()
	end
end

return BaseEntity
