-- PureFade: Event-driven condition & trigger evaluator (WoW Forever secret-value safe).
local _, ns = ...

local SafeNumber = ns.SafeNumber
local SafeBool = ns.SafeBool
local IsSecret = ns.IsSecret

-- Resources that rest at 0 rather than 100%
local EMPTY_AT_REST = {
	RAGE = true,
	RUNIC_POWER = true,
	FURY = true,
	INSANITY = true,
	MAELSTROM = true,
	LUNAR_POWER = true,
	COMBO_POINTS = true,
}

-- Gathering & creature tracking spell IDs and Classic icon fallbacks
local TRACKING_SPELLS = {
	[2580]  = true, -- Find Minerals
	[2383]  = true, -- Find Herbs
	[2481]  = true, -- Find Treasure
	[43308] = true, -- Find Fish
	[19883] = true, -- Track Humanoids (Hunter)
	[5225]  = true, -- Track Humanoids (Druid)
	[1494]  = true, -- Track Beasts
	[19878] = true, -- Track Demons (Hunter)
	[5500]  = true, -- Sense Demons (Warlock)
	[19884] = true, -- Track Undead (Hunter)
	[5502]  = true, -- Sense Undead (Paladin)
	[19879] = true, -- Track Dragonkin
	[19880] = true, -- Track Elementals
	[19882] = true, -- Track Giants
	[19885] = true, -- Track Hidden
}

local TRACKING_ICONS = {
	[136025] = true,
	[136065] = true,
	[135725] = true,
	["interface\\icons\\spell_nature_earthquake"] = true,
	["interface\\icons\\inv_misc_flower_02"] = true,
	["interface\\icons\\racial_dwarf_findtreasure"] = true,
}

local state = {
	inCombat = false,
	combatHoldUntil = 0,
	loginHoldUntil = 0,
	minimapPingUntil = 0,
	buffPeekUntil = 0,
	buffPeekWholeUntil = 0,
	questPeekUntil = 0,
	questReadyAt = 0,
	auraReadyAt = 0,
	auraDirty = true,
	hasDebuff = false,
	casting = false,
	lastHealthChange = -100,
	lastPowerChange = -100,
	lastPetHealthChange = -100,
	trackingDirty = true,
	trackingActive = false,
}

-- Active-tab chat message peek tracking (no AddMessage hook, which breaks on Forever)
local chatLastCount = {}
local chatLastTail = {}
local chatPeekUntil = {}
local chatOverlayFrame = nil
local chatOverlayUntil = 0
local chatInitialized = false

-- In-place single-buff peek icon tracking ([iconFileID] = expireTime)
local peekBuffIcons = {}
-- Short / expiring buff icons ([iconFileID] = true) refreshed every 0.5s or on UNIT_AURA
local expiringBuffIcons = {}
local hasExpiringBuff = false
local lastExpiringScanAt = 0

local function GetChatOverlayFrame()
	if chatOverlayFrame then
		return chatOverlayFrame
	end
	local f = CreateFrame("ScrollingMessageFrame", "PureFadeChatPeekFrame", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetFontObject(ChatFontNormal)
	f:EnableMouse(false)
	f:SetFading(true)
	f:SetMaxLines(30)
	f:SetIndentedWordWrap(true)
	f:SetJustifyH("LEFT")
	f:Hide()
	chatOverlayFrame = f
	return f
end

local function SyncChatOverlayTo(cf, dur, fadeOut)
	local f = GetChatOverlayFrame()
	f:ClearAllPoints()
	f:SetAllPoints(cf)
	if cf.GetFont then
		local fontFile, fontSize, fontFlags = cf:GetFont()
		if fontFile and fontSize then
			pcall(f.SetFont, f, fontFile, fontSize, fontFlags)
		end
	end
	if cf.GetJustifyH then
		pcall(f.SetJustifyH, f, cf:GetJustifyH())
	end
	if cf.GetInsertMode then
		pcall(f.SetInsertMode, f, cf:GetInsertMode())
	end
	f:SetTimeVisible(dur)
	f:SetFadeDuration(math.max(0.15, fadeOut or 0.8))
	f:Show()
	return f
end

-- Lightweight quest log snapshot to detect real objective progress, completion, or failure
local questSnapshot = {}
local questSnapReady = false

local function BuildQuestSnapshot()
	local snap = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local num = SafeNumber(C_QuestLog.GetNumQuestLogEntries()) or 0
		for i = 1, num do
			local info = C_QuestLog.GetInfo(i)
			if type(info) == "table" and not info.isHeader and SafeNumber(info.questID) and info.questID > 0 then
				local qid = info.questID
				local parts = {}
				if C_QuestLog.GetQuestObjectives then
					local objs = C_QuestLog.GetQuestObjectives(qid)
					if type(objs) == "table" then
						for j, o in ipairs(objs) do
							local txt = (type(o) == "table" and type(o.text) == "string" and not IsSecret(o.text)) and o.text or ""
							local fin = (type(o) == "table" and SafeBool(o.finished)) and "1" or "0"
							parts[j] = txt .. ":" .. fin
						end
					end
				end
				local complete = C_QuestLog.IsComplete and SafeBool(C_QuestLog.IsComplete(qid)) and "C" or ""
				local failed = C_QuestLog.IsFailed and SafeBool(C_QuestLog.IsFailed(qid)) and "F" or ""
				snap[qid] = table.concat(parts, "|") .. "#" .. complete .. failed
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		local num = SafeNumber(GetNumQuestLogEntries()) or 0
		for i = 1, num do
			local title, _, _, isHeader, _, isComplete, _, questID = GetQuestLogTitle(i)
			if not isHeader and SafeNumber(questID) and questID > 0 then
				local parts = {}
				if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
					local nObj = SafeNumber(GetNumQuestLeaderBoards(i)) or 0
					for j = 1, nObj do
						local text, _, finished = GetQuestLogLeaderBoard(j, i)
						parts[j] = tostring(text or "") .. ":" .. (finished and "1" or "0")
					end
				end
				snap[questID] = table.concat(parts, "|") .. "#" .. tostring(isComplete or 0)
			end
		end
	end
	return snap
end

local function CheckQuestSnapshotChanged()
	local cur = BuildQuestSnapshot()
	if not questSnapReady then
		questSnapshot = cur
		questSnapReady = true
		return false
	end
	local changed = false
	for qid, sig in pairs(cur) do
		if questSnapshot[qid] ~= sig then
			changed = true
			break
		end
	end
	if not changed then
		for qid in pairs(questSnapshot) do
			if cur[qid] == nil then
				changed = true
				break
			end
		end
	end
	questSnapshot = cur
	return changed
end

local function RegisterSafeEvent(frame, event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		if C_EventUtils.IsEventValid(event) then
			frame:RegisterEvent(event)
		end
	else
		pcall(frame.RegisterEvent, frame, event)
	end
end

local function RegisterSafeUnitEvent(frame, event, ...)
	if C_EventUtils and C_EventUtils.IsEventValid then
		if C_EventUtils.IsEventValid(event) then
			frame:RegisterUnitEvent(event, ...)
		end
	else
		pcall(frame.RegisterUnitEvent, frame, event, ...)
	end
end

local eventFrame = CreateFrame("Frame")
RegisterSafeEvent(eventFrame, "PLAYER_REGEN_DISABLED")
RegisterSafeEvent(eventFrame, "PLAYER_REGEN_ENABLED")
RegisterSafeEvent(eventFrame, "MINIMAP_PING")
RegisterSafeEvent(eventFrame, "MINIMAP_UPDATE_TRACKING")
RegisterSafeEvent(eventFrame, "PLAYER_ENTERING_WORLD")
RegisterSafeEvent(eventFrame, "QUEST_ACCEPTED")
RegisterSafeEvent(eventFrame, "QUEST_REMOVED")
RegisterSafeEvent(eventFrame, "QUEST_TURNED_IN")
RegisterSafeEvent(eventFrame, "QUEST_WATCH_LIST_CHANGED")
RegisterSafeEvent(eventFrame, "QUEST_WATCH_UPDATE")
RegisterSafeEvent(eventFrame, "QUEST_LOG_UPDATE")
RegisterSafeUnitEvent(eventFrame, "UNIT_HEALTH", "player", "pet")
RegisterSafeUnitEvent(eventFrame, "UNIT_MAXHEALTH", "player", "pet")
RegisterSafeUnitEvent(eventFrame, "UNIT_POWER_UPDATE", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_DISPLAYPOWER", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_AURA", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_START", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_STOP", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_FAILED", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_INTERRUPTED", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_START", "player")
RegisterSafeUnitEvent(eventFrame, "UNIT_SPELLCAST_CHANNEL_STOP", "player")

eventFrame:SetScript("OnEvent", function(_, event, unit, arg2)
	local db = ns.GetDB and ns.GetDB()
	local now = GetTime()

	if event == "PLAYER_REGEN_DISABLED" then
		state.inCombat = true
	elseif event == "PLAYER_REGEN_ENABLED" then
		state.inCombat = false
		local delay = db and db.combatFadeOutDelay or 10
		if delay > 0 then
			state.combatHoldUntil = now + delay
		end
	elseif event == "MINIMAP_PING" then
		local dur = db and db.minimapPingDuration or 5
		if dur > 0 then
			state.minimapPingUntil = now + dur
		end
	elseif event == "MINIMAP_UPDATE_TRACKING" or event == "PLAYER_ENTERING_WORLD" then
		state.trackingDirty = true
		if event == "PLAYER_ENTERING_WORLD" then
			state.auraDirty = true
			state.auraReadyAt = now + 2.0
			state.questReadyAt = now + 3.0
			questSnapReady = false
			CheckQuestSnapshotChanged()
		end
	elseif event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED"
		or event == "QUEST_TURNED_IN" or event == "QUEST_WATCH_LIST_CHANGED" then
		CheckQuestSnapshotChanged()
		if now >= state.questReadyAt then
			local dur = db and db.questPeekDuration or 6
			if dur > 0 then
				state.questPeekUntil = now + dur
			end
		end
	elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" then
		local changed = CheckQuestSnapshotChanged()
		if changed and now >= state.questReadyAt then
			local dur = db and db.questPeekDuration or 6
			if dur > 0 then
				state.questPeekUntil = now + dur
			end
		end
	elseif event == "UNIT_AURA" and unit == "player" then
		state.trackingDirty = true
		state.auraDirty = true
		if now >= state.auraReadyAt then
			local dur = db and db.buffPeekDuration or 5
			if dur > 0 then
				local changed = false
				local gotIcon = false
				local onlyRemoved = false

				if type(arg2) == "table" and not IsSecret(arg2) then
					local hasAdded = arg2.addedAuras ~= nil and #arg2.addedAuras > 0
					local hasUpdated = arg2.updatedAuraInstanceIDs ~= nil and #arg2.updatedAuraInstanceIDs > 0
					local hasRemoved = arg2.removedAuraInstanceIDs ~= nil and #arg2.removedAuraInstanceIDs > 0
					changed = (arg2.isFullUpdate == true) or hasAdded or hasUpdated or hasRemoved

					if hasAdded then
						local anyHelpfulOrUnknown = false
						for _, aura in ipairs(arg2.addedAuras) do
							if type(aura) == "table" and not IsSecret(aura) then
								local isHarmful = SafeBool(aura.isHarmful)
								if not isHarmful then
									anyHelpfulOrUnknown = true
									local icon = aura.icon
									if icon ~= nil and not IsSecret(icon) then
										peekBuffIcons[icon] = now + dur
										gotIcon = true
									end
								end
							else
								anyHelpfulOrUnknown = true
							end
						end
						if not anyHelpfulOrUnknown and not hasUpdated and not hasRemoved and arg2.isFullUpdate ~= true then
							changed = false
						end
					end
					if hasUpdated and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
						for _, id in ipairs(arg2.updatedAuraInstanceIDs) do
							if SafeNumber(id) then
								local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
								if ok and type(aura) == "table" and not IsSecret(aura) then
									local isHarmful = SafeBool(aura.isHarmful)
									local icon = aura.icon
									if not isHarmful and icon ~= nil and not IsSecret(icon) then
										peekBuffIcons[icon] = now + dur
										gotIcon = true
									end
								end
							end
						end
					end
					if hasRemoved and not hasAdded and not hasUpdated then
						onlyRemoved = true
					end
				else
					changed = true
				end

				if changed then
					local onlyNew = db and db.buffPeekOnlyNew ~= false
					if not (onlyNew and onlyRemoved) then
						state.buffPeekUntil = now + dur
						if not gotIcon and not onlyRemoved then
							-- Secret or full-update fallback: peek whole BuffFrame
							state.buffPeekWholeUntil = now + dur
						end
					end
				end
			end
		end
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		if unit == "player" then
			state.lastHealthChange = now
		elseif unit == "pet" then
			state.lastPetHealthChange = now
		end
	elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_DISPLAYPOWER" then
		state.lastPowerChange = now
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		state.casting = true
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		state.casting = false
	end
end)

function ns.StartLoginHold()
	local db = ns.GetDB and ns.GetDB()
	if db and db.loginBehavior == "delay" and (db.loginDelay or 0) > 0 then
		state.loginHoldUntil = GetTime() + db.loginDelay
	else
		state.loginHoldUntil = 0
	end
end

function ns.IsLoginHoldActive(now)
	return (now or GetTime()) < state.loginHoldUntil
end

-- Check tracking state (cached until UNIT_AURA / MINIMAP_UPDATE_TRACKING)
local function RefreshTracking()
	state.trackingDirty = false
	local found = false

	-- 1. Modern / Forever C_Minimap tracking list
	if C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo then
		local num = C_Minimap.GetNumTrackingTypes() or 0
		for i = 1, num do
			local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
			if ok and type(info) == "table" and SafeBool(info.active) then
				local spellID = SafeNumber(info.spellID)
				if spellID and TRACKING_SPELLS[spellID] then
					found = true
					break
				end
			end
		end
	end

	-- 2. Player buffs (Classic / Forever tracking spells)
	if not found then
		for i = 1, 40 do
			local spellID
			if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
				local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
				if not ok or IsSecret(aura) or not aura then
					break
				end
				spellID = SafeNumber(aura.spellId)
			elseif UnitBuff then
				local name, _, _, _, _, _, _, _, _, id = UnitBuff("player", i)
				if IsSecret(name) or not name then
					break
				end
				spellID = SafeNumber(id)
			else
				break
			end
			if spellID and TRACKING_SPELLS[spellID] then
				found = true
				break
			end
		end
	end

	-- 3. Classic GetTrackingTexture fallback
	if not found and GetTrackingTexture then
		local icon = GetTrackingTexture()
		if type(icon) == "string" then
			found = TRACKING_ICONS[icon:lower()] or false
		elseif type(icon) == "number" then
			found = TRACKING_ICONS[icon] or false
		end
	end

	state.trackingActive = found
end

local GHOST_DEBUFF_SPELL_ID = 8326

-- Check if the player currently has any debuff applied (secret-value & combat safe; ignores Ghost debuff)
local function RefreshDebuffs()
	state.auraDirty = false
	local found = false
	local isDead = SafeBool(UnitIsDeadOrGhost("player"))
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
			if not ok or aura == nil then
				break
			end
			if IsSecret(aura) then
				found = true
				break
			elseif type(aura) == "table" then
				local spellId = SafeNumber(aura.spellId)
				local name = (type(aura.name) == "string" and not IsSecret(aura.name)) and aura.name or nil
				if spellId ~= GHOST_DEBUFF_SPELL_ID and name ~= "Ghost" then
					found = true
					break
				end
			end
		end
	elseif UnitDebuff then
		for i = 1, 40 do
			local ok, name, _, _, _, _, _, _, _, _, spellId = pcall(UnitDebuff, "player", i)
			if not ok or name == nil then
				break
			end
			if IsSecret(name) then
				found = true
				break
			end
			local safeId = SafeNumber(spellId)
			if safeId ~= GHOST_DEBUFF_SPELL_ID and name ~= "Ghost" then
				found = true
				break
			end
		end
	end

	-- Combat/secret fallback: inspect Blizzard's DebuffFrame for any active visible debuff button
	-- (skipped while dead/ghost so the Ghost debuff icon does not falsely trip Has Any Debuff)
	if not found and not isDead then
		local df = _G.DebuffFrame
		if ns.IsUsableFrame(df) and SafeBool(df:IsShown()) then
			local buttons = (type(df.auraFrames) == "table" and #df.auraFrames > 0) and df.auraFrames
				or (ns.IsUsableFrame(df.AuraContainer) and df.AuraContainer.GetChildren and { df.AuraContainer:GetChildren() })
				or nil
			if buttons then
				for _, btn in ipairs(buttons) do
					if ns.IsUsableFrame(btn) and SafeBool(btn:IsVisible())
						and btn.IsMouseEnabled and SafeBool(btn:IsMouseEnabled()) then
						if type(btn.buttonInfo) ~= "table" or btn.buttonInfo.texture ~= nil then
							found = true
							break
						end
					end
				end
			end
		end
	end

	state.hasDebuff = found
end

local function ReadChatLine(cf, idx)
	if not cf.GetMessageInfo then
		return nil, false
	end
	local ok, text, r, g, b, _, _, lineID = pcall(cf.GetMessageInfo, cf, idx)
	if not ok or text == nil then
		return nil, false
	end
	if IsSecret(text) then
		return nil, true
	end
	if type(text) ~= "string" or text == "" then
		return nil, false
	end
	local safeLineID = SafeNumber(lineID) or 0
	return {
		text = text,
		r = SafeNumber(r) or 1,
		g = SafeNumber(g) or 1,
		b = SafeNumber(b) or 1,
		sig = safeLineID .. "|" .. text,
	}, false
end

local function CaptureChatTail(cf, count)
	local tail = {}
	for k = 0, 2 do
		local idx = count - k
		if idx < 1 then
			break
		end
		local line = ReadChatLine(cf, idx)
		tail[k + 1] = line and line.sig or ""
	end
	return tail
end

local function MatchesChatTail(cf, m, tail)
	if not tail or #tail == 0 then
		return false
	end
	for k = 1, #tail do
		local idx = m - (k - 1)
		if idx < 1 then
			return false
		end
		local line = ReadChatLine(cf, idx)
		local sig = line and line.sig or ""
		if sig ~= tail[k] then
			return false
		end
	end
	return true
end

-- Poll ChatFrame1..NUM_CHAT_WINDOWS at 4 Hz for active-tab peek (works even when 128-line buffer is full
-- and when consecutive lines have identical text, e.g. repeated loot messages)
function ns.PollChatPeek(now)
	local db = ns.GetDB and ns.GetDB()
	local dur = (db and db.chatPeekDuration) or 8
	local fadeOut = (db and db.fadeOutTime) or 0.8
	local linesOnly = db and db.chatPeekLinesOnly ~= false
	local chatTriggerOn = db and db.elements and db.elements.chat and db.elements.chat.triggers and db.elements.chat.triggers.chatMessage
	local numWindows = NUM_CHAT_WINDOWS or 10

	for i = 1, numWindows do
		local cf = _G["ChatFrame" .. i]
		if ns.IsUsableFrame(cf) and cf.GetNumMessages then
			local count = SafeNumber(cf:GetNumMessages()) or 0
			local prevCount = chatLastCount[cf]
			local prevTail = chatLastTail[cf]

			if count == 0 then
				chatLastCount[cf] = 0
				chatLastTail[cf] = nil
			elseif prevCount == nil then
				-- Initial baseline on startup (don't peek old history)
				chatLastCount[cf] = count
				chatLastTail[cf] = CaptureChatTail(cf, count)
			else
				local newLines = {}
				local hadSecret = false
				local countGrew = count > prevCount

				if countGrew then
					-- Buffer has not wrapped: exact new range is (prevCount + 1) .. count
					local startIdx = math.max(prevCount + 1, count - 15)
					for m = count, startIdx, -1 do
						local line, isSec = ReadChatLine(cf, m)
						if isSec then
							hadSecret = true
						elseif line then
							newLines[#newLines + 1] = line
						end
					end
				elseif prevTail and #prevTail > 0 then
					-- Full ring buffer (e.g. 128 lines): scan backwards until the 3-line tail matches
					local scanFloor = math.max(1, count - 15)
					for m = count, scanFloor, -1 do
						if MatchesChatTail(cf, m, prevTail) then
							break
						end
						local line, isSec = ReadChatLine(cf, m)
						if isSec then
							hadSecret = true
						elseif line then
							newLines[#newLines + 1] = line
						end
					end
				end

				chatLastCount[cf] = count
				chatLastTail[cf] = CaptureChatTail(cf, count)

				if chatInitialized and (#newLines > 0 or (hadSecret and countGrew)) then
					-- Only peek if this exact chat tab/window is currently active/shown
					if SafeBool(cf:IsShown()) then
						local pushedToOverlay = false
						if linesOnly and chatTriggerOn and #newLines > 0 and not hadSecret then
							local overlay = SyncChatOverlayTo(cf, dur, fadeOut)
							-- Add in chronological order (oldest new line first)
							for k = #newLines, 1, -1 do
								local l = newLines[k]
								overlay:AddMessage(l.text, l.r, l.g, l.b)
							end
							chatOverlayUntil = now + dur + math.max(0.2, fadeOut)
							pushedToOverlay = true
						end
						if not pushedToOverlay then
							chatPeekUntil[cf] = now + dur
						end
					end
				end
			end
		end
	end
	chatInitialized = true
end

function ns.IsChatFramePeeking(chatFrame, now)
	local untilTime = chatPeekUntil[chatFrame]
	return untilTime ~= nil and now < untilTime
end

function ns.IsAnyChatPeeking(now)
	if now < chatOverlayUntil then
		return true
	end
	for _, untilTime in pairs(chatPeekUntil) do
		if now < untilTime then
			return true
		end
	end
	return false
end

function ns.SyncChatPeekOverlay(chatWindowVisible, chatCurAlpha, now)
	if not chatOverlayFrame then
		return
	end
	if now >= chatOverlayUntil then
		if chatOverlayFrame:IsShown() then
			chatOverlayFrame:Hide()
		end
		chatOverlayFrame:Clear()
		return
	end

	local a = chatCurAlpha or 0
	if a >= 0.99 then
		-- Real chat window is fully opaque: hide overlay without clearing so any message
		-- that arrives while hovering remains ready to peek when the chat window fades out.
		if chatOverlayFrame:IsShown() then
			chatOverlayFrame:Hide()
		end
	else
		-- Hold overlay at full 1.0 alpha while ChatFrame fades in/out:
		-- Porter-Duff compositing gives 1.0 + a*(1-1.0) = 1.000 (zero opacity dip!).
		chatOverlayFrame:SetAlpha(1)
		if not chatOverlayFrame:IsShown() then
			chatOverlayFrame:Show()
		end
	end
end

-- Scan player buffs for any non-permanent buff with remaining time <= buffExpiringThreshold
local function RefreshExpiringBuffs(now, threshold)
	lastExpiringScanAt = now
	wipe(expiringBuffIcons)
	hasExpiringBuff = false
	if not threshold or threshold <= 0 then
		return
	end
	for i = 1, 40 do
		local duration, expTime, icon
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok or IsSecret(aura) or not aura then
				break
			end
			duration = SafeNumber(aura.duration)
			expTime = SafeNumber(aura.expirationTime)
			icon = (aura.icon ~= nil and not IsSecret(aura.icon)) and aura.icon or nil
		elseif UnitBuff then
			local name, tex, _, _, dur, exp = UnitBuff("player", i)
			if IsSecret(name) or not name then
				break
			end
			duration = SafeNumber(dur)
			expTime = SafeNumber(exp)
			icon = (tex ~= nil and not IsSecret(tex)) and tex or nil
		else
			break
		end
		if duration and duration > 0 and expTime and expTime > now then
			if (expTime - now) <= threshold then
				hasExpiringBuff = true
				if icon ~= nil then
					expiringBuffIcons[icon] = true
				end
			end
		end
	end
end

function ns.GetActivePeekBuffIcons(now, fadeOutTime, includeExpiring)
	if now < state.buffPeekWholeUntil and not includeExpiring then
		return nil
	end
	local fade = (fadeOutTime and fadeOutTime > 0.001) and fadeOutTime or 0
	local active = nil
	if now >= state.buffPeekWholeUntil then
		for icon, exp in pairs(peekBuffIcons) do
			if now < exp then
				active = active or {}
				active[icon] = 1.0
			elseif fade > 0 and now < exp + fade then
				active = active or {}
				active[icon] = math.max(0, 1.0 - ((now - exp) / fade))
			else
				peekBuffIcons[icon] = nil
			end
		end
	end
	if includeExpiring and hasExpiringBuff then
		for icon in pairs(expiringBuffIcons) do
			active = active or {}
			active[icon] = 1.0
		end
	end
	return active
end

-- QoL interaction checks
local SPELLBOOK_FRAMES = { "SpellBookFrame", "PlayerSpellsFrame", "MacroFrame", "MultiCastFlyoutFrame" }

function ns.IsSpellbookOpen()
	for _, name in ipairs(SPELLBOOK_FRAMES) do
		local f = _G[name]
		if ns.IsUsableFrame(f) and SafeBool(f:IsShown()) then
			return true
		end
	end
	return false
end

function ns.IsDragging()
	return GetCursorInfo and GetCursorInfo() ~= nil or false
end

function ns.IsBagsOpen()
	local combined = _G.ContainerFrameCombinedBags
	if ns.IsUsableFrame(combined) and SafeBool(combined:IsShown()) then
		return true
	end
	for i = 1, 13 do
		local bag = _G["ContainerFrame" .. i]
		if ns.IsUsableFrame(bag) and SafeBool(bag:IsShown()) then
			return true
		end
	end
	return false
end

function ns.IsChatTyping()
	return ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() ~= nil or false
end

-- Evaluate all trigger flags once per engine tick (fast, zero allocations)
local currentFlags = {}

function ns.EvaluateConditions(now)
	local db = ns.GetDB and ns.GetDB()
	local hpThresh = ((db and db.healthThreshold) or 100) / 100
	local powThresh = ((db and db.powerThreshold) or 90) / 100

	-- Core: Combat (+ Combat Fade-Out Delay)
	local fighting = state.inCombat or (InCombatLockdown and InCombatLockdown()) or SafeBool(UnitAffectingCombat("player"))
	currentFlags.combat = fighting or (now < state.combatHoldUntil)

	-- Core: Target (Enemy = living hostile + neutral; Friendly = ally/friendly NPC)
	local hasTarget = SafeBool(UnitExists("target"))
	if hasTarget then
		local canAttack = SafeBool(UnitCanAttack("player", "target"))
		local reaction = SafeNumber(UnitReaction("player", "target"))
		local isEnemy = canAttack or (reaction ~= nil and reaction <= 4)
		local isDead = SafeBool(UnitIsDeadOrGhost("target"))
		currentFlags.enemyTarget = isEnemy and not isDead
		currentFlags.friendlyTarget = not isEnemy
	else
		currentFlags.enemyTarget = false
		currentFlags.friendlyTarget = false
	end

	-- Vitals: Health Not Full (secret-value safe)
	local hp = SafeNumber(UnitHealth("player"))
	local hpMax = SafeNumber(UnitHealthMax("player"))
	if hp and hpMax and hpMax > 0 then
		currentFlags.healthNotFull = (hp / hpMax) < (hpThresh - 0.0001)
	else
		-- Secret value fallback: active while health is changing/regenerating (4s window covers slow ticks)
		currentFlags.healthNotFull = (now - state.lastHealthChange) < 4.0
	end

	-- Vitals: Power Not Full (Mana/Energy below %, Rage/Runic Power draining to 0)
	local powerType, powerToken = UnitPowerType("player")
	local safeType = SafeNumber(powerType)
	local safeToken = (type(powerToken) == "string" and not IsSecret(powerToken)) and powerToken or nil
	if safeType ~= nil then
		local curP = SafeNumber(UnitPower("player", safeType))
		local maxP = SafeNumber(UnitPowerMax("player", safeType))
		if safeToken and EMPTY_AT_REST[safeToken] then
			if curP ~= nil then
				currentFlags.powerNotFull = curP > 0
			else
				currentFlags.powerNotFull = (now - state.lastPowerChange) < 3.0
			end
		else
			if curP and maxP and maxP > 0 then
				currentFlags.powerNotFull = (curP / maxP) < (powThresh - 0.0001)
			else
				currentFlags.powerNotFull = (now - state.lastPowerChange) < 3.0
			end
		end
	else
		currentFlags.powerNotFull = (now - state.lastPowerChange) < 3.0
	end

	-- Vitals: Pet Health Not Full & Pet Not Happy (Hunter happiness: 1=Unhappy, 2=Content, 3=Happy)
	if SafeBool(UnitExists("pet")) then
		local pHp = SafeNumber(UnitHealth("pet"))
		local pMax = SafeNumber(UnitHealthMax("pet"))
		if pHp and pMax and pMax > 0 then
			currentFlags.petHealth = (pHp / pMax) < (hpThresh - 0.0001)
		else
			currentFlags.petHealth = (now - state.lastPetHealthChange) < 4.0
		end
		local happiness = GetPetHappiness and SafeNumber(GetPetHappiness())
		currentFlags.petUnhappy = (happiness ~= nil and happiness < 3)
	else
		currentFlags.petHealth = false
		currentFlags.petUnhappy = false
	end

	-- Vitals: Buff Changed (Peek), Short / Expiring Buff & Has Any Debuff
	if state.auraDirty or (now - lastExpiringScanAt) >= 0.5 then
		RefreshDebuffs()
		RefreshExpiringBuffs(now, (db and db.buffExpiringThreshold) or 90)
	end
	currentFlags.buffChanged = now < state.buffPeekUntil
	currentFlags.buffExpiring = hasExpiringBuff
	currentFlags.hasDebuff = state.hasDebuff

	-- Context / Location
	currentFlags.inGroup = SafeBool(IsInGroup and IsInGroup()) or SafeBool(IsInRaid and IsInRaid())
	local inInst = SafeBool(IsInInstance and select(1, IsInInstance()))
	local resting = SafeBool(IsResting and IsResting())
	currentFlags.inInstance = inInst
	currentFlags.inCity = resting
	currentFlags.openWorld = (not inInst) and (not resting)

	-- Casting / Channeling
	local castName = UnitCastingInfo and UnitCastingInfo("player")
	local chanName = UnitChannelInfo and UnitChannelInfo("player")
	currentFlags.casting = state.casting or (castName ~= nil) or (chanName ~= nil)

	currentFlags.mounted = SafeBool(IsMounted and IsMounted())
	currentFlags.onTaxi = SafeBool(UnitOnTaxi and UnitOnTaxi("player"))
	currentFlags.questChanged = now < state.questPeekUntil
	currentFlags.chatMessage = ns.IsAnyChatPeeking(now)

	-- Minimap & World
	if state.trackingDirty then
		RefreshTracking()
	end
	currentFlags.tracking = state.trackingActive
	currentFlags.unreadMail = SafeBool(HasNewMail and HasNewMail())
	currentFlags.minimapPing = now < state.minimapPingUntil
	currentFlags.indoors = SafeBool(IsIndoors and IsIndoors())

	-- Suppress automatic triggers while dead/ghost (keeps hover, Always Show, and chat peeks working)
	if (not db or db.fadeWhenDead ~= false) and SafeBool(UnitIsDeadOrGhost("player")) then
		for k in pairs(currentFlags) do
			if k ~= "chatMessage" then
				currentFlags[k] = false
			end
		end
	end

	return currentFlags
end
