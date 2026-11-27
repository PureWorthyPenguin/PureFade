-- PureFade: Catalog of WoW Forever UI elements, triggers, starter groups, and defaults.
local _, ns = ...

-- Safe value helpers for WoW Forever (secret values & forbidden frames)
local issecretvalue = _G.issecretvalue

function ns.IsSecret(val)
	return issecretvalue ~= nil and issecretvalue(val) == true
end

function ns.SafeNumber(val)
	if type(val) ~= "number" or (issecretvalue and issecretvalue(val)) then
		return nil
	end
	return val
end

function ns.SafeBool(val)
	if issecretvalue and issecretvalue(val) then
		return false
	end
	return val and true or false
end

function ns.IsUsableFrame(obj)
	if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then
		return false
	end
	if obj.IsForbidden and obj:IsForbidden() then
		return false
	end
	return true
end

function ns.DeepCopy(src)
	if type(src) ~= "table" then
		return src
	end
	local copy = {}
	for k, v in pairs(src) do
		copy[k] = ns.DeepCopy(v)
	end
	return copy
end

-- Categories for the Elements settings page
ns.CATEGORIES = {
	{ key = "all",       label = "All" },
	{ key = "bars",      label = "Action Bars" },
	{ key = "units",     label = "Unit Frames" },
	{ key = "group",     label = "Group & PvP" },
	{ key = "minimap",   label = "Minimap" },
	{ key = "hud",       label = "HUD & Trackers" },
	{ key = "interface", label = "Interface & Chat" },
	{ key = "gamepad",   label = "Gamepad" },
	{ key = "custom",    label = "Custom" },
}

-- Trigger definitions (displayed in the per-element Triggers checklist)
ns.TRIGGERS = {
	-- Core
	{ key = "combat",        label = "In Combat",          section = "Core",     tip = "Show while in combat and during the Combat Fade-Out Delay." },
	{ key = "enemyTarget",   label = "Enemy Targeted",     section = "Core",     tip = "Show when targeting any living hostile or neutral unit (ignores dead corpses)." },
	{ key = "friendlyTarget",label = "Friendly Targeted",  section = "Core",     tip = "Show when targeting a friendly player or NPC." },
	-- Vitals / Resources
	{ key = "healthNotFull", label = "Health Not Full",    section = "Vitals",   tip = "Show when your health is below the Health threshold (works out of combat too, e.g. fall damage)." },
	{ key = "powerNotFull",  label = "Power Not Full",     section = "Vitals",   tip = "Show when Mana/Energy/Focus is below the Power threshold, or Rage/Runic Power is draining back to 0." },
	{ key = "petHealth",     label = "Pet Health Not Full",section = "Vitals",   tip = "Show when your pet's health is below the Health threshold." },
	{ key = "petUnhappy",    label = "Pet Not Happy",      section = "Vitals",   tip = "Show when your hunter pet is not Happy (Content/Yellow or Unhappy/Red)." },
	{ key = "hasDebuff",     label = "Has Any Debuff",     section = "Vitals",   tip = "Stay visible as long as you have any debuff applied." },
	{ key = "buffExpiring",  label = "Short / Expiring Buff", section = "Vitals", tip = "Keep buffs visible while their remaining duration is below the Short / Expiring Buff threshold (default 1m 30s). Permanent buffs (Aspects, Auras) are excluded." },
	-- Context / Location
	{ key = "inGroup",       label = "In Group / Raid",    section = "Context",  tip = "Show while in a party or raid." },
	{ key = "inInstance",    label = "In Instance",        section = "Context",  tip = "Show in dungeons, raids, battlegrounds, or arenas." },
	{ key = "inCity",        label = "In City / Resting",  section = "Context",  tip = "Show while resting in a city or inn." },
	{ key = "openWorld",     label = "Open World",         section = "Context",  tip = "Show in the open world (outside instances and resting areas)." },
	{ key = "casting",       label = "Casting / Channeling",section = "Context", tip = "Show while casting or channeling a spell." },
	{ key = "mounted",       label = "Mounted",            section = "Context",  tip = "Show while mounted." },
	{ key = "onTaxi",        label = "On Flight Path",     section = "Context",  tip = "Show while on a flight path (taxi)." },
	{ key = "inVehicle",     label = "In Vehicle",         section = "Context",  tip = "Show while in a vehicle or possessing a unit (e.g. quest vehicles, cannons)." },
	-- Minimap & World
	{ key = "tracking",      label = "Tracking Active",    section = "Minimap",  tip = "Show while a gathering or creature tracking ability is active (Find Minerals, Find Herbs, Track Beasts, etc.)." },
	{ key = "unreadMail",    label = "Unread Mail",        section = "Minimap",  tip = "Show while you have unread mail." },
	{ key = "indoors",       label = "Indoors",            section = "Minimap",  tip = "Show while indoors (caves, buildings, inns)." },
	-- Peek (Temporary Reveal)
	{ key = "chatMessage",   label = "New Chat Message",        section = "Peek", tip = "Briefly show when a new message arrives in your currently active chat tab (uses Chat Peek Duration)." },
	{ key = "buffChanged",   label = "Buff Changed",            section = "Peek", tip = "Briefly show when any buff is gained, refreshed, or removed (uses Buff Peek Duration)." },
	{ key = "questChanged",  label = "Quest Progress / Change", section = "Peek", tip = "Briefly show when you accept, complete, fail, track/untrack, or make progress on a quest (uses Quest Peek Duration)." },
	{ key = "minimapPing",   label = "Minimap Ping",            section = "Peek", tip = "Briefly show when a group member pings the minimap (uses Minimap Ping Peek)." },
}

ns.TRIGGER_BY_KEY = {}
for _, t in ipairs(ns.TRIGGERS) do
	ns.TRIGGER_BY_KEY[t.key] = t
end

-- Built-in WoW Forever UI element catalog
-- Special `resolver` keys are handled dynamically by Engine.lua:
--   "prd"           -> player nameplate (Personal Resource Display on WoW Forever)
--   "barart"        -> action bar end caps / background art
--   "minimapheader" -> MinimapCluster.BorderTop / MinimapBorderTop
--   "minimapzone"   -> MinimapCluster.ZoneTextButton / MinimapZoneTextButton
--   "minimaptrack"  -> MinimapCluster.Tracking
--   "minimapdial"   -> MinimapCluster.DielFrame
--   "minimapmail"   -> MiniMapMailFrame / MinimapCluster.IndicatorFrame.MailFrame
--   "minimapaddons" -> LibDBIcon10_* buttons on Minimap
--   "chatmessages"  -> ChatFrame1..10 message windows
--   "chatbuttons"   -> ChatFrameMenuButton, ChannelButton, QuickJoin, Friends, Voice, ChatFrameNButtonFrame
--   "damagemeter"   -> DamageMeter and dynamic DamageMeter* frames
ns.ELEMENTS = {
	-- Action Bars
	{ key = "mainbar",     label = "Action Bar 1 (Main)",         category = "bars", defaultGroup = "Action Bars",
		frames = { "MainMenuBar", "MainActionBar", "MainMenuBarVehicleLeaveButton" },
		defaultTriggers = { combat = true, enemyTarget = true, inVehicle = true } },
	{ key = "barart",      label = "Action Bar Art",              category = "bars", defaultGroup = "Action Bars",
		resolver = "barart",
		defaultTriggers = { combat = true, enemyTarget = true, inVehicle = true } },
	{ key = "bar2",        label = "Action Bar 2 (Bottom Left)",  category = "bars", defaultGroup = "Action Bars",
		frames = { "MultiBarBottomLeft" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "bar3",        label = "Action Bar 3 (Bottom Right)", category = "bars", defaultGroup = "Action Bars",
		frames = { "MultiBarBottomRight" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "bar4",        label = "Action Bar 4 (Right 1)",      category = "bars", defaultGroup = "Side Bars",
		frames = { "MultiBarRight" },
		defaultTriggers = {} },
	{ key = "bar5",        label = "Action Bar 5 (Right 2)",      category = "bars", defaultGroup = "Side Bars",
		frames = { "MultiBarLeft" },
		defaultTriggers = {} },
	{ key = "bar6",        label = "Action Bar 6",                category = "bars", defaultGroup = "Extra Bars",
		frames = { "MultiBar5" },
		defaultTriggers = {} },
	{ key = "bar7",        label = "Action Bar 7",                category = "bars", defaultGroup = "Extra Bars",
		frames = { "MultiBar6" },
		defaultTriggers = {} },
	{ key = "bar8",        label = "Action Bar 8",                category = "bars", defaultGroup = "Extra Bars",
		frames = { "MultiBar7" },
		defaultTriggers = {} },
	{ key = "petbar",      label = "Pet Action Bar",              category = "bars", defaultGroup = "Action Bars",
		frames = { "PetActionBarFrame", "PetActionBar" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "stancebar",   label = "Stance / Shapeshift Bar",     category = "bars", defaultGroup = "Action Bars",
		frames = { "StanceBarFrame", "StanceBar" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "totembar",    label = "Totem Bar",                   category = "bars", defaultGroup = "Action Bars",
		frames = {
			"MultiCastActionBarFrame", "MultiCastSummonSpellButton", "MultiCastRecallSpellButton",
			"MultiCastFlyoutFrame", "MultiCastSlotButton1", "MultiCastSlotButton2",
			"MultiCastSlotButton3", "MultiCastSlotButton4",
			"MultiCastActionPage1", "MultiCastActionPage2", "MultiCastActionPage3", "TotemFrame",
		},
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "extrabar",    label = "Extra Action / Zone Ability", category = "bars", defaultGroup = "None",
		frames = { "ExtraActionBarFrame", "ZoneAbilityFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },

	-- Unit Frames
	{ key = "player",      label = "Player Frame",                category = "units", defaultGroup = "Unit Frames",
		frames = { "PlayerFrame" },
		defaultTriggers = { combat = true, enemyTarget = true, healthNotFull = true, powerNotFull = true } },
	{ key = "pet",         label = "Pet Frame",                   category = "units", defaultGroup = "Unit Frames",
		frames = { "PetFrame" },
		defaultTriggers = { combat = true, enemyTarget = true, petHealth = true, petUnhappy = true } },
	{ key = "prd",         label = "Personal Resource Display",   category = "units", defaultGroup = "None",
		resolver = "prd",
		defaultTriggers = { combat = true, healthNotFull = true, powerNotFull = true } },
	{ key = "target",      label = "Target Frame",                category = "units", defaultGroup = "Unit Frames",
		frames = { "TargetFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "tot",         label = "Target of Target",            category = "units", defaultGroup = "Unit Frames",
		frames = { "TargetFrameToT" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "focus",       label = "Focus Frame",                 category = "units", defaultGroup = "Unit Frames",
		frames = { "FocusFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "focustot",    label = "Focus Target",                category = "units", defaultGroup = "Unit Frames",
		frames = { "FocusFrameToT" },
		defaultAlwaysShow = true, defaultTriggers = {} },

	-- Group & PvP
	{ key = "party",       label = "Party Frames",                category = "group", defaultGroup = "None",
		frames = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4", "PartyMemberBackground" },
		defaultTriggers = { combat = true, inGroup = true } },
	{ key = "raid",        label = "Raid Frames",                 category = "group", defaultGroup = "None",
		frames = { "CompactRaidFrameContainer" },
		defaultTriggers = { combat = true, inGroup = true } },
	{ key = "raidmanager", label = "Raid Frame Manager",          category = "group", defaultGroup = "None",
		frames = { "CompactRaidFrameManager" },
		defaultTriggers = {} },
	{ key = "flags",       label = "BG Flag Carriers",            category = "group", defaultGroup = "None",
		frames = { "ArenaEnemyFramesContainer" },
		defaultAlwaysShow = true, defaultTriggers = {} },

	-- Minimap
	{ key = "minimap",     label = "Minimap",                     category = "minimap", defaultGroup = "Minimap",
		frames = { "MinimapCluster", "Minimap", "QueueStatusButton", "LFGMinimapFrame", "MiniMapLFGFrame", "QueueStatusMinimapButton", "MiniMapBattlefieldFrame" },
		defaultTriggers = { combat = true, enemyTarget = true, tracking = true, minimapPing = true } },
	{ key = "minimapheader", label = "Minimap Header Bar",        category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapheader", defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapzone", label = "Minimap Zone Name",           category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapzone", defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimaptrack",label = "Minimap Tracking Button",     category = "minimap", defaultGroup = "Minimap",
		resolver = "minimaptrack", defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapcal",  label = "Minimap Calendar",            category = "minimap", defaultGroup = "Minimap",
		frames = { "GameTimeFrame" }, defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapclock",label = "Minimap Clock",               category = "minimap", defaultGroup = "Minimap",
		frames = { "TimeManagerClockButton" }, defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapdial", label = "Minimap Day/Night Dial",      category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapdial", defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapcoords",label = "Minimap Coordinates",        category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapcoords", defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapmail", label = "Minimap Unread Mail",         category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapmail", defaultTriggers = { combat = true, enemyTarget = true, unreadMail = true } },
	{ key = "minimapcomp", label = "Addon Compartment",           category = "minimap", defaultGroup = "Minimap",
		frames = { "AddonCompartmentFrame" }, defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "minimapaddons",label = "Minimap Addon Buttons",      category = "minimap", defaultGroup = "Minimap",
		resolver = "minimapaddons", defaultTriggers = {} },
	{ key = "belowminimap",label = "Objective Boxes (Below Map)", category = "minimap", defaultGroup = "Minimap",
		frames = { "UIWidgetBelowMinimapContainerFrame" }, defaultAlwaysShow = true, defaultTriggers = {} },

	-- HUD & Trackers
	{ key = "buffs",       label = "Buffs",                       category = "hud", defaultGroup = "None",
		frames = { "BuffFrame", "TemporaryEnchantFrame" },
		defaultTriggers = { combat = true, enemyTarget = true, buffChanged = true, buffExpiring = true } },
	{ key = "debuffs",     label = "Debuffs",                     category = "hud", defaultGroup = "None",
		frames = { "DebuffFrame" },
		defaultTriggers = { combat = true, hasDebuff = true } },
	{ key = "castbar",     label = "Player Cast Bar",             category = "hud", defaultGroup = "None",
		frames = { "PlayerCastingBarFrame", "OverlayPlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "quests",      label = "Quest Tracker",               category = "hud", defaultGroup = "None",
		frames = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" },
		defaultTriggers = { questChanged = true } },
	{ key = "questtimer",  label = "Quest Timer",                 category = "hud", defaultGroup = "None",
		frames = { "QuestTimerFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "topcenter",   label = "Top-Center Event Boxes",      category = "hud", defaultGroup = "None",
		frames = { "UIWidgetTopCenterContainerFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "swing",       label = "Swing Timer",                 category = "hud", defaultGroup = "None",
		frames = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" },
		defaultTriggers = { combat = true } },
	{ key = "cdessential", label = "Cooldown Manager: Essential", category = "hud", defaultGroup = "None",
		frames = { "EssentialCooldownViewer" },
		defaultTriggers = { combat = true } },
	{ key = "cdutility",   label = "Cooldown Manager: Utility",   category = "hud", defaultGroup = "None",
		frames = { "UtilityCooldownViewer" },
		defaultTriggers = { combat = true } },
	{ key = "cdbuffs",     label = "Cooldown Manager: Buffs",     category = "hud", defaultGroup = "None",
		frames = { "BuffIconCooldownViewer" },
		defaultTriggers = { combat = true } },
	{ key = "cdbars",      label = "Cooldown Manager: Bars",      category = "hud", defaultGroup = "None",
		frames = { "BuffBarCooldownViewer" },
		defaultTriggers = { combat = true } },
	{ key = "mirror",      label = "Breath / Fatigue Bars",       category = "hud", defaultGroup = "None",
		frames = { "MirrorTimerContainer", "MirrorTimer1", "MirrorTimer2", "MirrorTimer3" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "encounter",   label = "Encounter Bar",               category = "hud", defaultGroup = "None",
		frames = { "EncounterBar", "PlayerPowerBarAlt" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "damagemeter", label = "Damage Meter",                category = "hud", defaultGroup = "None",
		resolver = "damagemeter",
		defaultTriggers = {} },

	-- Interface & Chat
	{ key = "chat",        label = "Chat Messages",               category = "interface", defaultGroup = "None",
		resolver = "chatmessages",
		defaultTriggers = { chatMessage = true } },
	{ key = "chattabs",    label = "Chat Tabs",                   category = "interface", defaultGroup = "None",
		frames = { "GeneralDockManager" },
		defaultTriggers = {} },
	{ key = "chatbuttons", label = "Chat Buttons",                category = "interface", defaultGroup = "None",
		resolver = "chatbuttons",
		defaultTriggers = {} },
	{ key = "voice",       label = "Voice Chat Speakers",         category = "interface", defaultGroup = "None",
		frames = { "VoiceActivityManager" },
		defaultAlwaysShow = true, defaultTriggers = {} },
	{ key = "micro",       label = "Micro Menu",                  category = "interface", defaultGroup = "Action Bars",
		frames = { "MicroButtonAndBagsBar", "MicroMenuContainer" },
		defaultTriggers = {} },
	{ key = "bags",        label = "Bags Bar",                    category = "interface", defaultGroup = "Action Bars",
		frames = { "BagsBar" },
		defaultTriggers = {} },
	{ key = "xp",          label = "XP & Reputation Bars",        category = "interface", defaultGroup = "Action Bars",
		frames = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "StatusTrackingBarManager" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "durability",  label = "Durability Figure",           category = "interface", defaultGroup = "None",
		frames = { "DurabilityFrame" },
		defaultAlwaysShow = true, defaultTriggers = {} },

	-- Gamepad (WoW Forever)
	{ key = "gamepadbars",   label = "Gamepad Action Bars",       category = "gamepad", defaultGroup = "None",
		frames = { "GamepadMainActionBarFrame" },
		defaultTriggers = { combat = true, enemyTarget = true } },
	{ key = "gamepadlegend", label = "Gamepad Button Hints",      category = "gamepad", defaultGroup = "None",
		frames = { "GamepadPersistentInputLegend" },
		defaultTriggers = {} },
	{ key = "gamepadreticle",label = "Gamepad Reticle",           category = "gamepad", defaultGroup = "None",
		frames = { "GamepadReticle" },
		defaultTriggers = { combat = true, enemyTarget = true } },
}

ns.ELEMENT_BY_KEY = {}
for _, el in ipairs(ns.ELEMENTS) do
	ns.ELEMENT_BY_KEY[el.key] = el
end

-- Default orbiting angle on Minimap rim (173° — evenly spaced 19° above PureFish 192° & PureGrid 211°)
ns.DEFAULT_MINIMAP_ANGLE = 173

-- Build default profile table
function ns.BuildDefaultGeneral()
	return {
		enabled = true,
		showCompartmentButton = true,
		showMinimapButton = false,
		lockMinimapButton = false,
		minimapAngle = ns.DEFAULT_MINIMAP_ANGLE,
		loginBehavior = "delay", -- "delay" or "faded"
		loginDelay = 10,         -- seconds visible on login before fading
		fadeInTime = 0.15,       -- 0.00 (instant) to 2.00s
		combatFadeInTime = 0.15, -- 0.00 (instant) to 2.00s (used when entering combat)
		fadeOutTime = 0.80,      -- 0.00 (instant) to 5.00s
		fadedAlpha = 0.00,       -- 0.00 (invisible) to 0.50 (dimmed)
		hoverRevealDelay = 0.00, -- 0.00 (instant) to 0.50s delay before hover reveals a faded element
		mouseoverHold = 2.5,     -- seconds visible after mouse leaves
		mouseoverBuffer = 25,    -- UI units (~px) of extra hover reach around each element
		combatFadeOutDelay = 10, -- seconds visible after combat ends
		chatPeekDuration = 8,    -- seconds active chat tab stays visible on new message
		buffPeekDuration = 5,    -- seconds buffs stay visible when a buff changes
		questPeekDuration = 6,   -- seconds quest tracker stays visible on quest progress/change
		minimapPingDuration = 5, -- seconds minimap stays visible on ping
		healthThreshold = 100,   -- % below which Health Not Full triggers (100 = any missing HP)
		powerThreshold = 90,     -- % below which Power Not Full triggers (90 = ignores minor buff casts)
		buffExpiringThreshold = 90, -- seconds remaining below which Short / Expiring Buff triggers (90 = 1m 30s)
		-- QoL Interaction triggers
		qolSpellbook = true,     -- Spellbook / Macros open -> Action Bars
		qolDrag = true,          -- Dragging item/spell -> Action Bars & Bags
		qolBagsOpen = false,     -- Bags open -> Bags Bar
		qolChatTyping = true,    -- Typing in chat -> Full Chat (Messages + Tabs + Buttons)
		chatPeekLinesOnly = true,-- Chat Peek shows only newly arrived lines (overlay)
		buffPeekOnlyNew = true,  -- Buff Peek shows only newly gained/refreshed buff icons in-place
		fadeWhenDead = true,     -- Suppress automatic triggers while dead/ghost (hover & chat peeks still work)
	}
end

function ns.BuildDefaultGroups()
	return {
		["Action Bars"] = { syncMode = "all" },   -- "all" (Hover + Triggers) or "hover" (Hover Only)
		["Side Bars"]   = { syncMode = "hover" },
		["Extra Bars"]  = { syncMode = "hover" },
		["Minimap"]     = { syncMode = "hover" },
		["Unit Frames"] = { syncMode = "hover" },
	}
end

function ns.BuildDefaultElements()
	local elements = {}
	for _, el in ipairs(ns.ELEMENTS) do
		local triggers = {}
		if el.defaultTriggers then
			for k, v in pairs(el.defaultTriggers) do
				triggers[k] = v
			end
		end
		elements[el.key] = {
			group = el.defaultGroup or "None",
			alwaysShow = el.defaultAlwaysShow and true or false,
			hover = true,
			triggers = triggers,
		}
	end
	return elements
end

function ns.BuildDefaultAddons()
	local addons = {}
	for _, entry in ipairs(ns.SUPPORTED_ADDONS or {}) do
		local triggers = {}
		if entry.defaultTriggers then
			for k, v in pairs(entry.defaultTriggers) do
				triggers[k] = v
			end
		end
		addons[entry.key] = {
			enabled = true,
			mode = entry.defaultMode or "follow",
			follow = entry.defaultFollow or "None",
			group = "None",
			alwaysShow = entry.defaultAlwaysShow and true or false,
			hover = true,
			triggers = triggers,
		}
	end
	return addons
end

function ns.BuildDefaultProfile()
	local profile = ns.BuildDefaultGeneral()
	profile.groups = ns.BuildDefaultGroups()
	profile.elements = ns.BuildDefaultElements()
	profile.addons = ns.BuildDefaultAddons()
	profile.customFrames = {} -- [frameName] = { mode = "custom"|"follow", follow = "None", group = "None", alwaysShow = false, hover = true, triggers = {} }
	return profile
end
