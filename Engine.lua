-- PureFade: Core fade engine, frame discovery, grouping, hover hold, and smooth/instant alpha interpolation.
local _, ns = ...

local SafeBool = ns.SafeBool
local SafeNumber = ns.SafeNumber
local IsUsableFrame = ns.IsUsableFrame

-- Elements that receive QoL interaction reveals
local ACTION_BAR_KEYS = {
	mainbar = true, barart = true, bar2 = true, bar3 = true,
	bar4 = true, bar5 = true, bar6 = true, bar7 = true, bar8 = true,
	petbar = true, stancebar = true, totembar = true,
}

local function IsBagElement(key)
	if key == "bags" then
		return true
	end
	-- Classic Era fallback only: when no separate BagsBar exists, bags live inside MicroButtonAndBagsBar
	if key == "micro" and not IsUsableFrame(_G.BagsBar) then
		return true
	end
	return false
end

local CHAT_FULL_KEYS = {
	chat = true, chattabs = true, chatbuttons = true,
}

-- Elements whose frames sit inside a parent that may also be faded (detach alpha so they don't double-fade)
local DETACH_ALPHA_KEYS = {
	barart = true,
	pet = true, tot = true, focustot = true,
	minimapheader = true, minimapzone = true, minimaptrack = true,
	minimapcal = true, minimapclock = true, minimapdial = true,
	minimapcoords = true, minimapmail = true, minimapcomp = true, minimapaddons = true,
	belowminimap = true,
}

-- Runtime state
local elementFrames = {}      -- [elementKey] = { frame1, frame2, ... }
local frameAlpha = {}         -- [frame] = current applied alpha (0..1)
local frameElementKey = {}    -- [frame] = elementKey (first owner)
local elementHoverUntil = {}  -- [elementKey] = timestamp
local groupHoverUntil = {}    -- [groupName] = timestamp
local paused = false
local pickerPreview = false
local engineRunning = false
local lastScanAt = 0
local lastChatPollAt = 0
local lastEvalAt = 0
local lastDriftCheckAt = 0

-- Cached target alphas for per-frame smooth interpolation
local frameTargetAlpha = {}   -- [frame] = target alpha (0..1)
local activeFrames = {}       -- list of all currently managed frames

-- Minimap arrow/icon sync & indoor stale-canvas refresh:
-- WoW's 3D player arrow and blips ignore SetAlpha, so we drive Minimap:SetIconScale(alpha)
-- smoothly in lockstep with the fade. Indoors, a 1-frame zoom nudge refreshes Blizzard's canvas.
local minimapLastIconScale = nil
local minimapWasFaded = false

local MINIMAP_BLOB_ALPHA_METHODS = {
	"SetQuestBlobInsideAlpha",
	"SetQuestBlobOutsideAlpha",
	"SetQuestBlobRingAlpha",
	"SetTaskBlobInsideAlpha",
	"SetTaskBlobOutsideAlpha",
	"SetTaskBlobRingAlpha",
	"SetArchBlobInsideAlpha",
	"SetArchBlobOutsideAlpha",
	"SetArchBlobRingAlpha",
}

local function SetMinimapIconScale(alpha)
	local mm = _G.Minimap
	if not IsUsableFrame(mm) or not mm.SetIconScale then
		return false
	end
	local scale = alpha <= 0.005 and 0 or alpha
	if minimapLastIconScale ~= nil and math.abs(minimapLastIconScale - scale) < 0.002 then
		return true
	end
	local ok = pcall(mm.SetIconScale, mm, scale)
	if not ok and scale == 0 then
		ok = pcall(mm.SetIconScale, mm, 0.0001)
		scale = 0.0001
	end
	if ok then
		minimapLastIconScale = scale
	end
	return ok
end

local function SetMinimapBlobAlpha(alpha)
	local mm = _G.Minimap
	if not IsUsableFrame(mm) then
		return
	end
	for _, method in ipairs(MINIMAP_BLOB_ALPHA_METHODS) do
		if mm[method] then
			pcall(mm[method], mm, alpha)
		end
	end
end

local function RefreshIndoorMinimapCanvas()
	if not (IsIndoors and SafeBool(IsIndoors())) then
		return
	end
	local mm = _G.Minimap
	if not IsUsableFrame(mm) or not mm.GetZoom or not mm.SetZoom then
		return
	end
	local z = SafeNumber(mm:GetZoom())
	if z == nil then return end
	local nudge = z > 0 and (z - 1) or 1
	pcall(mm.SetZoom, mm, nudge)
	C_Timer.After(0, function()
		if IsUsableFrame(mm) and mm.SetZoom then
			pcall(mm.SetZoom, mm, z)
		end
	end)
end

local function GetTopMouseFocus()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if type(foci) == "table" and foci[1] then
			return foci[1]
		end
	end
	return nil
end

local function IsDescendantOf(child, ancestor)
	local cur = child
	local guard = 0
	while cur and guard < 20 do
		if cur == ancestor then
			return true
		end
		if not IsUsableFrame(cur) or not cur.GetParent then
			break
		end
		cur = cur:GetParent()
		guard = guard + 1
	end
	return false
end

local function AddUniqueFrame(list, frame, elementKey, detach)
	if not IsUsableFrame(frame) then
		return
	end
	if not frame.SetAlpha then
		return
	end
	for _, existing in ipairs(list) do
		if existing == frame then
			return
		end
	end
	list[#list + 1] = frame
	if not frameElementKey[frame] then
		frameElementKey[frame] = elementKey
	end
	if detach and frame.SetIgnoreParentAlpha then
		pcall(frame.SetIgnoreParentAlpha, frame, true)
	end
end

-- Dynamic frame resolvers for WoW Forever
local function ResolveDynamic(key, list)
	local cluster = IsUsableFrame(_G.MinimapCluster) and _G.MinimapCluster or nil
	local detach = DETACH_ALPHA_KEYS[key]

	if key == "prd" then
		if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			local plate = C_NamePlate.GetNamePlateForUnit("player")
			if IsUsableFrame(plate) then
				AddUniqueFrame(list, plate, key, false)
			end
		end
		if _G.PersonalResourceDisplayFrame then
			AddUniqueFrame(list, _G.PersonalResourceDisplayFrame, key, false)
		end
	elseif key == "barart" then
		AddUniqueFrame(list, _G.MainMenuBarArtFrameBackground, key, detach)
		AddUniqueFrame(list, _G.MainMenuBarLeftEndCap, key, detach)
		AddUniqueFrame(list, _G.MainMenuBarRightEndCap, key, detach)
		for _, barName in ipairs({ "MainMenuBar", "MainActionBar" }) do
			local bar = _G[barName]
			if IsUsableFrame(bar) then
				AddUniqueFrame(list, bar.EndCaps, key, detach)
				AddUniqueFrame(list, bar.BorderArt, key, detach)
				if IsUsableFrame(bar.EndCaps) then
					AddUniqueFrame(list, bar.EndCaps.LeftEndCap, key, detach)
					AddUniqueFrame(list, bar.EndCaps.RightEndCap, key, detach)
				end
			end
		end
		if IsUsableFrame(_G.MainMenuBarArtFrame) then
			AddUniqueFrame(list, _G.MainMenuBarArtFrame.LeftEndCap, key, detach)
			AddUniqueFrame(list, _G.MainMenuBarArtFrame.RightEndCap, key, detach)
		end
	elseif key == "minimapheader" then
		if cluster then
			AddUniqueFrame(list, cluster.BorderTop, key, detach)
		end
		AddUniqueFrame(list, _G.MinimapBorderTop, key, detach)
	elseif key == "minimapzone" then
		if cluster then
			AddUniqueFrame(list, cluster.ZoneTextButton, key, detach)
		end
		AddUniqueFrame(list, _G.MinimapZoneTextButton, key, detach)
	elseif key == "minimaptrack" then
		if cluster then
			AddUniqueFrame(list, cluster.Tracking, key, detach)
		end
	elseif key == "minimapdial" then
		if cluster then
			AddUniqueFrame(list, cluster.DielFrame, key, detach)
		end
	elseif key == "minimapcoords" then
		local mm = IsUsableFrame(_G.Minimap) and _G.Minimap or nil
		local function FindCoords(frame, depth)
			if not IsUsableFrame(frame) or not frame.GetRegions then
				return false
			end
			local regions = { frame:GetRegions() }
			for _, reg in ipairs(regions) do
				if IsUsableFrame(reg) and reg.GetObjectType and reg:GetObjectType() == "FontString" and reg.GetText then
					local ok, text = pcall(reg.GetText, reg)
					if ok and type(text) == "string" and not ns.IsSecret(text)
						and text:match("^%s*%d+%.?%d*%s*,%s*%d+%.?%d*%s*$") then
						local target = (frame ~= cluster and frame ~= mm) and frame or reg
						AddUniqueFrame(list, target, key, detach)
						return true
					end
				end
			end
			if depth > 0 and frame.GetChildren then
				for _, child in ipairs({ frame:GetChildren() }) do
					if FindCoords(child, depth - 1) then
						return true
					end
				end
			end
			return false
		end
		if cluster then FindCoords(cluster, 2) end
		if #list == 0 and mm then FindCoords(mm, 2) end
	elseif key == "minimapmail" then
		if cluster then
			if type(cluster.IndicatorFrame) == "table" then
				AddUniqueFrame(list, cluster.IndicatorFrame.MailFrame, key, detach)
			end
			AddUniqueFrame(list, cluster.MailFrame, key, detach)
		end
		AddUniqueFrame(list, _G.MiniMapMailFrame, key, detach)
	elseif key == "minimapaddons" then
		local mm = _G.Minimap
		if IsUsableFrame(mm) and mm.GetChildren then
			for _, child in ipairs({ mm:GetChildren() }) do
				if IsUsableFrame(child) and child.GetName then
					local ok, name = pcall(child.GetName, child)
					if ok and type(name) == "string" and name:find("^LibDBIcon10_") then
						AddUniqueFrame(list, child, key, detach)
					end
				end
			end
		end
	elseif key == "chatmessages" then
		local num = NUM_CHAT_WINDOWS or 10
		for i = 1, num do
			local cf = _G["ChatFrame" .. i]
			if IsUsableFrame(cf) then
				AddUniqueFrame(list, cf, key, false)
			end
		end
	elseif key == "chatbuttons" then
		local names = {
			"ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
			"FriendsMicroButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
		}
		for _, n in ipairs(names) do
			AddUniqueFrame(list, _G[n], key, false)
		end
		local num = NUM_CHAT_WINDOWS or 10
		for i = 1, num do
			AddUniqueFrame(list, _G["ChatFrame" .. i .. "ButtonFrame"], key, false)
		end
	elseif key == "damagemeter" then
		AddUniqueFrame(list, _G.DamageMeter, key, false)
		for i = 1, 5 do
			AddUniqueFrame(list, _G["DamageMeterSessionWindow" .. i], key, false)
		end
	end
end

function ns.DiscoverFrames()
	local db = ns.GetDB and ns.GetDB()
	if not db then
		return
	end

	wipe(activeFrames)
	local seenActive = {}

	local function TrackList(key, list)
		elementFrames[key] = list
		for _, f in ipairs(list) do
			if not seenActive[f] then
				seenActive[f] = true
				activeFrames[#activeFrames + 1] = f
				if frameAlpha[f] == nil then
					local cur = SafeNumber(f:GetAlpha())
					frameAlpha[f] = cur or 1
				end
			end
		end
	end

	-- Built-in catalog
	for _, el in ipairs(ns.ELEMENTS) do
		local list = {}
		local detach = DETACH_ALPHA_KEYS[el.key]
		if el.frames then
			for _, name in ipairs(el.frames) do
				-- Avoid double-fading Minimap when MinimapCluster is already in the same element,
				-- and skip legacy MicroButtonAndBagsBar when modern MicroMenuContainer exists.
				if not (name == "Minimap" and IsUsableFrame(_G.MinimapCluster))
					and not (name == "MicroButtonAndBagsBar" and IsUsableFrame(_G.MicroMenuContainer)) then
					AddUniqueFrame(list, _G[name], el.key, detach)
				end
			end
		end
		if el.resolver then
			ResolveDynamic(el.resolver, list)
		end
		TrackList(el.key, list)
	end

	-- Supported 3rd-party addons (only when loaded)
	if ns.SUPPORTED_ADDONS and db.addons then
		for _, entry in ipairs(ns.SUPPORTED_ADDONS) do
			if ns.IsAddOnLoadedSafe(entry.addon) then
				local key = "addon:" .. entry.key
				local cfg = db.addons[entry.key]
				local list = {}
				if cfg and cfg.enabled ~= false then
					if entry.frames then
						for _, name in ipairs(entry.frames) do
							AddUniqueFrame(list, _G[name], key, false)
						end
					end
					TrackList(key, list)
				else
					-- Disabled addon: restore any previously managed frames to 100%
					if elementFrames[key] then
						for _, f in ipairs(elementFrames[key]) do
							if IsUsableFrame(f) then
								f:SetAlpha(1)
								frameAlpha[f] = 1
								frameTargetAlpha[f] = 1
							end
						end
					end
					elementFrames[key] = nil
				end
			end
		end
	end

	-- Custom /fstack & picked frames
	if db.customFrames then
		for frameName in pairs(db.customFrames) do
			local key = "custom:" .. frameName
			local list = {}
			AddUniqueFrame(list, _G[frameName], key, false)
			TrackList(key, list)
		end
	end
end

local GetBuffIconButtons

local function IsFrameHovered(frame, elementKey, mouseFocus, pad)
	if not IsUsableFrame(frame) then
		return false
	end
	if not SafeBool(frame:IsVisible()) then
		return false
	end

	local reach = pad or 0
	if elementKey == "buffs" or elementKey == "debuffs" then
		-- BuffFrame & DebuffFrame are large fixed-size containers even when mostly empty.
		-- Only count as hovered when the cursor is near an actual visible aura icon (never empty space).
		if mouseFocus and mouseFocus ~= WorldFrame and not IsDescendantOf(mouseFocus, frame) then
			return false
		end
		local auraReach = reach > 0 and reach or 12
		local buttons = (type(frame.auraFrames) == "table" and #frame.auraFrames > 0) and frame.auraFrames
			or (IsUsableFrame(frame.AuraContainer) and frame.AuraContainer.GetChildren and { frame.AuraContainer:GetChildren() })
			or nil
		if buttons then
			for _, btn in ipairs(buttons) do
				if IsUsableFrame(btn) and SafeBool(btn:IsVisible()) and btn.IsMouseEnabled and SafeBool(btn:IsMouseEnabled())
					and type(btn.buttonInfo) == "table" and btn.buttonInfo.texture ~= nil
					and btn.IsMouseOver and SafeBool(btn:IsMouseOver(auraReach, -auraReach, -auraReach, auraReach)) then
					return true
				end
			end
		end
		return false
	end

	local w = frame.GetWidth and SafeNumber(frame:GetWidth()) or 0
	local h = frame.GetHeight and SafeNumber(frame:GetHeight()) or 0

	-- Widget containers (belowminimap, topcenter) can hold huge invisible layout/EditMode children:
	-- only count as hovered when the actual mouse focus is on one of their interactive widgets.
	if elementKey == "belowminimap" or elementKey == "topcenter" then
		return mouseFocus ~= nil and mouseFocus ~= WorldFrame and IsDescendantOf(mouseFocus, frame)
	end

	-- Ignore oversized fullscreen invisible containers
	local uiW = UIParent and SafeNumber(UIParent:GetWidth()) or 1920
	local uiH = UIParent and SafeNumber(UIParent:GetHeight()) or 1080
	local isHuge = (w >= uiW * 0.75) or (h >= uiH * 0.75)

	-- Direct mouseover rect check (only on frames with a real size > 4x4 and not fullscreen)
	if not isHuge and w > 4 and h > 4 and frame.IsMouseOver and SafeBool(frame:IsMouseOver(reach, -reach, -reach, reach)) then
		if elementKey == "chat" then
			return true
		end
		if not mouseFocus or mouseFocus == WorldFrame or IsDescendantOf(mouseFocus, frame) then
			return true
		end
	end

	-- 1x1 container frames (like Bartender4's BT4Bar* anchors) hold their buttons outside their own rect:
	-- check visible child buttons that have a real size (> 4x4) so Mouseover Buffer works smoothly.
	if (w <= 4 or h <= 4) and frame.GetChildren then
		if not mouseFocus or mouseFocus == WorldFrame or IsDescendantOf(mouseFocus, frame) then
			local children = { frame:GetChildren() }
			for _, child in ipairs(children) do
				if IsUsableFrame(child) and SafeBool(child:IsVisible()) and child.IsMouseOver then
					local cw = child.GetWidth and SafeNumber(child:GetWidth()) or 0
					local ch = child.GetHeight and SafeNumber(child:GetHeight()) or 0
					if cw > 4 and ch > 4 and SafeBool(child:IsMouseOver(reach, -reach, -reach, reach)) then
						return true
					end
				end
			end
		end
	end

	-- Mouse focus on a child extending outside parent rect
	if mouseFocus and mouseFocus ~= WorldFrame and IsDescendantOf(mouseFocus, frame) then
		return true
	end

	return false
end

-- Returns effective config table and optional followed built-in element key
local function GetElementConfig(db, key)
	if key:sub(1, 6) == "addon:" then
		local aKey = key:sub(7)
		local aCfg = db.addons and db.addons[aKey]
		if not aCfg or aCfg.enabled == false then
			return nil, nil
		end
		if aCfg.mode == "follow" and aCfg.follow and aCfg.follow ~= "None" and db.elements and db.elements[aCfg.follow] then
			return db.elements[aCfg.follow], aCfg.follow
		end
		return aCfg, nil
	elseif key:sub(1, 7) == "custom:" then
		local name = key:sub(8)
		local cCfg = db.customFrames and db.customFrames[name]
		if not cCfg then
			return nil, nil
		end
		if cCfg.mode == "follow" and cCfg.follow and cCfg.follow ~= "None" and db.elements and db.elements[cCfg.follow] then
			return db.elements[cCfg.follow], cCfg.follow
		end
		return cCfg, nil
	end
	return db.elements and db.elements[key], nil
end

local function ApplyFrameAlpha(frame, alpha, elementKey)
	if not IsUsableFrame(frame) then
		return
	end
	local isMinimap = (elementKey == "minimap" or frame == _G.MinimapCluster or frame == _G.Minimap)
	if isMinimap then
		SetMinimapIconScale(alpha)
		SetMinimapBlobAlpha(alpha)
		if alpha < 0.95 then
			minimapWasFaded = true
		elseif alpha >= 0.99 and minimapWasFaded then
			minimapWasFaded = false
			RefreshIndoorMinimapCanvas()
		end
	end
	frame:SetAlpha(alpha)
	frameAlpha[frame] = alpha
end

-- In-place single-buff peek state (fades non-peeking child aura icons without moving frames)
local buffIconsDimmed = false
local dimmedBuffButtons = {}
local activeBuffPeekIcons = nil
local activeBuffPeekFadedAlpha = 0
local activeBuffPeekIncludeExpiring = false
local nonPeekBuffAlpha = 0

function GetBuffIconButtons()
	local bf = _G.BuffFrame
	if not IsUsableFrame(bf) then
		return nil
	end
	if type(bf.auraFrames) == "table" and #bf.auraFrames > 0 then
		return bf.auraFrames
	end
	if IsUsableFrame(bf.AuraContainer) and bf.AuraContainer.GetChildren then
		return { bf.AuraContainer:GetChildren() }
	end
	return nil
end

local function GetBuffButtonTexture(btn)
	local info = btn.buttonInfo
	if type(info) == "table" then
		if info.texture ~= nil and not ns.IsSecret(info.texture) then
			return info.texture
		end
		if info.icon ~= nil and not ns.IsSecret(info.icon) then
			return info.icon
		end
	end
	local icon = btn.Icon
	if IsUsableFrame(icon) and icon.GetTexture then
		local ok, tex = pcall(icon.GetTexture, icon)
		if ok and tex ~= nil and not ns.IsSecret(tex) then
			return tex
		end
	end
	return nil
end

local function RestoreBuffIcons()
	activeBuffPeekIcons = nil
	nonPeekBuffAlpha = 1
	if not buffIconsDimmed then
		return
	end
	buffIconsDimmed = false
	for btn in pairs(dimmedBuffButtons) do
		if IsUsableFrame(btn) and btn.SetAlpha then
			btn:SetAlpha(1)
		end
	end
	wipe(dimmedBuffButtons)
end

local function ApplySingleBuffPeek(activeIcons, fadedAlpha)
	local buttons = GetBuffIconButtons()
	if not buttons then return false end
	-- When entering single-buff peek from a hidden BuffFrame, start non-peeking icons hidden;
	-- when transitioning from a visible/hovered BuffFrame, smoothly fade them down from 1.0.
	if not buffIconsDimmed then
		local bf = _G.BuffFrame
		local bfAlpha = bf and frameAlpha[bf] or 0
		nonPeekBuffAlpha = (bfAlpha > fadedAlpha + 0.05) and 1.0 or fadedAlpha
	end
	for _, btn in ipairs(buttons) do
		if IsUsableFrame(btn) and btn.SetAlpha and SafeBool(btn:IsVisible()) then
			local tex = GetBuffButtonTexture(btn)
			local iconAlpha = tex ~= nil and activeIcons[tex] or nil
			if iconAlpha and iconAlpha >= 0.999 then
				-- Restore once if we previously dimmed it, then leave untouched so Blizzard's native
				-- expiring-buff breathing/pulse animation plays normally!
				if dimmedBuffButtons[btn] then
					dimmedBuffButtons[btn] = nil
					btn:SetAlpha(1)
				end
			elseif iconAlpha then
				dimmedBuffButtons[btn] = true
				btn:SetAlpha(math.max(nonPeekBuffAlpha, iconAlpha))
			else
				dimmedBuffButtons[btn] = true
				btn:SetAlpha(nonPeekBuffAlpha)
			end
		end
	end
	buffIconsDimmed = true
	activeBuffPeekIcons = activeIcons
	activeBuffPeekFadedAlpha = fadedAlpha
	return true
end

function ns.RestoreAllFrames()
	SetMinimapIconScale(1)
	SetMinimapBlobAlpha(1)
	if minimapWasFaded then
		minimapWasFaded = false
		RefreshIndoorMinimapCanvas()
	end
	RestoreBuffIcons()
	if ns.SyncChatPeekOverlay then
		ns.SyncChatPeekOverlay(true, 1, GetTime())
	end
	for _, f in ipairs(activeFrames) do
		if IsUsableFrame(f) then
			f:SetAlpha(1)
			frameAlpha[f] = 1
			frameTargetAlpha[f] = 1
		end
	end
end

function ns.SetPaused(state)
	paused = state and true or false
	if paused then
		ns.RestoreAllFrames()
	end
end

function ns.IsPaused()
	return paused
end

function ns.SetPickerPreview(active)
	pickerPreview = active and true or false
	if pickerPreview then
		ns.RestoreAllFrames()
	else
		ns.ForceRefresh()
	end
end

-- Check whether `frame` (or any of its ancestors) is already managed by PureFade
function ns.FindExistingOwner(frame)
	local db = ns.GetDB and ns.GetDB()
	local cur = frame
	local guard = 0
	while cur and cur ~= UIParent and cur ~= WorldFrame and guard < 20 do
		local ownerKey = frameElementKey[cur]
		if ownerKey then
			if ownerKey:sub(1, 6) == "addon:" then
				local aKey = ownerKey:sub(7)
				local entry = ns.SUPPORTED_ADDON_BY_KEY and ns.SUPPORTED_ADDON_BY_KEY[aKey]
				return { kind = "addon", key = aKey, label = entry and entry.label or aKey }
			elseif ownerKey:sub(1, 7) == "custom:" then
				local name = ownerKey:sub(8)
				return { kind = "custom", key = name, label = name }
			else
				local el = ns.ELEMENT_BY_KEY and ns.ELEMENT_BY_KEY[ownerKey]
				if el then
					return { kind = "element", key = el.key, category = el.category, label = el.label }
				end
			end
		end
		-- Also check by frame name against disabled supported addons or custom frames
		if IsUsableFrame(cur) and cur.GetName then
			local ok, name = pcall(cur.GetName, cur)
			if ok and type(name) == "string" and name ~= "" then
				if db and db.customFrames and db.customFrames[name] then
					return { kind = "custom", key = name, label = name }
				end
				if ns.SUPPORTED_ADDONS then
					for _, entry in ipairs(ns.SUPPORTED_ADDONS) do
						if ns.IsAddOnLoadedSafe(entry.addon) and entry.frames then
							for _, fn in ipairs(entry.frames) do
								if fn == name then
									return { kind = "addon", key = entry.key, label = entry.label }
								end
							end
						end
					end
				end
			end
		end
		if not IsUsableFrame(cur) or not cur.GetParent then
			break
		end
		cur = cur:GetParent()
		guard = guard + 1
	end
	return nil
end

-- Build list of all element keys (built-in + loaded addons + custom)
local function CollectAllElementKeys(db)
	local keys = {}
	for _, el in ipairs(ns.ELEMENTS) do
		keys[#keys + 1] = el.key
	end
	if ns.SUPPORTED_ADDONS and db.addons then
		for _, entry in ipairs(ns.SUPPORTED_ADDONS) do
			if ns.IsAddOnLoadedSafe(entry.addon) then
				local cfg = db.addons[entry.key]
				if cfg and cfg.enabled ~= false then
					keys[#keys + 1] = "addon:" .. entry.key
				end
			end
		end
	end
	if db.customFrames then
		for frameName in pairs(db.customFrames) do
			keys[#keys + 1] = "custom:" .. frameName
		end
	end
	return keys
end

-- Evaluate target alphas for every managed frame
local function EvaluateTargets(now)
	local db = ns.GetDB and ns.GetDB()
	if not db then
		return
	end

	-- Refresh live Personal Resource Display nameplate (can spawn/despawn anytime)
	if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
		local plate = C_NamePlate.GetNamePlateForUnit("player")
		local prdList = elementFrames["prd"]
		if IsUsableFrame(plate) then
			if not prdList then
				prdList = {}
				elementFrames["prd"] = prdList
			end
			local hasPlate = false
			for _, f in ipairs(prdList) do
				if f == plate then
					hasPlate = true
					break
				end
			end
			if not hasPlate then
				prdList[#prdList + 1] = plate
				activeFrames[#activeFrames + 1] = plate
				frameElementKey[plate] = "prd"
				frameAlpha[plate] = SafeNumber(plate:GetAlpha()) or 1
			end
		end
	end

	-- Master disabled, paused, Frame Picker preview, or Login Delay active -> show everything
	if paused or pickerPreview or not db.enabled or ns.IsLoginHoldActive(now) then
		for _, f in ipairs(activeFrames) do
			frameTargetAlpha[f] = 1
		end
		return
	end

	local conds = ns.EvaluateConditions(now)
	local mouseFocus = GetTopMouseFocus()
	local hoverHold = db.mouseoverHold or 2.5
	local hoverPad = db.mouseoverBuffer or 0
	local fadedAlpha = db.fadedAlpha or 0

	-- QoL states
	local spellbookUp = db.qolSpellbook and ns.IsSpellbookOpen()
	local draggingUp  = db.qolDrag and ns.IsDragging()
	local bagsUp      = db.qolBagsOpen and ns.IsBagsOpen()
	local chatTyping  = db.qolChatTyping and ns.IsChatTyping()

	local allKeys = CollectAllElementKeys(db)
	local elemHovered = {}
	local elemTriggered = {}
	local groupTriggered = {}
	local anyChatHovered = false

	-- Pass 1: per-element hover & trigger evaluation
	for _, key in ipairs(allKeys) do
		local cfg, followedKey = GetElementConfig(db, key)
		local effectiveKey = followedKey or key
		local frames = elementFrames[key]
		if cfg and frames and #frames > 0 then
			-- Hover check
			local hoveredNow = false
			if cfg.hover ~= false then
				for _, f in ipairs(frames) do
					if IsFrameHovered(f, effectiveKey, mouseFocus, hoverPad) then
						hoveredNow = true
						break
					end
				end
			end

			if hoveredNow then
				elementHoverUntil[key] = now + hoverHold
				if followedKey then
					elementHoverUntil[followedKey] = now + hoverHold
				end
				if cfg.group and cfg.group ~= "None" then
					groupHoverUntil[cfg.group] = now + hoverHold
				end
				if CHAT_FULL_KEYS[effectiveKey] then
					anyChatHovered = true
				end
			end

			local isHovered = hoveredNow
				or (elementHoverUntil[key] ~= nil and now < elementHoverUntil[key])
				or (followedKey ~= nil and elementHoverUntil[followedKey] ~= nil and now < elementHoverUntil[followedKey])
			elemHovered[key] = isHovered

			-- Trigger check (Always Show applies only to this element, never forces the rest of its group)
			-- Note: on "chat", chatMessage is evaluated per-ChatFrameN in Pass 2 so only the active tab peeks.
			local triggered = false
			if cfg.triggers then
				for trigKey, enabled in pairs(cfg.triggers) do
					if enabled and conds[trigKey] and not (effectiveKey == "chat" and trigKey == "chatMessage") then
						triggered = true
						break
					end
				end
			end

			-- QoL triggers
			if not triggered then
				if spellbookUp and ACTION_BAR_KEYS[effectiveKey] then
					triggered = true
				elseif draggingUp and (ACTION_BAR_KEYS[effectiveKey] or IsBagElement(effectiveKey)) then
					triggered = true
				elseif bagsUp and IsBagElement(effectiveKey) then
					triggered = true
				elseif chatTyping and CHAT_FULL_KEYS[effectiveKey] then
					triggered = true
				end
			end

			elemTriggered[key] = triggered or (cfg.alwaysShow and true or false)
			if triggered and cfg.group and cfg.group ~= "None" then
				groupTriggered[cfg.group] = true
			end
		end
	end

	-- Hovering any chat part reveals all chat parts (window + tabs + buttons) together
	if anyChatHovered then
		for chatKey in pairs(CHAT_FULL_KEYS) do
			elementHoverUntil[chatKey] = now + hoverHold
			elemHovered[chatKey] = true
		end
	end

	-- Pass 2: group propagation & target alpha assignment
	local anyChatWindowShowing = false
	local maxChatAlpha = 0
	local buffOnlyPeeking = false
	local buffShownNormally = false
	for _, key in ipairs(allKeys) do
		local cfg, followedKey = GetElementConfig(db, key)
		local frames = elementFrames[key]
		if cfg and frames and #frames > 0 then
			local groupName = cfg.group
			local groupCfg = (groupName and groupName ~= "None" and db.groups) and db.groups[groupName] or nil

			local show = elemTriggered[key] or elemHovered[key]
				or (followedKey ~= nil and (elemHovered[followedKey] or false))

			if not show and groupCfg then
				-- Sync hover across group
				if cfg.hover ~= false and groupHoverUntil[groupName] and now < groupHoverUntil[groupName] then
					show = true
				end
				-- Sync triggers across group (when syncMode == "all")
				if not show and groupCfg.syncMode ~= "hover" and groupTriggered[groupName] then
					show = true
				end
			end

			-- Check if BuffFrame is showing ONLY because of buffChanged and/or buffExpiring (for in-place single-buff mode)
			local isBuffPeekActive = cfg.triggers and (
				(cfg.triggers.buffChanged and conds.buffChanged)
				or (cfg.triggers.buffExpiring and conds.buffExpiring)
			)
			if key == "buffs" and show and db.buffPeekOnlyNew ~= false and isBuffPeekActive then
				local nonPeekShow = cfg.alwaysShow or elemHovered[key]
					or (groupCfg and cfg.hover ~= false and groupHoverUntil[groupName] and now < groupHoverUntil[groupName])
				if not nonPeekShow and cfg.triggers then
					for trigKey, enabled in pairs(cfg.triggers) do
						if enabled and trigKey ~= "buffChanged" and trigKey ~= "buffExpiring" and conds[trigKey] then
							nonPeekShow = true
							break
						end
					end
				end
				if not nonPeekShow then
					local includeExpiring = (cfg.triggers.buffExpiring and conds.buffExpiring) and true or false
					local activeIcons = ns.GetActivePeekBuffIcons and ns.GetActivePeekBuffIcons(now, db.fadeOutTime, includeExpiring)
					if activeIcons and ApplySingleBuffPeek(activeIcons, fadedAlpha) then
						buffOnlyPeeking = true
						activeBuffPeekIncludeExpiring = includeExpiring
					end
				end
			end
			if key == "buffs" and show and not buffOnlyPeeking then
				buffShownNormally = true
			end

			for _, f in ipairs(frames) do
				local frameShow = show
				-- Active-tab chat peek: reveals ONLY the specific ChatFrameN that got a new message
				if not frameShow and (key == "chat" or followedKey == "chat") and cfg.triggers and cfg.triggers.chatMessage then
					if ns.IsChatFramePeeking(f, now) then
						frameShow = true
					end
				end
				if key == "chat" or followedKey == "chat" then
					if frameShow then
						anyChatWindowShowing = true
					end
					local curA = frameAlpha[f] or 0
					if curA > maxChatAlpha then
						maxChatAlpha = curA
					end
				end
				frameTargetAlpha[f] = frameShow and 1.0 or fadedAlpha
			end
		end
	end

	if buffShownNormally then
		RestoreBuffIcons()
	elseif not buffOnlyPeeking and buffIconsDimmed then
		-- Keep non-peeking buffs hidden while BuffFrame finishes fading out; restore once fully faded
		local bf = _G.BuffFrame
		local bfAlpha = bf and frameAlpha[bf] or 0
		if bfAlpha <= fadedAlpha + 0.01 then
			RestoreBuffIcons()
		end
	end
	if ns.SyncChatPeekOverlay then
		ns.SyncChatPeekOverlay(anyChatWindowShowing, maxChatAlpha, now)
	end
end

-- Main OnUpdate driver
local driver = CreateFrame("Frame")

local function OnUpdate(_, elapsed)
	if not engineRunning then
		return
	end
	local now = GetTime()
	local db = ns.GetDB and ns.GetDB()
	if not db then
		return
	end

	-- Periodic frame rescan (every 5s for late-loaded Blizzard/addon frames)
	if now - lastScanAt >= 5.0 then
		lastScanAt = now
		ns.DiscoverFrames()
	end

	-- Poll active-tab chat message counts at 4 Hz (0.25s)
	if now - lastChatPollAt >= 0.25 then
		lastChatPollAt = now
		ns.PollChatPeek(now)
	end

	-- Evaluate conditions & hover at ~20 Hz (0.05s)
	if now - lastEvalAt >= 0.05 then
		lastEvalAt = now
		EvaluateTargets(now)
	end

	-- Re-apply single-buff peek per frame (smoothly fading out non-peeking icons and each peeking icon)
	if activeBuffPeekIcons then
		local fadeOut = db.fadeOutTime or 0
		if nonPeekBuffAlpha > activeBuffPeekFadedAlpha + 0.001 then
			if fadeOut <= 0.001 then
				nonPeekBuffAlpha = activeBuffPeekFadedAlpha
			else
				nonPeekBuffAlpha = math.max(activeBuffPeekFadedAlpha, nonPeekBuffAlpha - (elapsed / fadeOut))
			end
		end
		local freshIcons = ns.GetActivePeekBuffIcons and ns.GetActivePeekBuffIcons(now, fadeOut, activeBuffPeekIncludeExpiring)
		ApplySingleBuffPeek(freshIcons or activeBuffPeekIcons, activeBuffPeekFadedAlpha)
	end

	-- Interpolate alphas smoothly (or snap instantly when duration == 0)
	local inCombat = (InCombatLockdown and InCombatLockdown()) or SafeBool(UnitAffectingCombat("player"))
	local fadeInTime = (inCombat and db.combatFadeInTime ~= nil) and db.combatFadeInTime or (db.fadeInTime or 0)
	local fadeOutTime = db.fadeOutTime or 0

	-- Only check for external alpha drift at 4 Hz (0.25s) so idle per-frame OnUpdate does zero WoW API calls
	local checkDrift = (now - lastDriftCheckAt) >= 0.25
	if checkDrift then
		lastDriftCheckAt = now
	end

	for _, f in ipairs(activeFrames) do
		local target = frameTargetAlpha[f]
		if target ~= nil then
			local cur = frameAlpha[f]
			if cur == nil then
				cur = SafeNumber(f:GetAlpha()) or 1
				frameAlpha[f] = cur
			end

			if math.abs(cur - target) > 0.001 then
				local nextAlpha
				if target > cur then
					if fadeInTime <= 0.001 then
						nextAlpha = target
					else
						nextAlpha = math.min(target, cur + (elapsed / fadeInTime))
					end
				else
					if fadeOutTime <= 0.001 then
						nextAlpha = target
					else
						nextAlpha = math.max(target, cur - (elapsed / fadeOutTime))
					end
				end
				ApplyFrameAlpha(f, nextAlpha, frameElementKey[f])
			elseif checkDrift then
				-- Guard against Blizzard or another addon resetting a frame's alpha behind our back
				local realAlpha = SafeNumber(f:GetAlpha())
				if realAlpha ~= nil and math.abs(realAlpha - target) > 0.02 then
					ApplyFrameAlpha(f, target, frameElementKey[f])
				end
			end
		end
	end

	-- Keep chat peek overlay frame-exact with ChatFrame's live interpolated alpha every frame
	if ns.SyncChatPeekOverlay then
		local chatFrames = elementFrames["chat"]
		local maxChatA = 0
		if chatFrames then
			for _, cf in ipairs(chatFrames) do
				local a = frameAlpha[cf] or 0
				if a > maxChatA then maxChatA = a end
			end
		end
		ns.SyncChatPeekOverlay(maxChatA >= 0.99, maxChatA, now)
	end
end

function ns.StartEngine()
	ns.DiscoverFrames()
	local now = GetTime()
	lastScanAt = now
	lastChatPollAt = now
	lastEvalAt = 0
	ns.PollChatPeek(now)
	EvaluateTargets(now)

	-- If loginBehavior == "faded", snap immediately to target alpha on login
	local db = ns.GetDB and ns.GetDB()
	if db and db.enabled and db.loginBehavior == "faded" then
		for _, f in ipairs(activeFrames) do
			local target = frameTargetAlpha[f]
			if target ~= nil then
				ApplyFrameAlpha(f, target, frameElementKey[f])
			end
		end
	end

	engineRunning = true
	driver:SetScript("OnUpdate", OnUpdate)

	-- Quick follow-up scan for addons that create frames shortly after login (e.g. Questie_BaseFrame)
	C_Timer.After(1.5, function()
		ns.DiscoverFrames()
		EvaluateTargets(GetTime())
	end)
end

function ns.ForceRefresh()
	ns.DiscoverFrames()
	EvaluateTargets(GetTime())
end

-- Diagnostic helper: /purefade why [filter]
function ns.DebugWhy(filter)
	local db = ns.GetDB and ns.GetDB()
	if not db then return end
	local now = GetTime()
	local conds = ns.EvaluateConditions(now)
	local fLower = (filter or ""):lower()
	local shown = 0

	print("|cff66ccffPureFade Why" .. (fLower ~= "" and (" (" .. fLower .. ")") or "") .. ":|r")
	if ns.IsLoginHoldActive(now) then
		print("  Login Hold active")
	end
	if paused or not db.enabled then
		print("  Paused or Disabled")
	end

	for _, key in ipairs(CollectAllElementKeys(db)) do
		if fLower == "" or key:lower():find(fLower, 1, true) then
			local cfg, followedKey = GetElementConfig(db, key)
			local frames = elementFrames[key]
			if cfg and frames and #frames > 0 then
				local reasons = {}
				if cfg.alwaysShow then reasons[#reasons + 1] = "AlwaysShow" end
				if elementHoverUntil[key] and now < elementHoverUntil[key] then
					reasons[#reasons + 1] = ("Hover(%.1fs)"):format(elementHoverUntil[key] - now)
				end
				if cfg.group and cfg.group ~= "None" and groupHoverUntil[cfg.group] and now < groupHoverUntil[cfg.group] then
					reasons[#reasons + 1] = ("GroupHover:%s(%.1fs)"):format(cfg.group, groupHoverUntil[cfg.group] - now)
				end
				if cfg.triggers then
					for tk, en in pairs(cfg.triggers) do
						if en and conds[tk] then
							reasons[#reasons + 1] = "Trigger:" .. tk
						end
					end
				end
				local f1 = frames[1]
				local tA = frameTargetAlpha[f1]
				local rA = IsUsableFrame(f1) and SafeNumber(f1:GetAlpha()) or -1
				if #reasons > 0 or (tA and tA > 0.05) or (rA and rA > 0.05) then
					print(("  |cffffff00%s|r [frames=%d, target=%.2f, alpha=%.2f]: %s"):format(
						key, #frames, tA or -1, rA or -1,
						#reasons > 0 and table.concat(reasons, ", ") or "none (should fade)"
					))
					shown = shown + 1
				end
			end
		end
	end
	if shown == 0 then
		print("  Nothing matching is currently visible or held.")
	end
end
