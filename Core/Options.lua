local ADDON, ns = ...

local Options = {}
ns.Options = Options

local Registry = ns.Registry
local Conditions = ns.Conditions
local Profiles = ns.Profiles

local PRESETS = {
	immersive = {
		label = "Immersive",
		description = "Hides most of the interface until you hold a modifier, enter combat, or take damage.",
		rules = {
			actionBar1 = "[mod:ctrl][mod:alt][combat] show; hide",
			actionBar2 = "[mod:ctrl][mod:alt][combat] show; hide",
			actionBar3 = "[mod:ctrl][mod:alt][combat] show; hide",
			actionBar4 = "[mod:ctrl][mod:alt,nocombat] show; hide",
			actionBar5 = "[mod:ctrl][mod:alt,nocombat] show; hide",
			petBar = "[mod:ctrl][combat] show; hide",
			stanceBar = "[mod:ctrl][combat] show; hide",
			playerFrame = "[mod:ctrl][combat][damaged] show; hide",
			targetFrame = "[mod:ctrl][@target,exists] show; hide",
			petFrame = "[mod:ctrl][combat] show; hide",
			bossFrames = "[mod:ctrl][combat] show; hide",
			minimap = "[mod:ctrl][noinstance] show; hide",
			microMenu = "[mod:ctrl] show; hide",
			bags = "[mod:ctrl] show; hide",
			experienceBar = "[mod:ctrl][mod:alt] show; hide",
			objectiveTracker = "[mod:ctrl][noinstance,nocombat] show; hide",
			castBar = "[combat][mod:ctrl] show; hide",
		},
	},
	resting = {
		label = "Rested",
		description = "Keeps the interface visible everywhere except while resting in an inn or city.",
		rules = {
			actionBar1 = "[resting,nomod,nocombat] hide; show",
			actionBar2 = "[resting,nomod,nocombat] hide; show",
			minimap = "[resting,nomod,nocombat] hide; show",
			microMenu = "[resting,nomod,nocombat] hide; show",
			objectiveTracker = "[resting,nomod,nocombat] hide; show",
		},
	},
}

function Options:GetPresets()
	return PRESETS
end

local GROUP_ORDER = { "Health", "Resources", "Target", "Stealth", "Location" }

local function buildConditionHelp()
	local byGroup = {}
	local found = {}

	for _, name in ipairs(Conditions:GetNames()) do
		local definition = Conditions:Get(name)
		local group = definition.group or "Other"

		if not byGroup[group] then
			byGroup[group] = {}
			found[#found + 1] = group
		end

		local list = byGroup[group]
		list[#list + 1] = string.format("|cff00ccff%s|r  %s", definition.usage, definition.description)
	end

	local order, seen = {}, {}
	for _, group in ipairs(GROUP_ORDER) do
		if byGroup[group] then
			order[#order + 1] = group
			seen[group] = true
		end
	end
	for _, group in ipairs(found) do
		if not seen[group] then
			order[#order + 1] = group
			seen[group] = true
		end
	end

	local lines = {
		"|cffffd200LootsUI conditions|r",
		"Everything below is added by LootsUI. Mix them with the game's own conditionals freely, and put no in front of any of them to invert it.",
		"",
	}

	for _, group in ipairs(order) do
		lines[#lines + 1] = "|cffffd200" .. group .. "|r"
		for _, line in ipairs(byGroup[group]) do
			lines[#lines + 1] = line
		end
		lines[#lines + 1] = ""
	end

	return table.concat(lines, "\n")
end

local HELP = table.concat({
	"|cffffd200How it works|r",
	"Give a frame a macro conditional and LootsUI shows or hides it to match.",
	"An empty box means LootsUI leaves that frame alone.",
	"",
	"|cffffd200Syntax|r",
	"[condition] show; hide",
	"[condition] hide; show",
	"Several groups in a row are an or, so [mod:ctrl][combat] matches either.",
	"",
	"|cffffd200Examples|r",
	"|cff00ff00Action Bar 1|r  [mod:ctrl][combat] show; hide",
	"|cff00ff00Player Frame|r  [mod:ctrl][combat][damaged] show; hide",
	"|cff00ff00Minimap|r  [resting,nomod] hide; show",
	"|cff00ff00Raid Frames|r  [group:raid] show; hide",
	"",
}, "\n")

local FOOTER = table.concat({
	"|cffffd200Commands|r",
	"|cff00ccff/loots|r opens these options",
	"|cff00ccff/loots show|r reveals everything without losing your rules",
	"|cff00ccff/loots hide|r puts your rules back in charge",
	"|cff00ccff/loots toggle|r flips between the two, handy in a macro",
	"",
	"Stock conditionals are documented at |cff00ccffhttps://warcraft.wiki.gg/wiki/Macro_conditionals|r",
}, "\n")

function Options:Build(addon)
	local options = {
		name = "LootsUI",
		handler = addon,
		type = "group",
		childGroups = "tab",
		get = "GetRuleValue",
		set = "SetRuleValue",
		args = {
			help = {
				type = "group",
				name = "Help",
				order = 0,
				args = {
					intro = { type = "description", order = 1, fontSize = "medium", name = HELP },
					conditions = { type = "description", order = 2, fontSize = "medium", name = buildConditionHelp() },
					footer = { type = "description", order = 3, fontSize = "medium", name = FOOTER },
				},
			},
			fading = {
				type = "group",
				name = "Fading",
				order = 80,
				get = "GetFadeSetting",
				set = "SetFadeSetting",
				args = {
					intro = {
						type = "description",
						order = 1,
						fontSize = "medium",
						name = "How frames come and go when a rule changes. Fading costs a little more than snapping straight to hidden, so anything you want to react instantly is better left on Instant.\n",
					},
					mode = {
						type = "select",
						order = 2,
						name = "Transition",
						desc = "Used by every frame that does not override it below.",
						values = { instant = "Instant", fade = "Fade" },
					},
					inDuration = {
						type = "range",
						order = 3,
						name = "Fade in time",
						desc = "Seconds a frame takes to go from hidden to fully visible.",
						min = 0.05,
						max = 2,
						step = 0.05,
					},
					outDuration = {
						type = "range",
						order = 4,
						name = "Fade out time",
						desc = "Seconds a frame takes to go from fully visible to hidden.",
						min = 0.05,
						max = 2,
						step = 0.05,
					},
					overrides = {
						type = "group",
						inline = true,
						order = 10,
						name = "Per frame",
						get = "GetFadeOverride",
						set = "SetFadeOverride",
						args = {},
					},
				},
			},
			presets = {
				type = "group",
				name = "Presets",
				order = 90,
				args = {
					warning = {
						type = "description",
						order = 1,
						fontSize = "medium",
						name = "Applying a preset overwrites the rules in the active profile. Branch or export your profile in the Profiles tab first if you want to keep what you have.\n",
					},
					clear = {
						type = "execute",
						order = 2,
						name = "Clear all rules",
						desc = "Empties every box in this profile and hands all frames back to the game.",
						confirm = true,
						confirmText = "Clear every rule in the active profile?",
						func = function() addon:ClearAllRules() end,
					},
				},
			},
		},
	}

	local presetKeys = {}
	for key in pairs(PRESETS) do
		presetKeys[#presetKeys + 1] = key
	end
	table.sort(presetKeys)

	for index, key in ipairs(presetKeys) do
		local preset = PRESETS[key]
		options.args.presets.args[key] = {
			type = "execute",
			order = 10 + index,
			name = preset.label,
			desc = preset.description,
			confirm = true,
			confirmText = preset.label .. " will replace every rule in the active profile.",
			func = function() addon:ApplyPreset(key) end,
		}
	end

	options.args.profiles = Profiles:BuildOptions(addon)

	local categoryOrder = 1
	local overrideOrder = 1
	for _, category in ipairs(Registry:GetCategories()) do
		local group = {
			type = "group",
			name = category.label,
			order = categoryOrder,
			args = {},
		}

		local entryOrder = 1
		for _, entry in ipairs(Registry:GetCategoryEntries(category.key)) do
			group.args[entry.key] = {
				type = "input",
				name = entry.label,
				width = "full",
				order = entryOrder,
				desc = function()
					local frames = Registry:ResolveFrames(entry)
					if #frames == 0 then
						return "Not present in this version of the game."
					end
					return "Frame: " .. table.concat(frames, ", ")
				end,
				disabled = function()
					return not Registry:IsAvailable(entry)
				end,
				validate = function(_, value)
					return addon:ValidateRule(value)
				end,
			}
			options.args.fading.args.overrides.args[entry.key] = {
				type = "select",
				name = entry.label,
				order = overrideOrder,
				values = { default = "Default", instant = "Instant", fade = "Fade" },
				disabled = function()
					return not Registry:IsAvailable(entry)
				end,
			}

			entryOrder = entryOrder + 1
			overrideOrder = overrideOrder + 1
		end

		options.args[category.key] = group
		categoryOrder = categoryOrder + 1
	end

	return options
end
