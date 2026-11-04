--!optimize 2
--[=[
	KeyValues (ModuleScript)
	ReplicatedStorage.BloxSDK.Shared.KeyValues

	Port of tier1 KeyValues (text format) - the format used by .vmt, .res, gameinfo.txt,
	game_sounds*.txt, soundscapes, VMF, etc.

	local kv = KeyValues.LoadFromString([[
		"Root"
		{
			"speed" "190"
			"Sub" { "a" "1" }
		}
	]])
	kv:GetName()                 -> "Root"
	kv:GetFloat("speed")         -> 190
	kv:FindKey("Sub"):GetInt("a")-> 1
	kv:FindKey("Sub/a")          -> nested path lookup
	for _, sub in kv:GetSubKeys() do ... end
	kv:ToString()

	Supports // comments, quoted and unquoted tokens, escape sequences (\n \t \\ \"),
	[$CONDITIONAL] tags (evaluated against KeyValues.Conditionals), #base / #include
	(resolved through an optional loader callback).
]=]

local KeyValues = {}
KeyValues.__index = KeyValues

-- conditionals considered true, e.g. [$WIN32] [!$X360]
KeyValues.Conditionals = {
	["$WIN32"] = true,
	["$WINDOWS"] = true,
	["$PC"] = true,
}

function KeyValues.new(name: string?)
	return setmetatable({
		name = name or "",
		value = nil :: string?,
		children = {},
	}, KeyValues)
end

------------------------------------------------------------------------
-- Accessors
------------------------------------------------------------------------

function KeyValues:GetName(): string
	return self.name
end

function KeyValues:SetName(name: string)
	self.name = name
end

function KeyValues:IsLeaf(): boolean
	return self.value ~= nil
end

function KeyValues:GetSubKeys(): { any }
	return self.children
end

function KeyValues:GetFirstSubKey()
	return self.children[1]
end

-- case-insensitive, supports "a/b/c" paths
function KeyValues:FindKey(path: string, create: boolean?)
	local node = self
	for part in path:gmatch("[^/]+") do
		local lower = string.lower(part)
		local found = nil
		for _, child in node.children do
			if string.lower(child.name) == lower then
				found = child
				break
			end
		end
		if not found then
			if not create then
				return nil
			end
			found = KeyValues.new(part)
			table.insert(node.children, found)
		end
		node = found
	end
	return node
end

function KeyValues:AddSubKey(kv)
	table.insert(self.children, kv)
	return kv
end

function KeyValues:RemoveSubKey(kv)
	local i = table.find(self.children, kv)
	if i then
		table.remove(self.children, i)
	end
end

function KeyValues:GetString(key: string?, default: string?): string
	local node = if key then self:FindKey(key) else self
	if node and node.value ~= nil then
		return node.value
	end
	return default or ""
end

function KeyValues:GetFloat(key: string?, default: number?): number
	local node = if key then self:FindKey(key) else self
	if node and node.value ~= nil then
		return tonumber(node.value) or 0
	end
	return default or 0
end

function KeyValues:GetInt(key: string?, default: number?): number
	return math.floor(self:GetFloat(key, default))
end

function KeyValues:GetBool(key: string?, default: boolean?): boolean
	local node = if key then self:FindKey(key) else self
	if node and node.value ~= nil then
		return (tonumber(node.value) or 0) ~= 0
	end
	return default or false
end

function KeyValues:IsEmpty(key: string?): boolean
	local node = if key then self:FindKey(key) else self
	return node == nil or (node.value == nil and #node.children == 0)
end

function KeyValues:SetString(key: string, value: string)
	local node = self:FindKey(key, true)
	node.value = tostring(value)
	table.clear(node.children)
end

function KeyValues:SetFloat(key: string, value: number)
	self:SetString(key, tostring(value))
end

function KeyValues:SetInt(key: string, value: number)
	self:SetString(key, tostring(math.floor(value)))
end

function KeyValues:SetBool(key: string, value: boolean)
	self:SetString(key, if value then "1" else "0")
end

function KeyValues:MakeCopy()
	local copy = KeyValues.new(self.name)
	copy.value = self.value
	for _, child in self.children do
		table.insert(copy.children, child:MakeCopy())
	end
	return copy
end

-- merges other into self (other wins), used by #base
function KeyValues:MergeFrom(other)
	for _, child in other.children do
		local mine = self:FindKey(child.name)
		if mine and not mine:IsLeaf() and not child:IsLeaf() then
			mine:MergeFrom(child)
		elseif mine then
			mine.value = child.value
			mine.children = child:MakeCopy().children
		else
			table.insert(self.children, child:MakeCopy())
		end
	end
end

-- flatten leaf values into a plain table (lowercase keys)
function KeyValues:ToTable(): { [string]: any }
	local out = {}
	for _, child in self.children do
		local key = string.lower(child.name)
		if child:IsLeaf() then
			out[key] = child.value
		else
			out[key] = child:ToTable()
		end
	end
	return out
end

------------------------------------------------------------------------
-- Tokenizer
------------------------------------------------------------------------

local ESCAPES = { n = "\n", t = "\t", v = "\v", b = "\b", r = "\r", f = "\f", a = "\a", ["\\"] = "\\", ["?"] = "?", ["'"] = "'", ['"'] = '"' }

local function tokenize(text: string): { { kind: string, value: string } }
	local tokens = {}
	local i, n = 1, #text

	while i <= n do
		local c = text:sub(i, i)

		if c:match("%s") then
			i += 1
		elseif c == "/" and text:sub(i + 1, i + 1) == "/" then
			local nl = text:find("\n", i, true)
			i = if nl then nl + 1 else n + 1
		elseif c == "{" or c == "}" then
			table.insert(tokens, { kind = c, value = c })
			i += 1
		elseif c == "[" then
			local close = text:find("]", i, true) or n
			table.insert(tokens, { kind = "conditional", value = text:sub(i + 1, close - 1) })
			i = close + 1
		elseif c == '"' then
			local buf = {}
			i += 1
			while i <= n do
				local ch = text:sub(i, i)
				if ch == "\\" and i < n then
					local nxt = text:sub(i + 1, i + 1)
					table.insert(buf, ESCAPES[nxt] or ("\\" .. nxt))
					i += 2
				elseif ch == '"' then
					i += 1
					break
				else
					table.insert(buf, ch)
					i += 1
				end
			end
			table.insert(tokens, { kind = "string", value = table.concat(buf) })
		else
			local token = text:match('^[^%s{}"%[%]]+', i) :: string
			-- unquoted tokens stop at a // comment
			local comment = token:find("//", 1, true)
			if comment then
				token = token:sub(1, comment - 1)
			end
			if token == "" then
				i += 1
			else
				table.insert(tokens, { kind = "string", value = token })
				i += #token
			end
		end
	end

	return tokens
end

local function evaluateConditional(cond: string): boolean
	-- supports !, ||, &&
	local function term(t: string): boolean
		t = t:gsub("^%s+", ""):gsub("%s+$", "")
		local negate = false
		if t:sub(1, 1) == "!" then
			negate = true
			t = t:sub(2)
		end
		local v = KeyValues.Conditionals[string.upper(t)] == true
		return if negate then not v else v
	end
	for orPart in (cond .. "||"):gmatch("(.-)||") do
		local all = true
		for andPart in (orPart .. "&&"):gmatch("(.-)&&") do
			if not term(andPart) then
				all = false
				break
			end
		end
		if all then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- Parser
------------------------------------------------------------------------

export type Loader = (path: string) -> string?

local function parseBlock(tokens, pos: number, node, loader: Loader?): number
	while pos <= #tokens do
		local tok = tokens[pos]

		if tok.kind == "}" then
			return pos + 1
		end

		if tok.kind ~= "string" then
			pos += 1
			continue
		end

		local key = tok.value
		pos += 1

		-- #base / #include
		if (key == "#base" or key == "#include") and tokens[pos] and tokens[pos].kind == "string" then
			local path = tokens[pos].value
			pos += 1
			if loader then
				local text = loader(path)
				if text then
					local included = KeyValues.LoadFromString(text, loader)
					if included then
						if key == "#base" then
							node:MergeFrom(included)
						else
							table.insert(node.children, included)
						end
					end
				end
			end
			continue
		end

		local nextTok = tokens[pos]
		if not nextTok then
			break
		end

		if nextTok.kind == "{" then
			local child = KeyValues.new(key)
			pos = parseBlock(tokens, pos + 1, child, loader)
			local include = true
			if tokens[pos] and tokens[pos].kind == "conditional" then
				include = evaluateConditional(tokens[pos].value)
				pos += 1
			end
			if include then
				table.insert(node.children, child)
			end
		elseif nextTok.kind == "string" then
			pos += 1
			local include = true
			if tokens[pos] and tokens[pos].kind == "conditional" then
				include = evaluateConditional(tokens[pos].value)
				pos += 1
			end
			if include then
				local child = KeyValues.new(key)
				child.value = nextTok.value
				table.insert(node.children, child)
			end
		else
			pos += 1
		end
	end
	return pos
end

-- Returns the first root key (like KeyValues::LoadFromBuffer). Use LoadAllFromString for multi-root files.
function KeyValues.LoadFromString(text: string, loader: Loader?)
	local roots = KeyValues.LoadAllFromString(text, loader)
	return roots[1]
end

function KeyValues.LoadAllFromString(text: string, loader: Loader?): { any }
	local tokens = tokenize(text)
	local container = KeyValues.new("")
	parseBlock(tokens, 1, container, loader)
	return container.children
end

------------------------------------------------------------------------
-- Writer
------------------------------------------------------------------------

local function escape(s: string): string
	return (s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t"))
end

function KeyValues:ToString(indent: number?): string
	indent = indent or 0
	local pad = string.rep("\t", indent :: number)
	local out = {}
	if self.value ~= nil then
		table.insert(out, string.format('%s"%s"\t\t"%s"', pad, escape(self.name), escape(self.value)))
	else
		table.insert(out, string.format('%s"%s"', pad, escape(self.name)))
		table.insert(out, pad .. "{")
		for _, child in self.children do
			table.insert(out, child:ToString((indent :: number) + 1))
		end
		table.insert(out, pad .. "}")
	end
	return table.concat(out, "\n")
end

return KeyValues
