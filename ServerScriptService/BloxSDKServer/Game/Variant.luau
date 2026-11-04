--!optimize 2
--[[
	Variant (ModuleScript) - port of variant_t (game/server/variant_t.h)
	Values passed through entity I/O. Stored typed, converts on demand like Source.
]]

local Variant = {}
Variant.__index = Variant

Variant.FIELD_VOID = "void"
Variant.FIELD_FLOAT = "float"
Variant.FIELD_INTEGER = "integer"
Variant.FIELD_BOOLEAN = "boolean"
Variant.FIELD_STRING = "string"
Variant.FIELD_VECTOR = "vector"
Variant.FIELD_COLOR32 = "color32"
Variant.FIELD_EHANDLE = "ehandle"

function Variant.new(value: any?)
	local self = setmetatable({ fieldType = Variant.FIELD_VOID, value = nil }, Variant)
	if value ~= nil then
		self:Set(value)
	end
	return self
end

function Variant.Void()
	return Variant.new()
end

function Variant:Set(value: any)
	local t = typeof(value)
	if t == "number" then
		self.fieldType = if value == math.floor(value) then Variant.FIELD_INTEGER else Variant.FIELD_FLOAT
	elseif t == "boolean" then
		self.fieldType = Variant.FIELD_BOOLEAN
	elseif t == "Vector3" then
		self.fieldType = Variant.FIELD_VECTOR
	elseif t == "Color3" then
		self.fieldType = Variant.FIELD_COLOR32
	elseif t == "table" and value.classname then
		self.fieldType = Variant.FIELD_EHANDLE
	else
		self.fieldType = Variant.FIELD_STRING
		value = tostring(value)
	end
	self.value = value
end

function Variant:FieldType(): string
	return self.fieldType
end

function Variant:IsVoid(): boolean
	return self.fieldType == Variant.FIELD_VOID
end

function Variant:String(): string
	local t, v = self.fieldType, self.value
	if t == Variant.FIELD_VOID then
		return ""
	elseif t == Variant.FIELD_STRING then
		return v
	elseif t == Variant.FIELD_INTEGER then
		return string.format("%d", v)
	elseif t == Variant.FIELD_FLOAT then
		return string.format("%g", v)
	elseif t == Variant.FIELD_BOOLEAN then
		return if v then "1" else "0"
	elseif t == Variant.FIELD_VECTOR then
		return string.format("[%g %g %g]", v.X, v.Y, v.Z)
	elseif t == Variant.FIELD_COLOR32 then
		return string.format("%d %d %d", v.R * 255, v.G * 255, v.B * 255)
	elseif t == Variant.FIELD_EHANDLE then
		return v.targetname ~= "" and v.targetname or v.classname
	end
	return tostring(v)
end

function Variant:Float(): number
	local t, v = self.fieldType, self.value
	if t == Variant.FIELD_FLOAT or t == Variant.FIELD_INTEGER then
		return v
	elseif t == Variant.FIELD_BOOLEAN then
		return if v then 1 else 0
	elseif t == Variant.FIELD_STRING then
		return tonumber(v:match("^%s*([%-%+%.%deE]+)")) or 0
	end
	return 0
end

function Variant:Int(): number
	local f = self:Float()
	return if f >= 0 then math.floor(f) else math.ceil(f)
end

function Variant:Bool(): boolean
	local t, v = self.fieldType, self.value
	if t == Variant.FIELD_BOOLEAN then
		return v
	end
	return self:Float() ~= 0
end

function Variant:Vector3(): Vector3
	local t, v = self.fieldType, self.value
	if t == Variant.FIELD_VECTOR then
		return v
	elseif t == Variant.FIELD_STRING then
		local x, y, z = v:gsub("[%[%]]", ""):match("(%S+)%s+(%S+)%s+(%S+)")
		return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
	end
	return Vector3.zero
end

function Variant:Color3(): Color3
	local t, v = self.fieldType, self.value
	if t == Variant.FIELD_COLOR32 then
		return v
	elseif t == Variant.FIELD_STRING then
		local r, g, b = v:match("(%d+)%s+(%d+)%s+(%d+)")
		return Color3.fromRGB(tonumber(r) or 255, tonumber(g) or 255, tonumber(b) or 255)
	end
	return Color3.new(1, 1, 1)
end

function Variant:Entity()
	if self.fieldType == Variant.FIELD_EHANDLE then
		return self.value
	end
	return nil
end

function Variant:Copy()
	local c = Variant.new()
	c.fieldType = self.fieldType
	c.value = self.value
	return c
end

Variant.__tostring = function(self)
	return self:String()
end

return Variant
