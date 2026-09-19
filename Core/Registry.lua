local ADDON, ns = ...

local Registry = {}
ns.Registry = Registry

local _G = _G

local CATEGORIES = {
	{ key = "actionbars", label = "Action Bars" },
	{ key = "unitframes", label = "Unit Frames" },
	{ key = "interface", label = "Interface" },
	{ key = "cooldowns", label = "Cooldown Manager" },
}

-- Frame names drifted between expansions and then converged again on the unified
-- UI codebase. Listing candidates and taking the first one that exists keeps a
-- single entry working on every flavor without branching on the client build.
local function firstExisting(...)
	for index = 1, select("#", ...) do
		local name = select(index, ...)
		if _G[name] then
			return { name }
		end
	end
	return {}
end

local function indexed(pattern, count)
	local names = {}
	for index = 1, count do
		local name = pattern:format(index)
		if _G[name] then
			names[#names + 1] = name
		end
	end
	return names
end

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local names = select(index, ...)
		if #names > 0 then
			return names
		end
	end
	return {}
end

local ENTRIES = {
	{
		key = "actionBar1", category = "actionbars", label = "Action Bar 1",
		resolve = function() return firstExisting("MainActionBar", "MainMenuBar") end,
	},
	{
		key = "actionBar2", category = "actionbars", label = "Action Bar 2",
		resolve = function() return firstExisting("MultiBarBottomLeft") end,
	},
	{
		key = "actionBar3", category = "actionbars", label = "Action Bar 3",
		resolve = function() return firstExisting("MultiBarBottomRight") end,
	},
	{
		key = "actionBar4", category = "actionbars", label = "Action Bar 4",
		resolve = function() return firstExisting("MultiBarRight") end,
	},
	{
		key = "actionBar5", category = "actionbars", label = "Action Bar 5",
		resolve = function() return firstExisting("MultiBarLeft") end,
	},
	{
		key = "actionBar6", category = "actionbars", label = "Action Bar 6",
		resolve = function() return firstExisting("MultiBar5") end,
	},
	{
		key = "actionBar7", category = "actionbars", label = "Action Bar 7",
		resolve = function() return firstExisting("MultiBar6") end,
	},
	{
		key = "actionBar8", category = "actionbars", label = "Action Bar 8",
		resolve = function() return firstExisting("MultiBar7") end,
	},
	{
		key = "petBar", category = "actionbars", label = "Pet Action Bar",
		resolve = function() return firstExisting("PetActionBar", "PetActionBarFrame") end,
	},
	{
		key = "stanceBar", category = "actionbars", label = "Stance Bar",
		resolve = function() return firstExisting("StanceBar", "StanceBarFrame") end,
	},
	{
		key = "extraActionButton", category = "actionbars", label = "Extra Action Button",
		resolve = function() return firstExisting("ExtraActionBarFrame") end,
	},
	{
		key = "zoneAbility", category = "actionbars", label = "Zone Ability",
		resolve = function() return firstExisting("ZoneAbilityFrame") end,
	},
	{
		key = "vehicleLeave", category = "actionbars", label = "Leave Vehicle Button",
		resolve = function() return firstExisting("MainMenuBarVehicleLeaveButton") end,
	},

	{
		key = "playerFrame", category = "unitframes", label = "Player Frame",
		resolve = function() return firstExisting("PlayerFrame") end,
	},
	{
		key = "targetFrame", category = "unitframes", label = "Target Frame",
		resolve = function() return firstExisting("TargetFrame") end,
	},
	{
		key = "focusFrame", category = "unitframes", label = "Focus Frame",
		resolve = function() return firstExisting("FocusFrame") end,
	},
	{
		key = "petFrame", category = "unitframes", label = "Pet Frame",
		resolve = function() return firstExisting("PetFrame") end,
	},
	{
		key = "partyFrames", category = "unitframes", label = "Party Frames",
		resolve = function()
			return firstNonEmpty(firstExisting("PartyFrame"), indexed("PartyMemberFrame%d", 4))
		end,
	},
	{
		key = "raidFrames", category = "unitframes", label = "Raid Frames",
		resolve = function() return firstExisting("CompactRaidFrameContainer") end,
	},
	{
		key = "bossFrames", category = "unitframes", label = "Boss Frames",
		resolve = function()
			return firstNonEmpty(firstExisting("BossTargetFrameContainer"), indexed("Boss%dTargetFrame", 5))
		end,
	},
	{
		key = "totemFrame", category = "unitframes", label = "Totem Frame",
		resolve = function() return firstExisting("TotemFrame") end,
	},
	-- The alternate power bar lives inside the encounter bar on modern clients,
	-- so the container is taken when it exists and the bar itself otherwise.
	{
		key = "encounterBar", category = "unitframes", label = "Encounter Bar",
		resolve = function() return firstExisting("EncounterBar", "PlayerPowerBarAlt") end,
	},

	{
		key = "minimap", category = "interface", label = "Minimap",
		resolve = function() return firstExisting("MinimapCluster") end,
	},
	{
		key = "buffs", category = "interface", label = "Buff Frame",
		resolve = function() return firstExisting("BuffFrame") end,
	},
	{
		key = "debuffs", category = "interface", label = "Debuff Frame",
		resolve = function() return firstExisting("DebuffFrame") end,
	},
	{
		key = "castBar", category = "interface", label = "Cast Bar",
		resolve = function() return firstExisting("PlayerCastingBarFrame", "CastingBarFrame") end,
	},
	{
		key = "objectiveTracker", category = "interface", label = "Objective Tracker",
		resolve = function()
			local names = firstExisting("ObjectiveTrackerFrame", "QuestWatchFrame")
			-- Questie puts its tracker in a frame of its own and leaves the stock
			-- one alone, so the rule has to cover both. Its quest item buttons are
			-- re-parented into the tracker lines when active, so they come along.
			for _, name in ipairs(firstExisting("Questie_BaseFrame")) do
				names[#names + 1] = name
			end
			return names
		end,
	},
	{
		key = "microMenu", category = "interface", label = "Micro Menu",
		resolve = function() return firstExisting("MicroMenuContainer", "MicroButtonAndBagsBar") end,
	},
	{
		key = "bags", category = "interface", label = "Bags Bar",
		resolve = function() return firstExisting("BagsBar", "MainMenuBarBackpackButton") end,
	},
	{
		key = "experienceBar", category = "interface", label = "Experience Bar",
		resolve = function() return firstExisting("MainStatusTrackingBarContainer", "MainMenuExpBar") end,
	},
	-- The status tracking manager puts experience in the main container and the
	-- watched faction in the secondary one, so the reputation bar is that frame.
	{
		key = "reputationBar", category = "interface", label = "Reputation Bar",
		resolve = function() return firstExisting("SecondaryStatusTrackingBarContainer", "ReputationWatchBar") end,
	},
	{
		key = "personalResource", category = "interface", label = "Personal Resource Display",
		resolve = function() return firstExisting("PersonalResourceDisplayFrame") end,
	},
	{
		key = "chatFrames", category = "interface", label = "Chat Frames",
		resolve = function()
			local names = {}
			for index = 1, (_G.NUM_CHAT_WINDOWS or 10) do
				local name = "ChatFrame" .. index
				if _G[name] then
					names[#names + 1] = name
				end
			end
			for _, name in ipairs({ "GeneralDockManager", "QuickJoinToastButton" }) do
				if _G[name] then
					names[#names + 1] = name
				end
			end
			return names
		end,
	},
	{
		key = "damageMeter", category = "interface", label = "Damage Meter",
		resolve = function() return firstExisting("DamageMeter") end,
	},
	-- World of Warcraft: Forever's optional swing timer is three frames, one per
	-- hand and one for ranged, each placed on its own in edit mode and each with
	-- a rule of its own here.
	{
		key = "swingTimerMainHand", category = "interface", label = "Swing Timer (Main Hand)",
		resolve = function() return firstExisting("SwingTimerMainHandFrame") end,
	},
	{
		key = "swingTimerOffHand", category = "interface", label = "Swing Timer (Off Hand)",
		resolve = function() return firstExisting("SwingTimerOffHandFrame") end,
	},
	{
		key = "swingTimerRanged", category = "interface", label = "Swing Timer (Ranged)",
		resolve = function() return firstExisting("SwingTimerRangedFrame") end,
	},
	{
		key = "durability", category = "interface", label = "Durability Figure",
		resolve = function() return firstExisting("DurabilityFrame") end,
	},
	{
		key = "vehicleSeats", category = "interface", label = "Vehicle Seat Indicator",
		resolve = function() return firstExisting("VehicleSeatIndicator") end,
	},
	{
		key = "queueStatus", category = "interface", label = "Queue Status Eye",
		resolve = function() return firstExisting("QueueStatusButton") end,
	},
	{
		key = "talkingHead", category = "interface", label = "Talking Head",
		resolve = function() return firstExisting("TalkingHeadFrame") end,
	},
	-- Beta and PTR clients load Blizzard_PTRFeedback, whose report button sits
	-- on screen with no way to move or hide it. The frame has no XML name, but
	-- the addon keeps it in a global of the same spelling.
	{
		key = "issueReporter", category = "interface", label = "Issue Reporter (Beta and PTR)",
		resolve = function() return firstExisting("PTR_IssueReporter") end,
	},

	{
		key = "essentialCooldowns", category = "cooldowns", label = "Essential Cooldowns",
		resolve = function() return firstExisting("EssentialCooldownViewer") end,
	},
	{
		key = "utilityCooldowns", category = "cooldowns", label = "Utility Cooldowns",
		resolve = function() return firstExisting("UtilityCooldownViewer") end,
	},
	{
		key = "trackedBuffs", category = "cooldowns", label = "Tracked Buffs",
		resolve = function() return firstExisting("BuffIconCooldownViewer") end,
	},
	{
		key = "trackedBars", category = "cooldowns", label = "Tracked Bars",
		resolve = function() return firstExisting("BuffBarCooldownViewer") end,
	},
}

local byKey = {}
for _, entry in ipairs(ENTRIES) do
	byKey[entry.key] = entry
end

function Registry:GetCategories()
	return CATEGORIES
end

function Registry:GetEntries()
	return ENTRIES
end

function Registry:GetEntry(key)
	return byKey[key]
end

function Registry:GetCategoryEntries(categoryKey)
	local entries = {}
	for _, entry in ipairs(ENTRIES) do
		if entry.category == categoryKey then
			entries[#entries + 1] = entry
		end
	end
	return entries
end

function Registry:ResolveFrames(entry)
	local resolved = entry.resolve()
	local names = {}
	for _, name in ipairs(resolved) do
		if _G[name] then
			names[#names + 1] = name
		end
	end
	return names
end

function Registry:IsAvailable(entry)
	return #self:ResolveFrames(entry) > 0
end

function Registry:BuildDefaults()
	local defaults = {}
	for _, entry in ipairs(ENTRIES) do
		defaults[entry.key] = ""
	end
	return defaults
end
