--!optimize 2
--[[
	Logic entities - ports of game/server/logicentities.cpp, logicrelay.cpp, logic_timer,
	logic_branch.cpp, logic_compare, logic_case, math_counter (mathcounter in logicentities),
	filters.cpp, point_servercommand / point_clientcommand.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local Cvar = require(Shared:WaitForChild("ConVar"))
local Net = require(Shared:WaitForChild("Net"))

local Game = script.Parent.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local EntityIO = require(Game:WaitForChild("EntityIO"))
local EntityList = require(Game:WaitForChild("EntityList"))

------------------------------------------------------------------------
-- logic_relay
------------------------------------------------------------------------

local SF_REMOVE_ON_FIRE = 1
local SF_ALLOW_FAST_RETRIGGER = 2

local LogicRelay = BaseEntity.extend("logic_relay")
LogicRelay:DeclareOutputs({ "OnTrigger", "OnSpawn" })

function LogicRelay:Spawn()
	self.waitForRefire = false
	-- Fire an output when we spawn. This is used for self-initializing an entity.
	if self:GetOutput("OnSpawn"):NumberOfElements() > 0 then
		self:SetThink(function(ent)
			ent:FireOutput("OnSpawn", ent)
		end, 0.01)
	end
end

LogicRelay.Inputs.trigger = function(self, data)
	if self.disabled or self.waitForRefire then
		return
	end
	self:FireOutput("OnTrigger", data.activator)

	if self:HasSpawnFlags(SF_REMOVE_ON_FIRE) then
		self:Remove()
	elseif not self:HasSpawnFlags(SF_ALLOW_FAST_RETRIGGER) then
		-- Disable the relay so that it cannot be refired until after the last output
		-- has been fired and post an input to re-enable ourselves.
		self.waitForRefire = true
		EntityIO.AddEventToEntity(self, "EnableRefire", nil, self:GetOutput("OnTrigger"):GetMaxDelay() + 0.001, self, self)
	end
end

LogicRelay.Inputs.enablerefire = function(self)
	self.waitForRefire = false
end

LogicRelay.Inputs.enable = function(self)
	self.disabled = false
end

LogicRelay.Inputs.disable = function(self)
	self.disabled = true
end

LogicRelay.Inputs.toggle = function(self)
	self.disabled = not self.disabled
end

LogicRelay.Inputs.cancelpending = function(self)
	EntityIO.CancelEvents(self)
	-- Stop waiting; allow another Trigger.
	self.waitForRefire = false
end

------------------------------------------------------------------------
-- logic_auto
------------------------------------------------------------------------

local LogicAuto = BaseEntity.extend("logic_auto")
LogicAuto:DeclareOutputs({
	"OnMapSpawn", "OnNewGame", "OnLoadGame", "OnMapTransition",
	"OnBackgroundMap", "OnMultiNewMap", "OnMultiNewRound",
})

function LogicAuto:Spawn()
	self:SetThink(function(ent)
		ent:FireOutput("OnMapSpawn", ent)
		ent:FireOutput("OnNewGame", ent)
		ent:FireOutput("OnMultiNewMap", ent)
		ent:FireOutput("OnMultiNewRound", ent)
		if ent:HasSpawnFlags(1) then
			ent:Remove()
		end
	end, 0.2)
end

------------------------------------------------------------------------
-- logic_timer
------------------------------------------------------------------------

local SF_TIMER_UPDOWN = 1
local LOGIC_TIMER_MIN_INTERVAL = 0.01

local LogicTimer = BaseEntity.extend("logic_timer")
LogicTimer:DeclareOutputs({ "OnTimer", "OnTimerHigh", "OnTimerLow" })

function LogicTimer:Spawn()
	self.refireTime = self:GetKeyFloat("refiretime", 0)
	self.useRandom = self:GetKeyBool("userandomtime", false)
	self.lowerBound = self:GetKeyFloat("lowerrandombound", 0)
	self.upperBound = self:GetKeyFloat("upperrandombound", 0)
	self.upDownState = false

	if not self.useRandom and self.refireTime < LOGIC_TIMER_MIN_INTERVAL then
		self.refireTime = LOGIC_TIMER_MIN_INTERVAL
	end

	if not self.disabled then
		self:Schedule()
	end
end

function LogicTimer:GetInterval(): number
	if self.useRandom then
		local lo, hi = math.min(self.lowerBound, self.upperBound), math.max(self.lowerBound, self.upperBound)
		return math.max(lo + math.random() * (hi - lo), LOGIC_TIMER_MIN_INTERVAL)
	end
	return self.refireTime
end

function LogicTimer:Schedule()
	self:SetThink(self.TimerThink, self:GetInterval())
end

function LogicTimer:FireTimer(activator)
	if self:HasSpawnFlags(SF_TIMER_UPDOWN) then
		if self.upDownState then
			self:FireOutput("OnTimerHigh", activator or self)
		else
			self:FireOutput("OnTimerLow", activator or self)
		end
		self.upDownState = not self.upDownState
	else
		self:FireOutput("OnTimer", activator or self)
	end
end

function LogicTimer:TimerThink()
	self:FireTimer(self)
	if not self.disabled and not self.removed then
		self:Schedule()
	end
end

LogicTimer.Inputs.refiretime = function(self, data)
	self.refireTime = math.max(data.value:Float(), LOGIC_TIMER_MIN_INTERVAL)
	if not self.disabled then
		self:Schedule()
	end
end

LogicTimer.Inputs.firetimer = function(self, data)
	self:FireTimer(data.activator)
	if not self.disabled then
		self:Schedule()
	end
end

LogicTimer.Inputs.enable = function(self)
	if self.disabled then
		self.disabled = false
		self:Schedule()
	end
end

LogicTimer.Inputs.disable = function(self)
	self.disabled = true
	self:SetThink(nil)
end

LogicTimer.Inputs.toggle = function(self)
	if self.disabled then
		LogicTimer.Inputs.enable(self)
	else
		LogicTimer.Inputs.disable(self)
	end
end

LogicTimer.Inputs.lowerrandombound = function(self, data)
	self.lowerBound = data.value:Float()
end

LogicTimer.Inputs.upperrandombound = function(self, data)
	self.upperBound = data.value:Float()
end

LogicTimer.Inputs.resettimer = function(self)
	if not self.disabled then
		self:Schedule()
	end
end

LogicTimer.Inputs.addtotimer = function(self, data)
	if not self.disabled and self.nextThink then
		self.nextThink += data.value:Float()
	end
end

LogicTimer.Inputs.subtractfromtimer = function(self, data)
	if not self.disabled and self.nextThink then
		self.nextThink = math.max(self.nextThink - data.value:Float(), EntityIO.CurTime())
	end
end

------------------------------------------------------------------------
-- logic_branch
------------------------------------------------------------------------

local LogicBranch = BaseEntity.extend("logic_branch")
LogicBranch:DeclareOutputs({ "OnTrue", "OnFalse" })

function LogicBranch:Spawn()
	self.inValue = self:GetKeyBool("initialvalue", false)
end

function LogicBranch:UpdateValue(value: boolean, activator, test: boolean)
	self.inValue = value
	if test then
		self:Test(activator)
	end
end

function LogicBranch:Test(activator)
	if self.inValue then
		self:FireOutput("OnTrue", activator)
	else
		self:FireOutput("OnFalse", activator)
	end
end

LogicBranch.Inputs.setvalue = function(self, data)
	self:UpdateValue(data.value:Bool(), data.activator, false)
end

LogicBranch.Inputs.setvaluetest = function(self, data)
	self:UpdateValue(data.value:Bool(), data.activator, true)
end

LogicBranch.Inputs.toggle = function(self, data)
	self:UpdateValue(not self.inValue, data.activator, false)
end

LogicBranch.Inputs.toggletest = function(self, data)
	self:UpdateValue(not self.inValue, data.activator, true)
end

LogicBranch.Inputs.test = function(self, data)
	self:Test(data.activator)
end

------------------------------------------------------------------------
-- logic_compare
------------------------------------------------------------------------

local LogicCompare = BaseEntity.extend("logic_compare")
LogicCompare:DeclareOutputs({ "OnLessThan", "OnEqualTo", "OnNotEqualTo", "OnGreaterThan" })

function LogicCompare:Spawn()
	self.inValue = self:GetKeyFloat("initialvalue", 0)
	self.compareValue = self:GetKeyFloat("comparevalue", 0)
end

function LogicCompare:DoCompare(activator)
	local value = self.inValue
	if value == self.compareValue then
		self:FireOutput("OnEqualTo", activator, value)
	else
		self:FireOutput("OnNotEqualTo", activator, value)
		if value > self.compareValue then
			self:FireOutput("OnGreaterThan", activator, value)
		else
			self:FireOutput("OnLessThan", activator, value)
		end
	end
end

LogicCompare.Inputs.setvalue = function(self, data)
	self.inValue = data.value:Float()
end

LogicCompare.Inputs.setvaluecompare = function(self, data)
	self.inValue = data.value:Float()
	self:DoCompare(data.activator)
end

LogicCompare.Inputs.setcomparevalue = function(self, data)
	self.compareValue = data.value:Float()
end

LogicCompare.Inputs.compare = function(self, data)
	self:DoCompare(data.activator)
end

------------------------------------------------------------------------
-- logic_case
------------------------------------------------------------------------

local MAX_LOGIC_CASES = 16

local LogicCase = BaseEntity.extend("logic_case")
do
	local outputs = { "OnDefault" }
	for i = 1, MAX_LOGIC_CASES do
		table.insert(outputs, string.format("OnCase%02d", i))
	end
	LogicCase:DeclareOutputs(outputs)
end

function LogicCase:Spawn()
	self.cases = {}
	for i = 1, MAX_LOGIC_CASES do
		local v = self:GetKey(string.format("case%02d", i))
		self.cases[i] = if v ~= nil then tostring(v) else nil
	end
	self.shuffleBag = {}
end

function LogicCase:FireCase(i: number, activator)
	self:FireOutput(string.format("OnCase%02d", i), activator)
end

LogicCase.Inputs.invalue = function(self, data)
	local text = data.value:String()
	local num = tonumber(text)
	for i = 1, MAX_LOGIC_CASES do
		local case = self.cases[i]
		if case ~= nil then
			local caseNum = tonumber(case)
			if string.lower(case) == string.lower(text) or (num and caseNum and num == caseNum) then
				self:FireCase(i, data.activator)
				return
			end
		end
	end
	self:FireOutput("OnDefault", data.activator, data.value)
end

local function usedCases(self): { number }
	local list = {}
	for i = 1, MAX_LOGIC_CASES do
		if self:GetOutput(string.format("OnCase%02d", i)):NumberOfElements() > 0 then
			table.insert(list, i)
		end
	end
	return list
end

LogicCase.Inputs.pickrandom = function(self, data)
	local list = usedCases(self)
	if #list > 0 then
		self:FireCase(list[math.random(1, #list)], data.activator)
	end
end

LogicCase.Inputs.pickrandomshuffle = function(self, data)
	if #self.shuffleBag == 0 then
		self.shuffleBag = usedCases(self)
		for i = #self.shuffleBag, 2, -1 do
			local j = math.random(1, i)
			self.shuffleBag[i], self.shuffleBag[j] = self.shuffleBag[j], self.shuffleBag[i]
		end
	end
	local pick = table.remove(self.shuffleBag)
	if pick then
		self:FireCase(pick, data.activator)
	end
end

------------------------------------------------------------------------
-- math_counter
------------------------------------------------------------------------

local MathCounter = BaseEntity.extend("math_counter")
MathCounter:DeclareOutputs({ "OutValue", "OnHitMin", "OnHitMax", "OnGetValue", "OnChangedFromMin", "OnChangedFromMax" })

function MathCounter:Spawn()
	self.min = self:GetKeyFloat("min", 0)
	self.max = self:GetKeyFloat("max", 0)
	if self.min > self.max and self.max ~= 0 then
		self.min, self.max = self.max, self.min
	end
	self.value = math.clamp(self:GetKeyFloat("startvalue", 0), math.min(self.min, self.max), math.max(self.min, self.max))
	if self.min == 0 and self.max == 0 then
		self.value = self:GetKeyFloat("startvalue", 0)
	end
	self.hitMin = false
	self.hitMax = false
end

function MathCounter:HasBounds(): boolean
	return self.min ~= 0 or self.max ~= 0
end

function MathCounter:UpdateOutValue(activator, newValue: number, fire: boolean)
	local old = self.value

	if self:HasBounds() then
		if newValue >= self.max then
			newValue = self.max
			if not self.hitMax then
				self.hitMax = true
				if fire then
					self:FireOutput("OnHitMax", activator)
				end
			end
		else
			self.hitMax = false
		end

		if newValue <= self.min then
			newValue = self.min
			if not self.hitMin then
				self.hitMin = true
				if fire then
					self:FireOutput("OnHitMin", activator)
				end
			end
		else
			self.hitMin = false
		end

		if fire and old == self.max and newValue ~= self.max then
			self:FireOutput("OnChangedFromMax", activator)
		end
		if fire and old == self.min and newValue ~= self.min then
			self:FireOutput("OnChangedFromMin", activator)
		end
	end

	self.value = newValue
	if fire then
		self:FireOutput("OutValue", activator, newValue)
	end
end

local function counterInput(fn: (number, number) -> number?)
	return function(self, data)
		if self.disabled then
			Cvar.DevMsg(1, string.format("Math Counter %s ignoring input because it is disabled", self.targetname))
			return
		end
		local result = fn(self.value, data.value:Float())
		if result then
			self:UpdateOutValue(data.activator, result, true)
		end
	end
end

MathCounter.Inputs.add = counterInput(function(a, b) return a + b end)
MathCounter.Inputs.subtract = counterInput(function(a, b) return a - b end)
MathCounter.Inputs.multiply = counterInput(function(a, b) return a * b end)
MathCounter.Inputs.divide = counterInput(function(a, b)
	if b == 0 then
		Cvar.Warning("math_counter: attempt to divide by zero")
		return nil
	end
	return a / b
end)
MathCounter.Inputs.setvalue = counterInput(function(_, b) return b end)

MathCounter.Inputs.setvaluenofire = function(self, data)
	if not self.disabled then
		self:UpdateOutValue(data.activator, data.value:Float(), false)
	end
end

MathCounter.Inputs.getvalue = function(self, data)
	self:FireOutput("OnGetValue", data.activator, self.value)
end

MathCounter.Inputs.sethitmax = function(self, data)
	self.max = data.value:Float()
	self:UpdateOutValue(data.activator, self.value, true)
end

MathCounter.Inputs.sethitmin = function(self, data)
	self.min = data.value:Float()
	self:UpdateOutValue(data.activator, self.value, true)
end

MathCounter.Inputs.setmaxvaluenofire = function(self, data)
	self.max = data.value:Float()
	self:UpdateOutValue(data.activator, self.value, false)
end

MathCounter.Inputs.setminvaluenofire = function(self, data)
	self.min = data.value:Float()
	self:UpdateOutValue(data.activator, self.value, false)
end

MathCounter.Inputs.enable = function(self)
	self.disabled = false
end

MathCounter.Inputs.disable = function(self)
	self.disabled = true
end

------------------------------------------------------------------------
-- Filters (filters.cpp)
------------------------------------------------------------------------

local BaseFilter = BaseEntity.extend(BaseEntity)
BaseFilter:DeclareOutputs({ "OnPass", "OnFail" })

function BaseFilter:Spawn()
	self.negated = self:GetKeyBool("negated", false)
end

function BaseFilter:PassesFilterImpl(caller, entity): boolean
	return true
end

function BaseFilter:PassesFilter(caller, entity): boolean
	if not entity then
		return false
	end
	local pass = self:PassesFilterImpl(caller, entity)
	if self.negated then
		return not pass
	end
	return pass
end

BaseFilter.Inputs.testactivator = function(self, data)
	if self:PassesFilter(data.caller, data.activator) then
		self:FireOutput("OnPass", data.activator)
	else
		self:FireOutput("OnFail", data.activator)
	end
end

local FilterName = BaseEntity.extend(BaseFilter, "filter_activator_name")

function FilterName:PassesFilterImpl(caller, entity): boolean
	local pattern = self:GetKeyString("filtername")
	if EntityList.NameMatches(pattern, entity.targetname) then
		return true
	end
	-- players have no targetname in Source; let mappers match the Roblox name
	if entity.player then
		return EntityList.NameMatches(pattern, entity.player.Name)
	end
	return false
end

local FilterClass = BaseEntity.extend(BaseFilter, "filter_activator_class")

function FilterClass:PassesFilterImpl(caller, entity): boolean
	return EntityList.NameMatches(self:GetKeyString("filterclass"), entity.classname)
end

local FilterTeam = BaseEntity.extend(BaseFilter, "filter_activator_team")

function FilterTeam:PassesFilterImpl(caller, entity): boolean
	local plr = entity.player
	if not plr or not plr.Team then
		return false
	end
	local want = self:GetKeyString("filterteam")
	return plr.Team.Name == want or tostring(plr.TeamColor.Number) == want
end

local FilterMulti = BaseEntity.extend(BaseFilter, "filter_multi")

function FilterMulti:Activate()
	FilterMulti.super.Activate(self)
	self.filters = {}
	for i = 1, 5 do
		local name = self:GetKeyString(string.format("filter%02d", i))
		if name ~= "" then
			local f = EntityList.FindEntityByName(name, self)
			if f and f.PassesFilter then
				table.insert(self.filters, f)
			end
		end
	end
end

function FilterMulti:PassesFilterImpl(caller, entity): boolean
	local filters = self.filters or {}
	-- filtertype 0 = AND, 1 = OR
	if self:GetKeyInt("filtertype", 0) == 0 then
		for _, f in filters do
			if not f:PassesFilter(caller, entity) then
				return false
			end
		end
		return true
	end
	for _, f in filters do
		if f:PassesFilter(caller, entity) then
			return true
		end
	end
	return #filters == 0
end

------------------------------------------------------------------------
-- point_servercommand / point_clientcommand
------------------------------------------------------------------------

local PointServerCommand = BaseEntity.extend("point_servercommand")

PointServerCommand.Inputs.command = function(self, data)
	local text = data.value:String()
	if text ~= "" then
		Cvar.Execute(text)
	end
end

local PointClientCommand = BaseEntity.extend("point_clientcommand")

PointClientCommand.Inputs.command = function(self, data)
	local activator = data.activator
	local text = data.value:String()
	if activator and activator.player and text ~= "" then
		Net.Get("EntityMessage"):FireClient(activator.player, "command", { text = text })
	end
end

return {}
