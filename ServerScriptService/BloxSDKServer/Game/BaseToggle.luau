--!optimize 2
--[[
	BaseToggle (ModuleScript) - port of CBaseToggle (game/server/subs.cpp):
	LinearMove / AngularMove with move-done callbacks, used by doors, buttons, movelinear.

	Moving brushes are anchored and moved with PivotTo, so the client's platform carry
	(GameMovement:UpdateGroundCarry) rides them. If a move would overlap a player the
	entity's Blocked() is called and the move pauses that frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathLib = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("MathLib"))

local Game = script.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local EntityIO = require(Game:WaitForChild("EntityIO"))

local BaseToggle = BaseEntity.extend(BaseEntity)
BaseToggle.ClassName = "basetoggle"

BaseToggle.TS_AT_TOP = 0
BaseToggle.TS_AT_BOTTOM = 1
BaseToggle.TS_GOING_UP = 2
BaseToggle.TS_GOING_DOWN = 3

-- entity -> true while moving; serviced by Main every Heartbeat
BaseToggle.Movers = {} :: { [any]: boolean }

-- set by Main: () -> { playerEntity }
BaseToggle.GetLivingPlayers = function(): { any }
	return {}
end

function BaseToggle:Init(instance)
	BaseToggle.super.Init(self, instance)
	self.toggleState = BaseToggle.TS_AT_BOTTOM
	self.move = nil
	self.blockedSince = nil
end

function BaseToggle:AnchorParts()
	for _, part in self:GetParts() do
		part.Anchored = true
	end
end

-- speed in Source units/sec
function BaseToggle:LinearMove(dest: CFrame, speed: number, onDone: ((any) -> ())?)
	local from = self:GetPivot()
	local distUnits = (dest.Position - from.Position).Magnitude * MathLib.UnitsPerStud()
	if distUnits < 0.01 or speed <= 0 then
		self:SetPivot(dest)
		self.move = nil
		BaseToggle.Movers[self] = nil
		if onDone then
			onDone(self)
		end
		return
	end
	self.move = {
		from = from,
		to = dest,
		elapsed = 0,
		duration = distUnits / speed,
		done = onDone,
	}
	BaseToggle.Movers[self] = true
end

-- speed in degrees/sec; dest must be < 180 degrees from the current rotation
function BaseToggle:AngularMove(dest: CFrame, speed: number, onDone: ((any) -> ())?)
	local from = self:GetPivot()
	local _, angle = (from:ToObjectSpace(dest)):ToAxisAngle()
	local degrees = math.deg(math.abs(angle))
	if degrees < 0.01 or speed <= 0 then
		self:SetPivot(dest)
		self.move = nil
		BaseToggle.Movers[self] = nil
		if onDone then
			onDone(self)
		end
		return
	end
	self.move = {
		from = from,
		to = dest,
		elapsed = 0,
		duration = degrees / speed,
		done = onDone,
	}
	BaseToggle.Movers[self] = true
end

function BaseToggle:StopMoving()
	self.move = nil
	BaseToggle.Movers[self] = nil
end

function BaseToggle:IsMoving(): boolean
	return self.move ~= nil
end

-- override: called while a move is blocked by a player. Return true to keep pushing.
function BaseToggle:Blocked(other: any): boolean
	return false
end

-- would our parts at pivot `cf` overlap this player?
function BaseToggle:WouldOverlap(cf: CFrame, playerEnt: any): boolean
	local current = self:GetPivot()
	local center, half = playerEnt:GetHullBox(-1)
	for _, part in self:GetParts() do
		if part.CanCollide then
			local partCF = cf * current:ToObjectSpace(part.CFrame)
			if MathLib.BoxesOverlap(CFrame.new(center), half, partCF, part.Size / 2) then
				return true
			end
		end
	end
	return false
end

function BaseToggle:StepMove(dt: number)
	local move = self.move
	if not move then
		BaseToggle.Movers[self] = nil
		return
	end

	local t = math.clamp((move.elapsed + dt) / move.duration, 0, 1)
	local cf = move.from:Lerp(move.to, t)

	-- blocking
	for _, playerEnt in BaseToggle.GetLivingPlayers() do
		if self:WouldOverlap(cf, playerEnt) then
			local keepPushing = self:Blocked(playerEnt)
			if self.move ~= move then
				return -- Blocked() started a different move (e.g. reversed)
			end
			if not keepPushing then
				return -- pause this frame
			end
		end
	end

	move.elapsed += dt
	self:SetPivot(cf)

	if t >= 1 then
		self.move = nil
		BaseToggle.Movers[self] = nil
		if move.done then
			move.done(self)
		end
	end
end

function BaseToggle.ServiceMovers(dt: number)
	for ent in table.clone(BaseToggle.Movers) do
		if ent.removed then
			BaseToggle.Movers[ent] = nil
		else
			ent:StepMove(dt)
		end
	end
end

-- helpers for the travel distance of doors/buttons (Source: |movedir . (size - 2)| - lip)
function BaseToggle:TravelDistanceStuds(dir: Vector3, lipUnits: number): number
	local ups = MathLib.UnitsPerStud()
	local extent = self:ExtentAlong(dir)
	local inset = 2 * (math.abs(dir.X) + math.abs(dir.Y) + math.abs(dir.Z)) / ups
	return math.max(extent - inset - lipUnits / ups, 0)
end

BaseToggle.CurTime = EntityIO.CurTime

return BaseToggle
