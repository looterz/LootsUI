local ADDON, ns = ...

local Visibility = {}
ns.Visibility = Visibility

local Registry = ns.Registry
local Conditions = ns.Conditions
local Fade = ns.Fade

local _G = _G

local ALWAYS_SHOW = "show"

local wrappers = {}
local gates = {}
local originals = {}
local hooked = {}
local rules = {}
local overrides = {}
local applied = {}
local pending = {}
local deferred = {}

local fadeSettings = { mode = "instant", inDuration = 0.2, outDuration = 0.3 }

local suspended = false
local reparenting = false
local rechecking = false

-- Built in conditions are re-evaluated by the game whenever it likes, while
-- custom ones are only recomputed here, so a poll keeps the two in step.
local REFRESH_THROTTLE = 0.15

local ticker = CreateFrame("Frame")
local sinceRefresh = 0
local ticking = false

local hookSetParent

local function usesFade(entryKey)
	local mode = fadeSettings.mode
	local override = entryKey and overrides[entryKey]
	if override == "instant" or override == "fade" then
		mode = override
	end

	return mode == "fade"
end

-- A rule with a custom condition changes while you are playing, including mid
-- fight, and registering a driver then is impossible: the state driver manager
-- is a protected frame, so writing its attributes is blocked in combat. Those
-- rules are carried by alpha instead, which is never protected.
local function usesAlpha(entryKey, usesCustom)
	return usesCustom or usesFade(entryKey)
end

local function verdictFor(rewritten)
	if not rewritten or rewritten == "" then
		return nil
	end
	return SecureCmdOptionParse(rewritten)
end

local function applyAlpha(wrapper, target, instant, duration)
	if instant or not duration or duration <= 0 then
		Fade:Cancel(wrapper)
		wrapper:SetAlpha(target)
	else
		Fade:To(wrapper, target, duration)
	end
end

-- The rule is parsed here rather than read off the gate, because the gate can be
-- holding an older rule whenever a registration was blocked.
local function syncAlpha(frameName, entryKey, rewritten, instant)
	local wrapper = wrappers[frameName]
	if not wrapper then
		return
	end

	local verdict = verdictFor(rewritten)
	if verdict ~= "show" and verdict ~= "hide" then
		return
	end

	local target = verdict == "show" and 1 or 0
	if wrapper:GetAlpha() == target and not Fade:IsFading(wrapper) then
		return
	end

	local duration
	if usesFade(entryKey) then
		duration = target == 1 and fadeSettings.inDuration or fadeSettings.outDuration
	end

	applyAlpha(wrapper, target, instant, duration)
end

local function driveWrapper(wrapper, rule)
	RegisterAttributeDriver(wrapper, "state-visibility", rule)
end

-- Alpha only means something while the wrapper itself is shown, so it gets a
-- constant rule once and is then left alone.
local function ensureAlwaysShow(frameName, wrapper)
	if wrapper.lootsAlwaysShow then
		return
	end

	if InCombatLockdown() then
		deferred[frameName] = true
		return
	end

	wrapper.lootsAlwaysShow = true
	driveWrapper(wrapper, ALWAYS_SHOW)
end

local function reevaluate(frameName)
	local wrapper = wrappers[frameName]
	if not wrapper or suspended then
		return
	end

	local entryKey = wrapper.lootsEntry
	Visibility:Recheck(entryKey)

	-- A gate left over from a previous mode must never touch the alpha of a frame
	-- the driver is carrying, or it would be left invisible when the driver
	-- shows it again.
	local record = applied[entryKey]
	if record and usesAlpha(entryKey, record.usesCustom) then
		syncAlpha(frameName, entryKey, record.rewritten, false)
	end
end

local function onGateShow(gate)
	reevaluate(gate.lootsFrame)
end

local function onGateHide(gate)
	reevaluate(gate.lootsFrame)
end

local function onWrapperHide(wrapper)
	local record = applied[wrapper.lootsEntry]
	if record and not usesAlpha(wrapper.lootsEntry, record.usesCustom) then
		Visibility:Recheck(wrapper.lootsEntry)
	end
end

local function getWrapper(frameName, frame)
	local wrapper = wrappers[frameName]
	if not wrapper then
		wrapper = CreateFrame("Frame", "LootsUI_" .. frameName, UIParent, "SecureHandlerStateTemplate")
		wrapper:SetAllPoints(UIParent)
		wrapper:SetFrameStrata(frame:GetFrameStrata())
		wrapper:HookScript("OnHide", onWrapperHide)
		wrappers[frameName] = wrapper
	end
	return wrapper
end

-- The gate holds nothing, so the game showing and hiding it can never be a
-- protected action. It exists to react to built in conditions immediately
-- instead of waiting for the poll.
local function getGate(frameName)
	local gate = gates[frameName]
	if not gate then
		gate = CreateFrame("Frame", nil, UIParent)
		gate.lootsFrame = frameName
		gate:SetScript("OnShow", onGateShow)
		gate:SetScript("OnHide", onGateHide)
		gates[frameName] = gate
	end
	return gate
end

local function clearGate(frameName)
	local gate = gates[frameName]
	if gate and not InCombatLockdown() then
		UnregisterAttributeDriver(gate, "state-visibility")
		gate.lootsDriven = nil
	end
end

local function releaseFrame(frameName)
	local wrapper = wrappers[frameName]
	if not wrapper then
		return
	end

	clearGate(frameName)
	Fade:Cancel(wrapper)
	wrapper:SetAlpha(1)
	ensureAlwaysShow(frameName, wrapper)
end

local function applyRule(frameName, entryKey, rewritten, usesCustom)
	local wrapper = wrappers[frameName]
	if not wrapper then
		return
	end

	if rewritten == "" then
		releaseFrame(frameName)
		return
	end

	if usesAlpha(entryKey, usesCustom) then
		local gate = getGate(frameName)
		ensureAlwaysShow(frameName, wrapper)

		local first = not gate.lootsDriven

		if InCombatLockdown() then
			-- Registration is blocked right now, so remember it and let the alpha
			-- below carry the rule until the fight is over.
			deferred[frameName] = true
		else
			deferred[frameName] = nil
			gate.lootsDriven = true
			RegisterAttributeDriver(gate, "state-visibility", rewritten)
		end

		syncAlpha(frameName, entryKey, rewritten, first)
	else
		clearGate(frameName)
		Fade:Cancel(wrapper)
		wrapper:SetAlpha(1)
		wrapper.lootsAlwaysShow = nil

		if InCombatLockdown() then
			deferred[frameName] = true
		else
			deferred[frameName] = nil
			driveWrapper(wrapper, rewritten)
		end
	end
end

local function onTick(_, elapsed)
	sinceRefresh = sinceRefresh + elapsed
	if sinceRefresh >= REFRESH_THROTTLE then
		sinceRefresh = 0
		Visibility:Refresh()
	end
end

-- Only rules that mix in a custom condition can go stale on their own, so the
-- poll runs only while at least one of those is active.
local function updateTicker()
	local needed = false

	if not suspended then
		for _, record in pairs(applied) do
			if record.usesCustom then
				needed = true
				break
			end
		end
	end

	if needed ~= ticking then
		ticking = needed
		ticker:SetScript("OnUpdate", needed and onTick or nil)
	end
end

function Visibility:ApplyEntry(entry)
	local rule = rules[entry.key]
	if not rule or rule == "" then
		self:ClearEntry(entry)
		return
	end

	local frames = Registry:ResolveFrames(entry)
	if #frames == 0 then
		return
	end

	local rewritten, usesCustom = Conditions:Rewrite(rule)

	for _, frameName in ipairs(frames) do
		local frame = _G[frameName]
		local wrapper = getWrapper(frameName, frame)
		wrapper.lootsEntry = entry.key

		if frame:GetParent() ~= wrapper then
			-- Re-parenting a protected frame is blocked in combat, so the whole
			-- entry waits for the fight to end rather than erroring.
			if InCombatLockdown() then
				pending[entry.key] = true
				return
			end

			originals[frameName] = originals[frameName] or frame:GetParent()
			reparenting = true
			frame:SetParent(wrapper)
			reparenting = false

			-- A blocked call fails quietly apart from the game's own message, so
			-- check whether it actually took.
			if frame:GetParent() ~= wrapper then
				Visibility.blocked = (Visibility.blocked or 0) + 1
				pending[entry.key] = true
				return
			end

			hookSetParent(frameName, frame)
		end

		if suspended then
			releaseFrame(frameName)
		else
			applyRule(frameName, entry.key, rewritten, usesCustom)
		end
	end

	applied[entry.key] = { frames = frames, rewritten = rewritten, usesCustom = usesCustom }
	pending[entry.key] = nil
	updateTicker()
end

function Visibility:ClearEntry(entry)
	local record = applied[entry.key]
	if not record then
		return
	end

	for _, frameName in ipairs(record.frames) do
		releaseFrame(frameName)

		local frame = _G[frameName]
		local wrapper = wrappers[frameName]
		local original = originals[frameName]
		if frame and wrapper and original and frame:GetParent() ~= original and not InCombatLockdown() then
			UnregisterAttributeDriver(wrapper, "state-visibility")
			wrapper.lootsAlwaysShow = nil
			wrapper:Show()
			reparenting = true
			frame:SetParent(original)
			reparenting = false
			originals[frameName] = nil
		end
	end

	applied[entry.key] = nil
	pending[entry.key] = nil
	updateTicker()
end

local function reapplyFrame(frameName)
	for key, record in pairs(applied) do
		for _, name in ipairs(record.frames) do
			if name == frameName then
				local entry = Registry:GetEntry(key)
				if entry then
					Visibility:ApplyEntry(entry)
				end
				return
			end
		end
	end
end

-- The game re-parents some frames on its own, for instance on level up or when
-- edit mode takes over, which silently drops them out of their wrapper.
function hookSetParent(frameName, frame)
	if hooked[frameName] then
		return
	end
	hooked[frameName] = true

	hooksecurefunc(frame, "SetParent", function(_, parent)
		if reparenting or suspended then
			return
		end

		local wrapper = wrappers[frameName]
		if wrapper and parent ~= wrapper then
			reapplyFrame(frameName)
		end
	end)
end

function Visibility:SetProfile(profile)
	for _, entry in ipairs(Registry:GetEntries()) do
		rules[entry.key] = profile.rules[entry.key] or ""
		overrides[entry.key] = profile.overrides[entry.key]
	end

	fadeSettings.mode = profile.fade.mode
	fadeSettings.inDuration = profile.fade.inDuration
	fadeSettings.outDuration = profile.fade.outDuration
end

function Visibility:SetRule(entry, rule)
	rules[entry.key] = rule or ""
	self:ApplyEntry(entry)
end

function Visibility:SetOverride(entry, mode)
	overrides[entry.key] = mode
	self:ApplyEntry(entry)
end

function Visibility:SetFadeSettings(fade)
	fadeSettings.mode = fade.mode
	fadeSettings.inDuration = fade.inDuration
	fadeSettings.outDuration = fade.outDuration
	self:ApplyAll()
end

function Visibility:ApplyAll()
	for _, entry in ipairs(Registry:GetEntries()) do
		local rule = rules[entry.key]
		if rule and rule ~= "" then
			self:ApplyEntry(entry)
		else
			self:ClearEntry(entry)
		end
	end
end

function Visibility:RestoreAll()
	for _, entry in ipairs(Registry:GetEntries()) do
		self:ClearEntry(entry)
	end
end

-- Recompiles one entry on the spot, used when the game decides to hide a frame
-- so a rule built from a stale custom value is corrected before it is seen.
function Visibility:Recheck(entryKey)
	if rechecking or suspended or not entryKey then
		return
	end

	local record = applied[entryKey]
	if not record or not record.usesCustom then
		return
	end

	rechecking = true

	local rewritten, usesCustom = Conditions:Rewrite(rules[entryKey])
	record.usesCustom = usesCustom

	if rewritten ~= record.rewritten then
		record.rewritten = rewritten
		for _, frameName in ipairs(record.frames) do
			applyRule(frameName, entryKey, rewritten, usesCustom)
		end
	end

	rechecking = false
end

local function verifyFrame(frameName, entryKey, rewritten, usesCustom)
	local wrapper = wrappers[frameName]
	if not wrapper or Fade:IsFading(wrapper) then
		return
	end

	-- The game re-parents frames on its own, and not always through a path the
	-- SetParent hook can see. A frame that has drifted out of its wrapper is
	-- following whatever it landed in instead of its own rule, so put it back.
	local frame = _G[frameName]
	if frame and frame:GetParent() ~= wrapper and not InCombatLockdown() then
		local entry = Registry:GetEntry(entryKey)
		if entry then
			Visibility:ApplyEntry(entry)
		end
		return
	end

	if usesAlpha(entryKey, usesCustom) then
		syncAlpha(frameName, entryKey, rewritten, false)
		return
	end

	-- Otherwise the game's own loop re-applies show and hide every tick, so the
	-- only thing worth correcting is a rule it cannot see, and never in combat
	-- where re-registering is blocked anyway.
	if InCombatLockdown() then
		return
	end

	local verdict = verdictFor(rewritten)
	if verdict ~= "show" and verdict ~= "hide" then
		return
	end

	if (verdict == "show") ~= wrapper:IsShown() then
		applyRule(frameName, entryKey, rewritten, usesCustom)
	end
end

function Visibility:Refresh()
	if suspended then
		return
	end

	for key, record in pairs(applied) do
		local rewritten, usesCustom = Conditions:Rewrite(rules[key])
		record.usesCustom = usesCustom

		if rewritten ~= record.rewritten then
			record.rewritten = rewritten
			for _, frameName in ipairs(record.frames) do
				applyRule(frameName, key, rewritten, usesCustom)
			end
		else
			for _, frameName in ipairs(record.frames) do
				verifyFrame(frameName, key, rewritten, usesCustom)
			end
		end
	end
end

function Visibility:FlushPending()
	local keys = {}
	for key in pairs(pending) do
		keys[#keys + 1] = key
	end

	for _, key in ipairs(keys) do
		local entry = Registry:GetEntry(key)
		if entry then
			self:ApplyEntry(entry)
		end
	end

	-- Registrations that could not happen during the fight.
	local names = {}
	for frameName in pairs(deferred) do
		names[#names + 1] = frameName
	end

	for _, frameName in ipairs(names) do
		deferred[frameName] = nil
		local wrapper = wrappers[frameName]
		local entry = wrapper and Registry:GetEntry(wrapper.lootsEntry)
		if entry then
			self:ApplyEntry(entry)
		end
	end
end

function Visibility:Suspend()
	suspended = true
	for _, record in pairs(applied) do
		for _, frameName in ipairs(record.frames) do
			releaseFrame(frameName)
		end
	end
	updateTicker()
end

function Visibility:Resume()
	suspended = false
	for _, record in pairs(applied) do
		record.rewritten = nil
	end
	self:Refresh()
	self:FlushPending()
	updateTicker()
end

function Visibility:IsSuspended()
	return suspended
end

function Visibility:GetRule(entry)
	return rules[entry.key] or ""
end

function Visibility:GetPreview(entry)
	local rule = rules[entry.key]
	if not rule or rule == "" then
		return ""
	end
	return (Conditions:Rewrite(rule))
end

function Visibility:GetDiagnostics(entry)
	local now = Conditions:Rewrite(rules[entry.key] or "")
	local record = applied[entry.key]

	if not record then
		return "NOT APPLIED, would use: " .. now
	end

	local pieces = { "rule=[" .. (record.rewritten or "none") .. "]" }

	if now ~= record.rewritten then
		pieces[#pieces + 1] = "STALE now=[" .. now .. "]"
	end

	pieces[#pieces + 1] = "verdict=" .. tostring(verdictFor(record.rewritten))
	pieces[#pieces + 1] = usesAlpha(entry.key, record.usesCustom) and "alpha" or "driver"

	for _, frameName in ipairs(record.frames) do
		local wrapper = wrappers[frameName]
		local frame = _G[frameName]
		local state = "no wrapper"

		if wrapper then
			state = string.format("%s a%.1f", wrapper:IsShown() and "shown" or "hidden", wrapper:GetAlpha())
			if deferred[frameName] then
				state = state .. " DEFERRED"
			end
			if frame and frame:GetParent() ~= wrapper then
				state = state .. " UNPARENTED"
			end
			if frame and not frame:IsShown() then
				state = state .. " frame-hidden"
			end
		end

		pieces[#pieces + 1] = frameName .. "=" .. state
	end

	return table.concat(pieces, " ")
end
