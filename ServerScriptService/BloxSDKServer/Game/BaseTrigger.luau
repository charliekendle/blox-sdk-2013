--!optimize 2
--[[
	BaseTrigger (ModuleScript) - port of CBaseTrigger (game/server/triggers.cpp)
	Brush volume that tracks touching players and fires OnStartTouch / OnEndTouch etc.

	spawnflags:  1 = Clients (players)   (only players are tracked in BloxSDK for now)
	keyvalues:   StartDisabled, filtername
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathLib = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("MathLib"))

local Game = script.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local EntityList = require(Game:WaitForChild("EntityList"))
local TouchSystem = require(Game:WaitForChild("TouchSystem"))

local BaseTrigger = BaseEntity.extend(BaseEntity)
BaseTrigger.ClassName = "basetrigger"
BaseTrigger:DeclareOutputs({ "OnStartTouch", "OnStartTouchAll", "OnEndTouch", "OnEndTouchAll", "OnTouching", "OnNotTouching" })

BaseTrigger.SF_TRIGGER_ALLOW_CLIENTS = 1
BaseTrigger.SF_TRIGGER_ALLOW_NPCS = 2
BaseTrigger.SF_TRIGGER_ALLOW_PUSHABLES = 4
BaseTrigger.SF_TRIGGER_ALLOW_PHYSICS = 8
BaseTrigger.SF_TRIGGER_ONLY_PLAYER_ALLY_NPCS = 16
BaseTrigger.SF_TRIGGER_ONLY_CLIENTS_IN_VEHICLES = 32
BaseTrigger.SF_TRIGGER_ALLOW_ALL = 64

-- all live triggers, serviced by TouchSystem
BaseTrigger.ActiveTriggers = {} :: { [any]: boolean }

function BaseTrigger:Init(instance)
	BaseTrigger.super.Init(self, instance)
	self.touching = {} :: { [any]: boolean }
	self.filter = nil
	self.spawnflags = BaseTrigger.SF_TRIGGER_ALLOW_CLIENTS
end

function BaseTrigger:IsTrigger(): boolean
	return true
end

function BaseTrigger:Spawn()
	BaseTrigger.super.Spawn(self)
	self:HideBrush()
	BaseTrigger.ActiveTriggers[self] = true
	TouchSystem.Register(self, 0)
end

function BaseTrigger:Activate()
	BaseTrigger.super.Activate(self)
	local filterName = self:GetKeyString("filtername")
	if filterName ~= "" then
		self.filter = EntityList.FindEntityByName(filterName, self)
	end
end

function BaseTrigger:OnRemove()
	BaseTrigger.ActiveTriggers[self] = nil
	TouchSystem.Unregister(self)
	for ent in table.clone(self.touching) do
		self:EndTouch(ent)
	end
end

-- PassesTriggerFilters
function BaseTrigger:PassesTriggerFilters(other: any): boolean
	if other:IsPlayer() then
		if not self:HasSpawnFlags(BaseTrigger.SF_TRIGGER_ALLOW_CLIENTS + BaseTrigger.SF_TRIGGER_ALLOW_ALL) then
			return false
		end
	elseif not self:HasSpawnFlags(BaseTrigger.SF_TRIGGER_ALLOW_ALL) then
		return false
	end
	local filter = self.filter
	if filter and not filter.removed and filter.PassesFilter then
		return filter:PassesFilter(self, other)
	end
	return true
end

-- overlap test against our parts (studs)
function BaseTrigger:Overlaps(center: Vector3, half: Vector3): boolean
	for _, part in self:GetParts() do
		if part.Parent and MathLib.BoxOverlapsPart(center, half, part) then
			return true
		end
	end
	return false
end

function BaseTrigger:IsTouching(other: any): boolean
	return self.touching[other] == true
end

function BaseTrigger:CountTouching(): number
	local n = 0
	for _ in self.touching do
		n += 1
	end
	return n
end

-- called by TouchSystem
function BaseTrigger:StartTouch(other: any)
	if not self:PassesTriggerFilters(other) then
		return
	end
	local wasEmpty = next(self.touching) == nil
	self.touching[other] = true
	self:FireOutput("OnStartTouch", other)
	if wasEmpty then
		self:FireOutput("OnStartTouchAll", other)
	end
	self:OnStartTouch(other)
end

function BaseTrigger:Touch(other: any)
	if self.touching[other] then
		self:OnTouch(other)
	end
end

function BaseTrigger:EndTouch(other: any)
	if not self.touching[other] then
		return
	end
	self.touching[other] = nil
	self:FireOutput("OnEndTouch", other)
	if next(self.touching) == nil then
		self:FireOutput("OnEndTouchAll", other)
	end
	self:OnEndTouch(other)
end

-- subclass hooks
function BaseTrigger:OnStartTouch(other: any) end
function BaseTrigger:OnTouch(other: any) end
function BaseTrigger:OnEndTouch(other: any) end

function BaseTrigger:Enable()
	self.disabled = false
end

function BaseTrigger:Disable()
	self.disabled = true
	for ent in table.clone(self.touching) do
		self:EndTouch(ent)
	end
end

BaseTrigger.Inputs.enable = function(self)
	self:Enable()
end

BaseTrigger.Inputs.disable = function(self)
	self:Disable()
end

BaseTrigger.Inputs.toggle = function(self)
	if self.disabled then
		self:Enable()
	else
		self:Disable()
	end
end

-- TouchTest: fires OnTouching / OnNotTouching
BaseTrigger.Inputs.touchtest = function(self, data)
	if next(self.touching) ~= nil then
		self:FireOutput("OnTouching", data.activator)
	else
		self:FireOutput("OnNotTouching", data.activator)
	end
end

return BaseTrigger
