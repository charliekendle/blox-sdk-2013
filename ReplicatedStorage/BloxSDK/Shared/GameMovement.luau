--!optimize 2
--[[
	GameMovement (ModuleScript)
	ReplicatedStorage.BloxSDK.Shared.GameMovement

	Luau port of CGameMovement from Source SDK 2013 (game/shared/gamemovement.cpp),
	including the HL2 jump boost from the HL2_DLL path.

	Conventions:
	  * All maths is in Source units (1 unit = 1 inch), converted to studs only for
	    traces and when the client places the character (ConVars.units_per_stud).
	  * Axes are Roblox axes: Y is up. Source's "z" is "Y" here.
	  * origin is the player's feet (bottom-centre of the hull), same as Source.

	Ported:   FullWalkMove, WalkMove, AirMove, StepMove, TryPlayerMove, ClipVelocity,
	          Accelerate, AirAccelerate, Friction, CheckJumpButton (+HL2 boost),
	          Start/FinishGravity, CategorizePosition, StayOnGround, CheckVelocity,
	          CheckFalling, Duck (incl. in-air duck), CanUnDuck, CheckStuck, FullNoClipMove.
	Not yet:  water, ladders, TryTouchGroundInQuadrants.
	Extra:    moving-platform carry (Roblox has no ground-entity parenting).
]]

local Workspace = game:GetService("Workspace")

local GameMovement = {}
GameMovement.__index = GameMovement

GameMovement.ConVars = {
	sv_gravity = 600,
	sv_maxspeed = 320,
	sv_accelerate = 10,
	sv_airaccelerate = 10,
	sv_friction = 4,
	sv_stopspeed = 100,
	sv_stepsize = 18,
	sv_bounce = 0,
	sv_maxvelocity = 3500,
	sv_noclipspeed = 5,
	sv_noclipaccelerate = 5,
	sv_autobunnyhopping = false, -- false = must release jump between hops (stock Source)
	hl2_jumpboost = true, -- HL2 singleplayer forward jump boost (the thing that causes ABH)
	units_per_stud = 14, -- 72-unit player = ~5.1 studs, close to an R15 rig
}
local ConVars = GameMovement.ConVars

-- Hulls (Roblox axes, feet at origin)
local VEC_HULL_MIN = Vector3.new(-16, 0, -16)
local VEC_HULL_MAX = Vector3.new(16, 72, 16)
local VEC_DUCK_HULL_MIN = Vector3.new(-16, 0, -16)
local VEC_DUCK_HULL_MAX = Vector3.new(16, 36, 16)
local VEC_VIEW = 64
local VEC_DUCK_VIEW = 28
local DUCK_HULL_DELTA = (VEC_HULL_MAX - VEC_HULL_MIN).Y - (VEC_DUCK_HULL_MAX - VEC_DUCK_HULL_MIN).Y -- 36

GameMovement.VEC_HULL_MIN = VEC_HULL_MIN
GameMovement.VEC_HULL_MAX = VEC_HULL_MAX
GameMovement.VEC_DUCK_HULL_MIN = VEC_DUCK_HULL_MIN
GameMovement.VEC_DUCK_HULL_MAX = VEC_DUCK_HULL_MAX
GameMovement.VEC_VIEW = VEC_VIEW
GameMovement.VEC_DUCK_VIEW = VEC_DUCK_VIEW

local TIME_TO_DUCK = 0.4
local TIME_TO_UNDUCK = 0.2
local PLAYER_DUCKING_MULTIPLIER = 0.333
local GAMEMOVEMENT_JUMP_HEIGHT = 21
local NON_JUMP_VELOCITY = 140
local MAX_CLIP_PLANES = 5
local MIN_GROUND_NORMAL = 0.7
local COORD_RESOLUTION = 1 / 32
local PLAYER_FALL_PUNCH_THRESHOLD = 350
local PLAYER_MAX_SAFE_FALL_SPEED = 526.5
local PLAYER_FATAL_FALL_SPEED = 922.5
local DAMAGE_FOR_FALL_SPEED = 100 / (PLAYER_FATAL_FALL_SPEED - PLAYER_MAX_SAFE_FALL_SPEED)

GameMovement.PLAYER_FALL_PUNCH_THRESHOLD = PLAYER_FALL_PUNCH_THRESHOLD

-- Roblox-specific
local SKIN_STUDS = 0.01 -- how far traces stop short of a surface (Roblox's DIST_EPSILON)
local OVERLAP_SHRINK_STUDS = 0.02
local MAX_CARRY_PER_TICK = 64 -- units; anything bigger is a teleport, not a platform
local STUCK_RETRY_DELAY = 0.2
local FRICTION_REFERENCE = 0.2 -- Roblox friction at/above this = full Source friction (1.0)

local ZERO = Vector3.zero
local UP = Vector3.yAxis

-- Offsets tried by CheckStuck, nearest first (like Source's rgv3tStuckTable)
local STUCK_OFFSETS = {}
do
	for y = 1, DUCK_HULL_DELTA do
		table.insert(STUCK_OFFSETS, Vector3.new(0, y, 0))
	end
	local dirs = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 1).Unit, Vector3.new(-1, 0, 1).Unit, Vector3.new(1, 0, -1).Unit, Vector3.new(-1, 0, -1).Unit,
	}
	for r = 2, 16, 2 do
		for _, d in dirs do
			table.insert(STUCK_OFFSETS, d * r)
			table.insert(STUCK_OFFSETS, d * r + Vector3.new(0, r, 0))
		end
	end
	for y = 1, 8 do
		table.insert(STUCK_OFFSETS, Vector3.new(0, -y, 0))
	end
end

local function SimpleSpline(v: number): number
	return 3 * v * v - 2 * v * v * v
end

local function Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function SetY(v: Vector3, y: number): Vector3
	return Vector3.new(v.X, y, v.Z)
end

local function ClipVelocity(vin: Vector3, normal: Vector3, overbounce: number): Vector3
	local backoff = vin:Dot(normal) * overbounce
	local out = vin - normal * backoff
	-- iterate once to make sure we aren't still moving through the plane
	local adjust = out:Dot(normal)
	if adjust < 0 then
		out -= normal * adjust
	end
	return out
end
GameMovement.ClipVelocity = ClipVelocity

local function YawBasis(yawDeg: number): (Vector3, Vector3)
	local r = math.rad(yawDeg)
	local s, c = math.sin(r), math.cos(r)
	-- matches CFrame.fromOrientation(0, r, 0).LookVector / .RightVector
	return Vector3.new(-s, 0, -c), Vector3.new(c, 0, -s)
end

function GameMovement.GetFallDamage(fallSpeed: number): number
	if fallSpeed <= PLAYER_MAX_SAFE_FALL_SPEED then
		return 0
	end
	return (fallSpeed - PLAYER_MAX_SAFE_FALL_SPEED) * DAMAGE_FOR_FALL_SPEED
end

export type Trace = {
	fraction: number,
	endpos: Vector3,
	normal: Vector3?,
	instance: Instance?,
	material: Enum.Material?,
}

export type MoveCmd = {
	forwardmove: number,
	sidemove: number,
	upmove: number,
	jump: boolean,
	duck: boolean,
	sprint: boolean,
	maxspeed: number,
	pitch: number,
	yaw: number,
}

function GameMovement.new(ignore: { Instance }?)
	local self = setmetatable({}, GameMovement)

	self.origin = ZERO
	self.velocity = ZERO
	self.pitch = 0
	self.yaw = 0

	self.onGround = false
	self.groundInstance = nil :: Instance?
	self.surfaceFriction = 1

	self.ducked = false
	self.duckAmount = 0
	self.viewOffset = VEC_VIEW

	self.fallVelocity = 0
	self.noclip = false
	self.oldJump = false
	self.maxspeed = ConVars.sv_maxspeed

	self.frametime = 0
	self.fmove = 0
	self.smove = 0
	self.umove = 0
	self.cmd = nil :: MoveCmd?

	-- platform carry
	self.carryPart = nil :: BasePart?
	self.carryCFrame = nil :: CFrame?
	self.platformVelocity = ZERO
	self.carryYaw = 0
	self.carried = false

	self.stuckCooldown = 0

	-- callbacks
	self.OnLand = nil :: ((fallSpeed: number) -> ())?
	self.OnJump = nil :: (() -> ())?

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.RespectCanCollide = true
	self.rayParams.IgnoreWater = true

	self.overlapParams = OverlapParams.new()
	self.overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self.overlapParams.RespectCanCollide = true

	local probe = Instance.new("Part")
	probe.Name = "BloxSDK_HullProbe"
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Parent = Workspace.CurrentCamera or Workspace
	self.probe = probe

	self:SetIgnoreList(ignore or {})
	return self
end

function GameMovement:Destroy()
	if self.probe then
		self.probe:Destroy()
		self.probe = nil
	end
end

function GameMovement:SetIgnoreList(list: { Instance })
	local filter = table.clone(list)
	table.insert(filter, self.probe)
	self.rayParams.FilterDescendantsInstances = filter
	self.overlapParams.FilterDescendantsInstances = filter
end

function GameMovement:GetHull(): (Vector3, Vector3)
	if self.ducked then
		return VEC_DUCK_HULL_MIN, VEC_DUCK_HULL_MAX
	end
	return VEC_HULL_MIN, VEC_HULL_MAX
end

function GameMovement:Teleport(origin: Vector3)
	self.origin = origin
	self.velocity = ZERO
	self.fallVelocity = 0
	self.carryPart = nil
	self.carryCFrame = nil
	self.platformVelocity = ZERO
	if not self.noclip then
		self:CheckStuck()
		self:CategorizePosition()
	end
end

function GameMovement:SetNoclip(enabled: boolean)
	if self.noclip == enabled then
		return
	end
	self.noclip = enabled
	self.ducked = false
	self.duckAmount = 0
	self.viewOffset = VEC_VIEW
	self.surfaceFriction = 1
	self.onGround = false
	self.groundInstance = nil
	self.carryPart = nil
	self.carryCFrame = nil
	self.platformVelocity = ZERO
	if not enabled then
		self.stuckCooldown = 0
		self:CheckStuck()
		self:CategorizePosition()
	end
end

------------------------------------------------------------------------
-- Traces (UTIL_TraceHull equivalent)
------------------------------------------------------------------------

function GameMovement:TraceHull(start: Vector3, finish: Vector3, mins: Vector3, maxs: Vector3): Trace
	local ups = ConVars.units_per_stud
	local delta = finish - start
	local lenUnits = delta.Magnitude

	if lenUnits < 1e-4 then
		return { fraction = 1, endpos = finish }
	end

	local size = (maxs - mins) / ups
	local center = (start + (mins + maxs) * 0.5) / ups
	local result = Workspace:Blockcast(CFrame.new(center), size, delta / ups, self.rayParams)

	if not result then
		return { fraction = 1, endpos = finish }
	end

	local fraction = math.clamp(result.Distance / (lenUnits / ups), 0, 1)
	local normal = result.Normal
	-- stop at the contact point and back off along the surface normal so the
	-- next cast never starts inside it (shapecasts ignore initial overlaps)
	local endpos = start + delta * fraction + normal * (SKIN_STUDS * ups)

	return {
		fraction = fraction,
		endpos = endpos,
		normal = normal,
		instance = result.Instance,
		material = result.Material,
	}
end

-- true if the hull fits at origin
function GameMovement:TestHull(origin: Vector3, mins: Vector3, maxs: Vector3): boolean
	local ups = ConVars.units_per_stud
	local probe = self.probe
	local size = (maxs - mins) / ups - Vector3.one * OVERLAP_SHRINK_STUDS
	probe.Size = Vector3.new(math.max(size.X, 0.01), math.max(size.Y, 0.01), math.max(size.Z, 0.01))
	probe.CFrame = CFrame.new((origin + (mins + maxs) * 0.5) / ups)
	return #Workspace:GetPartsInPart(probe, self.overlapParams) == 0
end

------------------------------------------------------------------------
-- Entry point (CGameMovement::ProcessMovement / PlayerMove)
------------------------------------------------------------------------

function GameMovement:ProcessMovement(cmd: MoveCmd, dt: number)
	self.cmd = cmd
	self.frametime = dt
	self.pitch = cmd.pitch
	self.yaw = cmd.yaw
	self.carryYaw = 0
	self.carried = false

	self:CheckParameters()

	if self.noclip then
		self:FullNoClipMove()
		return
	end

	self:UpdateGroundCarry()
	self:CheckStuck()

	-- sv_optimizedmovement
	if self.carried then
		self:CategorizePosition()
	elseif self.velocity.Y > 250 then
		self:SetGroundEntity(nil)
	end

	-- If we are not on ground, store off how fast we are moving down
	if not self.onGround then
		self.fallVelocity = -self.velocity.Y
	end

	self:Duck()
	self:FullWalkMove()
end

function GameMovement:CheckParameters()
	local cmd = self.cmd
	local maxspeed = math.min(cmd.maxspeed or ConVars.sv_maxspeed, ConVars.sv_maxspeed)
	self.maxspeed = maxspeed

	local fmove, smove, umove = cmd.forwardmove, cmd.sidemove, cmd.upmove

	if not self.noclip then
		local spd = fmove * fmove + smove * smove + umove * umove
		if spd ~= 0 and spd > maxspeed * maxspeed then
			local ratio = maxspeed / math.sqrt(spd)
			fmove *= ratio
			smove *= ratio
			umove *= ratio
		end
	end

	self.fmove, self.smove, self.umove = fmove, smove, umove
end

------------------------------------------------------------------------
-- Walking
------------------------------------------------------------------------

function GameMovement:FullWalkMove()
	self:StartGravity()

	if self.cmd.jump then
		self:CheckJumpButton()
	else
		self.oldJump = false
	end

	-- Friction is handled before we add in any base velocity.
	if self.onGround then
		self.velocity = SetY(self.velocity, 0)
		self:Friction()
	end

	self:CheckVelocity()

	if self.onGround then
		self:WalkMove()
	else
		self:AirMove()
	end

	self:CategorizePosition()
	self:CheckVelocity()
	self:FinishGravity()

	if self.onGround then
		self.velocity = SetY(self.velocity, 0)
	end

	self:CheckFalling()
end

function GameMovement:WalkMove()
	local forward, right = YawBasis(self.yaw)
	local wishvel = forward * self.fmove + right * self.smove
	local wishspeed = wishvel.Magnitude
	local wishdir = if wishspeed > 0 then wishvel / wishspeed else ZERO

	if wishspeed ~= 0 and wishspeed > self.maxspeed then
		wishspeed = self.maxspeed
	end

	self.velocity = SetY(self.velocity, 0)
	self:Accelerate(wishdir, wishspeed, ConVars.sv_accelerate)
	self.velocity = SetY(self.velocity, 0)

	local spd = self.velocity.Magnitude
	if spd < 1 then
		self.velocity = ZERO
		return
	end

	local mins, maxs = self:GetHull()
	local dest = self.origin + self.velocity * self.frametime
	local trace = self:TraceHull(self.origin, dest, mins, maxs)

	if trace.fraction == 1 then
		self.origin = trace.endpos
		self:StayOnGround()
		return
	end

	self:StepMove()
	self:StayOnGround()
end

function GameMovement:StepMove()
	local mins, maxs = self:GetHull()
	local stepsize = ConVars.sv_stepsize
	local vecPos = self.origin
	local vecVel = self.velocity

	-- Slide move down.
	self:TryPlayerMove()
	local vecDownPos = self.origin
	local vecDownVel = self.velocity

	-- Reset original values.
	self.origin = vecPos
	self.velocity = vecVel

	-- Move up a stair height.
	local trace = self:TraceHull(self.origin, self.origin + UP * stepsize, mins, maxs)
	self.origin = trace.endpos

	-- Slide move up.
	self:TryPlayerMove()

	-- Move down a stair (attempt to).
	trace = self:TraceHull(self.origin, self.origin - UP * stepsize, mins, maxs)
	self.origin = trace.endpos

	-- If we are not on the ground any more then use the original movement attempt.
	if not trace.normal or trace.normal.Y < MIN_GROUND_NORMAL then
		self.origin = vecDownPos
		self.velocity = vecDownVel
		return
	end

	local vecUpPos = self.origin

	-- decide which one went farther
	local downDist = (vecDownPos.X - vecPos.X) ^ 2 + (vecDownPos.Z - vecPos.Z) ^ 2
	local upDist = (vecUpPos.X - vecPos.X) ^ 2 + (vecUpPos.Z - vecPos.Z) ^ 2
	if downDist > upDist then
		self.origin = vecDownPos
		self.velocity = vecDownVel
	else
		-- copy z value from slide move
		self.velocity = SetY(self.velocity, vecDownVel.Y)
	end
end

function GameMovement:StayOnGround()
	local mins, maxs = self:GetHull()
	local start = self.origin + UP * 2
	local finish = self.origin - UP * ConVars.sv_stepsize

	-- See how far up we can go without getting stuck
	local trace = self:TraceHull(self.origin, start, mins, maxs)
	start = trace.endpos

	-- Now trace down from a known safe position
	trace = self:TraceHull(start, finish, mins, maxs)
	if trace.fraction > 0 and trace.fraction < 1 and trace.normal and trace.normal.Y >= MIN_GROUND_NORMAL then
		if math.abs(self.origin.Y - trace.endpos.Y) > 0.5 * COORD_RESOLUTION then
			self.origin = trace.endpos
		end
	end
end

------------------------------------------------------------------------
-- Air
------------------------------------------------------------------------

function GameMovement:AirMove()
	local forward, right = YawBasis(self.yaw)
	local wishvel = forward * self.fmove + right * self.smove
	local wishspeed = wishvel.Magnitude
	local wishdir = if wishspeed > 0 then wishvel / wishspeed else ZERO

	if wishspeed ~= 0 and wishspeed > self.maxspeed then
		wishspeed = self.maxspeed
	end

	self:AirAccelerate(wishdir, wishspeed, ConVars.sv_airaccelerate)
	self:TryPlayerMove()
end

------------------------------------------------------------------------
-- Acceleration / friction
------------------------------------------------------------------------

function GameMovement:Accelerate(wishdir: Vector3, wishspeed: number, accel: number)
	local currentspeed = self.velocity:Dot(wishdir)
	local addspeed = wishspeed - currentspeed
	if addspeed <= 0 then
		return
	end

	local accelspeed = accel * self.frametime * wishspeed * self.surfaceFriction
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	self.velocity += wishdir * accelspeed
end

function GameMovement:AirAccelerate(wishdir: Vector3, wishspeed: number, accel: number)
	local wishspd = wishspeed
	-- Cap speed (CGameMovement::GetAirSpeedCap)
	if wishspd > 30 then
		wishspd = 30
	end

	local currentspeed = self.velocity:Dot(wishdir)
	local addspeed = wishspd - currentspeed
	if addspeed <= 0 then
		return
	end

	local accelspeed = accel * wishspeed * self.frametime * self.surfaceFriction
	if accelspeed > addspeed then
		accelspeed = addspeed
	end

	self.velocity += wishdir * accelspeed
end

function GameMovement:Friction()
	local speed = self.velocity.Magnitude
	if speed < 0.1 then
		return
	end

	local drop = 0
	if self.onGround then
		local friction = ConVars.sv_friction * self.surfaceFriction
		local control = if speed < ConVars.sv_stopspeed then ConVars.sv_stopspeed else speed
		drop += control * friction * self.frametime
	end

	local newspeed = math.max(speed - drop, 0)
	if newspeed ~= speed then
		self.velocity *= newspeed / speed
	end
end

------------------------------------------------------------------------
-- Slide move
------------------------------------------------------------------------

function GameMovement:TryPlayerMove(): number
	local mins, maxs = self:GetHull()
	local numbumps = 4
	local blocked = 0
	local numplanes = 0
	local planes = table.create(MAX_CLIP_PLANES)
	local primalVelocity = self.velocity
	local originalVelocity = self.velocity
	local allFraction = 0
	local timeLeft = self.frametime

	for _ = 1, numbumps do
		if self.velocity.Magnitude == 0 then
			break
		end

		local endPos = self.origin + self.velocity * timeLeft
		local trace = self:TraceHull(self.origin, endPos, mins, maxs)

		allFraction += trace.fraction

		-- actually covered some distance
		if trace.fraction > 0 then
			self.origin = trace.endpos
			originalVelocity = self.velocity
			numplanes = 0
		end

		-- moved the entire distance
		if trace.fraction == 1 then
			break
		end

		local n = trace.normal :: Vector3
		if n.Y > MIN_GROUND_NORMAL then
			blocked = bit32.bor(blocked, 1) -- floor
		end
		if math.abs(n.Y) < 1e-4 then
			blocked = bit32.bor(blocked, 2) -- step / wall
		end

		timeLeft -= timeLeft * trace.fraction

		if numplanes >= MAX_CLIP_PLANES then
			self.velocity = ZERO
			break
		end

		numplanes += 1
		planes[numplanes] = n

		if numplanes == 1 and not self.onGround then
			-- reflect player velocity; only one plane in the air
			local newVelocity
			if n.Y > MIN_GROUND_NORMAL then
				newVelocity = ClipVelocity(originalVelocity, n, 1)
			else
				newVelocity = ClipVelocity(originalVelocity, n, 1 + ConVars.sv_bounce * (1 - self.surfaceFriction))
			end
			self.velocity = newVelocity
			originalVelocity = newVelocity
		else
			local i = 1
			while i <= numplanes do
				self.velocity = ClipVelocity(originalVelocity, planes[i], 1)
				local j = 1
				while j <= numplanes do
					if j ~= i and self.velocity:Dot(planes[j]) < 0 then
						break -- not ok
					end
					j += 1
				end
				if j > numplanes then
					break -- didn't have to clip, so we're ok
				end
				i += 1
			end

			if i > numplanes then
				-- go along the crease
				if numplanes ~= 2 then
					self.velocity = ZERO
					break
				end
				local dir = planes[1]:Cross(planes[2])
				if dir.Magnitude < 1e-6 then
					self.velocity = ZERO
					break
				end
				dir = dir.Unit
				self.velocity = dir * dir:Dot(self.velocity)
			end

			-- if velocity is against the original velocity, stop dead
			-- to avoid tiny occilations in sloping corners
			if self.velocity:Dot(primalVelocity) <= 0 then
				self.velocity = ZERO
				break
			end
		end
	end

	if allFraction == 0 then
		self.velocity = ZERO
	end

	return blocked
end

------------------------------------------------------------------------
-- Gravity / velocity
------------------------------------------------------------------------

function GameMovement:StartGravity()
	local v = self.velocity
	self.velocity = SetY(v, v.Y - ConVars.sv_gravity * 0.5 * self.frametime)
	self:CheckVelocity()
end

function GameMovement:FinishGravity()
	local v = self.velocity
	self.velocity = SetY(v, v.Y - ConVars.sv_gravity * 0.5 * self.frametime)
	self:CheckVelocity()
end

function GameMovement:CheckVelocity()
	local maxv = ConVars.sv_maxvelocity
	local v = self.velocity
	local x, y, z = v.X, v.Y, v.Z
	if x ~= x then x = 0 end
	if y ~= y then y = 0 end
	if z ~= z then z = 0 end
	self.velocity = Vector3.new(math.clamp(x, -maxv, maxv), math.clamp(y, -maxv, maxv), math.clamp(z, -maxv, maxv))
	local o = self.origin
	if o.X ~= o.X or o.Y ~= o.Y or o.Z ~= o.Z then
		self.origin = ZERO
	end
end

------------------------------------------------------------------------
-- Jumping
------------------------------------------------------------------------

function GameMovement:CheckJumpButton(): boolean
	-- No more effect
	if not self.onGround then
		self.oldJump = true
		return false
	end

	-- Don't allow jumping when the player is in a stasis field / holding jump
	if self.oldJump and not ConVars.sv_autobunnyhopping then
		return false
	end

	self:SetGroundEntity(nil)

	local gravity = ConVars.sv_gravity
	local flMul = if gravity == 600 then 160 else math.sqrt(2 * gravity * GAMEMOVEMENT_JUMP_HEIGHT)

	local v = self.velocity
	if self.ducked or self.duckAmount > 0 then
		v = SetY(v, flMul)
	else
		v = SetY(v, v.Y + flMul)
	end
	self.velocity = v

	-- HL2: add a little forward velocity based on your current forward velocity
	if ConVars.hl2_jumpboost then
		local forward = YawBasis(self.yaw)
		local flSpeedBoostPerc = if not self.cmd.sprint and not self.ducked then 0.5 else 0.1
		local flSpeedAddition = math.abs(self.fmove * flSpeedBoostPerc)
		local flMaxSpeed = self.maxspeed + self.maxspeed * flSpeedBoostPerc
		local flNewSpeed = flSpeedAddition + Flat(self.velocity).Magnitude

		-- If we're over the maximum, we want to only boost as much as will get us to the goal speed
		if flNewSpeed > flMaxSpeed then
			flSpeedAddition -= flNewSpeed - flMaxSpeed
		end

		if self.fmove < 0 then
			flSpeedAddition *= -1
		end

		self.velocity += forward * flSpeedAddition
	end

	self:FinishGravity()

	self.oldJump = true -- don't jump again until released
	if self.OnJump then
		self.OnJump()
	end
	return true
end

------------------------------------------------------------------------
-- Ground
------------------------------------------------------------------------

function GameMovement:CategorizePosition()
	local mins, maxs = self:GetHull()
	local zvel = self.velocity.Y
	local bMovingUpRapidly = zvel > NON_JUMP_VELOCITY

	if bMovingUpRapidly then
		self:SetGroundEntity(nil)
		return
	end

	local point = self.origin - UP * 2
	local trace = self:TraceHull(self.origin, point, mins, maxs)

	if not trace.instance or not trace.normal or trace.normal.Y < MIN_GROUND_NORMAL then
		self:SetGroundEntity(nil)
		if zvel > 0 then
			self.surfaceFriction = 0.25
		end
	else
		self:SetGroundEntity(trace)
	end
end

function GameMovement:SetGroundEntity(trace: Trace?)
	local wasOnGround = self.onGround

	if trace then
		self.onGround = true
		self.groundInstance = trace.instance
		self.velocity = SetY(self.velocity, 0)
		self:CategorizeGroundSurface(trace)
	else
		if wasOnGround then
			-- keep the platform's momentum when leaving it
			self.velocity += self.platformVelocity
		end
		self.onGround = false
		self.groundInstance = nil
		self.platformVelocity = ZERO
	end
end

function GameMovement:CategorizeGroundSurface(trace: Trace)
	local inst = trace.instance
	local friction = 0.3
	if inst and inst:IsA("Terrain") and trace.material then
		friction = PhysicalProperties.new(trace.material).Friction
	elseif inst and inst:IsA("BasePart") then
		friction = inst.CurrentPhysicalProperties.Friction
	end
	-- Source: m_surfaceFriction = clamp(surfacedata friction * 1.25, 0, 1)
	self.surfaceFriction = math.clamp(friction / FRICTION_REFERENCE, 0, 1)
end

function GameMovement:CheckFalling()
	if self.onGround and self.fallVelocity > 0 then
		if self.fallVelocity >= PLAYER_FALL_PUNCH_THRESHOLD and self.OnLand then
			self.OnLand(self.fallVelocity)
		end
		self.fallVelocity = 0
	end
end

-- Moves the player with whatever part they're standing on (anchored + tweened parts too)
function GameMovement:UpdateGroundCarry()
	local ground = self.onGround and self.groundInstance
	if not ground or not ground:IsA("BasePart") then
		self.carryPart = nil
		self.carryCFrame = nil
		return
	end

	local part = ground :: BasePart
	local cf = part.CFrame

	if self.carryPart == part and self.carryCFrame then
		local ups = ConVars.units_per_stud
		local oldCF = self.carryCFrame :: CFrame
		local originStuds = self.origin / ups
		local movedStuds = cf:PointToWorldSpace(oldCF:PointToObjectSpace(originStuds))
		local delta = (movedStuds - originStuds) * ups
		local mag = delta.Magnitude

		if mag > 1e-4 and mag < MAX_CARRY_PER_TICK then
			local mins, maxs = self:GetHull()
			local trace = self:TraceHull(self.origin, self.origin + delta, mins, maxs)
			self.origin = trace.endpos
			self.platformVelocity = delta / self.frametime
			self.carried = true

			local _, ry = (cf * oldCF:Inverse()):ToEulerAnglesYXZ()
			self.carryYaw = math.deg(ry)
		else
			self.platformVelocity = ZERO
		end
	end

	self.carryPart = part
	self.carryCFrame = cf
end

------------------------------------------------------------------------
-- Ducking
------------------------------------------------------------------------

function GameMovement:Duck()
	-- HandleDuckingSpeedCrop
	if self.ducked and self.onGround then
		self.fmove *= PLAYER_DUCKING_MULTIPLIER
		self.smove *= PLAYER_DUCKING_MULTIPLIER
		self.umove *= PLAYER_DUCKING_MULTIPLIER
	end

	local dt = self.frametime

	if self.cmd.duck then
		if not self.ducked then
			if not self.onGround then
				-- in-air duck is instant and pulls the feet up
				self:FinishDuck()
			else
				self.duckAmount = math.min(self.duckAmount + dt / TIME_TO_DUCK, 1)
				if self.duckAmount >= 1 then
					self:FinishDuck()
				end
			end
		end
	else
		if self.ducked then
			if self:CanUnduck() then
				if not self.onGround then
					self:FinishUnDuck()
				else
					self.duckAmount = math.max(self.duckAmount - dt / TIME_TO_UNDUCK, 0)
					if self.duckAmount <= 0 then
						self:FinishUnDuck()
					end
				end
			else
				-- something above us, stay down
				self.duckAmount = 1
			end
		elseif self.duckAmount > 0 then
			self.duckAmount = math.max(self.duckAmount - dt / TIME_TO_UNDUCK, 0)
		end
	end

	self.viewOffset = VEC_VIEW + (VEC_DUCK_VIEW - VEC_VIEW) * SimpleSpline(self.duckAmount)
end

function GameMovement:FinishDuck()
	if self.ducked then
		return
	end
	self.ducked = true
	self.duckAmount = 1

	if not self.onGround then
		self.origin += UP * DUCK_HULL_DELTA
	end

	self.stuckCooldown = 0
	self:CheckStuck()
	self:CategorizePosition()
end

function GameMovement:CanUnduck(): boolean
	local newOrigin = self.origin
	if not self.onGround then
		newOrigin -= UP * DUCK_HULL_DELTA
	end
	return self:TestHull(newOrigin, VEC_HULL_MIN, VEC_HULL_MAX)
end

function GameMovement:FinishUnDuck()
	if not self.ducked then
		return
	end

	if not self.onGround then
		self.origin -= UP * DUCK_HULL_DELTA
	end

	self.ducked = false
	self.duckAmount = 0
	self:CategorizePosition()
end

------------------------------------------------------------------------
-- Stuck
------------------------------------------------------------------------

function GameMovement:CheckStuck(): boolean
	if self.stuckCooldown > 0 then
		self.stuckCooldown -= self.frametime
		return true
	end

	local mins, maxs = self:GetHull()
	if self:TestHull(self.origin, mins, maxs) then
		return false
	end

	for _, offset in STUCK_OFFSETS do
		local test = self.origin + offset
		if self:TestHull(test, mins, maxs) then
			self.origin = test
			return false
		end
	end

	-- couldn't find a way out; let traces carry us (shapecasts ignore starting overlap)
	self.stuckCooldown = STUCK_RETRY_DELAY
	return true
end

------------------------------------------------------------------------
-- Noclip
------------------------------------------------------------------------

function GameMovement:FullNoClipMove()
	local factor = ConVars.sv_noclipspeed
	local maxacceleration = ConVars.sv_noclipaccelerate

	if self.cmd.sprint then
		factor /= 2
	end

	local forward = CFrame.fromOrientation(math.rad(self.pitch), math.rad(self.yaw), 0).LookVector
	local _, right = YawBasis(self.yaw)

	local wishvel = forward * (self.fmove * factor) + right * (self.smove * factor) + UP * (self.umove * factor)
	local wishspeed = wishvel.Magnitude
	local wishdir = if wishspeed > 0 then wishvel / wishspeed else ZERO
	local maxspeed = ConVars.sv_maxspeed * factor

	if wishspeed > maxspeed then
		wishvel *= maxspeed / wishspeed
		wishspeed = maxspeed
	end

	if maxacceleration > 0 then
		self:Accelerate(wishdir, wishspeed, maxacceleration)

		local spd = self.velocity.Magnitude
		if spd < 1 then
			self.velocity = ZERO
			return
		end

		-- Bleed off some speed, but if we have less than the bleed threshold, bleed the threshold amount.
		local control = if spd < maxspeed / 4 then maxspeed / 4 else spd
		local friction = ConVars.sv_friction * self.surfaceFriction
		local drop = control * friction * self.frametime
		local newspeed = math.max(spd - drop, 0)
		self.velocity *= newspeed / spd
	else
		self.velocity = wishvel
	end

	self.origin += self.velocity * self.frametime
end

return GameMovement
