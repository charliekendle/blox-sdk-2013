--!optimize 2
--[[
	Net (ModuleScript)
	ReplicatedStorage.BloxSDK.Shared.Net

	Remote definitions. The server creates them under ReplicatedStorage.BloxSDK.Remotes,
	clients wait for them.

	PlayerState     client -> server  (unreliable) origin, velocity, ducked, onGround, pitch, yaw, teleportSeq
	MovementEffect  server -> client  "teleport" | "push" | "impulse" | "clearpush"
	Use             client -> server  eye (studs), direction
	EntityMessage   server -> client  "gametext" ...
	ServerCommand   client -> server  console text
	ConsolePrint    server -> client  text, color
]]

local RunService = game:GetService("RunService")

local Net = {}

local DEFS = {
	PlayerState = "UnreliableRemoteEvent",
	MovementEffect = "RemoteEvent",
	Use = "RemoteEvent",
	EntityMessage = "RemoteEvent",
	ServerCommand = "RemoteEvent",
	ConsolePrint = "RemoteEvent",
}

local root = script.Parent.Parent -- ReplicatedStorage.BloxSDK
local folder: Instance? = nil
local cache: { [string]: any } = {}

local function getFolder(): Instance
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = root:FindFirstChild("Remotes")
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = "Remotes"
			existing.Parent = root
		end
		folder = existing
	else
		folder = root:WaitForChild("Remotes")
	end
	return folder :: Instance
end

function Net.Get(name: string): any
	local remote = cache[name]
	if remote then
		return remote
	end

	local className = DEFS[name]
	assert(className, "Unknown remote " .. name)

	local parent = getFolder()
	if RunService:IsServer() then
		remote = parent:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = parent
		end
	else
		remote = parent:WaitForChild(name)
	end

	cache[name] = remote
	return remote
end

-- server: create everything up front so clients never wait
function Net.Init()
	for name in DEFS do
		Net.Get(name)
	end
end

return Net
