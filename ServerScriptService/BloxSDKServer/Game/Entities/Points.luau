--!optimize 2
--[[
	Point entities - info_target, info_teleport_destination, info_landmark, info_player_start
	(+ HL2DM/CS/TF spawn variants), point_teleport, game_text, ambient_generic
	Point entities are hidden at spawn; their part's pivot is the origin/angles.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("BloxSDK"):WaitForChild("Shared")
local MathLib = require(Shared:WaitForChild("MathLib"))
local Net = require(Shared:WaitForChild("Net"))

local Game = script.Parent.Parent
local BaseEntity = require(Game:WaitForChild("BaseEntity"))
local EntityList = require(Game:WaitForChild("EntityList"))
local PlayerManager = require(Game:WaitForChild("PlayerManager"))

------------------------------------------------------------------------
-- markers
------------------------------------------------------------------------

local PointMarker = BaseEntity.extend(BaseEntity)

for _, classname in {
	"info_target",
	"info_teleport_destination",
	"info_landmark",
	"info_null",
	"info_player_start",
	"info_player_deathmatch",
	"info_player_combine",
	"info_player_rebel",
	"info_player_terrorist",
	"info_player_counterterrorist",
	"info_player_teamspawn",
} do
	local class = BaseEntity.extend(PointMarker, classname)
	class.Inputs.enable = function(self)
		self.disabled = false
	end
	class.Inputs.disable = function(self)
		self.disabled = true
	end
end

-- HL2DM / CS / TF spawns all count as player starts
do
	local original = EntityList.FindAllByClassname
	EntityList.FindAllSpawnPoints = function(): { any }
		local list = {}
		for _, cls in { "info_player_start", "info_player_deathmatch", "info_player_combine", "info_player_rebel", "info_player_terrorist", "info_player_counterterrorist", "info_player_teamspawn" } do
			for _, ent in original(cls) do
				table.insert(list, ent)
			end
		end
		return list
	end
end

------------------------------------------------------------------------
-- point_teleport
------------------------------------------------------------------------

local PointTeleport = BaseEntity.extend("point_teleport")

PointTeleport.Inputs.teleport = function(self, data)
	local targets = EntityList.FindAllGeneric(self:GetKeyString("target"), self, data.activator, data.caller)
	local pivot = self:GetPivot()
	for _, target in targets do
		if target.Teleport then
			target:Teleport(pivot.Position * MathLib.UnitsPerStud(), self:GetYaw(), nil)
		else
			target:SetPivot(pivot)
		end
	end
end

------------------------------------------------------------------------
-- game_text
------------------------------------------------------------------------

local SF_ENVTEXT_ALLPLAYERS = 1

local GameText = BaseEntity.extend("game_text")

local function parseColor(value: any, default: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "string" then
		local r, g, b = value:match("(%d+)%s+(%d+)%s+(%d+)")
		if r then
			return Color3.fromRGB(tonumber(r) :: number, tonumber(g) :: number, tonumber(b) :: number)
		end
	end
	return default
end

function GameText:BuildMessage()
	return {
		message = self:GetKeyString("message"):gsub("\\n", "\n"),
		x = self:GetKeyFloat("x", -1),
		y = self:GetKeyFloat("y", -1),
		effect = self:GetKeyInt("effect", 0),
		color = parseColor(self:GetKey("color"), Color3.fromRGB(100, 100, 100)),
		color2 = parseColor(self:GetKey("color2"), Color3.fromRGB(240, 110, 0)),
		fadein = self:GetKeyFloat("fadein", 1.5),
		fadeout = self:GetKeyFloat("fadeout", 0.5),
		holdtime = self:GetKeyFloat("holdtime", 1.2),
		fxtime = self:GetKeyFloat("fxtime", 0.25),
		channel = self:GetKeyInt("channel", 1),
	}
end

function GameText:Display(activator)
	local msg = self:BuildMessage()
	local remote = Net.Get("EntityMessage")
	if self:HasSpawnFlags(SF_ENVTEXT_ALLPLAYERS) then
		remote:FireAllClients("gametext", msg)
	elseif activator and activator.player then
		remote:FireClient(activator.player, "gametext", msg)
	end
end

GameText.Inputs.display = function(self, data)
	self:Display(data.activator)
end

GameText.Inputs.settext = function(self, data)
	self.keyvalues.message = data.value:String()
end

function GameText:Use(activator)
	self:Display(activator)
end

------------------------------------------------------------------------
-- ambient_generic
------------------------------------------------------------------------

local SF_AMBIENT_SOUND_EVERYWHERE = 1
local SF_AMBIENT_SOUND_START_SILENT = 16
local SF_AMBIENT_SOUND_NOT_LOOPING = 32

local AmbientGeneric = BaseEntity.extend("ambient_generic")

function AmbientGeneric:Spawn()
	local id = BaseEntity.ResolveSoundId(self:GetKey("message"))
	if not id then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "ambient_generic"
	sound.SoundId = id
	sound.Looped = not self:HasSpawnFlags(SF_AMBIENT_SOUND_NOT_LOOPING)
	sound.Volume = math.clamp(self:GetKeyFloat("health", 10), 0, 10) / 10
	sound.PlaybackSpeed = math.clamp(self:GetKeyFloat("pitch", 100), 1, 255) / 100
	sound.RollOffMaxDistance = self:GetKeyFloat("radius", 1250) / MathLib.UnitsPerStud()
	sound.RollOffMinDistance = math.min(10, sound.RollOffMaxDistance)

	local parent: Instance = SoundService
	if not self:HasSpawnFlags(SF_AMBIENT_SOUND_EVERYWHERE) then
		-- SourceEntityName: play from another entity
		local sourceName = self:GetKeyString("sourceentityname")
		local source = if sourceName ~= "" then EntityList.FindEntityByName(sourceName, self) else nil
		parent = (source and source:GetParts()[1]) or self:GetParts()[1] or SoundService
	end
	sound.Parent = parent
	self.sound = sound
	self.baseVolume = sound.Volume

	if not self:HasSpawnFlags(SF_AMBIENT_SOUND_START_SILENT) and sound.Looped then
		sound:Play()
	end
end

function AmbientGeneric:OnRemove()
	if self.sound then
		self.sound:Destroy()
	end
end

AmbientGeneric.Inputs.playsound = function(self)
	if self.sound then
		self.sound.Volume = self.baseVolume
		self.sound:Play()
	end
end

AmbientGeneric.Inputs.stopsound = function(self)
	if self.sound then
		self.sound:Stop()
	end
end

AmbientGeneric.Inputs.togglesound = function(self)
	if self.sound then
		if self.sound.IsPlaying then
			self.sound:Stop()
		else
			self.sound:Play()
		end
	end
end

AmbientGeneric.Inputs.volume = function(self, data)
	if self.sound then
		self.sound.Volume = math.clamp(data.value:Float(), 0, 10) / 10
	end
end

AmbientGeneric.Inputs.pitch = function(self, data)
	if self.sound then
		self.sound.PlaybackSpeed = math.clamp(data.value:Float(), 1, 255) / 100
	end
end

AmbientGeneric.Inputs.fadein = function(self, data)
	if self.sound then
		self.sound.Volume = 0
		self.sound:Play()
		TweenService:Create(self.sound, TweenInfo.new(math.max(data.value:Float(), 0)), { Volume = self.baseVolume }):Play()
	end
end

AmbientGeneric.Inputs.fadeout = function(self, data)
	if self.sound then
		local tween = TweenService:Create(self.sound, TweenInfo.new(math.max(data.value:Float(), 0)), { Volume = 0 })
		tween.Completed:Connect(function()
			if self.sound then
				self.sound:Stop()
			end
		end)
		tween:Play()
	end
end

------------------------------------------------------------------------
-- spawn point selection uses every spawn variant
------------------------------------------------------------------------

PlayerManager.SpawnPointProvider = EntityList.FindAllSpawnPoints

return {}
