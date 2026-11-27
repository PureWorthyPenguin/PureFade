-- PureFade: Built-in 3rd-party addon support registry and 1-click Visual Frame Picker.
local _, ns = ...

local IsUsableFrame = ns.IsUsableFrame
local SafeBool = ns.SafeBool
local SafeNumber = ns.SafeNumber

function ns.IsAddOnLoadedSafe(name)
	if not name then return false end
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name) and true or false
	end
	if IsAddOnLoaded then
		return IsAddOnLoaded(name) and true or false
	end
	return false
end

-- Build numbered frame name lists cleanly (e.g. Questie_ItemButton1..35)
local function Numbered(prefix, count)
	local list = {}
	for i = 1, count do
		list[i] = prefix .. i
	end
	return list
end

local function ConcatLists(...)
	local out = {}
	for i = 1, select("#", ...) do
		local src = select(i, ...)
		if type(src) == "table" then
			for _, v in ipairs(src) do
				out[#out + 1] = v
			end
		end
	end
	return out
end

-- Declarative 3rd-party addon catalog (costs 0 CPU if the addon is not loaded)
ns.SUPPORTED_ADDONS = {
	{
		key = "questie",
		addon = "Questie",
		label = "Questie Tracker",
		defaultMode = "follow",
		defaultFollow = "quests",
		frames = ConcatLists({ "Questie_BaseFrame" }, Numbered("Questie_ItemButton", 35)),
	},
	{
		key = "details",
		addon = "Details",
		label = "Details! Damage Meter",
		defaultMode = "follow",
		defaultFollow = "damagemeter",
		frames = Numbered("DetailsBaseFrame", 5),
	},
	{
		key = "rxp",
		addon = "RXPGuides",
		label = "RestedXP Guides",
		defaultMode = "follow",
		defaultFollow = "quests",
		frames = { "RXPFrame" },
	},
	{
		key = "tomtom_arrow",
		addon = "TomTom",
		label = "TomTom Crazy Arrow",
		defaultMode = "custom",
		defaultAlwaysShow = true,
		frames = { "TomTomCrazyArrow" },
	},
	{
		key = "tomtom_coords",
		addon = "TomTom",
		label = "TomTom Coordinates",
		defaultMode = "follow",
		defaultFollow = "minimap",
		frames = { "TomTomBlock" },
	},
	{
		key = "mbb",
		addon = "MinimapButtonButton",
		label = "MinimapButtonButton",
		defaultMode = "follow",
		defaultFollow = "minimapaddons",
		frames = { "MinimapButtonButton", "MBB_MinimapButtonFrame" },
	},
	-- Bartender4: individual 1-to-1 entries following their matching Blizzard UI elements
	{ key = "bt4_bar1",    addon = "Bartender4", label = "Bartender4: Bar 1",                  defaultMode = "follow", defaultFollow = "mainbar",   frames = { "BT4Bar1" } },
	{ key = "bt4_bar2",    addon = "Bartender4", label = "Bartender4: Bar 2",                  defaultMode = "follow", defaultFollow = "bar2",      frames = { "BT4Bar2" } },
	{ key = "bt4_bar3",    addon = "Bartender4", label = "Bartender4: Bar 3 (Right 1)",        defaultMode = "follow", defaultFollow = "bar4",      frames = { "BT4Bar3" } },
	{ key = "bt4_bar4",    addon = "Bartender4", label = "Bartender4: Bar 4 (Right 2)",        defaultMode = "follow", defaultFollow = "bar5",      frames = { "BT4Bar4" } },
	{ key = "bt4_bar5",    addon = "Bartender4", label = "Bartender4: Bar 5 (Bottom Right)",   defaultMode = "follow", defaultFollow = "bar3",      frames = { "BT4Bar5" } },
	{ key = "bt4_bar6",    addon = "Bartender4", label = "Bartender4: Bar 6 (Bottom Left)",    defaultMode = "follow", defaultFollow = "bar2",      frames = { "BT4Bar6" } },
	{ key = "bt4_bar7",    addon = "Bartender4", label = "Bartender4: Bar 7 (Bonus)",          defaultMode = "follow", defaultFollow = "bar6",      frames = { "BT4Bar7" } },
	{ key = "bt4_bar8",    addon = "Bartender4", label = "Bartender4: Bar 8 (Class 1)",        defaultMode = "follow", defaultFollow = "bar6",      frames = { "BT4Bar8" } },
	{ key = "bt4_bar9",    addon = "Bartender4", label = "Bartender4: Bar 9 (Class 2)",        defaultMode = "follow", defaultFollow = "bar7",      frames = { "BT4Bar9" } },
	{ key = "bt4_bar10",   addon = "Bartender4", label = "Bartender4: Bar 10 (Class 3)",       defaultMode = "follow", defaultFollow = "bar8",      frames = { "BT4Bar10" } },
	{ key = "bt4_bar13",   addon = "Bartender4", label = "Bartender4: Extra Bar 6 (Bar 13)",   defaultMode = "follow", defaultFollow = "bar6",      frames = { "BT4Bar13" } },
	{ key = "bt4_bar14",   addon = "Bartender4", label = "Bartender4: Extra Bar 7 (Bar 14)",   defaultMode = "follow", defaultFollow = "bar7",      frames = { "BT4Bar14" } },
	{ key = "bt4_bar15",   addon = "Bartender4", label = "Bartender4: Extra Bar 8 (Bar 15)",   defaultMode = "follow", defaultFollow = "bar8",      frames = { "BT4Bar15" } },
	{ key = "bt4_pet",     addon = "Bartender4", label = "Bartender4: Pet Bar",                defaultMode = "follow", defaultFollow = "petbar",    frames = { "BT4BarPetBar" } },
	{ key = "bt4_stance",  addon = "Bartender4", label = "Bartender4: Stance Bar",             defaultMode = "follow", defaultFollow = "stancebar", frames = { "BT4BarStanceBar" } },
	{ key = "bt4_totem",   addon = "Bartender4", label = "Bartender4: Totem Bar",              defaultMode = "follow", defaultFollow = "totembar",  frames = { "BT4BarMultiCast" } },
	{ key = "bt4_extra",   addon = "Bartender4", label = "Bartender4: Extra Action Bar",       defaultMode = "follow", defaultFollow = "extrabar",  frames = { "BT4BarExtraActionBar", "BT4BarZoneAbilityBar" } },
	{ key = "bt4_bags",    addon = "Bartender4", label = "Bartender4: Bag Bar",                defaultMode = "follow", defaultFollow = "bags",      frames = { "BT4BarBagBar" } },
	{ key = "bt4_micro",   addon = "Bartender4", label = "Bartender4: Micro Menu",             defaultMode = "follow", defaultFollow = "micro",     frames = { "BT4BarMicroMenu" } },
	{ key = "bt4_vehicle", addon = "Bartender4", label = "Bartender4: Vehicle Bar",            defaultMode = "follow", defaultFollow = "mainbar",   frames = { "BT4BarVehicle" } },
	{ key = "bt4_queue",   addon = "Bartender4", label = "Bartender4: Queue Status Bar",       defaultMode = "follow", defaultFollow = "minimap",   frames = { "BT4BarQueueStatus" } },
	{ key = "bt4_status",  addon = "Bartender4", label = "Bartender4: Status Tracking Bar",    defaultMode = "follow", defaultFollow = "xp",        frames = { "BT4BarStatusTrackingBar", "BT4BarStatus", "BT4BarXP", "BT4BarRep" } },
	{ key = "bt4_art",     addon = "Bartender4", label = "Bartender4: Blizzard Art Bar",       defaultMode = "follow", defaultFollow = "barart",    frames = { "BT4BarBlizzardArt" } },
	{
		key = "titan",
		addon = "Titan",
		label = "Titan Panel",
		defaultMode = "custom",
		defaultFollow = "None",
		defaultTriggers = {},
		frames = { "Titan_Bar__Display_Bar", "Titan_Bar__Display_Bar2", "Titan_Bar__Display_AuxBar", "Titan_Bar__Display_AuxBar2" },
	},
	{
		key = "rarescanner",
		addon = "RareScanner",
		label = "RareScanner Alert",
		defaultMode = "custom",
		defaultFollow = "None",
		defaultAlwaysShow = true,
		defaultTriggers = {},
		frames = { "scanner_button" },
	},
	{
		key = "healbot",
		addon = "HealBot",
		label = "HealBot Frames",
		defaultMode = "follow",
		defaultFollow = "raid",
		frames = { "HealBot_Action" },
	},
	{
		key = "bigwigs",
		addon = "BigWigs",
		label = "BigWigs Bars",
		defaultMode = "custom",
		defaultFollow = "None",
		defaultTriggers = { combat = true },
		frames = { "BigWigsAnchor", "BigWigsEmphasizeAnchor" },
	},
	{
		key = "dbm",
		addon = "DBM-Core",
		label = "DBM Timers",
		defaultMode = "custom",
		defaultFollow = "None",
		defaultTriggers = { combat = true },
		frames = { "DBT_Bar_1", "DBT_Bar_2" },
	},
	-- Dominos: individual entries following their matching Blizzard UI elements
	{ key = "dom_bar1",   addon = "Dominos", label = "Dominos: Bar 1",             defaultMode = "follow", defaultFollow = "mainbar",   frames = { "DominosFrame1" } },
	{ key = "dom_bar2",   addon = "Dominos", label = "Dominos: Bar 2",             defaultMode = "follow", defaultFollow = "bar2",      frames = { "DominosFrame2" } },
	{ key = "dom_bar3",   addon = "Dominos", label = "Dominos: Bar 3",             defaultMode = "follow", defaultFollow = "bar3",      frames = { "DominosFrame3" } },
	{ key = "dom_bar4",   addon = "Dominos", label = "Dominos: Bar 4",             defaultMode = "follow", defaultFollow = "bar4",      frames = { "DominosFrame4" } },
	{ key = "dom_bar5",   addon = "Dominos", label = "Dominos: Bar 5",             defaultMode = "follow", defaultFollow = "bar5",      frames = { "DominosFrame5" } },
	{ key = "dom_bar6",   addon = "Dominos", label = "Dominos: Bar 6",             defaultMode = "follow", defaultFollow = "bar6",      frames = { "DominosFrame6" } },
	{ key = "dom_bar7",   addon = "Dominos", label = "Dominos: Bar 7",             defaultMode = "follow", defaultFollow = "bar7",      frames = { "DominosFrame7" } },
	{ key = "dom_bar8",   addon = "Dominos", label = "Dominos: Bar 8",             defaultMode = "follow", defaultFollow = "bar8",      frames = { "DominosFrame8" } },
	{ key = "dom_bar9",   addon = "Dominos", label = "Dominos: Bar 9",             defaultMode = "follow", defaultFollow = "bar7",      frames = { "DominosFrame9" } },
	{ key = "dom_bar10",  addon = "Dominos", label = "Dominos: Bar 10",            defaultMode = "follow", defaultFollow = "bar8",      frames = { "DominosFrame10" } },
	{ key = "dom_pet",    addon = "Dominos", label = "Dominos: Pet Bar",           defaultMode = "follow", defaultFollow = "petbar",    frames = { "DominosFramepet" } },
	{ key = "dom_class",  addon = "Dominos", label = "Dominos: Class / Stance Bar",defaultMode = "follow", defaultFollow = "stancebar", frames = { "DominosFrameclass" } },
	{ key = "dom_bags",   addon = "Dominos", label = "Dominos: Bag Bar",           defaultMode = "follow", defaultFollow = "bags",      frames = { "DominosFramebags" } },
	{ key = "dom_menu",   addon = "Dominos", label = "Dominos: Micro Menu",        defaultMode = "follow", defaultFollow = "micro",     frames = { "DominosFramemenu" } },
	{ key = "dom_extra",  addon = "Dominos", label = "Dominos: Extra Action Bar",  defaultMode = "follow", defaultFollow = "extrabar",  frames = { "DominosFrameextra" } },
	{
		key = "recount",
		addon = "Recount",
		label = "Recount Damage Meter",
		defaultMode = "follow",
		defaultFollow = "damagemeter",
		frames = { "Recount_MainWindow" },
	},
	{
		key = "skada",
		addon = "Skada",
		label = "Skada Damage Meter",
		defaultMode = "follow",
		defaultFollow = "damagemeter",
		frames = ConcatLists({ "SkadaBarWindowSkada" }, Numbered("SkadaBarWindow", 5)),
	},
}

ns.SUPPORTED_ADDON_BY_KEY = {}
for _, entry in ipairs(ns.SUPPORTED_ADDONS) do
	ns.SUPPORTED_ADDON_BY_KEY[entry.key] = entry
end

--------------------------------------------------------------------------------
-- 1-CLICK VISUAL FRAME PICKER (for any unsupported addon)
--------------------------------------------------------------------------------
local pickerActive = false
local pickerReadyAt = 0
local pickerBanner, pickerHighlight, pickerCatcher
local pickerTargetName, pickerTargetOwner, pickerCallback

local function GetTopMouseFrame()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if type(foci) == "table" then
			for _, f in ipairs(foci) do
				if f ~= pickerCatcher and f ~= pickerHighlight and f ~= pickerBanner and f ~= WorldFrame then
					return f
				end
			end
		end
	end
	return nil
end

-- Walk up to the nearest usable named frame (skipping UIParent / WorldFrame)
local function FindNamedFrameUnderCursor()
	local cur = GetTopMouseFrame()
	local guard = 0
	while cur and guard < 15 do
		if IsUsableFrame(cur) and cur ~= UIParent and cur ~= WorldFrame and cur.GetName then
			local ok, name = pcall(cur.GetName, cur)
			if ok and type(name) == "string" and name ~= "" and _G[name] == cur then
				return cur, name
			end
		end
		if not IsUsableFrame(cur) or not cur.GetParent then
			break
		end
		cur = cur:GetParent()
		guard = guard + 1
	end
	return nil, nil
end

local function StopFramePicker(pickedName, existingOwner)
	pickerActive = false
	if pickerBanner then pickerBanner:Hide() end
	if pickerHighlight then pickerHighlight:Hide() end
	if pickerCatcher then
		pickerCatcher:UnregisterAllEvents()
		pickerCatcher:SetScript("OnUpdate", nil)
		pickerCatcher:Hide()
	end
	if ns.SetPickerPreview then
		ns.SetPickerPreview(false)
	end
	local cb = pickerCallback
	pickerCallback = nil
	pickerTargetName = nil
	pickerTargetOwner = nil
	if cb then
		cb(pickedName, existingOwner)
	end
end

function ns.StartFramePicker(onPicked)
	if pickerActive then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		print("|cff66ccffPureFade:|r Cannot use Frame Picker during combat.")
		return
	end

	-- Hide Blizzard Settings temporarily and reveal all UI elements at 100% so everything is visible to pick
	if SettingsPanel and SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	end
	if ns.SetPickerPreview then
		ns.SetPickerPreview(true)
	end

	if not pickerBanner then
		pickerBanner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		pickerBanner:SetFrameStrata("TOOLTIP")
		pickerBanner:SetSize(460, 54)
		pickerBanner:SetPoint("TOP", UIParent, "TOP", 0, -40)
		pickerBanner:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		pickerBanner:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
		pickerBanner:SetBackdropBorderColor(1, 0.82, 0, 0.95)

		pickerBanner.title = pickerBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		pickerBanner.title:SetPoint("TOP", pickerBanner, "TOP", 0, -8)
		pickerBanner.title:SetText("PureFade Frame Picker — Left-Click to Add | Right-Click or Esc to Cancel")

		pickerBanner.nameFS = pickerBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		pickerBanner.nameFS:SetPoint("BOTTOM", pickerBanner, "BOTTOM", 0, 9)
		pickerBanner.nameFS:SetText("|cffaaaaaaHover over any addon frame...|r")
	end

	if not pickerHighlight then
		pickerHighlight = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		pickerHighlight:SetFrameStrata("TOOLTIP")
		pickerHighlight:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		pickerHighlight:SetBackdropColor(1, 0.82, 0, 0.14)
		pickerHighlight:SetBackdropBorderColor(1, 0.82, 0, 1)
		pickerHighlight:EnableMouse(false)
	end

	if not pickerCatcher then
		pickerCatcher = CreateFrame("Frame", nil, UIParent)
		pickerCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
		pickerCatcher:EnableMouse(false)
		pickerCatcher:EnableKeyboard(true)
		pickerCatcher:SetPropagateKeyboardInput(false)
		pickerCatcher:SetScript("OnEvent", function(_, event, button)
			if not pickerActive or GetTime() < pickerReadyAt then return end
			if event == "GLOBAL_MOUSE_DOWN" then
				if button == "RightButton" then
					StopFramePicker(nil, nil)
				elseif button == "LeftButton" and (pickerTargetName or pickerTargetOwner) then
					StopFramePicker(pickerTargetName, pickerTargetOwner)
				end
			end
		end)
		pickerCatcher:SetScript("OnKeyDown", function(_, key)
			if key == "ESCAPE" then
				StopFramePicker(nil, nil)
			end
		end)
	end

	pickerActive = true
	pickerReadyAt = GetTime() + 0.25
	pickerCallback = onPicked
	pickerTargetName = nil
	pickerTargetOwner = nil
	pickerBanner:Show()
	pickerHighlight:Hide()
	pickerCatcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	pickerCatcher:Show()

	pickerCatcher:SetScript("OnUpdate", function()
		if not pickerActive then return end
		local frame, name = FindNamedFrameUnderCursor()

		if frame and name then
			local owner = ns.FindExistingOwner and ns.FindExistingOwner(frame) or nil
			pickerTargetName = name
			pickerTargetOwner = owner
			if owner then
				pickerBanner.nameFS:SetText("|cff77ccffAlready managed:|r |cffffff00" .. owner.label .. "|r — Left-Click to open settings")
				pickerHighlight:SetBackdropColor(0.3, 0.7, 1, 0.16)
				pickerHighlight:SetBackdropBorderColor(0.35, 0.78, 1, 1)
			else
				pickerBanner.nameFS:SetText("New frame: |cff66ff66" .. name .. "|r — Left-Click to add")
				pickerHighlight:SetBackdropColor(1, 0.82, 0, 0.14)
				pickerHighlight:SetBackdropBorderColor(1, 0.82, 0, 1)
			end
			local l, b, w, h = frame:GetRect()
			local sc = SafeNumber(frame:GetEffectiveScale())
			local uiSc = SafeNumber(UIParent:GetEffectiveScale()) or 1
			if SafeNumber(l) and SafeNumber(b) and SafeNumber(w) and SafeNumber(h) and sc and sc > 0 then
				local ratio = sc / uiSc
				pickerHighlight:ClearAllPoints()
				pickerHighlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
				pickerHighlight:SetSize(math.max(8, w * ratio), math.max(8, h * ratio))
				pickerHighlight:Show()
			else
				pickerHighlight:Hide()
			end
		else
			pickerTargetName = nil
			pickerTargetOwner = nil
			pickerBanner.nameFS:SetText("|cffaaaaaaHover over any UI or addon frame...|r")
			pickerHighlight:Hide()
		end
	end)
end
