--!optimize 2
--[[
	EntityList (ModuleScript) - port of CGlobalEntityList (gEntList) + the entity factory
	(LINK_ENTITY_TO_CLASS / CreateEntityByName).

	Names support Source's special targets and wildcards:
	  !self !activator !caller !player !picker   and   "door_*" (trailing wildcard)
]]

local EntityList = {}

local entities: { any } = {}
local byInstance: { [Instance]: any } = {}
local factories: { [string]: any } = {}
local nextIndex = 1

-- set by PlayerManager: (activatorEntity) -> entity under that player's crosshair
EntityList.PickerResolver = nil :: ((any) -> any)?

------------------------------------------------------------------------
-- Factory
------------------------------------------------------------------------

function EntityList.LinkEntityToClass(classname: string, class: any)
	factories[string.lower(classname)] = class
	class.ClassName = string.lower(classname)
end

function EntityList.GetFactory(classname: string): any
	return factories[string.lower(classname)]
end

function EntityList.GetFactoryNames(): { string }
	local names = {}
	for name in factories do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- CreateEntityByName: allocates, does not spawn
function EntityList.CreateEntityByName(classname: string, instance: Instance?): any?
	local class = factories[string.lower(classname)]
	if not class then
		return nil
	end
	local ent = class.new(instance)
	ent.classname = string.lower(classname)
	return ent
end

------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------

function EntityList.Add(ent: any)
	ent.entindex = nextIndex
	nextIndex += 1
	table.insert(entities, ent)
	if ent.instance then
		byInstance[ent.instance] = ent
	end
end

function EntityList.Remove(ent: any)
	local i = table.find(entities, ent)
	if i then
		table.remove(entities, i)
	end
	if ent.instance then
		byInstance[ent.instance] = nil
	end
end

function EntityList.All(): { any }
	return entities
end

function EntityList.Count(): number
	return #entities
end

function EntityList.ByIndex(index: number): any?
	for _, ent in entities do
		if ent.entindex == index then
			return ent
		end
	end
	return nil
end

-- walks up from a part to the entity that owns it
function EntityList.FromInstance(inst: Instance?): any?
	while inst and inst ~= workspace and inst ~= game do
		local ent = byInstance[inst]
		if ent then
			return ent
		end
		inst = inst.Parent
	end
	return nil
end

------------------------------------------------------------------------
-- Searching
------------------------------------------------------------------------

local function nameMatches(pattern: string, name: string?): boolean
	if not name or name == "" then
		return false
	end
	local p, n = string.lower(pattern), string.lower(name)
	if p:sub(-1) == "*" then
		return n:sub(1, #p - 1) == p:sub(1, -2)
	end
	return p == n
end
EntityList.NameMatches = nameMatches

local function resolveSpecial(name: string, searchingEntity: any?, activator: any?, caller: any?): (boolean, { any })
	local lower = string.lower(name)
	if lower:sub(1, 1) ~= "!" then
		return false, {}
	end

	if lower == "!self" then
		return true, { searchingEntity }
	elseif lower == "!activator" then
		return true, { activator }
	elseif lower == "!caller" then
		return true, { caller }
	elseif lower == "!player" or lower == "!pvsplayer" then
		for _, ent in entities do
			if ent.classname == "player" and not ent.removed then
				return true, { ent }
			end
		end
		return true, {}
	elseif lower == "!picker" then
		local resolver = EntityList.PickerResolver
		if resolver and activator then
			return true, { resolver(activator) }
		end
		return true, {}
	end
	return true, {}
end

-- every entity with this targetname (handles !special and wildcards)
function EntityList.FindAllByName(name: string, searchingEntity: any?, activator: any?, caller: any?): { any }
	local special, list = resolveSpecial(name, searchingEntity, activator, caller)
	if special then
		local out = {}
		for _, ent in list do
			if ent and not ent.removed then
				table.insert(out, ent)
			end
		end
		return out
	end

	local out = {}
	for _, ent in entities do
		if not ent.removed and nameMatches(name, ent.targetname) then
			table.insert(out, ent)
		end
	end
	return out
end

function EntityList.FindAllByClassname(classname: string): { any }
	local out = {}
	for _, ent in entities do
		if not ent.removed and nameMatches(classname, ent.classname) then
			table.insert(out, ent)
		end
	end
	return out
end

-- FindEntityGeneric: targetname first, then classname
function EntityList.FindAllGeneric(name: string, searchingEntity: any?, activator: any?, caller: any?): { any }
	local list = EntityList.FindAllByName(name, searchingEntity, activator, caller)
	if #list == 0 then
		list = EntityList.FindAllByClassname(name)
	end
	return list
end

function EntityList.FindEntityByName(name: string, searchingEntity: any?, activator: any?, caller: any?): any?
	return EntityList.FindAllByName(name, searchingEntity, activator, caller)[1]
end

function EntityList.FindEntityByClassname(classname: string): any?
	return EntityList.FindAllByClassname(classname)[1]
end

function EntityList.FindEntityGeneric(name: string, searchingEntity: any?, activator: any?, caller: any?): any?
	return EntityList.FindAllGeneric(name, searchingEntity, activator, caller)[1]
end

return EntityList
