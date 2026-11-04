--!optimize 2
--[[
	TouchSystem (ModuleScript)
	Source does touch via the engine's collision; here we test reported player hulls
	against registered brush entities and call StartTouch / Touch / EndTouch.

	TouchSystem.Register(ent, marginUnits)  - triggers use 0, "touch opens" doors/buttons ~2
]]

local TouchSystem = {}

local touchables: { [any]: number } = {}
local contacts: { [any]: { [any]: boolean } } = {}

function TouchSystem.Register(ent: any, marginUnits: number?)
	touchables[ent] = marginUnits or 0
	contacts[ent] = contacts[ent] or {}
end

function TouchSystem.Unregister(ent: any)
	local c = contacts[ent]
	if c then
		for other in c do
			if ent.EndTouch then
				ent:EndTouch(other)
			end
		end
	end
	touchables[ent] = nil
	contacts[ent] = nil
end

local function overlaps(ent: any, other: any, margin: number): boolean
	local center, half = other:GetHullBox(margin)
	if ent.Overlaps then
		return ent:Overlaps(center, half)
	end
	return false
end

-- players: { playerEntity } (living ones)
function TouchSystem.Service(players: { any })
	for ent, margin in touchables do
		if ent.removed then
			TouchSystem.Unregister(ent)
			continue
		end

		local c = contacts[ent]
		local active = not (ent.disabled and ent:IsTrigger())

		-- end touches for players who left / died / were removed
		for other in table.clone(c) do
			if not active or other.removed or not other:IsAlive() or not overlaps(ent, other, margin) then
				c[other] = nil
				ent:EndTouch(other)
			end
		end

		if active then
			for _, other in players do
				if not c[other] and overlaps(ent, other, margin) then
					c[other] = true
					ent:StartTouch(other)
				end
			end
			for other in table.clone(c) do
				if ent.removed then
					break
				end
				ent:Touch(other)
			end
		end
	end
end

function TouchSystem.IsTouching(ent: any, other: any): boolean
	local c = contacts[ent]
	return c ~= nil and c[other] == true
end

return TouchSystem
