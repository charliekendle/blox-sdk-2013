--!optimize 2
--[[
	ConVar (ModuleScript)
	ReplicatedStorage.BloxSDK.Shared.ConVar

	Luau port of Source SDK 2013 tier1 ConVar / ConCommand / ICvar + CCommand tokenizer.

	local Cvar = require(ReplicatedStorage.BloxSDK.Shared.ConVar)

	local sv_gravity = Cvar.ConVar("sv_gravity", 600, Cvar.FCVAR_NOTIFY + Cvar.FCVAR_REPLICATED, "World gravity.")
	sv_gravity:GetFloat()
	sv_gravity:AddChangeCallback(function(var, oldString, oldFloat) end)

	Cvar.ConCommand("hello", function(args)
		Cvar.Msg("hello " .. args:ArgS())
	end, "Says hello.")

	Cvar.Execute("sv_gravity 300; hello world")

	Registry is per Luau VM (client and server each have their own).
]]

local Cvar = {}

------------------------------------------------------------------------
-- Flags (same bit values as Source's iconvar.h)
------------------------------------------------------------------------

Cvar.FCVAR_NONE = 0
Cvar.FCVAR_UNREGISTERED = bit32.lshift(1, 0)
Cvar.FCVAR_DEVELOPMENTONLY = bit32.lshift(1, 1)
Cvar.FCVAR_GAMEDLL = bit32.lshift(1, 2)
Cvar.FCVAR_CLIENTDLL = bit32.lshift(1, 3)
Cvar.FCVAR_HIDDEN = bit32.lshift(1, 4)
Cvar.FCVAR_PROTECTED = bit32.lshift(1, 5)
Cvar.FCVAR_SPONLY = bit32.lshift(1, 6)
Cvar.FCVAR_ARCHIVE = bit32.lshift(1, 7)
Cvar.FCVAR_NOTIFY = bit32.lshift(1, 8)
Cvar.FCVAR_USERINFO = bit32.lshift(1, 9)
Cvar.FCVAR_PRINTABLEONLY = bit32.lshift(1, 10)
Cvar.FCVAR_UNLOGGED = bit32.lshift(1, 11)
Cvar.FCVAR_NEVER_AS_STRING = bit32.lshift(1, 12)
Cvar.FCVAR_REPLICATED = bit32.lshift(1, 13)
Cvar.FCVAR_CHEAT = bit32.lshift(1, 14)

local FLAG_NAMES = {
	{ Cvar.FCVAR_GAMEDLL, "game" },
	{ Cvar.FCVAR_CLIENTDLL, "client" },
	{ Cvar.FCVAR_ARCHIVE, "archive" },
	{ Cvar.FCVAR_NOTIFY, "notify" },
	{ Cvar.FCVAR_SPONLY, "singleplayer" },
	{ Cvar.FCVAR_PROTECTED, "protected" },
	{ Cvar.FCVAR_USERINFO, "user" },
	{ Cvar.FCVAR_REPLICATED, "replicated" },
	{ Cvar.FCVAR_CHEAT, "cheat" },
	{ Cvar.FCVAR_HIDDEN, "hidden" },
	{ Cvar.FCVAR_DEVELOPMENTONLY, "devonly" },
}

local function hasFlag(flags: number, flag: number): boolean
	return bit32.band(flags, flag) ~= 0
end
Cvar.HasFlag = hasFlag

function Cvar.FlagString(flags: number): string
	local out = {}
	for _, pair in FLAG_NAMES do
		if hasFlag(flags, pair[1]) then
			table.insert(out, pair[2])
		end
	end
	return table.concat(out, " ")
end

------------------------------------------------------------------------
-- Output
------------------------------------------------------------------------

Cvar.COLOR_NORMAL = Color3.fromRGB(216, 222, 211)
Cvar.COLOR_ECHO = Color3.fromRGB(255, 255, 255)
Cvar.COLOR_WARNING = Color3.fromRGB(255, 120, 100)
Cvar.COLOR_HIGHLIGHT = Color3.fromRGB(196, 181, 80)

local MAX_HISTORY = 300
local history = {}
local printListeners = {}

-- set by the console UI so other scripts know to release the mouse / ignore keys
Cvar.consoleVisible = false

function Cvar.ConColorMsg(color: Color3, text: string)
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		local entry = { text = line, color = color }
		table.insert(history, entry)
		if #history > MAX_HISTORY then
			table.remove(history, 1)
		end
		for _, fn in printListeners do
			task.spawn(fn, entry.text, entry.color)
		end
	end
end

function Cvar.Msg(text: string)
	Cvar.ConColorMsg(Cvar.COLOR_NORMAL, text)
end

function Cvar.Warning(text: string)
	Cvar.ConColorMsg(Cvar.COLOR_WARNING, text)
end

function Cvar.OnPrint(fn: (string, Color3) -> ()): () -> ()
	table.insert(printListeners, fn)
	return function()
		local i = table.find(printListeners, fn)
		if i then
			table.remove(printListeners, i)
		end
	end
end

function Cvar.GetHistory()
	return history
end

function Cvar.ClearHistory()
	table.clear(history)
end

------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------

local registry: { [string]: any } = {}
local aliases: { [string]: string } = {}
local globalChangeCallbacks = {}

local function formatNumber(n: number): string
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return (string.format("%.6f", n):gsub("0+$", ""):gsub("%.$", ""))
end

local function toValueString(value: any): string
	local t = typeof(value)
	if t == "boolean" then
		return if value then "1" else "0"
	elseif t == "number" then
		return formatNumber(value)
	end
	return tostring(value)
end

------------------------------------------------------------------------
-- ConVar
------------------------------------------------------------------------

local ConVarClass = {}
ConVarClass.__index = ConVarClass

function Cvar.ConVar(
	name: string,
	default: any,
	flags: number?,
	help: string?,
	min: number?,
	max: number?,
	callback: ((any, string, number) -> ())?
)
	local key = string.lower(name)
	local existing = registry[key]
	if existing then
		if not existing.isCommand and callback then
			existing:AddChangeCallback(callback)
		end
		return existing
	end

	local defaultString = toValueString(default)
	local self = setmetatable({
		name = name,
		isCommand = false,
		flags = flags or 0,
		help = help or "",
		default = defaultString,
		min = min,
		max = max,
		value = defaultString,
		float = tonumber(defaultString) or 0,
		int = 0,
		callbacks = {},
	}, ConVarClass)
	self.int = math.floor(self.float)

	if callback then
		table.insert(self.callbacks, callback)
	end

	registry[key] = self
	return self
end

function ConVarClass:GetName(): string
	return self.name
end

function ConVarClass:GetHelpText(): string
	return self.help
end

function ConVarClass:IsFlagSet(flag: number): boolean
	return hasFlag(self.flags, flag)
end

function ConVarClass:AddFlags(flags: number)
	self.flags = bit32.bor(self.flags, flags)
end

function ConVarClass:GetString(): string
	return self.value
end

function ConVarClass:GetFloat(): number
	return self.float
end

function ConVarClass:GetInt(): number
	return self.int
end

function ConVarClass:GetBool(): boolean
	return self.int ~= 0
end

function ConVarClass:GetDefault(): string
	return self.default
end

function ConVarClass:GetMin(): number?
	return self.min
end

function ConVarClass:GetMax(): number?
	return self.max
end

function ConVarClass:AddChangeCallback(fn: (any, string, number) -> ())
	table.insert(self.callbacks, fn)
end

function ConVarClass:SetValue(value: any)
	local s = toValueString(value)
	local f = tonumber(s)

	if f then
		local clamped = f
		if self.min and clamped < self.min then
			clamped = self.min
		end
		if self.max and clamped > self.max then
			clamped = self.max
		end
		if clamped ~= f then
			f = clamped
			s = formatNumber(clamped)
		end
	end

	if s == self.value then
		return
	end

	local oldString, oldFloat = self.value, self.float
	self.value = s
	self.float = f or 0
	self.int = math.floor(self.float)

	if hasFlag(self.flags, Cvar.FCVAR_NOTIFY) then
		Cvar.Msg(string.format("Server cvar \"%s\" changed to %s", self.name, s))
	end

	for _, fn in self.callbacks do
		task.spawn(fn, self, oldString, oldFloat)
	end
	for _, fn in globalChangeCallbacks do
		task.spawn(fn, self, oldString, oldFloat)
	end
end

function ConVarClass:Revert()
	self:SetValue(self.default)
end

------------------------------------------------------------------------
-- CCommand (args)
------------------------------------------------------------------------

local CCommand = {}
CCommand.__index = CCommand

function CCommand:ArgC(): number
	return #self.argv
end

-- 0-based like Source: Arg(0) is the command name
function CCommand:Arg(i: number): string
	return self.argv[i + 1] or ""
end

function CCommand:ArgS(): string
	return self.argS
end

function CCommand:GetCommandString(): string
	return self.commandString
end

function CCommand:FindArg(name: string): string?
	for i, v in self.argv do
		if string.lower(v) == string.lower(name) then
			return self.argv[i + 1]
		end
	end
	return nil
end

-- CCommand::Tokenize
local function tokenize(line: string)
	local argv = {}
	local argS = ""
	local i, n = 1, #line

	while i <= n do
		local ws = line:match("^%s+", i)
		if ws then
			i += #ws
		end
		if i > n then
			break
		end

		if #argv == 1 and argS == "" then
			argS = line:sub(i):gsub("%s+$", "")
		end

		local c = line:sub(i, i)
		if c == '"' then
			local close = line:find('"', i + 1, true)
			if close then
				table.insert(argv, line:sub(i + 1, close - 1))
				i = close + 1
			else
				table.insert(argv, line:sub(i + 1))
				i = n + 1
			end
		else
			local token = line:match("^[^%s\"]+", i) :: string
			table.insert(argv, token)
			i += #token
		end
	end

	return setmetatable({ argv = argv, argS = argS, commandString = line }, CCommand)
end
Cvar.Tokenize = tokenize

-- splits on ';' and newlines outside quotes, strips // comments
local function splitStatements(text: string): { string }
	local out = {}
	local current = {}
	local inQuote = false
	local i, n = 1, #text

	while i <= n do
		local c = text:sub(i, i)
		if c == '"' then
			inQuote = not inQuote
			table.insert(current, c)
		elseif not inQuote and (c == ";" or c == "\n") then
			table.insert(out, table.concat(current))
			table.clear(current)
		elseif not inQuote and c == "/" and text:sub(i + 1, i + 1) == "/" then
			local nl = text:find("\n", i, true)
			if not nl then
				break
			end
			i = nl - 1
		else
			table.insert(current, c)
		end
		i += 1
	end

	table.insert(out, table.concat(current))
	return out
end

------------------------------------------------------------------------
-- ConCommand
------------------------------------------------------------------------

local ConCommandClass = {}
ConCommandClass.__index = ConCommandClass

function Cvar.ConCommand(
	name: string,
	callback: (any) -> (),
	help: string?,
	flags: number?,
	completion: ((string) -> { string })?
)
	local key = string.lower(name)
	local self = setmetatable({
		name = name,
		isCommand = true,
		callback = callback,
		help = help or "",
		flags = flags or 0,
		completion = completion,
	}, ConCommandClass)
	registry[key] = self
	return self
end

function ConCommandClass:GetName(): string
	return self.name
end

function ConCommandClass:GetHelpText(): string
	return self.help
end

function ConCommandClass:IsFlagSet(flag: number): boolean
	return hasFlag(self.flags, flag)
end

function ConCommandClass:Dispatch(args)
	local ok, err = pcall(self.callback, args)
	if not ok then
		Cvar.Warning(string.format("%s: %s", self.name, tostring(err)))
	end
end

------------------------------------------------------------------------
-- ICvar
------------------------------------------------------------------------

function Cvar.Find(name: string)
	return registry[string.lower(name)]
end

function Cvar.FindVar(name: string)
	local base = registry[string.lower(name)]
	if base and not base.isCommand then
		return base
	end
	return nil
end

function Cvar.FindCommand(name: string)
	local base = registry[string.lower(name)]
	if base and base.isCommand then
		return base
	end
	return nil
end

function Cvar.Unregister(name: string)
	registry[string.lower(name)] = nil
end

function Cvar.InstallGlobalChangeCallback(fn: (any, string, number) -> ())
	table.insert(globalChangeCallbacks, fn)
end

function Cvar.GetAll(): { any }
	local list = {}
	for _, base in registry do
		table.insert(list, base)
	end
	table.sort(list, function(a, b)
		return string.lower(a.name) < string.lower(b.name)
	end)
	return list
end

local function isVisible(base): boolean
	return not hasFlag(base.flags, Cvar.FCVAR_HIDDEN) and not hasFlag(base.flags, Cvar.FCVAR_DEVELOPMENTONLY)
end

local function cheatsEnabled(): boolean
	local sv_cheats = registry["sv_cheats"]
	return sv_cheats ~= nil and sv_cheats:GetBool()
end

function Cvar.PrintConVar(var)
	local line = string.format('"%s" = "%s"', var.name, var.value)
	if var.value ~= var.default then
		line ..= string.format(' ( def. "%s" )', var.default)
	end
	if var.min then
		line ..= " min. " .. formatNumber(var.min)
	end
	if var.max then
		line ..= " max. " .. formatNumber(var.max)
	end
	Cvar.Msg(line)

	local flags = Cvar.FlagString(var.flags)
	if flags ~= "" then
		Cvar.Msg(" " .. flags)
	end
	if var.help ~= "" then
		Cvar.Msg(" - " .. var.help)
	end
end

function Cvar.Execute(text: string, depth: number?)
	depth = depth or 0
	if (depth :: number) > 32 then
		Cvar.Warning("Alias recursion too deep, aborting")
		return
	end

	for _, statement in splitStatements(text) do
		local args = tokenize(statement)
		if args:ArgC() == 0 then
			continue
		end

		local name = string.lower(args:Arg(0))
		local alias = aliases[name]
		local base = registry[name]

		if alias and not base then
			Cvar.Execute(alias, (depth :: number) + 1)
		elseif not base then
			Cvar.Msg(string.format('Unknown command "%s"', args:Arg(0)))
		elseif base.isCommand then
			if hasFlag(base.flags, Cvar.FCVAR_CHEAT) and not cheatsEnabled() then
				Cvar.Msg(string.format("Can't use cheat command %s in multiplayer, unless the server has sv_cheats set to 1.", base.name))
			else
				base:Dispatch(args)
			end
		else
			if args:ArgC() == 1 then
				Cvar.PrintConVar(base)
			elseif hasFlag(base.flags, Cvar.FCVAR_CHEAT) and not cheatsEnabled() then
				Cvar.Msg(string.format("Can't change cheat cvar %s unless sv_cheats is 1.", base.name))
			else
				base:SetValue(if args:ArgC() == 2 then args:Arg(1) else args:ArgS())
			end
		end
	end
end

-- echoes like the Source console ("] cmd") then runs it
function Cvar.ExecuteFromConsole(text: string)
	Cvar.ConColorMsg(Cvar.COLOR_ECHO, "] " .. text)
	Cvar.Execute(text)
end

function Cvar.Complete(partial: string, maxResults: number?): { string }
	maxResults = maxResults or 64
	local results = {}
	local lower = string.lower(partial)

	-- command-specific completion once a space is typed
	local space = lower:find(" ", 1, true)
	if space then
		local base = registry[lower:sub(1, space - 1)]
		if base and base.isCommand and base.completion then
			local ok, list = pcall(base.completion, partial)
			if ok and type(list) == "table" then
				for i = 1, math.min(#list, maxResults :: number) do
					table.insert(results, list[i])
				end
			end
		end
		return results
	end

	if lower == "" then
		return results
	end

	for key, base in registry do
		if key:sub(1, #lower) == lower and isVisible(base) then
			table.insert(results, base.name)
		end
	end
	for key in aliases do
		if key:sub(1, #lower) == lower and not registry[key] then
			table.insert(results, key)
		end
	end

	table.sort(results, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	while #results > (maxResults :: number) do
		table.remove(results)
	end
	return results
end

-- completion helper: "cmd <name of any cvar>"
function Cvar.CompleteCvarArgument(partial: string): { string }
	local cmd, rest = partial:match("^(%S+)%s+(.*)$")
	if not cmd then
		return {}
	end
	local out = {}
	for _, name in Cvar.Complete(rest :: string) do
		table.insert(out, cmd .. " " .. name)
	end
	return out
end

------------------------------------------------------------------------
-- Built-ins
------------------------------------------------------------------------

local FCVAR_NOTIFY_REPLICATED = Cvar.FCVAR_NOTIFY + Cvar.FCVAR_REPLICATED

Cvar.ConVar("sv_cheats", 1, FCVAR_NOTIFY_REPLICATED, "Allow cheats on server", 0, 1, function(var)
	if not var:GetBool() then
		-- RevertFlaggedConVars( FCVAR_CHEAT )
		for _, base in registry do
			if not base.isCommand and hasFlag(base.flags, Cvar.FCVAR_CHEAT) then
				base:Revert()
			end
		end
	end
end)

Cvar.ConCommand("help", function(args)
	if args:ArgC() < 2 then
		Cvar.Msg("Usage:  help <cvarname>")
		return
	end
	local base = Cvar.Find(args:Arg(1))
	if not base then
		Cvar.Msg(string.format('help:  no cvar or command named %s', args:Arg(1)))
		return
	end
	if base.isCommand then
		local flags = Cvar.FlagString(base.flags)
		Cvar.Msg(string.format('"%s"%s', base.name, if flags ~= "" then " " .. flags else ""))
		if base.help ~= "" then
			Cvar.Msg(" - " .. base.help)
		end
	else
		Cvar.PrintConVar(base)
	end
end, "Find help about a convar/concommand.", 0, Cvar.CompleteCvarArgument)

Cvar.ConCommand("find", function(args)
	if args:ArgC() < 2 then
		Cvar.Msg("Usage:  find <string>")
		return
	end
	local needle = string.lower(args:Arg(1))
	for _, base in Cvar.GetAll() do
		if not isVisible(base) then
			continue
		end
		if string.lower(base.name):find(needle, 1, true) or string.lower(base.help):find(needle, 1, true) then
			if base.isCommand then
				Cvar.Msg(string.format('"%s" %s - %s', base.name, Cvar.FlagString(base.flags), base.help))
			else
				Cvar.Msg(string.format('"%s" = "%s" %s - %s', base.name, base.value, Cvar.FlagString(base.flags), base.help))
			end
		end
	end
end, "Find concommands with the specified string in their name/help text.")

Cvar.ConCommand("cvarlist", function(args)
	local prefix = string.lower(args:Arg(1))
	local count = 0
	Cvar.Msg("cvar list\n--------------")
	for _, base in Cvar.GetAll() do
		if not isVisible(base) then
			continue
		end
		if prefix ~= "" and string.lower(base.name):sub(1, #prefix) ~= prefix then
			continue
		end
		count += 1
		Cvar.Msg(string.format(
			"%-32s : %-8s : %-24s : %s",
			base.name,
			if base.isCommand then "cmd" else base.value,
			Cvar.FlagString(base.flags),
			base.help
		))
	end
	Cvar.Msg(string.format("--------------\n%d total convars/concommands", count))
end, "Show the list of convars/concommands.")

Cvar.ConCommand("differences", function()
	for _, base in Cvar.GetAll() do
		if not base.isCommand and base.value ~= base.default then
			Cvar.PrintConVar(base)
		end
	end
end, "Show all convars which are not at their default values.")

Cvar.ConCommand("echo", function(args)
	Cvar.Msg(args:ArgS())
end, "Echo text to console.")

Cvar.ConCommand("toggle", function(args)
	if args:ArgC() < 2 then
		Cvar.Msg("Usage:  toggle <cvarname> [value1] [value2] [value3]...")
		return
	end
	local var = Cvar.FindVar(args:Arg(1))
	if not var then
		Cvar.Msg(string.format('toggle: no cvar named %s', args:Arg(1)))
		return
	end
	if hasFlag(var.flags, Cvar.FCVAR_CHEAT) and not cheatsEnabled() then
		Cvar.Msg(string.format("Can't change cheat cvar %s unless sv_cheats is 1.", var.name))
		return
	end

	if args:ArgC() == 2 then
		var:SetValue(if var:GetBool() then 0 else 1)
		return
	end

	-- cycle through the given values
	local values = {}
	for i = 2, args:ArgC() - 1 do
		table.insert(values, args:Arg(i))
	end
	local nextIndex = 1
	for i, v in values do
		if v == var:GetString() or tonumber(v) == var:GetFloat() then
			nextIndex = (i % #values) + 1
			break
		end
	end
	var:SetValue(values[nextIndex])
end, "Toggles a convar on or off, or cycles through a set of values.", 0, Cvar.CompleteCvarArgument)

Cvar.ConCommand("incrementvar", function(args)
	if args:ArgC() ~= 5 then
		Cvar.Msg("Usage:  incrementvar varName minValue maxValue delta")
		return
	end
	local var = Cvar.FindVar(args:Arg(1))
	if not var then
		Cvar.Msg(string.format("cvar \"%s\" not found", args:Arg(1)))
		return
	end
	if hasFlag(var.flags, Cvar.FCVAR_CHEAT) and not cheatsEnabled() then
		Cvar.Msg(string.format("Can't change cheat cvar %s unless sv_cheats is 1.", var.name))
		return
	end
	local minV = tonumber(args:Arg(2)) or 0
	local maxV = tonumber(args:Arg(3)) or 0
	local delta = tonumber(args:Arg(4)) or 0
	local newValue = var:GetFloat() + delta
	if newValue > maxV then
		newValue = minV
	elseif newValue < minV then
		newValue = maxV
	end
	var:SetValue(newValue)
end, "Increment specified convar value.", 0, Cvar.CompleteCvarArgument)

Cvar.ConCommand("alias", function(args)
	if args:ArgC() == 1 then
		Cvar.Msg("Current alias commands:")
		local names = {}
		for name in aliases do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			Cvar.Msg(string.format("%s : %s", name, aliases[name]))
		end
		return
	end

	local name = string.lower(args:Arg(1))
	if args:ArgC() == 2 then
		if aliases[name] then
			Cvar.Msg(string.format("%s : %s", name, aliases[name]))
		else
			Cvar.Msg(string.format("Alias %s not found", name))
		end
		return
	end

	if registry[name] then
		Cvar.Msg(string.format('Cannot alias "%s", it is already a command or cvar', name))
		return
	end

	local parts = {}
	for i = 2, args:ArgC() - 1 do
		table.insert(parts, args:Arg(i))
	end
	aliases[name] = table.concat(parts, " ")
end, "Alias a command.")

Cvar.ConCommand("unalias", function(args)
	local name = string.lower(args:Arg(1))
	if aliases[name] then
		aliases[name] = nil
	else
		Cvar.Msg(string.format("Alias %s not found", name))
	end
end, "Remove an alias.")

Cvar.ConCommand("revert", function(args)
	local var = Cvar.FindVar(args:Arg(1))
	if not var then
		Cvar.Msg("Usage:  revert <cvarname>")
		return
	end
	var:Revert()
end, "Revert a convar to its default value.", 0, Cvar.CompleteCvarArgument)

return Cvar
