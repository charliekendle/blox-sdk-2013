--!optimize 2
--[[
	EntityIO (ModuleScript) - port of COutputEvent / CEventAction / CEventQueue (g_EventQueue)
	from game/server/cbase.cpp + entityoutput.h

	Connection string (same as a VMF output): "target,input,parameter,delay,timesToFire"
	Source's ESC (\27) separator is also accepted. timesToFire -1 = infinite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cvar = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("ConVar"))
local EntityList = require(script.Parent:WaitForChild("EntityList"))
local Variant = require(script.Parent:WaitForChild("Variant"))

local EntityIO = {}

local function curtime(): number
	return workspace.DistributedGameTime
end
EntityIO.CurTime = curtime

------------------------------------------------------------------------
-- CEventAction
------------------------------------------------------------------------

export type EventAction = {
	target: string,
	input: string,
	parameter: string,
	delay: number,
	timesToFire: number,
	id: number,
}

local nextActionId = 1

function EntityIO.ParseAction(text: string): EventAction?
	local sep = if text:find("\27", 1, true) then "\27" else ","
	local fields = {}
	for field in (text .. sep):gmatch("(.-)" .. sep) do
		table.insert(fields, (field:gsub("^%s+", ""):gsub("%s+$", "")))
	end
	if not fields[1] or fields[1] == "" then
		return nil
	end

	local action = {
		target = fields[1],
		input = fields[2] or "",
		parameter = fields[3] or "",
		delay = tonumber(fields[4]) or 0,
		timesToFire = tonumber(fields[5]) or -1,
		id = nextActionId,
	}
	nextActionId += 1
	if action.timesToFire == 0 then
		action.timesToFire = -1
	end
	return action
end

------------------------------------------------------------------------
-- COutputEvent
------------------------------------------------------------------------

local OutputEvent = {}
OutputEvent.__index = OutputEvent

function EntityIO.NewOutput(name: string)
	return setmetatable({ name = name, actions = {} :: { EventAction }, value = Variant.Void() }, OutputEvent)
end

function OutputEvent:AddAction(action: EventAction)
	table.insert(self.actions, action)
end

function OutputEvent:ParseAndAdd(text: string): boolean
	local action = EntityIO.ParseAction(text)
	if action then
		self:AddAction(action)
		return true
	end
	return false
end

function OutputEvent:NumberOfElements(): number
	return #self.actions
end

function OutputEvent:GetMaxDelay(): number
	local m = 0
	for _, a in self.actions do
		m = math.max(m, a.delay)
	end
	return m
end

function OutputEvent:DeleteAllElements()
	table.clear(self.actions)
end

-- value: Variant|any (used when an action has no parameter override)
function OutputEvent:FireOutput(value: any?, activator: any?, caller: any?, extraDelay: number?)
	local variant = if type(value) == "table" and getmetatable(value) == Variant then value else Variant.new(value)
	local delayBase = extraDelay or 0

	local i = 1
	while i <= #self.actions do
		local action = self.actions[i]

		local param = if action.parameter ~= "" then Variant.new(action.parameter) else variant

		Cvar.DevMsg(2, string.format(
			"(%0.2f) output: (%s,%s) -> (%s,%s,%0.1f)(%s)",
			curtime(),
			caller and caller.classname or "?",
			caller and caller.targetname or "",
			action.target,
			action.input,
			action.delay,
			param:String()
		))

		EntityIO.AddEvent(action.target, action.input, param, delayBase + action.delay, activator, caller, action.id)

		if action.timesToFire > 0 then
			action.timesToFire -= 1
			if action.timesToFire == 0 then
				table.remove(self.actions, i)
				continue
			end
		end
		i += 1
	end
end

------------------------------------------------------------------------
-- CEventQueue
------------------------------------------------------------------------

type QueuedEvent = {
	fireTime: number,
	target: string?,
	targetEntity: any?,
	input: string,
	value: any,
	activator: any?,
	caller: any?,
	outputId: number,
}

local queue: { QueuedEvent } = {}

local function insertSorted(ev: QueuedEvent)
	-- keep queue ordered by fire time (stable for equal times)
	local i = #queue
	while i >= 1 and queue[i].fireTime > ev.fireTime do
		i -= 1
	end
	table.insert(queue, i + 1, ev)
end

-- by name (resolved when fired, like Source)
function EntityIO.AddEvent(target: string, input: string, value: any, delay: number, activator: any?, caller: any?, outputId: number?)
	insertSorted({
		fireTime = curtime() + math.max(delay, 0),
		target = target,
		input = input,
		value = value,
		activator = activator,
		caller = caller,
		outputId = outputId or 0,
	})
end

-- directly to an entity
function EntityIO.AddEventToEntity(ent: any, input: string, value: any, delay: number, activator: any?, caller: any?)
	insertSorted({
		fireTime = curtime() + math.max(delay, 0),
		targetEntity = ent,
		input = input,
		value = value,
		activator = activator,
		caller = caller,
		outputId = 0,
	})
end

-- CancelEvents( caller ): removes everything this entity queued
function EntityIO.CancelEvents(caller: any)
	local i = 1
	while i <= #queue do
		if queue[i].caller == caller then
			table.remove(queue, i)
		else
			i += 1
		end
	end
end

-- CancelEventOn( target, input )
function EntityIO.CancelEventOn(target: any, input: string)
	local lower = string.lower(input)
	local i = 1
	while i <= #queue do
		local ev = queue[i]
		if ev.targetEntity == target and string.lower(ev.input) == lower then
			table.remove(queue, i)
		else
			i += 1
		end
	end
end

function EntityIO.HasEventPending(target: any, input: string?): boolean
	for _, ev in queue do
		if ev.targetEntity == target and (input == nil or string.lower(ev.input) == string.lower(input)) then
			return true
		end
	end
	return false
end

function EntityIO.QueueSize(): number
	return #queue
end

function EntityIO.Clear()
	table.clear(queue)
end

function EntityIO.ServiceEvents()
	local now = curtime()

	while #queue > 0 and queue[1].fireTime <= now do
		local ev = table.remove(queue, 1) :: QueuedEvent
		local value = if type(ev.value) == "table" and getmetatable(ev.value) == Variant then ev.value else Variant.new(ev.value)

		local targets
		if ev.targetEntity then
			targets = if ev.targetEntity.removed then {} else { ev.targetEntity }
		else
			targets = EntityList.FindAllGeneric(ev.target :: string, ev.caller, ev.activator, ev.caller)
		end

		if #targets == 0 then
			Cvar.DevMsg(2, string.format("Unhandled input: (%s) -> (%s), from (%s,%s); target entity not found",
				ev.input,
				ev.target or "?",
				ev.caller and ev.caller.classname or "?",
				ev.caller and ev.caller.targetname or ""
			))
		end

		for _, ent in targets do
			Cvar.DevMsg(2, string.format("(%0.2f) input %s: %s.%s(%s)",
				now,
				ev.caller and ev.caller.targetname or "",
				ent.targetname ~= "" and ent.targetname or ent.classname,
				ev.input,
				value:String()
			))
			ent:AcceptInput(ev.input, ev.activator, ev.caller, value, ev.outputId)
		end
	end
end

return EntityIO
