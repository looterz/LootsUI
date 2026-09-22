local ADDON, ns = ...

local LootsUI = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = LootsUI
_G.LootsUI = LootsUI

local Registry = ns.Registry
local Conditions = ns.Conditions
local Visibility = ns.Visibility
local Options = ns.Options
local Profiles = ns.Profiles

-- World of Warcraft: Forever is the mainline client on the 1.60 line, the one
-- mainline build with an interface below 100000.
ns.isForever = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE and (select(4, GetBuildInfo()) or 0) < 100000

-- A short log kept inside the saved table itself, so that what the addon saw
-- at each stage of a session can be read back from the file the client wrote.
local TRACE_LIMIT = 40

function LootsUI:Trace(what)
	local sv = self.db and self.db.sv
	if not sv then
		return
	end

	-- AceDB strips defaults on logout before this runs, and a profile with no
	-- rules loses its rules table entirely.
	local live = 0
	for _, rule in pairs(self.db.profile.rules or {}) do
		if rule ~= "" then
			live = live + 1
		end
	end

	local global = _G.LootsUIDB
	local stored = 0
	local profile = global and global.profiles and global.profiles[self.db:GetCurrentProfile()]
	for _, rule in pairs(profile and profile.rules or {}) do
		if rule ~= "" then
			stored = stored + 1
		end
	end

	sv.trace = sv.trace or {}
	sv.trace[#sv.trace + 1] = string.format("%s %s live=%d global=%d same=%s profile=%s",
		date("%m-%d %H:%M:%S"), what, live, stored, tostring(global == sv), self.db:GetCurrentProfile())
	while #sv.trace > TRACE_LIMIT do
		table.remove(sv.trace, 1)
	end
end

function LootsUI:PrintTrace()
	local trace = self.db and self.db.sv and self.db.sv.trace
	if not trace or #trace == 0 then
		self:Print("No trace recorded yet.")
		return
	end
	for _, line in ipairs(trace) do
		self:Print(line)
	end
end

function LootsUI:OnInitialize()
	self.conditionEvents = {}
	local preloaded = _G.LootsUIDB
	local preloadedRules = preloaded and preloaded.profiles and preloaded.profiles.Default
		and preloaded.profiles.Default.rules
	local count = 0
	for _, rule in pairs(preloadedRules or {}) do
		if rule ~= "" then
			count = count + 1
		end
	end
	self:OpenDatabase()
	self:Trace(string.format("init global-before=%s default-rules-before=%d", tostring(preloaded ~= nil), count))

	local AceConfig = LibStub("AceConfig-3.0")
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")

	AceConfig:RegisterOptionsTable(ADDON .. "_options", Options:Build(self))
	self.optionsFrame = AceConfigDialog:AddToBlizOptions(ADDON .. "_options", "LootsUI")
end

-- Points self.db at the database on the client's own saved table, rebuilding it
-- when the client has swapped that table in late. Returns true when it did.
function LootsUI:OpenDatabase()
	local db, replaced = Profiles:Open(self.db)
	if db == self.db then
		return false
	end

	local previousTrace = self.db and self.db.sv and self.db.sv.trace
	if self.db then
		self.db.UnregisterAllCallbacks(self)
	end

	self.db = db
	if previousTrace then
		db.sv.trace = db.sv.trace or {}
		for _, line in ipairs(previousTrace) do
			db.sv.trace[#db.sv.trace + 1] = line
		end
	end
	db.RegisterCallback(self, "OnProfileChanged", "ReloadProfile")
	db.RegisterCallback(self, "OnProfileCopied", "ReloadProfile")
	db.RegisterCallback(self, "OnProfileReset", "ReloadProfile")

	if replaced then
		self.lateSavedVariables = (self.lateSavedVariables or 0) + 1
		self:Trace("adopted late saved table")
	end
	return replaced
end

-- The client serialises whatever the global points at when it writes the file,
-- on logout and on reload alike. If it swapped the global after the last check
-- above, the live database is not what it would write, so the global is pointed
-- back at the live table first.
function LootsUI:OnLogout()
	self:Trace("logout before")
	if self.db and _G.LootsUIDB ~= self.db.sv then
		_G.LootsUIDB = self.db.sv
		self.savedTableRestored = (self.savedTableRestored or 0) + 1
		self:Trace("logout pointed global at live table")
	end
end

-- The hand-over has no event of its own, so for a short while after each
-- loading screen the global is polled for it.
local ADOPT_WINDOW_SECONDS = 30

function LootsUI:WatchForLateSavedVariables()
	if self.adoptTicker then
		self.adoptTicker:Cancel()
	end

	self.adoptTicker = C_Timer.NewTicker(1, function()
		if self:OpenDatabase() then
			self:ReloadProfile()
		end
	end, ADOPT_WINDOW_SECONDS)
	C_Timer.After(ADOPT_WINDOW_SECONDS + 1, function()
		self:Trace("watch window over")
	end)
end

function LootsUI:OnEnable()
	self:OpenDatabase()
	self:Trace("login")
	self:RegisterChatCommand("loots", "HandleCommand")
	self:RegisterChatCommand("lootsui", "HandleCommand")

	-- The interface is rebuilt behind every loading screen, so the rules have to
	-- be reapplied each time rather than only at login.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ReloadProfile")
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
	-- Combat is the built in condition most rules hang off, so both edges get an
	-- immediate recompute rather than waiting for the poll.
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStarted")

	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", self.OnEditModeEnter, self)
		EventRegistry:RegisterCallback("EditMode.Exit", self.OnEditModeExit, self)
	end

	self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
	self:HookQuickKeybind()

	self:ReloadProfile()
end

-- Binding a key means hovering the button you want to bind, so everything has to
-- be on screen for it. This watches the frame rather than the addon that opens
-- it, so it works however quick keybind mode was entered.
function LootsUI:HookQuickKeybind()
	if self.keybindHooked or not QuickKeybindFrame then
		return
	end

	self.keybindHooked = true
	self:UnregisterEvent("ADDON_LOADED")

	QuickKeybindFrame:HookScript("OnShow", function()
		self:OnKeybindModeStart()
	end)

	QuickKeybindFrame:HookScript("OnHide", function()
		self:OnKeybindModeEnd()
	end)
end

function LootsUI:OnAddonLoaded()
	self:HookQuickKeybind()
end

function LootsUI:OnKeybindModeStart()
	if not Visibility:IsSuspended() then
		self.suspendedForKeybind = true
		Visibility:Suspend()
	end
end

function LootsUI:OnKeybindModeEnd()
	if self.suspendedForKeybind then
		self.suspendedForKeybind = nil
		Visibility:Resume()
	end
end

function LootsUI:OnDisable()
	self:UnregisterChatCommand("loots")
	self:UnregisterChatCommand("lootsui")

	if EventRegistry then
		EventRegistry:UnregisterCallback("EditMode.Enter", self)
		EventRegistry:UnregisterCallback("EditMode.Exit", self)
	end

	Visibility:RestoreAll()
end

-- Frames have to be visible and where the player left them while edit mode is
-- open, but a player who already asked for everything to show keeps that state.
function LootsUI:OnEditModeEnter()
	if not Visibility:IsSuspended() then
		self.suspendedForEditMode = true
		Visibility:Suspend()
	end
end

function LootsUI:OnEditModeExit()
	if self.suspendedForEditMode then
		self.suspendedForEditMode = nil
		Visibility:Resume()
	end
end

-- Rules used to live directly on the profile, before fade settings needed room
-- of their own. Carry anything still sitting there across.
function LootsUI:MigrateProfile()
	local profile = self.db.profile

	for _, entry in ipairs(Registry:GetEntries()) do
		local legacy = profile[entry.key]
		if type(legacy) == "string" then
			if legacy ~= "" and (profile.rules[entry.key] or "") == "" then
				profile.rules[entry.key] = legacy
			end
			profile[entry.key] = nil
		end
	end
end

-- The Forever beta writes saved settings but never reads them back, so every
-- login and reload starts from nothing. Rather than make players press the
-- preset button each time, the Forever preset is applied for them when the
-- profile comes back empty. A profile that comes back with rules in it is
-- left alone, so this stops doing anything the day the client is fixed.
function LootsUI:ApplyForeverPresetIfEmpty()
	if not ns.isForever or self.db.profile.foreverPresetAtLogin == false then
		return false
	end

	for _, rule in pairs(self.db.profile.rules or {}) do
		if rule ~= "" then
			return false
		end
	end

	local preset = Options:GetPresets().forever
	for _, entry in ipairs(Registry:GetEntries()) do
		self.db.profile.rules[entry.key] = preset.rules[entry.key] or ""
	end
	for key, value in pairs(preset.fade) do
		self.db.profile.fade[key] = value
	end

	self:Trace("forever preset applied at login")
	self:Print("The beta did not bring your settings back, so the Forever preset was applied. The Presets tab can turn this off.")
	return true
end

function LootsUI:ReloadProfile(event, isLogin, isReload)
	self:OpenDatabase()
	if event == "PLAYER_ENTERING_WORLD" then
		self:Trace(string.format("entering world login=%s reload=%s", tostring(isLogin), tostring(isReload)))
		if isLogin or isReload then
			self:ApplyForeverPresetIfEmpty()
		end
	elseif event then
		self:Trace(tostring(event))
	end
	self:MigrateProfile()
	Visibility:SetProfile(self.db.profile)
	Visibility:ApplyAll()
	self:UpdateConditionEvents()
	self:ScheduleLateApply()

	if event == "PLAYER_ENTERING_WORLD" then
		self:WatchForLateSavedVariables()
	end
end

-- Questie and addons like it build their frames well after we first apply, so a
-- couple of late passes pick up anything that did not exist yet. Re-applying an
-- entry that is already set up changes nothing on screen.
function LootsUI:ScheduleLateApply()
	if self.lateApplyScheduled then
		return
	end

	self.lateApplyScheduled = true

	C_Timer.After(5, function()
		Visibility:ApplyAll()
	end)

	C_Timer.After(20, function()
		self.lateApplyScheduled = nil
		Visibility:ApplyAll()
	end)
end

function LootsUI:OnCombatEnded()
	Conditions:NoteCombat(false)
	Visibility:Refresh()
	Visibility:FlushPending()
end

function LootsUI:OnCombatStarted()
	Conditions:NoteCombat(true)
	Visibility:Refresh()
end

-- Only the events the current rules actually need stay registered.
function LootsUI:UpdateConditionEvents()
	local used = {}
	for _, entry in ipairs(Registry:GetEntries()) do
		Conditions:CollectUsed(self.db.profile.rules[entry.key], used)
	end

	local wanted = Conditions:CollectEvents(used)

	for event in pairs(self.conditionEvents) do
		if not wanted[event] then
			self:UnregisterEvent(event)
			self.conditionEvents[event] = nil
		end
	end

	for event in pairs(wanted) do
		if not self.conditionEvents[event] then
			self:RegisterEvent(event, "OnConditionEvent")
			self.conditionEvents[event] = true
		end
	end
end

-- Every condition shipped so far reads the player, so unit events about anyone
-- else are noise. This filter needs revisiting when one reads another unit.
function LootsUI:OnConditionEvent(event, unit)
	if unit and unit ~= "player" then
		return
	end

	Visibility:Refresh()
end

function LootsUI:GetRuleValue(info)
	return self.db.profile.rules[info[#info]]
end

function LootsUI:SetRuleValue(info, value)
	local key = info[#info]
	self.db.profile.rules[key] = value

	local entry = Registry:GetEntry(key)
	if entry then
		Visibility:SetRule(entry, value)
	end

	self:UpdateConditionEvents()
end

function LootsUI:GetForeverPresetAtLogin()
	return self.db.profile.foreverPresetAtLogin ~= false
end

function LootsUI:SetForeverPresetAtLogin(_, value)
	self.db.profile.foreverPresetAtLogin = value and true or false
end

function LootsUI:GetFadeSetting(info)
	return self.db.profile.fade[info[#info]]
end

function LootsUI:SetFadeSetting(info, value)
	self.db.profile.fade[info[#info]] = value
	Visibility:SetFadeSettings(self.db.profile.fade)
end

function LootsUI:GetFadeOverride(info)
	return self.db.profile.overrides[info[#info]] or "default"
end

function LootsUI:SetFadeOverride(info, value)
	local key = info[#info]
	if value == "default" then
		value = nil
	end

	self.db.profile.overrides[key] = value

	local entry = Registry:GetEntry(key)
	if entry then
		Visibility:SetOverride(entry, value)
	end
end

function LootsUI:ValidateRule(value)
	if not value or value == "" then
		return true
	end

	local opened = select(2, value:gsub("%[", ""))
	local closed = select(2, value:gsub("%]", ""))
	if opened ~= closed then
		return "Unbalanced brackets in that conditional."
	end

	return true
end

function LootsUI:ApplyPreset(key)
	local preset = Options:GetPresets()[key]
	if not preset then
		return
	end

	for _, entry in ipairs(Registry:GetEntries()) do
		self.db.profile.rules[entry.key] = preset.rules[entry.key] or ""
	end

	if preset.fade then
		for key, value in pairs(preset.fade) do
			self.db.profile.fade[key] = value
		end
	end

	self:ReloadProfile()
	self:Trace("preset " .. key)
	self:Print(preset.label .. " preset applied to the " .. self.db:GetCurrentProfile() .. " profile.")
end

function LootsUI:ClearAllRules()
	for _, entry in ipairs(Registry:GetEntries()) do
		self.db.profile.rules[entry.key] = ""
	end

	self:ReloadProfile()
	self:Print("All rules cleared.")
end

function LootsUI:OpenOptions()
	if self.optionsFrame and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.optionsFrame.name)
	end
end

function LootsUI:PrintStatus()
	local blocked = Visibility.blocked or 0
	local state = Visibility:IsSuspended() and "Suspended, everything is visible." or "Active."
	if blocked > 0 then
		state = state .. " " .. blocked .. " of our own calls were blocked this session."
	end
	if self.lateSavedVariables then
		state = state .. " The game handed over saved settings late " .. self.lateSavedVariables .. " time(s), and they were picked up."
	end
	if self.savedTableRestored then
		state = state .. " The saved table was pointed back at the live settings " .. self.savedTableRestored .. " time(s)."
	end
	self:Print(state)
	self:Print(self:DescribeSavedTable())

	for _, entry in ipairs(Registry:GetEntries()) do
		local rule = self.db.profile.rules[entry.key]
		if rule and rule ~= "" then
			if Registry:IsAvailable(entry) then
				self:Print(entry.label .. ": " .. Visibility:GetDiagnostics(entry))
			else
				self:Print(entry.label .. ": not present in this version of the game")
			end
		end
	end
end

-- One line that says whether the table the game will save is the one in use,
-- and how many rules each side holds, which is the whole question on the
-- Forever beta.
function LootsUI:DescribeSavedTable()
	local live = 0
	for _, rule in pairs(self.db.profile.rules or {}) do
		if rule ~= "" then
			live = live + 1
		end
	end

	local global = _G.LootsUIDB
	local stored = 0
	local profile = global and global.profiles and global.profiles[self.db:GetCurrentProfile()]
	for _, rule in pairs(profile and profile.rules or {}) do
		if rule ~= "" then
			stored = stored + 1
		end
	end

	local same = global == self.db.sv
	return string.format("Saved table %s the live one. Live profile %s: %d rules, saved table: %d rules.",
		same and "is" or "is NOT", self.db:GetCurrentProfile(), live, stored)
end

function LootsUI:PrintDebug()
	local used = {}
	for _, entry in ipairs(Registry:GetEntries()) do
		Conditions:CollectUsed(self.db.profile.rules[entry.key], used)
	end

	local names = {}
	for name in pairs(used) do
		names[#names + 1] = name
	end
	table.sort(names)

	if #names == 0 then
		self:Print("No rule is using a LootsUI condition.")
	end

	for _, name in ipairs(names) do
		local detail = Conditions:Describe(name)
		if detail ~= "" then
			detail = " (" .. detail .. ")"
		end
		self:Print(string.format("[%s] = %s%s", name, tostring(Conditions:Evaluate(name)), detail))
	end

	local registered = {}
	for event in pairs(self.conditionEvents) do
		registered[#registered + 1] = event
	end
	table.sort(registered)

	if #registered == 0 then
		self:Print("No condition events registered. No rule is using a LootsUI condition.")
	else
		self:Print("Watching: " .. table.concat(registered, ", "))
	end
end

function LootsUI:HandleCommand(input)
	local command = strtrim(input or ""):lower()

	if command == "" or command == "config" or command == "options" then
		self:OpenOptions()
	elseif command == "show" then
		Visibility:Suspend()
		self:Print("Everything is visible. Your rules are still saved.")
	elseif command == "hide" then
		Visibility:Resume()
		self:Print("Your rules are back in charge.")
	elseif command == "toggle" then
		if Visibility:IsSuspended() then
			Visibility:Resume()
		else
			Visibility:Suspend()
		end
	elseif command == "status" then
		self:PrintStatus()
	elseif command == "debug" then
		self:PrintDebug()
	elseif command == "trace" then
		self:PrintTrace()
	else
		self:Print("Unknown command. Try show, hide, toggle, status, debug or trace.")
	end
end
