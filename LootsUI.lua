local ADDON, ns = ...

local LootsUI = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.Addon = LootsUI
_G.LootsUI = LootsUI

local Registry = ns.Registry
local Conditions = ns.Conditions
local Visibility = ns.Visibility
local Options = ns.Options

local function buildDefaults()
	return {
		profile = {
			rules = Registry:BuildDefaults(),
			overrides = {},
			fade = {
				mode = "fade",
				inDuration = 0.10,
				outDuration = 0.10,
			},
		},
	}
end

function LootsUI:OnInitialize()
	self.conditionEvents = {}
	self.db = LibStub("AceDB-3.0"):New("LootsUIDB", buildDefaults(), true)

	local AceConfig = LibStub("AceConfig-3.0")
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")

	AceConfig:RegisterOptionsTable(ADDON .. "_options", Options:Build(self))
	self.optionsFrame = AceConfigDialog:AddToBlizOptions(ADDON .. "_options", "LootsUI")

	AceConfig:RegisterOptionsTable(ADDON .. "_profiles", LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
	AceConfigDialog:AddToBlizOptions(ADDON .. "_profiles", "Profiles", "LootsUI")

	self.db.RegisterCallback(self, "OnProfileChanged", "ReloadProfile")
	self.db.RegisterCallback(self, "OnProfileCopied", "ReloadProfile")
	self.db.RegisterCallback(self, "OnProfileReset", "ReloadProfile")
end

function LootsUI:OnEnable()
	self:RegisterChatCommand("loots", "HandleCommand")
	self:RegisterChatCommand("lootsui", "HandleCommand")

	-- The interface is rebuilt behind every loading screen, so the rules have to
	-- be reapplied each time rather than only at login.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ReloadProfile")
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

function LootsUI:ReloadProfile()
	self:MigrateProfile()
	Visibility:SetProfile(self.db.profile)
	Visibility:ApplyAll()
	self:UpdateConditionEvents()
	self:ScheduleLateApply()
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
	Visibility:Refresh()
	Visibility:FlushPending()
end

function LootsUI:OnCombatStarted()
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

	self:ReloadProfile()
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
	self:Print(state)

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
	else
		self:Print("Unknown command. Try show, hide, toggle, status or debug.")
	end
end
