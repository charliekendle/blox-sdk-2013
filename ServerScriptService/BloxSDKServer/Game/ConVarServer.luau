--!optimize 2
--[[
	ConVarServer (ModuleScript)
	- FCVAR_REPLICATED convars are mirrored to clients as Attributes on
	  ReplicatedStorage.BloxSDK.ReplicatedConVars
	- server command names are published (Commands StringValue) so the client console can
	  autocomplete and forward them
	- ServerCommand remote runs console text on the server (Studio / place owner only)
	- server console output is mirrored to clients
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BloxSDK = ReplicatedStorage:WaitForChild("BloxSDK")
local Shared = BloxSDK:WaitForChild("Shared")
local Cvar = require(Shared:WaitForChild("ConVar"))
local Net = require(Shared:WaitForChild("Net"))

local ConVarServer = {}

local folder: Configuration
local commandsValue: StringValue
local publishQueued = false

local function canRunCommands(plr: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return plr.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return plr:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

local function replicate(var)
	if not var.isCommand and Cvar.HasFlag(var.flags, Cvar.FCVAR_REPLICATED) then
		folder:SetAttribute(var.name, var:GetString())
	end
end

local function publishCommands()
	if publishQueued then
		return
	end
	publishQueued = true
	task.defer(function()
		publishQueued = false
		local lines = {}
		for _, base in Cvar.GetAll() do
			if base.isCommand and not Cvar.HasFlag(base.flags, Cvar.FCVAR_HIDDEN) then
				table.insert(lines, string.format("%s\t%d\t%s", base.name, base.flags, (base.help:gsub("[\t\n]", " "))))
			end
		end
		commandsValue.Value = table.concat(lines, "\n")
	end)
end

function ConVarServer.Init()
	folder = BloxSDK:FindFirstChild("ReplicatedConVars") :: Configuration
	if not folder then
		folder = Instance.new("Configuration")
		folder.Name = "ReplicatedConVars"
		folder.Parent = BloxSDK
	end

	commandsValue = folder:FindFirstChild("Commands") :: StringValue
	if not commandsValue then
		commandsValue = Instance.new("StringValue")
		commandsValue.Name = "Commands"
		commandsValue.Parent = folder
	end

	for _, base in Cvar.GetAll() do
		if not base.isCommand then
			replicate(base)
		end
	end
	publishCommands()

	Cvar.InstallGlobalChangeCallback(replicate)
	Cvar.OnRegister(function(base)
		if base.isCommand then
			publishCommands()
		else
			replicate(base)
		end
	end)

	Net.Get("ServerCommand").OnServerEvent:Connect(function(plr, text)
		if type(text) ~= "string" or #text > 2000 then
			return
		end
		if not canRunCommands(plr) then
			Net.Get("ConsolePrint"):FireClient(plr, "You don't have access to server commands.", Cvar.COLOR_WARNING)
			return
		end
		Cvar.CommandPlayer = plr
		local ok, err = pcall(Cvar.Execute, text)
		Cvar.CommandPlayer = nil
		if not ok then
			Cvar.Warning(tostring(err))
		end
	end)

	-- mirror server console output to everyone's console
	Cvar.OnPrint(function(text, color)
		Net.Get("ConsolePrint"):FireAllClients(text, color)
	end)

	-- late joiners get the recent server history
	Players.PlayerAdded:Connect(function(plr)
		task.wait(2)
		local remote = Net.Get("ConsolePrint")
		local history = Cvar.GetHistory()
		for i = math.max(1, #history - 50), #history do
			remote:FireClient(plr, history[i].text, history[i].color)
		end
	end)
end

return ConVarServer
