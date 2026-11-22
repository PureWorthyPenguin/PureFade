-- PureFade: Addon entry point, SavedVariables & Profiles management, and /purefade slash command.
local ADDON_NAME, ns = ...

local charKey
local activeProfileName = "Default"
local activeDB

local function GetCharKey()
	if not charKey then
		local name = UnitName("player") or "Unknown"
		local realm = GetRealmName() or "Unknown"
		charKey = name .. " - " .. realm
	end
	return charKey
end

-- Fill any missing default keys in a profile without overwriting user customizations
local function MergeDefaults(profile)
	local defGeneral = ns.BuildDefaultGeneral()
	for k, v in pairs(defGeneral) do
		if profile[k] == nil then
			profile[k] = v
		end
	end

	if type(profile.groups) ~= "table" then
		profile.groups = ns.BuildDefaultGroups()
	end

	if type(profile.elements) ~= "table" then
		profile.elements = ns.BuildDefaultElements()
	else
		local defElements = ns.BuildDefaultElements()
		for k, defCfg in pairs(defElements) do
			if profile.elements[k] == nil then
				profile.elements[k] = ns.DeepCopy(defCfg)
			else
				if profile.elements[k].group == nil then profile.elements[k].group = defCfg.group end
				if profile.elements[k].alwaysShow == nil then profile.elements[k].alwaysShow = defCfg.alwaysShow end
				if profile.elements[k].hover == nil then profile.elements[k].hover = defCfg.hover end
				if type(profile.elements[k].triggers) ~= "table" then profile.elements[k].triggers = {} end
			end
		end
	end

	if type(profile.addons) ~= "table" then
		profile.addons = ns.BuildDefaultAddons()
	else
		local defAddons = ns.BuildDefaultAddons()
		for k, defCfg in pairs(defAddons) do
			if profile.addons[k] == nil then
				profile.addons[k] = ns.DeepCopy(defCfg)
			else
				if profile.addons[k].enabled == nil then profile.addons[k].enabled = defCfg.enabled end
				if profile.addons[k].mode == nil then profile.addons[k].mode = defCfg.mode end
				if profile.addons[k].follow == nil then profile.addons[k].follow = defCfg.follow end
				if profile.addons[k].group == nil then profile.addons[k].group = defCfg.group end
				if profile.addons[k].alwaysShow == nil then profile.addons[k].alwaysShow = defCfg.alwaysShow end
				if profile.addons[k].hover == nil then profile.addons[k].hover = defCfg.hover end
				if type(profile.addons[k].triggers) ~= "table" then profile.addons[k].triggers = {} end
			end
		end
	end

	if type(profile.customFrames) ~= "table" then
		profile.customFrames = {}
	end
	-- Remove legacy unused key (moved to Peek -> New Chat Message trigger)
	profile.qolChatPeek = nil
end

local function TablesEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not TablesEqual(v, b[k]) then return false end
	end
	for k, v in pairs(b) do
		if a[k] == nil and v ~= nil then return false end
	end
	return true
end

local function NextAvailableProfileName(base)
	if not PureFadeDB.profiles[base] then return base end
	for i = 2, 99 do
		local cand = base .. " " .. i
		if not PureFadeDB.profiles[cand] then return cand end
	end
	return base .. " " .. math.random(100, 999)
end

local function InitSavedVariables()
	if type(PureFadeDB) ~= "table" then
		PureFadeDB = {}
	end
	if type(PureFadeDB.profiles) ~= "table" then
		PureFadeDB.profiles = {}
	end
	if type(PureFadeDB.profileKeys) ~= "table" then
		PureFadeDB.profileKeys = {}
	end

	local freshDefault = ns.BuildDefaultProfile()

	-- One-time safe migration: if an existing "Default" profile has user customizations,
	-- preserve it as "Custom" before locking "Default" as strictly read-only.
	if not PureFadeDB.migratedDefaultV11 then
		PureFadeDB.migratedDefaultV11 = true
		local oldDef = PureFadeDB.profiles["Default"]
		if type(oldDef) == "table" then
			MergeDefaults(oldDef)
			if not TablesEqual(oldDef, freshDefault) then
				local targetName = NextAvailableProfileName("Custom")
				PureFadeDB.profiles[targetName] = ns.DeepCopy(oldDef)
				for k, v in pairs(PureFadeDB.profileKeys) do
					if v == "Default" then
						PureFadeDB.profileKeys[k] = targetName
					end
				end
				print("|cff66ccffPureFade:|r Preserved your customized settings in profile '|cffffff00" .. targetName .. "|r' (Default is now read-only).")
			end
		end
	end

	-- Default profile is always pure & read-only
	PureFadeDB.profiles["Default"] = freshDefault

	local key = GetCharKey()
	local savedName = PureFadeDB.profileKeys[key]
	if savedName and type(PureFadeDB.profiles[savedName]) == "table" then
		activeProfileName = savedName
	else
		activeProfileName = "Default"
		PureFadeDB.profileKeys[key] = "Default"
	end

	activeDB = PureFadeDB.profiles[activeProfileName]
	MergeDefaults(activeDB)
end

-- Profile API
function ns.GetDB()
	return activeDB
end

function ns.GetActiveProfileName()
	return activeProfileName
end

function ns.IsReadOnlyProfile()
	return activeProfileName == "Default"
end

-- Auto-fork "Default" into "Custom" on the first edit (overwriting any previous "Custom"
-- with a fresh copy starting from Default). Promotes the live table object so existing UI
-- closures immediately mutate "Custom", while "Default" gets a brand-new pristine table.
function ns.EnsureEditableProfile()
	if activeProfileName ~= "Default" then
		return activeDB, false
	end
	local promoted = activeDB
	PureFadeDB.profiles["Default"] = ns.BuildDefaultProfile()
	PureFadeDB.profiles["Custom"] = promoted
	activeProfileName = "Custom"
	PureFadeDB.profileKeys[GetCharKey()] = "Custom"
	activeDB = promoted
	print("|cff66ccffPureFade:|r Switched to '|cffffff00Custom|r' profile (Default stays unchanged).")
	return activeDB, true
end

function ns.GetProfileNames()
	local names = {}
	if PureFadeDB and PureFadeDB.profiles then
		for name in pairs(PureFadeDB.profiles) do
			names[#names + 1] = name
		end
	end
	table.sort(names, function(a, b)
		if a == "Default" then return true end
		if b == "Default" then return false end
		return a < b
	end)
	return names
end

function ns.SetProfile(name)
	if not PureFadeDB or not PureFadeDB.profiles or not PureFadeDB.profiles[name] then
		return false
	end
	activeProfileName = name
	PureFadeDB.profileKeys[GetCharKey()] = name
	activeDB = PureFadeDB.profiles[name]
	MergeDefaults(activeDB)
	print("|cff66ccffPureFade:|r Switched to profile '" .. name .. "'.")
	return true
end

function ns.CreateProfile(name, copyCurrent)
	if not name or name == "" or name == "Default" then
		return false
	end
	if PureFadeDB.profiles[name] then
		print("|cff66ccffPureFade:|r Profile '" .. name .. "' already exists.")
		return false
	end
	if copyCurrent and activeDB then
		PureFadeDB.profiles[name] = ns.DeepCopy(activeDB)
	else
		PureFadeDB.profiles[name] = ns.BuildDefaultProfile()
	end
	return ns.SetProfile(name)
end

function ns.RenameProfile(oldName, newName)
	newName = strtrim(newName or "")
	if not oldName or oldName == "Default" or newName == "" or newName == "Default" or newName == oldName then
		return false
	end
	if not PureFadeDB.profiles[oldName] then
		return false
	end
	if PureFadeDB.profiles[newName] then
		print("|cff66ccffPureFade:|r Profile '" .. newName .. "' already exists.")
		return false
	end
	PureFadeDB.profiles[newName] = PureFadeDB.profiles[oldName]
	PureFadeDB.profiles[oldName] = nil
	for k, v in pairs(PureFadeDB.profileKeys) do
		if v == oldName then
			PureFadeDB.profileKeys[k] = newName
		end
	end
	if activeProfileName == oldName then
		activeProfileName = newName
		activeDB = PureFadeDB.profiles[newName]
	end
	print("|cff66ccffPureFade:|r Renamed profile '" .. oldName .. "' to '" .. newName .. "'.")
	return true
end

function ns.RenameCurrentProfile(newName)
	return ns.RenameProfile(activeProfileName, newName)
end

function ns.DeleteProfile(targetName)
	if not targetName or targetName == "Default" or not PureFadeDB.profiles[targetName] then
		return false
	end
	PureFadeDB.profiles[targetName] = nil
	for k, v in pairs(PureFadeDB.profileKeys) do
		if v == targetName then
			PureFadeDB.profileKeys[k] = "Default"
		end
	end
	print("|cff66ccffPureFade:|r Deleted profile '" .. targetName .. "'.")
	if activeProfileName == targetName then
		return ns.SetProfile("Default")
	end
	return true
end

function ns.DeleteCurrentProfile()
	return ns.DeleteProfile(activeProfileName)
end

-- Per-page Reset to Defaults (blocked on read-only Default profile)
function ns.ResetPageDefaults(pageKey)
	if not activeDB or ns.IsReadOnlyProfile() then return end

	if pageKey == "general" then
		local def = ns.BuildDefaultGeneral()
		for k, v in pairs(def) do
			activeDB[k] = v
		end
		print("|cff66ccffPureFade:|r General settings reset to defaults.")
	elseif pageKey == "elements" then
		activeDB.elements = ns.BuildDefaultElements()
		activeDB.customFrames = {}
		print("|cff66ccffPureFade:|r Elements settings reset to defaults.")
	elseif pageKey == "groups" then
		activeDB.groups = ns.BuildDefaultGroups()
		-- Ensure elements pointing to deleted groups revert to None
		for _, cfg in pairs(activeDB.elements or {}) do
			if cfg.group and cfg.group ~= "None" and not activeDB.groups[cfg.group] then
				cfg.group = "None"
			end
		end
		print("|cff66ccffPureFade:|r Groups reset to defaults.")
	elseif pageKey == "addons" then
		activeDB.addons = ns.BuildDefaultAddons()
		if ns.RestoreAllFrames then ns.RestoreAllFrames() end
		print("|cff66ccffPureFade:|r Addons settings reset to defaults.")
	elseif pageKey == "all" then
		PureFadeDB.profiles[activeProfileName] = ns.BuildDefaultProfile()
		activeDB = PureFadeDB.profiles[activeProfileName]
		print("|cff66ccffPureFade:|r Profile '" .. activeProfileName .. "' reset to defaults.")
	end
end

--------------------------------------------------------------------------------
-- ZERO-DEPENDENCY PROFILE EXPORT / IMPORT (PF1:<Base64>)
--------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INV = {}
for i = 1, #B64 do
	B64_INV[B64:sub(i, i)] = i - 1
end

local function B64Encode(data)
	local out = {}
	local n = #data
	for i = 1, n, 3 do
		local a = data:byte(i) or 0
		local b = data:byte(i + 1)
		local c = data:byte(i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(v / 262144) % 64 + 1
		local c2 = math.floor(v / 4096) % 64 + 1
		local c3 = math.floor(v / 64) % 64 + 1
		local c4 = v % 64 + 1
		out[#out + 1] = B64:sub(c1, c1)
		out[#out + 1] = B64:sub(c2, c2)
		out[#out + 1] = b and B64:sub(c3, c3) or "="
		out[#out + 1] = c and B64:sub(c4, c4) or "="
	end
	return table.concat(out)
end

local function B64Decode(str)
	str = str:gsub("%s+", "")
	if (#str % 4) ~= 0 then return nil end
	local out = {}
	for i = 1, #str, 4 do
		local s1, s2, s3, s4 = str:sub(i, i), str:sub(i + 1, i + 1), str:sub(i + 2, i + 2), str:sub(i + 3, i + 3)
		local a, b = B64_INV[s1], B64_INV[s2]
		if not a or not b then return nil end
		local c = (s3 == "=") and nil or B64_INV[s3]
		local d = (s4 == "=") and nil or B64_INV[s4]
		if (s3 ~= "=" and not c) or (s4 ~= "=" and not d) then return nil end
		local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
		out[#out + 1] = string.char(math.floor(v / 65536) % 256)
		if c then out[#out + 1] = string.char(math.floor(v / 256) % 256) end
		if d then out[#out + 1] = string.char(v % 256) end
	end
	return table.concat(out)
end

-- Compact safe serializer: S<len>:<str> | N<num>; | T | F | {<k><v>...}
local function SerializeVal(val, out)
	local t = type(val)
	if t == "string" then
		out[#out + 1] = "S" .. #val .. ":" .. val
	elseif t == "number" then
		out[#out + 1] = "N" .. tostring(val) .. ";"
	elseif t == "boolean" then
		out[#out + 1] = val and "T" or "F"
	elseif t == "table" then
		out[#out + 1] = "{"
		for k, v in pairs(val) do
			if (type(k) == "string" or type(k) == "number")
				and (type(v) == "string" or type(v) == "number" or type(v) == "boolean" or type(v) == "table") then
				SerializeVal(k, out)
				SerializeVal(v, out)
			end
		end
		out[#out + 1] = "}"
	end
end

local function DeserializeVal(str, pos, depth)
	if depth > 12 or pos > #str then return nil, pos end
	local tag = str:sub(pos, pos)
	if tag == "T" then
		return true, pos + 1
	elseif tag == "F" then
		return false, pos + 1
	elseif tag == "N" then
		local semi = str:find(";", pos + 1, true)
		if not semi then return nil, pos end
		local num = tonumber(str:sub(pos + 1, semi - 1))
		if not num then return nil, pos end
		return num, semi + 1
	elseif tag == "S" then
		local colon = str:find(":", pos + 1, true)
		if not colon then return nil, pos end
		local len = tonumber(str:sub(pos + 1, colon - 1))
		if not len or len < 0 or (colon + len) > #str then return nil, pos end
		return str:sub(colon + 1, colon + len), colon + len + 1
	elseif tag == "{" then
		local tbl = {}
		local cur = pos + 1
		local guard = 0
		while cur <= #str and str:sub(cur, cur) ~= "}" do
			guard = guard + 1
			if guard > 2000 then return nil, cur end
			local k, nextPos = DeserializeVal(str, cur, depth + 1)
			if k == nil then return nil, cur end
			local v, afterPos = DeserializeVal(str, nextPos, depth + 1)
			if v == nil then return nil, nextPos end
			tbl[k] = v
			cur = afterPos
		end
		if str:sub(cur, cur) ~= "}" then return nil, cur end
		return tbl, cur + 1
	end
	return nil, pos
end

function ns.ExportProfile()
	if not activeDB then return "" end
	local out = {}
	SerializeVal(activeDB, out)
	return "PF1:" .. B64Encode(table.concat(out))
end

function ns.ValidateImportString(encoded)
	encoded = strtrim(encoded or "")
	if encoded:sub(1, 4) ~= "PF1:" then
		return false, "Invalid profile string (must start with PF1:)."
	end
	local raw = B64Decode(encoded:sub(5))
	if not raw then
		return false, "Could not decode profile string (corrupted or incomplete)."
	end
	local parsed, endPos = DeserializeVal(raw, 1, 0)
	if type(parsed) ~= "table" or endPos <= 1 then
		return false, "Profile data is invalid or corrupted."
	end
	return true
end

function ns.ImportProfile(encoded, requestedName)
	encoded = strtrim(encoded or "")
	if encoded:sub(1, 4) ~= "PF1:" then
		return false, "Invalid profile string (must start with PF1:)."
	end
	local raw = B64Decode(encoded:sub(5))
	if not raw then
		return false, "Could not decode profile string (corrupted or incomplete)."
	end
	local parsed, endPos = DeserializeVal(raw, 1, 0)
	if type(parsed) ~= "table" or endPos <= 1 then
		return false, "Profile data is invalid or corrupted."
	end
	MergeDefaults(parsed)

	local baseName = strtrim(requestedName or "")
	if baseName == "" or baseName == "Default" then
		baseName = "Imported"
	end
	local finalName = NextAvailableProfileName(baseName)
	PureFadeDB.profiles[finalName] = parsed
	ns.SetProfile(finalName)
	return true, finalName
end

-- Addon Compartment callbacks (Left-Click: Pause/Resume, Right-Click: Settings)
function PureFade_OnAddonCompartmentClick(_, buttonName)
	if buttonName == "RightButton" then
		ns.OpenSettings()
	else
		local newState = not ns.IsPaused()
		ns.SetPaused(newState)
		if newState then
			print("|cff66ccffPureFade:|r Paused (UI restored to 100%). Left-click again or type |cffffff00/purefade toggle|r to resume.")
		else
			print("|cff66ccffPureFade:|r Resumed.")
			ns.ForceRefresh()
		end
	end
end

function PureFade_OnAddonCompartmentEnter(_, menuButtonFrame)
	GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
	GameTooltip:SetText("PureFade", 1, 0.82, 0)
	local status = ns.IsPaused() and "|cffff6666Paused|r" or (ns.GetDB() and ns.GetDB().enabled and "|cff66ff66Active|r" or "|cffff6666Disabled|r")
	GameTooltip:AddLine("Status: " .. status, 1, 1, 1)
	GameTooltip:AddLine("Left-Click: Pause / Resume", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Right-Click: Open Settings", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

function PureFade_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- Slash command: /purefade
SLASH_PUREFADE1 = "/purefade"
SlashCmdList["PUREFADE"] = function(msg)
	local cmd = strtrim((msg or ""):lower())
	if cmd == "toggle" then
		local newState = not ns.IsPaused()
		ns.SetPaused(newState)
		if newState then
			print("|cff66ccffPureFade:|r Paused (UI restored to 100%). Type |cffffff00/purefade toggle|r to resume.")
		else
			print("|cff66ccffPureFade:|r Resumed.")
			ns.ForceRefresh()
		end
	elseif cmd:sub(1, 3) == "why" then
		local filter = strtrim(cmd:sub(4))
		if ns.DebugWhy then
			ns.DebugWhy(filter)
		end
	else
		ns.OpenSettings()
	end
end

-- Lifecycle events
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			InitSavedVariables()
			ns.InitUI()
		else
			-- Late-loaded Blizzard/addon frame: refresh discovery
			if ns.DiscoverFrames and activeDB then
				ns.DiscoverFrames()
			end
		end
	elseif event == "PLAYER_LOGIN" then
		ns.StartLoginHold()
		ns.StartEngine()
	end
end)
