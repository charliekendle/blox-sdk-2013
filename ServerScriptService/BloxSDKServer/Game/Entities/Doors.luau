--!optimize 2
--[[
	Doors / moving brushes - ports of game/server/doors.cpp, buttons.cpp, bmodels.cpp, func_movelinear.cpp
	func_door, func_door_rotating, func_button, func_rotating, func_movelinear, func_brush, func_wall_toggle

	Rotating things turn around the instance's pivot: set it with Studio's pivot tool
	(Model.WorldPivot / Part.PivotOffset), the same job an origin brush does in Hammer.
	movedir / pushdir: a Vector3 attribute (world direction) or a Source "pitch yaw roll" string.
	Speeds are Source units/sec (or degrees/sec), distances in units.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathLib = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("MathLib"))

local Game = script.Parent.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local BaseToggle = require(Game:WaitForChild("BaseToggle"))
local EntityIO = require(Game:WaitForChild("EntityIO"))
local TouchSystem = require(Game:WaitForChild("TouchSystem"))

local TS_AT_TOP = BaseToggle.TS_AT_TOP
local TS_AT_BOTTOM = BaseToggle.TS_AT_BOTTOM
local TS_GOING_UP = BaseToggle.TS_GOING_UP
local TS_GOING_DOWN = BaseToggle.TS_GOING_DOWN

local function now()
	return EntityIO.CurTime()
end

-- Source X/Y/Z rotation axis flags -> Roblox axis
local function rotationAxis(ent: any, xFlag: number, yFlag: number): Vector3
	if ent:HasSpawnFlags(xFlag) then
		return Vector3.xAxis -- Source X
	elseif ent:HasSpawnFlags(yFlag) then
		return -Vector3.zAxis -- Source Y
	end
	return Vector3.yAxis -- Source Z (default, yaw)
end

------------------------------------------------------------------------
-- func_door
------------------------------------------------------------------------

local SF_DOOR_ROTATE_BACKWARDS = 2
local SF_DOOR_ONEWAY = 16
local SF_DOOR_NO_AUTO_RETURN = 32
local SF_DOOR_ROTATE_ROLL = 64
local SF_DOOR_ROTATE_PITCH = 128
local SF_DOOR_PUSE = 256
local SF_DOOR_PTOUCH = 1024
local SF_DOOR_LOCKED = 2048
local SF_DOOR_SILENT = 4096
local SF_DOOR_IGNORE_USE = 32768

local FuncDoor = BaseEntity.extend(BaseToggle, "func_door")
FuncDoor:DeclareOutputs({
	"OnClose", "OnOpen", "OnFullyOpen", "OnFullyClosed",
	"OnBlockedClosing", "OnBlockedOpening", "OnUnblockedClosing", "OnUnblockedOpening",
	"OnLockedUse",
})

function FuncDoor:Init(instance)
	FuncDoor.super.Init(self, instance)
	self.spawnflags = SF_DOOR_PUSE
	self.locked = false
	self.blockedOutputFired = false
	self.lastBlockDamage = 0
end

function FuncDoor:Spawn()
	FuncDoor.super.Spawn(self)
	self:AnchorParts()

	self.speed = self:GetKeyFloat("speed", 100)
	self.wait = self:GetKeyFloat("wait", 4)
	self.lip = self:GetKeyFloat("lip", 0)
	self.blockDamage = self:GetKeyFloat("dmg", 0)
	self.forceClosed = self:GetKeyBool("forceclosed", false)
	self.locked = self:HasSpawnFlags(SF_DOOR_LOCKED)

	self:SetupPositions()

	-- spawnpos 1 = start open
	if self:GetKeyInt("spawnpos", 0) == 1 then
		self:SetPivot(self.position2)
		self.toggleState = TS_AT_TOP
	end

	if self:HasSpawnFlags(SF_DOOR_PTOUCH) then
		TouchSystem.Register(self, 2)
	end
end

function FuncDoor:SetupPositions()
	local dir = MathLib.Movedir(self:GetKey("movedir"))
	self.moveDir = dir
	self.position1 = self:GetPivot()
	self.position2 = self.position1 + dir * self:TravelDistanceStuds(dir, self.lip)
end

function FuncDoor:OnRemove()
	TouchSystem.Unregister(self)
end

function FuncDoor:IsUsable(): boolean
	return self:HasSpawnFlags(SF_DOOR_PUSE) and not self:HasSpawnFlags(SF_DOOR_IGNORE_USE)
end

function FuncDoor:PlayMoveSound()
	if not self:HasSpawnFlags(SF_DOOR_SILENT) then
		self:EmitSound(self:GetKey("noise1"))
	end
end

function FuncDoor:PlayStopSound()
	if not self:HasSpawnFlags(SF_DOOR_SILENT) then
		self:EmitSound(self:GetKey("noise2"))
	end
end

-- CBaseDoor::DoorActivate
function FuncDoor:DoorActivate(activator)
	if self.locked then
		self:FireOutput("OnLockedUse", activator)
		self:EmitSound(self:GetKey("locked_sound"))
		return
	end

	if self:HasSpawnFlags(SF_DOOR_NO_AUTO_RETURN) and self.toggleState == TS_AT_TOP then
		-- door should close
		self:DoorGoDown(activator)
	else
		-- door should open
		self:DoorGoUp(activator)
	end
end

function FuncDoor:DoorGoUp(activator)
	if self.toggleState == TS_GOING_UP or self.toggleState == TS_AT_TOP and not self:IsMoving() then
		if self.toggleState == TS_AT_TOP and self.wait ~= -1 and not self:HasSpawnFlags(SF_DOOR_NO_AUTO_RETURN) then
			-- re-use while open resets the auto-close timer
			self:SetThink(self.DoorGoDown, self.wait)
		end
		return
	end
	self.activator = activator
	self.toggleState = TS_GOING_UP
	self.blockedOutputFired = false
	self:SetThink(nil)
	self:PlayMoveSound()
	self:FireOutput("OnOpen", activator)
	self:MoveTo(self.position2, self.DoorHitTop, activator)
end

function FuncDoor:MoveTo(dest: CFrame, onDone, activator)
	self:LinearMove(dest, self.speed, onDone)
end

function FuncDoor:DoorHitTop()
	self.toggleState = TS_AT_TOP
	self:PlayStopSound()
	self:FireOutput("OnFullyOpen", self.activator)

	if self:HasSpawnFlags(SF_DOOR_NO_AUTO_RETURN) or self.wait == -1 then
		return
	end
	self:SetThink(self.DoorGoDown, self.wait)
end

function FuncDoor:DoorGoDown(activator)
	if self.toggleState == TS_GOING_DOWN or self.toggleState == TS_AT_BOTTOM then
		return
	end
	self.toggleState = TS_GOING_DOWN
	self.blockedOutputFired = false
	self:SetThink(nil)
	self:PlayMoveSound()
	self:FireOutput("OnClose", activator or self.activator)
	self:MoveTo(self.position1, self.DoorHitBottom, activator)
end

function FuncDoor:DoorHitBottom()
	self.toggleState = TS_AT_BOTTOM
	self:PlayStopSound()
	self:FireOutput("OnFullyClosed", self.activator)
end

function FuncDoor:Blocked(other): boolean
	local t = now()
	if self.blockDamage > 0 and t - self.lastBlockDamage >= 0.5 and other.TakeDamage then
		self.lastBlockDamage = t
		other:TakeDamage({ damage = self.blockDamage, damageType = BaseEntity.DMG_CRUSH, attacker = self, inflictor = self })
	end

	if not self.blockedOutputFired then
		self.blockedOutputFired = true
		if self.toggleState == TS_GOING_DOWN then
			self:FireOutput("OnBlockedClosing", other)
		else
			self:FireOutput("OnBlockedOpening", other)
		end
	end

	if self.forceClosed then
		return true
	end

	-- if a door has a negative wait, it would never come back if blocked, so let it just squash the object
	if self.wait >= 0 then
		if self.toggleState == TS_GOING_DOWN then
			self:DoorGoUp(other)
		else
			self:DoorGoDown(other)
		end
	end
	return false
end

function FuncDoor:Use(activator)
	if self:HasSpawnFlags(SF_DOOR_IGNORE_USE) then
		return
	end
	self:DoorActivate(activator)
end

function FuncDoor:StartTouch(other)
	if other:IsPlayer() and self.toggleState == TS_AT_BOTTOM then
		self:DoorActivate(other)
	end
end

FuncDoor.Inputs.open = function(self, data)
	if self.toggleState ~= TS_AT_TOP and self.toggleState ~= TS_GOING_UP then
		self:DoorGoUp(data.activator)
	end
end

FuncDoor.Inputs.close = function(self, data)
	if self.toggleState ~= TS_AT_BOTTOM and self.toggleState ~= TS_GOING_DOWN then
		self:DoorGoDown(data.activator)
	end
end

FuncDoor.Inputs.toggle = function(self, data)
	if self.toggleState == TS_AT_BOTTOM or self.toggleState == TS_GOING_DOWN then
		self:DoorGoUp(data.activator)
	else
		self:DoorGoDown(data.activator)
	end
end

FuncDoor.Inputs.lock = function(self)
	self.locked = true
end

FuncDoor.Inputs.unlock = function(self)
	self.locked = false
	self:EmitSound(self:GetKey("unlocked_sound"))
end

FuncDoor.Inputs.setspeed = function(self, data)
	self.speed = data.value:Float()
	if self.move then
		-- restart the current leg at the new speed
		local dest = self.move.to
		local done = self.move.done
		self:MoveTo(dest, done)
	end
end

------------------------------------------------------------------------
-- func_door_rotating
------------------------------------------------------------------------

local FuncDoorRotating = BaseEntity.extend(FuncDoor, "func_door_rotating")

function FuncDoorRotating:SetupPositions()
	self.axis = rotationAxis(self, SF_DOOR_ROTATE_ROLL, SF_DOOR_ROTATE_PITCH)
	self.distance = self:GetKeyFloat("distance", 90)
	if self:HasSpawnFlags(SF_DOOR_ROTATE_BACKWARDS) then
		self.distance = -self.distance
	end
	self.position1 = self:GetPivot()
	self.position2 = self:RotatedBy(self.distance)
end

function FuncDoorRotating:RotatedBy(degrees: number): CFrame
	local p1 = self.position1
	local localAxis = p1:VectorToObjectSpace(self.axis)
	return p1 * CFrame.fromAxisAngle(localAxis, math.rad(degrees))
end

-- opens away from the activator unless "one way"
function FuncDoorRotating:DoorGoUp(activator)
	if self.toggleState ~= TS_GOING_UP and self.toggleState ~= TS_AT_TOP
		and not self:HasSpawnFlags(SF_DOOR_ONEWAY) and activator and activator.GetAbsOrigin then
		local ups = MathLib.UnitsPerStud()
		local hinge = self.position1.Position
		local center = self.position1:PointToWorldSpace(self.position1:PointToObjectSpace(self:WorldSpaceCenter() / ups))
		local r = center - hinge
		local toPlayer = activator:GetAbsOrigin() / ups - hinge
		local swing = self.axis:Cross(r)
		local sign = if swing:Dot(toPlayer) > 0 then -1 else 1
		local d = math.abs(self.distance) * sign * (if self.distance < 0 then -1 else 1)
		self.position2 = self:RotatedBy(d)
	end
	FuncDoor.DoorGoUp(self, activator)
end

function FuncDoorRotating:MoveTo(dest: CFrame, onDone)
	self:AngularMove(dest, self.speed, onDone)
end

------------------------------------------------------------------------
-- func_button
------------------------------------------------------------------------

local SF_BUTTON_DONTMOVE = 1
local SF_BUTTON_TOGGLE = 32
local SF_BUTTON_TOUCH_ACTIVATES = 256
local SF_BUTTON_DAMAGE_ACTIVATES = 512
local SF_BUTTON_USE_ACTIVATES = 1024
local SF_BUTTON_LOCKED = 2048

local FuncButton = BaseEntity.extend(BaseToggle, "func_button")
FuncButton:DeclareOutputs({ "OnDamaged", "OnPressed", "OnUseLocked", "OnIn", "OnOut" })

function FuncButton:Init(instance)
	FuncButton.super.Init(self, instance)
	self.spawnflags = SF_BUTTON_DONTMOVE + SF_BUTTON_USE_ACTIVATES -- Hammer default (1025)
	self.locked = false
end

function FuncButton:Spawn()
	FuncButton.super.Spawn(self)
	self:AnchorParts()

	self.speed = self:GetKeyFloat("speed", 5)
	self.wait = self:GetKeyFloat("wait", 3)
	self.lip = self:GetKeyFloat("lip", 0)
	self.locked = self:HasSpawnFlags(SF_BUTTON_LOCKED)

	local dir = MathLib.Movedir(self:GetKey("movedir"))
	self.position1 = self:GetPivot()
	if self:HasSpawnFlags(SF_BUTTON_DONTMOVE) then
		self.position2 = self.position1
	else
		self.position2 = self.position1 + dir * self:TravelDistanceStuds(dir, self.lip)
	end

	if self:HasSpawnFlags(SF_BUTTON_TOUCH_ACTIVATES) then
		TouchSystem.Register(self, 2)
	end
	if self:HasSpawnFlags(SF_BUTTON_DAMAGE_ACTIVATES) and self.maxHealth <= 0 then
		self.maxHealth = 1
		self.health = 1
	end
end

function FuncButton:OnRemove()
	TouchSystem.Unregister(self)
end

function FuncButton:IsUsable(): boolean
	return self:HasSpawnFlags(SF_BUTTON_USE_ACTIVATES)
end

function FuncButton:ButtonActivate(activator)
	self:EmitSound(self:GetKey("sound") or self:GetKey("noise"))
	self.toggleState = TS_GOING_UP
	self:SetThink(nil)
	self:LinearMove(self.position2, self.speed, self.TriggerAndWait)
end

function FuncButton:TriggerAndWait()
	self.toggleState = TS_AT_TOP
	self:FireOutput("OnIn", self.activator)

	-- If button automatically comes back out, start it moving out.
	if not self:HasSpawnFlags(SF_BUTTON_TOGGLE) and self.wait ~= -1 then
		self:SetThink(self.ButtonReturn, self.wait)
	end
end

function FuncButton:ButtonReturn()
	self.toggleState = TS_GOING_DOWN
	self:SetThink(nil)
	self:LinearMove(self.position1, self.speed, self.ButtonBackHome)
end

function FuncButton:ButtonBackHome()
	self.toggleState = TS_AT_BOTTOM
	self:FireOutput("OnOut", self.activator)
end

-- CBaseButton::ButtonUse
function FuncButton:Press(activator)
	if self.toggleState == TS_GOING_UP or self.toggleState == TS_GOING_DOWN then
		return
	end

	if self.locked then
		self:FireOutput("OnUseLocked", activator)
		self:EmitSound(self:GetKey("locked_sound"))
		return
	end

	self.activator = activator
	if self.toggleState == TS_AT_TOP then
		-- If it's a toggle button it can return now. Otherwise, it will either
		-- return on its own or will stay pressed indefinitely.
		if self:HasSpawnFlags(SF_BUTTON_TOGGLE) then
			self:EmitSound(self:GetKey("sound"))
			self:FireOutput("OnPressed", activator)
			self:ButtonReturn()
		end
	else
		self:FireOutput("OnPressed", activator)
		self:ButtonActivate(activator)
	end
end

function FuncButton:Use(activator)
	self:Press(activator)
end

function FuncButton:StartTouch(other)
	if other:IsPlayer() and self.toggleState == TS_AT_BOTTOM then
		self:Press(other)
	end
end

function FuncButton:TakeDamage(info)
	self:FireOutput("OnDamaged", info.attacker)
	if self:HasSpawnFlags(SF_BUTTON_DAMAGE_ACTIVATES) then
		self:Press(info.attacker)
	end
end

FuncButton.Inputs.lock = function(self)
	self.locked = true
end

FuncButton.Inputs.unlock = function(self)
	self.locked = false
end

FuncButton.Inputs.press = function(self, data)
	self:Press(data.activator)
end

FuncButton.Inputs.pressin = function(self, data)
	if self.toggleState == TS_AT_BOTTOM or self.toggleState == TS_GOING_DOWN then
		self.activator = data.activator
		self:FireOutput("OnPressed", data.activator)
		self:ButtonActivate(data.activator)
	end
end

FuncButton.Inputs.pressout = function(self, data)
	if self.toggleState == TS_AT_TOP or self.toggleState == TS_GOING_UP then
		self.activator = data.activator
		self:ButtonReturn()
	end
end

------------------------------------------------------------------------
-- func_rotating
------------------------------------------------------------------------

local SF_BRUSH_ROTATE_START_ON = 1
local SF_BRUSH_ROTATE_BACKWARDS = 2
local SF_BRUSH_ROTATE_X_AXIS = 4
local SF_BRUSH_ROTATE_Y_AXIS = 8
local SF_BRUSH_ACCDCC = 16
local SF_BRUSH_HURT = 32
local SF_BRUSH_ROTATE_NOT_SOLID = 64

local FuncRotating = BaseEntity.extend(BaseEntity, "func_rotating")

FuncRotating.Rotators = {} :: { [any]: boolean }

function FuncRotating:Spawn()
	FuncRotating.super.Spawn(self)
	for _, part in self:GetParts() do
		part.Anchored = true
	end

	self.maxSpeed = self:GetKeyFloat("maxspeed", 100)
	self.friction = math.max(self:GetKeyFloat("fanfriction", 20), 1) / 100
	self.axis = rotationAxis(self, SF_BRUSH_ROTATE_X_AXIS, SF_BRUSH_ROTATE_Y_AXIS)
	self.direction = if self:HasSpawnFlags(SF_BRUSH_ROTATE_BACKWARDS) then -1 else 1
	self.speed = 0
	self.targetSpeed = 0
	self.blockDamage = self:GetKeyFloat("dmg", 0)
	self.lastBlockDamage = 0

	if self:HasSpawnFlags(SF_BRUSH_ROTATE_NOT_SOLID) then
		self:SetSolid(false)
	end
	if self:HasSpawnFlags(SF_BRUSH_ROTATE_START_ON) then
		self:SetTargetSpeed(self.maxSpeed)
	end
	FuncRotating.Rotators[self] = true
end

function FuncRotating:OnRemove()
	FuncRotating.Rotators[self] = nil
end

function FuncRotating:SetTargetSpeed(speed: number)
	self.targetSpeed = math.clamp(speed, -self.maxSpeed, self.maxSpeed)
	if not self:HasSpawnFlags(SF_BRUSH_ACCDCC) then
		self.speed = self.targetSpeed
	end
end

function FuncRotating:StepRotate(dt: number)
	if self:HasSpawnFlags(SF_BRUSH_ACCDCC) then
		local accel = self.maxSpeed * self.friction * 10
		self.speed = MathLib.Approach(self.targetSpeed, self.speed, accel * dt)
	end
	if self.speed == 0 then
		return
	end
	local pivot = self:GetPivot()
	local localAxis = pivot:VectorToObjectSpace(self.axis)
	self:SetPivot(pivot * CFrame.fromAxisAngle(localAxis, math.rad(self.speed * self.direction * dt)))
end

function FuncRotating.ServiceRotators(dt: number)
	for ent in FuncRotating.Rotators do
		if ent.removed then
			FuncRotating.Rotators[ent] = nil
		else
			ent:StepRotate(dt)
		end
	end
end

FuncRotating.Inputs.setspeed = function(self, data)
	self:SetTargetSpeed(math.clamp(data.value:Float(), 0, 1) * self.maxSpeed)
end

FuncRotating.Inputs.start = function(self)
	self:SetTargetSpeed(self.maxSpeed)
end

FuncRotating.Inputs.stop = function(self)
	self:SetTargetSpeed(0)
end

FuncRotating.Inputs.toggle = function(self)
	if self.targetSpeed ~= 0 then
		self:SetTargetSpeed(0)
	else
		self:SetTargetSpeed(self.maxSpeed)
	end
end

FuncRotating.Inputs.reverse = function(self)
	self.direction = -self.direction
end

FuncRotating.Inputs.startforward = function(self)
	self.direction = if self:HasSpawnFlags(SF_BRUSH_ROTATE_BACKWARDS) then -1 else 1
	self:SetTargetSpeed(self.maxSpeed)
end

FuncRotating.Inputs.startbackward = function(self)
	self.direction = if self:HasSpawnFlags(SF_BRUSH_ROTATE_BACKWARDS) then 1 else -1
	self:SetTargetSpeed(self.maxSpeed)
end

------------------------------------------------------------------------
-- func_movelinear
------------------------------------------------------------------------

local FuncMoveLinear = BaseEntity.extend(BaseToggle, "func_movelinear")
FuncMoveLinear:DeclareOutputs({ "OnFullyOpen", "OnFullyClosed" })

function FuncMoveLinear:Spawn()
	FuncMoveLinear.super.Spawn(self)
	self:AnchorParts()

	local ups = MathLib.UnitsPerStud()
	self.speed = self:GetKeyFloat("speed", 100)
	local dir = MathLib.Movedir(self:GetKey("movedir"))
	local distance = self:GetKeyFloat("movedistance", 100) / ups

	self.position1 = self:GetPivot()
	self.position2 = self.position1 + dir * distance

	local start = math.clamp(self:GetKeyFloat("startposition", 0), 0, 1)
	if start > 0 then
		self:SetPivot(self.position1:Lerp(self.position2, start))
	end
end

function FuncMoveLinear:MoveToFraction(fraction: number)
	local dest = self.position1:Lerp(self.position2, math.clamp(fraction, 0, 1))
	self:LinearMove(dest, self.speed, function(ent)
		if fraction >= 1 then
			ent:FireOutput("OnFullyOpen", ent)
		elseif fraction <= 0 then
			ent:FireOutput("OnFullyClosed", ent)
		end
	end)
end

FuncMoveLinear.Inputs.open = function(self)
	self:MoveToFraction(1)
end

FuncMoveLinear.Inputs.close = function(self)
	self:MoveToFraction(0)
end

FuncMoveLinear.Inputs.setposition = function(self, data)
	self:MoveToFraction(data.value:Float())
end

FuncMoveLinear.Inputs.setspeed = function(self, data)
	self.speed = data.value:Float()
end

------------------------------------------------------------------------
-- func_brush / func_wall_toggle
------------------------------------------------------------------------

local FuncBrush = BaseEntity.extend(BaseEntity, "func_brush")

function FuncBrush:Spawn()
	FuncBrush.super.Spawn(self)
	-- Solidity: 0 = toggle with visibility, 1 = never solid, 2 = always solid
	self.solidity = self:GetKeyInt("solidity", 0)
	self:ApplyState()
end

function FuncBrush:ApplyState()
	local on = not self.disabled
	self:SetVisible(on)
	if self.solidity == 1 then
		self:SetSolid(false)
	elseif self.solidity == 2 then
		self:SetSolid(true)
	else
		self:SetSolid(on)
	end
end

FuncBrush.Inputs.enable = function(self)
	self.disabled = false
	self:ApplyState()
end

FuncBrush.Inputs.disable = function(self)
	self.disabled = true
	self:ApplyState()
end

FuncBrush.Inputs.toggle = function(self)
	self.disabled = not self.disabled
	self:ApplyState()
end

local FuncWallToggle = BaseEntity.extend(FuncBrush, "func_wall_toggle")

function FuncWallToggle:Spawn()
	-- spawnflag 1 = starts invisible
	if self:HasSpawnFlags(1) then
		self.disabled = true
	end
	FuncWallToggle.super.Spawn(self)
end

return {
	FuncRotating = FuncRotating,
}
