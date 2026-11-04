--!optimize 2
--[[
	Triggers - port of game/server/triggers.cpp
	trigger_multiple, trigger_once, trigger_teleport, trigger_push, trigger_hurt
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathLib = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("MathLib"))

local Game = script.Parent.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local BaseTrigger = require(Game:WaitForChild("BaseTrigger"))
local EntityList = require(Game:WaitForChild("EntityList"))
local EntityIO = require(Game:WaitForChild("EntityIO"))

------------------------------------------------------------------------
-- trigger_multiple
------------------------------------------------------------------------

local TriggerMultiple = BaseEntity.extend(BaseTrigger, "trigger_multiple")
TriggerMultiple:DeclareOutputs({ "OnTrigger" })

function TriggerMultiple:Init(instance)
	TriggerMultiple.super.Init(self, instance)
	self.wait = 0
	self.waitUntil = 0
end

function TriggerMultiple:Spawn()
	TriggerMultiple.super.Spawn(self)
	self.wait = self:GetKeyFloat("wait", 0)
	if self.wait == 0 then
		self.wait = 0.2
	end
end

-- CTriggerMultiple::MultiTouch -> ActivateMultiTrigger
function TriggerMultiple:OnTouch(other)
	self:ActivateMultiTrigger(other)
end

function TriggerMultiple:ActivateMultiTrigger(activator)
	local now = EntityIO.CurTime()
	if now < self.waitUntil or self.removed then
		return
	end

	self:FireOutput("OnTrigger", activator)

	if self.wait > 0 then
		self.waitUntil = now + self.wait
	else
		-- we can't just remove (self) here, because this is a touch function
		-- called while C code is looping through area links...
		self.waitUntil = math.huge
		self:SetThink(function(ent)
			ent:Remove()
		end, 0.1)
	end
end

-- TriggerMultiple fires for a single activator via input, used by trigger_once too
TriggerMultiple.Inputs.trigger = function(self, data)
	self:ActivateMultiTrigger(data.activator)
end

------------------------------------------------------------------------
-- trigger_once
------------------------------------------------------------------------

local TriggerOnce = BaseEntity.extend(TriggerMultiple, "trigger_once")

function TriggerOnce:Spawn()
	TriggerOnce.super.Spawn(self)
	self.wait = -1
end

------------------------------------------------------------------------
-- trigger_teleport
------------------------------------------------------------------------

local SF_TELEPORT_PRESERVE_ANGLES = 32

local TriggerTeleport = BaseEntity.extend(BaseTrigger, "trigger_teleport")

function TriggerTeleport:OnTouch(other)
	if not self:PassesTriggerFilters(other) then
		return
	end

	local target = EntityList.FindEntityByName(self:GetKeyString("target"), self, other, self)
	if not target then
		return
	end

	local landmarkName = self:GetKeyString("landmark")
	local landmark = if landmarkName ~= "" then EntityList.FindEntityByName(landmarkName, self, other, self) else nil

	local dest = target:GetAbsOrigin()
	local yaw = nil

	if landmark then
		-- relative teleport
		dest += other:GetAbsOrigin() - landmark:GetAbsOrigin()
	elseif not self:HasSpawnFlags(SF_TELEPORT_PRESERVE_ANGLES) then
		yaw = target:GetYaw()
	end

	if other.Teleport then
		-- HL2 keeps velocity (Source's "BUGBUG - This does not set the player velocity")
		other:Teleport(dest, yaw, nil)
	else
		other:SetPivot(CFrame.new(dest / MathLib.UnitsPerStud()))
	end

	-- the teleport is now "in flight" to the client; stop touching until it reports back
	self:EndTouch(other)
end

------------------------------------------------------------------------
-- trigger_push
------------------------------------------------------------------------

local SF_TRIG_PUSH_ONCE = 128

local TriggerPush = BaseEntity.extend(BaseTrigger, "trigger_push")

function TriggerPush:Spawn()
	TriggerPush.super.Spawn(self)
	self.pushSpeed = self:GetKeyFloat("speed", 40)
	self.pushDir = MathLib.Movedir(self:GetKey("pushdir"))
end

function TriggerPush:GetPush(): Vector3
	return self.pushDir * self.pushSpeed
end

function TriggerPush:OnStartTouch(other)
	if self:HasSpawnFlags(SF_TRIG_PUSH_ONCE) then
		if other.ApplyAbsVelocityImpulse then
			other:ApplyAbsVelocityImpulse(self:GetPush())
		end
		self:SetThink(function(ent)
			ent:Remove()
		end, 0)
		return
	end
	if other.SetPush then
		other:SetPush(self, self:GetPush())
	end
end

function TriggerPush:OnEndTouch(other)
	if other.SetPush then
		other:SetPush(self, nil)
	end
end

TriggerPush.Inputs.setspeed = function(self, data)
	self.pushSpeed = data.value:Float()
	for other in self.touching do
		if other.SetPush then
			other:SetPush(self, self:GetPush())
		end
	end
end

------------------------------------------------------------------------
-- trigger_hurt
------------------------------------------------------------------------

local TriggerHurt = BaseEntity.extend(BaseTrigger, "trigger_hurt")
TriggerHurt:DeclareOutputs({ "OnHurt", "OnHurtPlayer" })

function TriggerHurt:Spawn()
	TriggerHurt.super.Spawn(self)
	self.damage = self:GetKeyFloat("damage", 10)
	self.damageCap = self:GetKeyFloat("damagecap", 20)
	self.damageType = self:GetKeyInt("damagetype", 0)
	self.damageModel = self:GetKeyInt("damagemodel", 0)
	self.lastDmgTime = 0
	self.originalDamage = self.damage
end

function TriggerHurt:OnStartTouch(other)
	if not self.thinkFn then
		self.lastDmgTime = EntityIO.CurTime()
		self:SetThink(self.HurtThink, 0)
	end
end

function TriggerHurt:HurtAllTouchers(dt: number): number
	local hurt = 0
	local amount = self.damage * dt

	-- damagemodel 1: "doubling" - damage doubles each time it's applied, up to damagecap
	if self.damageModel == 1 then
		amount = math.min(self.damage, self.damageCap)
	end

	if amount <= 0 then
		return 0
	end

	for other in table.clone(self.touching) do
		if other.TakeDamage then
			other:TakeDamage({ damage = amount, damageType = self.damageType, attacker = self, inflictor = self })
			hurt += 1
			self:FireOutput("OnHurt", other)
			if other:IsPlayer() then
				self:FireOutput("OnHurtPlayer", other)
			end
		end
	end

	if self.damageModel == 1 then
		self.damage = math.min(self.damage * 2, self.damageCap)
	end
	return hurt
end

function TriggerHurt:HurtThink()
	local now = EntityIO.CurTime()
	local dt = now - self.lastDmgTime
	self.lastDmgTime = now

	self:HurtAllTouchers(dt)
	if next(self.touching) == nil then
		self.thinkFn = nil
		self.damage = self.originalDamage
		return
	end
	self:SetThink(self.HurtThink, 0.5)
end

TriggerHurt.Inputs.setdamage = function(self, data)
	self.damage = data.value:Float()
	self.originalDamage = self.damage
end

return {}
