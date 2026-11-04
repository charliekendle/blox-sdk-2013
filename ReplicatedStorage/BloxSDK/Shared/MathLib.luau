--!optimize 2
--[[
	MathLib (ModuleScript)
	ReplicatedStorage.BloxSDK.Shared.MathLib

	Bits of Source's mathlib + the Source <-> Roblox conversions.

	Source axes:  X forward, Y left, Z up (right-handed)
	Roblox axes:  X right,   Y up,   Z back (right-handed)
	Mapping used everywhere in BloxSDK:  Roblox(x, y, z) = Source(x, z, -y)
]]

local MathLib = {}

local movementConVars = nil

function MathLib.UnitsPerStud(): number
	if not movementConVars then
		local ok, GameMovement = pcall(require, script.Parent:WaitForChild("GameMovement") :: any)
		if ok and GameMovement and GameMovement.ConVars then
			movementConVars = GameMovement.ConVars
		else
			return 14
		end
	end
	return movementConVars.units_per_stud
end

function MathLib.UnitsToStuds(units: number): number
	return units / MathLib.UnitsPerStud()
end

function MathLib.StudsToUnits(studs: number): number
	return studs * MathLib.UnitsPerStud()
end

-- Source vector (x, y, z) -> Roblox axes (same scale)
function MathLib.SourceToRoblox(v: Vector3): Vector3
	return Vector3.new(v.X, v.Z, -v.Y)
end

function MathLib.RobloxToSource(v: Vector3): Vector3
	return Vector3.new(v.X, -v.Z, v.Y)
end

-- AngleVectors( QAngle(pitch, yaw, roll) ) returned in Roblox axes
function MathLib.AngleVectors(pitch: number, yaw: number, roll: number?): (Vector3, Vector3, Vector3)
	local sp, cp = math.sin(math.rad(pitch)), math.cos(math.rad(pitch))
	local sy, cy = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
	local sr, cr = math.sin(math.rad(roll or 0)), math.cos(math.rad(roll or 0))

	local forward = Vector3.new(cp * cy, cp * sy, -sp)
	local right = Vector3.new(-1 * sr * sp * cy + -1 * cr * -sy, -1 * sr * sp * sy + -1 * cr * cy, -1 * sr * cp)
	local up = Vector3.new(cr * sp * cy + -sr * -sy, cr * sp * sy + -sr * cy, cr * cp)

	return MathLib.SourceToRoblox(forward), MathLib.SourceToRoblox(right), MathLib.SourceToRoblox(up)
end

-- parse "x y z" / "p y r" strings
function MathLib.ParseVector(s: any): Vector3?
	if typeof(s) == "Vector3" then
		return s
	end
	if type(s) ~= "string" then
		return nil
	end
	local x, y, z = s:match("^%s*(%S+)%s+(%S+)%s+(%S+)")
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if x and y and z then
		return Vector3.new(x, y, z)
	end
	return nil
end

-- CBaseEntity::SetMovedir: Hammer stores "Up" as 0 -1 0 and "Down" as 0 -2 0.
-- Accepts a Roblox-space Vector3 attribute or a Source "pitch yaw roll" string.
function MathLib.Movedir(value: any): Vector3
	if typeof(value) == "Vector3" then
		return if value.Magnitude > 0 then value.Unit else Vector3.xAxis
	end
	local angles = MathLib.ParseVector(value) or Vector3.zero
	if angles == Vector3.new(0, -1, 0) then
		return Vector3.yAxis
	elseif angles == Vector3.new(0, -2, 0) then
		return -Vector3.yAxis
	end
	local forward = MathLib.AngleVectors(angles.X, angles.Y, angles.Z)
	return forward
end

-- Source angles from a CFrame (pitch, yaw, roll in degrees, Source conventions)
function MathLib.CFrameToSourceAngles(cf: CFrame): (number, number, number)
	local look = MathLib.RobloxToSource(cf.LookVector)
	local yaw = math.deg(math.atan2(look.Y, look.X))
	local pitch = math.deg(math.atan2(-look.Z, math.sqrt(look.X * look.X + look.Y * look.Y)))
	return pitch, yaw, 0
end

-- Roblox camera/view yaw (degrees about +Y, 0 = -Z) from a Source yaw
function MathLib.SourceYawToRoblox(yaw: number): number
	return yaw - 90
end

function MathLib.RobloxYawToSource(yaw: number): number
	return yaw + 90
end

function MathLib.SimpleSpline(v: number): number
	return 3 * v * v - 2 * v * v * v
end

function MathLib.Approach(target: number, value: number, speed: number): number
	local delta = target - value
	if delta > speed then
		return value + speed
	elseif delta < -speed then
		return value - speed
	end
	return target
end

function MathLib.AngleNormalize(angle: number): number
	angle %= 360
	if angle > 180 then
		angle -= 360
	end
	return angle
end

function MathLib.RemapVal(val: number, a: number, b: number, c: number, d: number): number
	if a == b then
		return if val >= b then d else c
	end
	return c + (d - c) * (val - a) / (b - a)
end

function MathLib.RemapValClamped(val: number, a: number, b: number, c: number, d: number): number
	if a == b then
		return if val >= b then d else c
	end
	local t = math.clamp((val - a) / (b - a), 0, 1)
	return c + (d - c) * t
end

------------------------------------------------------------------------
-- Box overlap (separating axis test), used for triggers / touch
------------------------------------------------------------------------

local function axesOf(cf: CFrame): { Vector3 }
	return { cf.RightVector, cf.UpVector, -cf.LookVector }
end

-- OBB vs OBB. halfA/halfB are half sizes in each box's local axes.
function MathLib.BoxesOverlap(cfA: CFrame, halfA: Vector3, cfB: CFrame, halfB: Vector3): boolean
	local A = axesOf(cfA)
	local B = axesOf(cfB)
	local ha = { halfA.X, halfA.Y, halfA.Z }
	local hb = { halfB.X, halfB.Y, halfB.Z }
	local T = cfB.Position - cfA.Position

	local function separated(L: Vector3): boolean
		if L:Dot(L) < 1e-10 then
			return false
		end
		local ra = math.abs(A[1]:Dot(L)) * ha[1] + math.abs(A[2]:Dot(L)) * ha[2] + math.abs(A[3]:Dot(L)) * ha[3]
		local rb = math.abs(B[1]:Dot(L)) * hb[1] + math.abs(B[2]:Dot(L)) * hb[2] + math.abs(B[3]:Dot(L)) * hb[3]
		return math.abs(T:Dot(L)) > ra + rb
	end

	for i = 1, 3 do
		if separated(A[i]) or separated(B[i]) then
			return false
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if separated(A[i]:Cross(B[j])) then
				return false
			end
		end
	end
	return true
end

-- axis-aligned box (centre, half size) vs part
function MathLib.BoxOverlapsPart(center: Vector3, half: Vector3, part: BasePart): boolean
	return MathLib.BoxesOverlap(CFrame.new(center), half, part.CFrame, part.Size / 2)
end

function MathLib.PointInPart(point: Vector3, part: BasePart): boolean
	local lp = part.CFrame:PointToObjectSpace(point)
	local h = part.Size / 2
	return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
end

return MathLib
