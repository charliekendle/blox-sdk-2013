--!optimize 2
--[[
	EntityCommands (ModuleScript) - Source's entity debugging console commands
	ent_fire, ent_remove, ent_remove_all, ent_dump, ent_info, report_entities, ent_list_factories, ent_spawn_all
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cvar = require(ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared"):WaitForChild("ConVar"))

local Game = script.Parent
local EntityIO = require(Game:WaitForChild("EntityIO"))
local EntityList = require(Game:WaitForChild("EntityList"))
local PlayerManager = require(Game:WaitForChild("PlayerManager"))
local Variant = require(Game:WaitForChild("Variant"))

local EntityCommands = {}

local CHEAT = Cvar.FCVAR_CHEAT
local GAMEDLL = Cvar.FCVAR_GAMEDLL

local function commandActivator(): any?
	return PlayerManager.ForPlayer(Cvar.CommandPlayer)
end

local function describe(ent): string
	return string.format("%s(%s) #%d", ent.classname, ent.targetname ~= "" and ent.targetname or "unnamed", ent.entindex or 0)
end

function EntityCommands.Init()
	Cvar.ConCommand("ent_fire", function(args)
		if args:ArgC() < 2 then
			Cvar.Msg("Usage:\n   ent_fire <target> [action] [value] [delay]")
			return
		end
		local target = args:Arg(1)
		local action = if args:ArgC() >= 3 then args:Arg(2) else "Use"
		local value = args:Arg(3)
		local delay = tonumber(args:Arg(4)) or 0
		local activator = commandActivator()

		-- resolve !picker etc. now, against the commanding player
		local targets = EntityList.FindAllGeneric(target, activator, activator, activator)
		if #targets == 0 then
			Cvar.Msg(string.format("ent_fire: no entity matching '%s'", target))
			return
		end
		for _, ent in targets do
			EntityIO.AddEventToEntity(ent, action, Variant.new(value), delay, activator, activator)
		end
	end, "Usage:\n   ent_fire <target> [action] [value] [delay]\n   Fires an input on matching entities (name, classname, !picker, !player).", CHEAT + GAMEDLL)

	Cvar.ConCommand("ent_remove", function(args)
		local name = if args:ArgC() >= 2 then args:Arg(1) else "!picker"
		local activator = commandActivator()
		local ent = EntityList.FindEntityGeneric(name, activator, activator, activator)
		if not ent then
			Cvar.Msg("ent_remove: nothing found")
			return
		end
		Cvar.Msg("Removed " .. describe(ent))
		ent:Remove()
	end, "Removes the given entity (or the one under the crosshair)", CHEAT + GAMEDLL)

	Cvar.ConCommand("ent_remove_all", function(args)
		if args:ArgC() < 2 then
			Cvar.Msg("Removes all entities of the specified type\n\tArguments:   \t{entity_name} / {class_name}")
			return
		end
		local list = EntityList.FindAllGeneric(args:Arg(1))
		local n = 0
		for _, ent in list do
			if not ent:IsPlayer() then
				ent:Remove()
				n += 1
			end
		end
		Cvar.Msg(string.format("Removed %d %s's", n, args:Arg(1)))
	end, "Removes all entities of the specified type", CHEAT + GAMEDLL)

	Cvar.ConCommand("ent_dump", function(args)
		if args:ArgC() < 2 then
			Cvar.Msg("Usage:\n   ent_dump <entity name>")
			return
		end
		local activator = commandActivator()
		for _, ent in EntityList.FindAllGeneric(args:Arg(1), activator, activator, activator) do
			Cvar.Msg(describe(ent))
			local keys = {}
			for k in ent.keyvalues do
				table.insert(keys, k)
			end
			table.sort(keys)
			for _, k in keys do
				Cvar.Msg(string.format("  %s: %s", k, tostring(ent.keyvalues[k])))
			end
			for _, out in ent.outputs do
				for _, a in out.actions do
					Cvar.Msg(string.format("  %s -> %s,%s,%s,%g,%d", out.name, a.target, a.input, a.parameter, a.delay, a.timesToFire))
				end
			end
		end
	end, "Usage:\n   ent_dump <entity name>\n", CHEAT + GAMEDLL)

	Cvar.ConCommand("ent_info", function(args)
		if args:ArgC() < 2 then
			Cvar.Msg("Usage:\n   ent_info <class name>")
			return
		end
		local class = EntityList.GetFactory(args:Arg(1))
		if not class then
			Cvar.Msg("no such class " .. args:Arg(1))
			return
		end
		Cvar.Msg("Outputs:")
		for _, name in class.OutputNames do
			Cvar.Msg("  " .. name)
		end
		Cvar.Msg("Inputs:")
		local inputs = {}
		local t = class.Inputs
		while t do
			for k in t do
				if not table.find(inputs, k) then
					table.insert(inputs, k)
				end
			end
			local mt = getmetatable(t)
			t = mt and mt.__index
		end
		table.sort(inputs)
		for _, k in inputs do
			Cvar.Msg("  " .. k)
		end
	end, "Usage:\n   ent_info <class name>\n", GAMEDLL)

	Cvar.ConCommand("report_entities", function()
		local counts = {}
		for _, ent in EntityList.All() do
			counts[ent.classname] = (counts[ent.classname] or 0) + 1
		end
		local names = {}
		for name in counts do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			Cvar.Msg(string.format("Class: %s (%d)", name, counts[name]))
		end
		Cvar.Msg(string.format("Total %d entities, %d events queued", EntityList.Count(), EntityIO.QueueSize()))
	end, "Lists all entities", GAMEDLL)

	Cvar.ConCommand("ent_list_factories", function()
		for _, name in EntityList.GetFactoryNames() do
			Cvar.Msg(name)
		end
	end, "Lists all entity factory names.", GAMEDLL)
end

return EntityCommands
