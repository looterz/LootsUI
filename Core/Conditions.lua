local ADDON, ns = ...

local Conditions = {}
ns.Conditions = Conditions

local definitions = {}
local names = {}

function Conditions:Register(definition)
	definitions[definition.name] = definition
	names[#names + 1] = definition.name
	table.sort(names)
end

function Conditions:Get(name)
	return definitions[name]
end

function Conditions:GetNames()
	return names
end

local function trim(text)
	return text:match("^%s*(.-)%s*$")
end

-- Returns negated, name, argument for a single term, or nil when the term is not
-- a plain word (targeting units like @player, for instance) and must be left for
-- the game's parser.
local function parseTerm(term)
	local name, argument = term:match("^(%a+):(.*)$")
	if not name then
		name = term:match("^(%a+)$")
	end
	if not name then
		return false, nil, nil
	end

	name = name:lower()
	if not definitions[name] and name:sub(1, 2) == "no" and definitions[name:sub(3)] then
		return true, name:sub(3), argument
	end

	return false, name, argument
end

-- Strips the custom terms out of one bracket group. A satisfied term simply
-- disappears, an unsatisfied one kills the whole group, and everything else is
-- passed through untouched for the game to evaluate.
local function rewriteGroup(body)
	local kept = {}
	local dead = false
	local sawCustom = false

	for term in body:gmatch("[^,]+") do
		local trimmed = trim(term)
		if trimmed ~= "" then
			local negated, name, argument = parseTerm(trimmed)
			local definition = name and definitions[name]
			if definition then
				sawCustom = true
				local result = definition.evaluate(argument) and true or false
				if negated then
					result = not result
				end
				if not result then
					dead = true
				end
			else
				kept[#kept + 1] = trimmed
			end
		end
	end

	return kept, dead, sawCustom
end

local function splitSegment(segment)
	local groups = {}
	local rest = segment

	while true do
		local body, remainder = rest:match("^%s*%[(.-)%](.*)$")
		if not body then
			break
		end
		groups[#groups + 1] = body
		rest = remainder
	end

	return groups, trim(rest)
end

-- Resolves every custom term in a rule and returns a string containing only
-- stock macro conditionals, so the result can be handed straight to
-- RegisterAttributeDriver and evaluated by the game from then on.
function Conditions:Rewrite(rule)
	if not rule or trim(rule) == "" then
		return "", false
	end

	local output = {}
	local sawCustom = false

	for segment in rule:gmatch("[^;]+") do
		local groups, value = splitSegment(segment)
		if value ~= "" then
			if #groups == 0 then
				output[#output + 1] = value
			else
				local rebuilt = {}
				local unconditional = false

				for _, body in ipairs(groups) do
					local kept, dead, custom = rewriteGroup(body)
					sawCustom = sawCustom or custom
					if not dead then
						if #kept == 0 then
							unconditional = true
						else
							rebuilt[#rebuilt + 1] = "[" .. table.concat(kept, ",") .. "]"
						end
					end
				end

				if unconditional then
					output[#output + 1] = value
				elseif #rebuilt > 0 then
					output[#output + 1] = table.concat(rebuilt) .. " " .. value
				end
			end
		end
	end

	return table.concat(output, "; "), sawCustom
end

function Conditions:CollectUsed(rule, into)
	into = into or {}
	if not rule then
		return into
	end

	for body in rule:gmatch("%[(.-)%]") do
		for term in body:gmatch("[^,]+") do
			local _, name = parseTerm(trim(term))
			if name and definitions[name] then
				into[name] = true
			end
		end
	end

	return into
end

function Conditions:Evaluate(name, argument)
	local definition = definitions[name]
	if not definition then
		return nil
	end
	return definition.evaluate(argument) and true or false
end

function Conditions:Describe(name)
	local definition = definitions[name]
	if definition and definition.detail then
		return definition.detail()
	end
	return ""
end

function Conditions:CollectEvents(used, into)
	into = into or {}
	for name in pairs(used) do
		local definition = definitions[name]
		if definition and definition.events then
			for _, event in ipairs(definition.events) do
				into[event] = true
			end
		end
	end
	return into
end

Conditions:Register({
	name = "damaged",
	group = "Health",
	usage = "[damaged] or [damaged:70]",
	description = "Your health is below maximum, or below the given percent.",
	events = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
	detail = function()
		return string.format("health %d/%d", UnitHealth("player") or 0, UnitHealthMax("player") or 0)
	end,
	evaluate = function(argument)
		local maximum = UnitHealthMax("player")
		if not maximum or maximum <= 0 then
			return false
		end

		local threshold = tonumber(argument)
		if threshold then
			return (UnitHealth("player") / maximum) * 100 < threshold
		end

		return UnitHealth("player") < maximum
	end,
})

Conditions:Register({
	name = "hastarget",
	group = "Target",
	usage = "[hastarget]",
	description = "You have something targeted.",
	events = { "PLAYER_TARGET_CHANGED" },
	detail = function()
		if not UnitExists("target") then
			return "no target"
		end
		return UnitName("target") or "unknown"
	end,
	evaluate = function()
		return UnitExists("target")
	end,
})

Conditions:Register({
	name = "notarget",
	group = "Target",
	usage = "[notarget]",
	description = "You have nothing targeted.",
	events = { "PLAYER_TARGET_CHANGED" },
	evaluate = function()
		return not UnitExists("target")
	end,
})

Conditions:Register({
	name = "instance",
	group = "Location",
	usage = "[instance] or [instance:raid]",
	description = "You are in an instance, optionally of a given type: party, raid, pvp, arena or scenario.",
	events = { "ZONE_CHANGED_NEW_AREA" },
	evaluate = function(argument)
		local inInstance, instanceType = IsInInstance()
		if not inInstance then
			return false
		end

		if argument and argument ~= "" then
			return instanceType == argument:lower()
		end

		return true
	end,
})

local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }

-- Reading whichever resource the character is using right now is what lets one
-- set of conditions cover every class, and follow a druid through its forms.
local function powerValues()
	local index = UnitPowerType("player")
	local maximum = UnitPowerMax("player", index)
	if not maximum or maximum <= 0 then
		return nil
	end

	return UnitPower("player", index) or 0, maximum
end

local function powerDetail()
	local current, maximum = powerValues()
	if not current then
		return "none"
	end

	local _, token = UnitPowerType("player")
	return string.format("%s %d/%d", token and token:lower() or "resource", current, maximum)
end

Conditions:Register({
	name = "resource",
	group = "Resources",
	usage = "[resource] or [resource:90]",
	description = "Whatever your class runs on is below maximum, or below the given percent.",
	events = POWER_EVENTS,
	detail = powerDetail,
	evaluate = function(argument)
		local current, maximum = powerValues()
		if not current then
			return false
		end

		local threshold = tonumber(argument)
		if threshold then
			return (current / maximum) * 100 < threshold
		end

		return current < maximum
	end,
})

Conditions:Register({
	name = "noresource",
	group = "Resources",
	usage = "[noresource]",
	description = "Your resource is completely empty.",
	events = POWER_EVENTS,
	detail = powerDetail,
	evaluate = function()
		local current = powerValues()
		return current ~= nil and current <= 0
	end,
})

Conditions:Register({
	name = "fullresource",
	group = "Resources",
	usage = "[fullresource]",
	description = "Your resource is full.",
	events = POWER_EVENTS,
	detail = powerDetail,
	evaluate = function()
		local current, maximum = powerValues()
		return current ~= nil and current >= maximum
	end,
})
