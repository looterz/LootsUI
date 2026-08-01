local ADDON, ns = ...

local Profiles = {}
ns.Profiles = Profiles

local Registry = ns.Registry

local EXPORT_HEADER = "LootsUI:1"

function Profiles:Defaults()
	return {
		rules = Registry:BuildDefaults(),
		overrides = {},
		fade = {
			mode = "fade",
			inDuration = 0.10,
			outDuration = 0.10,
		},
	}
end

local function characterProfileName()
	return UnitName("player") .. " - " .. GetRealmName()
end

local function trim(text)
	return text:match("^%s*(.-)%s*$")
end

-- True when nothing in the stored table differs from the defaults, which is what
-- a profile looks like when it was created by a stray click and never edited.
local function matchesDefaults(data, defaults)
	if type(data) ~= "table" then
		return data == defaults
	end
	if type(defaults) ~= "table" then
		return false
	end

	for key, value in pairs(data) do
		if type(value) == "table" then
			if not matchesDefaults(value, defaults[key]) then
				return false
			end
		elseif value ~= defaults[key] then
			return false
		end
	end

	return true
end

-- AceDB's DeleteProfile leaves other characters' assignments behind, and a key
-- pointing at a missing profile resurrects it empty on their next login instead
-- of falling back to Default.
local function forgetProfileKeys(db, name)
	if not db.sv.profileKeys then
		return
	end

	for character, assigned in pairs(db.sv.profileKeys) do
		if assigned == name then
			db.sv.profileKeys[character] = nil
		end
	end
end

-- The stock profiles page offered class and realm names as one click profile
-- creators, so databases in the wild carry profiles like "Mage" or "Whitemane"
-- holding nothing. Anything indistinguishable from a fresh profile is dropped,
-- and characters parked on one go back to Default. A profile holding any real
-- setting is never touched.
function Profiles:Cleanup(db)
	local stored = db.sv and db.sv.profiles
	if not stored then
		return
	end

	local defaults = self:Defaults()

	if db:GetCurrentProfile() ~= "Default" and matchesDefaults(db.profile, defaults) then
		db:SetProfile("Default")
	end

	local current = db:GetCurrentProfile()

	local names = {}
	for name in pairs(stored) do
		names[#names + 1] = name
	end

	for _, name in ipairs(names) do
		if name ~= "Default" and name ~= current and matchesDefaults(stored[name], defaults) then
			db:DeleteProfile(name, true)
			forgetProfileKeys(db, name)
		end
	end
end

function Profiles:Export(profile)
	local lines = { EXPORT_HEADER }

	lines[#lines + 1] = "fade.mode=" .. tostring(profile.fade.mode)
	lines[#lines + 1] = "fade.inDuration=" .. tostring(profile.fade.inDuration)
	lines[#lines + 1] = "fade.outDuration=" .. tostring(profile.fade.outDuration)

	for _, entry in ipairs(Registry:GetEntries()) do
		local rule = profile.rules[entry.key]
		if rule and rule ~= "" then
			lines[#lines + 1] = "rule." .. entry.key .. "=" .. rule
		end

		local override = profile.overrides[entry.key]
		if override then
			lines[#lines + 1] = "override." .. entry.key .. "=" .. override
		end
	end

	return table.concat(lines, "\n")
end

-- Returns a full profile table built from defaults plus the export, or nil and
-- a reason. Unknown sections and keys are skipped rather than rejected, so an
-- export from a newer version still loads what this one understands.
function Profiles:Import(text)
	if type(text) ~= "string" then
		return nil, "Nothing to import."
	end

	local data = self:Defaults()
	local seenHeader = false

	for raw in text:gmatch("[^\r\n]+") do
		local line = trim(raw)
		if line ~= "" then
			if not seenHeader then
				if line ~= EXPORT_HEADER then
					return nil, "This is not a LootsUI export. The first line should be " .. EXPORT_HEADER .. "."
				end
				seenHeader = true
			else
				local section, key, value = line:match("^(%a+)%.([%w_]+)%s*=%s*(.-)%s*$")
				if not section then
					return nil, 'Could not read this line: "' .. line .. '"'
				end

				if section == "fade" then
					if key == "mode" then
						if value ~= "instant" and value ~= "fade" then
							return nil, "Fade mode must be instant or fade."
						end
						data.fade.mode = value
					elseif key == "inDuration" or key == "outDuration" then
						local number = tonumber(value)
						if not number then
							return nil, "Fade durations must be numbers."
						end
						data.fade[key] = math.min(2, math.max(0.05, number))
					end
				elseif section == "rule" then
					if Registry:GetEntry(key) then
						local opened = select(2, value:gsub("%[", ""))
						local closed = select(2, value:gsub("%]", ""))
						if opened ~= closed then
							return nil, "Unbalanced brackets in the rule for " .. key .. "."
						end
						data.rules[key] = value
					end
				elseif section == "override" then
					if Registry:GetEntry(key) and (value == "instant" or value == "fade") then
						data.overrides[key] = value
					end
				end
			end
		end
	end

	if not seenHeader then
		return nil, "Nothing to import."
	end

	return data
end

-- Returns the trimmed name, or nil and a reason. Names in the character key
-- format are refused because the picker treats them as belonging to a
-- character, so a shared profile named that way would vanish from the list.
function Profiles:ValidateName(db, value)
	local name = trim(value or "")

	if name == "" then
		return nil, "Give the profile a name."
	end
	if name:find(" - ", 1, true) then
		return nil, 'Names containing " - " are reserved for character profiles.'
	end
	if name == "Default" or (db.sv.profiles or {})[name] then
		return nil, "A profile named " .. name .. " already exists."
	end

	return name
end

function Profiles:Create(db, name)
	db:SetProfile(name)
end

function Profiles:Duplicate(db, name)
	local source = db:GetCurrentProfile()
	db:SetProfile(name)
	db:CopyProfile(source, true)
end

-- AceDB has no rename, so this is switch, copy, delete. Other characters
-- assigned to the old name are pointed at the new one, because a dangling key
-- would otherwise resurrect the old profile empty on their next login.
function Profiles:Rename(db, name)
	local old = db:GetCurrentProfile()

	db:SetProfile(name)
	db:CopyProfile(old, true)
	db:DeleteProfile(old, true)

	if db.sv.profileKeys then
		for character, assigned in pairs(db.sv.profileKeys) do
			if assigned == old then
				db.sv.profileKeys[character] = name
			end
		end
	end
end

local function listSwitchable(db)
	local values = { Default = "Default" }
	local character = characterProfileName()
	local current = db:GetCurrentProfile()

	for _, name in ipairs(db:GetProfiles()) do
		local characterStyle = name:find(" - ", 1, true) ~= nil
		if name == current or name == character or not characterStyle then
			values[name] = name
		end
	end

	return values
end

local function listDeletable(db)
	local values = {}
	local current = db:GetCurrentProfile()

	for _, name in ipairs(db:GetProfiles()) do
		if name ~= current and name ~= "Default" then
			values[name] = name
		end
	end

	return values
end

-- Unlike the picker, this list includes other characters' profiles. Reading
-- from one is the whole point: it is how a character borrows the setup of
-- another that shares its needs.
local function listCopyable(db)
	local values = {}
	local current = db:GetCurrentProfile()

	for _, name in ipairs(db:GetProfiles()) do
		if name ~= current then
			values[name] = name
		end
	end

	return values
end

local function applyImport(addon, data)
	local profile = addon.db.profile

	for _, entry in ipairs(Registry:GetEntries()) do
		profile.rules[entry.key] = data.rules[entry.key] or ""
		profile.overrides[entry.key] = data.overrides[entry.key]
	end

	profile.fade.mode = data.fade.mode
	profile.fade.inDuration = data.fade.inDuration
	profile.fade.outDuration = data.fade.outDuration

	addon:ReloadProfile()
	addon:Print("Settings imported into the " .. addon.db:GetCurrentProfile() .. " profile.")
end

function Profiles:BuildOptions(addon)
	return {
		type = "group",
		name = "Profiles",
		order = 100,
		args = {
			intro = {
				type = "description",
				order = 1,
				fontSize = "medium",
				name = "Every character starts on the shared Default profile, so a change made there follows you everywhere. To give one character its own settings, branch: the new profile starts as a copy of what you have now and only shows up for that character.\n",
			},
			current = {
				type = "select",
				order = 2,
				name = "Active profile",
				desc = "The profile this character reads its settings from.",
				values = function() return listSwitchable(addon.db) end,
				get = function() return addon.db:GetCurrentProfile() end,
				set = function(_, value) addon.db:SetProfile(value) end,
			},
			branch = {
				type = "execute",
				order = 3,
				name = function() return "Branch for " .. UnitName("player") end,
				desc = function()
					local name = characterProfileName()
					if (addon.db.sv.profiles or {})[name] then
						return name .. " already exists. Pick it from the Active profile list."
					end
					return "Copies the active profile into " .. name .. " and switches this character to it."
				end,
				disabled = function()
					return (addon.db.sv.profiles or {})[characterProfileName()] ~= nil
				end,
				func = function()
					Profiles:Duplicate(addon.db, characterProfileName())
				end,
			},
			manage = {
				type = "group",
				inline = true,
				order = 5,
				name = "Manage profiles",
				args = {
					create = {
						type = "input",
						order = 1,
						name = "New profile",
						desc = "Type a name and press Enter. The new profile starts from the defaults and this character switches to it.",
						get = function() return "" end,
						validate = function(_, value)
							local _, err = Profiles:ValidateName(addon.db, value)
							return err or true
						end,
						confirm = function(_, value)
							return "Create the " .. trim(value) .. " profile and switch to it?"
						end,
						set = function(_, value)
							local name = Profiles:ValidateName(addon.db, value)
							if name then
								Profiles:Create(addon.db, name)
							end
						end,
					},
					duplicate = {
						type = "input",
						order = 2,
						name = "Duplicate profile",
						desc = function()
							return "Type a name and press Enter. Copies the " .. addon.db:GetCurrentProfile() .. " profile into it and switches to the copy."
						end,
						get = function() return "" end,
						validate = function(_, value)
							local _, err = Profiles:ValidateName(addon.db, value)
							return err or true
						end,
						confirm = function(_, value)
							return "Duplicate the " .. addon.db:GetCurrentProfile() .. " profile into " .. trim(value) .. " and switch to it?"
						end,
						set = function(_, value)
							local name = Profiles:ValidateName(addon.db, value)
							if name then
								Profiles:Duplicate(addon.db, name)
							end
						end,
					},
					rename = {
						type = "input",
						order = 3,
						name = "Rename profile",
						desc = function()
							if addon.db:GetCurrentProfile() == "Default" then
								return "The shared Default profile cannot be renamed."
							end
							return "Type a name and press Enter. Renames the " .. addon.db:GetCurrentProfile() .. " profile, and characters using it follow the new name."
						end,
						disabled = function()
							return addon.db:GetCurrentProfile() == "Default"
						end,
						get = function() return "" end,
						validate = function(_, value)
							local _, err = Profiles:ValidateName(addon.db, value)
							return err or true
						end,
						confirm = function(_, value)
							return "Rename the " .. addon.db:GetCurrentProfile() .. " profile to " .. trim(value) .. "?"
						end,
						set = function(_, value)
							local name = Profiles:ValidateName(addon.db, value)
							if name then
								Profiles:Rename(addon.db, name)
							end
						end,
					},
					copyFrom = {
						type = "select",
						order = 4,
						name = "Copy settings from",
						desc = "Replaces everything in the active profile with the settings of the profile you pick, including other characters' profiles. The profile you copy from is not changed.",
						values = function() return listCopyable(addon.db) end,
						disabled = function() return next(listCopyable(addon.db)) == nil end,
						get = function() return nil end,
						confirm = function(_, value)
							return "Replace everything in the " .. addon.db:GetCurrentProfile() .. " profile with the settings from " .. value .. "?"
						end,
						set = function(_, value)
							addon.db:CopyProfile(value, true)
						end,
					},
					reset = {
						type = "execute",
						order = 5,
						name = "Reset profile",
						desc = "Returns every setting in the active profile to the defaults.",
						confirm = function()
							return "Reset the " .. addon.db:GetCurrentProfile() .. " profile? Every rule and setting in it goes back to the defaults."
						end,
						func = function() addon.db:ResetProfile() end,
					},
					delete = {
						type = "select",
						order = 6,
						name = "Delete a profile",
						desc = "Removes a profile permanently. The active profile and Default are protected.",
						values = function() return listDeletable(addon.db) end,
						disabled = function() return next(listDeletable(addon.db)) == nil end,
						get = function() return nil end,
						confirm = function(_, value)
							return "Delete the " .. value .. " profile? There is no undo."
						end,
						set = function(_, value)
							addon.db:DeleteProfile(value, true)
							forgetProfileKeys(addon.db, value)
						end,
					},
				},
			},
			transfer = {
				type = "group",
				inline = true,
				order = 10,
				name = "Backup and sharing",
				args = {
					about = {
						type = "description",
						order = 1,
						fontSize = "medium",
						name = "Copy the export text somewhere safe to back up this profile, or paste an export below to load one. Importing replaces everything in the active profile.",
					},
					export = {
						type = "input",
						multiline = 8,
						width = "full",
						order = 2,
						name = "Export",
						desc = "Select the text, then press Ctrl+C to copy it.",
						get = function() return Profiles:Export(addon.db.profile) end,
						set = function() end,
					},
					import = {
						type = "input",
						multiline = 8,
						width = "full",
						order = 3,
						name = "Import",
						desc = "Paste a LootsUI export, then press Accept.",
						get = function() return "" end,
						validate = function(_, value)
							local data, err = Profiles:Import(value)
							if not data then
								return err
							end
							return true
						end,
						confirm = function()
							return "Replace everything in the " .. addon.db:GetCurrentProfile() .. " profile with this import?"
						end,
						set = function(_, value)
							local data = Profiles:Import(value)
							if data then
								applyImport(addon, data)
							end
						end,
					},
				},
			},
		},
	}
end
