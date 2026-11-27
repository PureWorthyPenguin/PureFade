-- PureFade: Native Blizzard Settings UI (Options -> AddOns -> PureFade).
local _, ns = ...

local mainCategory
local subCategories = {}
local pageCanvases = {}
local refreshCallbacks = {}
local generalSearchItems = {}
local focusElementCallback -- set by BuildElementsPage to jump to & highlight a row
local focusAddonCallback   -- set by BuildAddonsPage to jump to & highlight a card

local function RefreshAllPages()
	for _, fn in ipairs(refreshCallbacks) do
		fn()
	end
end
ns.RefreshUI = RefreshAllPages

local function OpenPage(pageKey)
	if InCombatLockdown and InCombatLockdown() then
		print("|cff66ccffPureFade:|r Cannot switch Settings pages during combat.")
		return
	end
	local cat = subCategories[pageKey] or mainCategory
	if cat and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(cat:GetID())
	end
end

-- Collect searchable items across General, Elements, Groups, and Profiles
local function CollectSearchItems()
	local items = {}
	local db = ns.GetDB and ns.GetDB()

	-- General settings
	for _, g in ipairs(generalSearchItems) do
		items[#items + 1] = g
	end

	-- Built-in UI Elements
	for _, el in ipairs(ns.ELEMENTS) do
		items[#items + 1] = {
			label = el.label,
			search = (el.label .. " " .. el.key .. " " .. el.category):lower(),
			page = "elements",
			pageLabel = "Elements",
			category = el.category,
			elementKey = el.key,
		}
	end

	-- Custom /fstack frames
	if db and db.customFrames then
		for frameName in pairs(db.customFrames) do
			items[#items + 1] = {
				label = frameName .. " (Custom)",
				search = (frameName .. " custom frame"):lower(),
				page = "elements",
				pageLabel = "Elements",
				category = "custom",
				elementKey = frameName,
			}
		end
	end

	-- Groups
	if db and db.groups then
		local gNames = {}
		for gName in pairs(db.groups) do gNames[#gNames + 1] = gName end
		table.sort(gNames)
		for _, gName in ipairs(gNames) do
			items[#items + 1] = {
				label = gName .. " (Group)",
				search = (gName .. " group sync"):lower(),
				page = "groups",
				pageLabel = "Groups",
			}
		end
	end

	-- 3rd-Party Addons & Frame Picker
	items[#items + 1] = {
		label = "Pick Frame on Screen (Any Addon)",
		search = "pick frame on screen addon custom fstack",
		page = "addons",
		pageLabel = "Addons",
	}
	if ns.SUPPORTED_ADDONS then
		for _, entry in ipairs(ns.SUPPORTED_ADDONS) do
			if ns.IsAddOnLoadedSafe(entry.addon) then
				items[#items + 1] = {
					label = entry.label,
					search = (entry.label .. " " .. entry.addon .. " " .. entry.key .. " addon"):lower(),
					page = "addons",
					pageLabel = "Addons",
				}
			end
		end
	end

	-- Profiles
	local profileEntries = {
		{ label = "Active Profile",        search = "active profile switch select default" },
		{ label = "Create / Copy Profile", search = "create new copy profile" },
		{ label = "Rename Profile",        search = "rename profile" },
		{ label = "Delete Profile",        search = "delete remove profile" },
		{ label = "Export / Import Profile", search = "export import share copy paste string profile" },
	}
	for _, p in ipairs(profileEntries) do
		items[#items + 1] = {
			label = p.label,
			search = p.search,
			page = "profiles",
			pageLabel = "Profiles",
		}
	end

	return items
end

local function NavigateToSearchItem(item)
	OpenPage(item.page)
	if item.page == "elements" and focusElementCallback then
		focusElementCallback(item.category, item.elementKey)
	elseif item.page == "general" and pageCanvases.general and pageCanvases.general.scroll then
		local scroll = pageCanvases.general.scroll
		local targetY = math.max(0, (item.scrollY or 0) - 40)
		C_Timer.After(0.02, function()
			if scroll.SetVerticalScroll then
				local maxScroll = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
				scroll:SetVerticalScroll(math.min(targetY, maxScroll))
			end
		end)
	end
end

-- Shared floating search results popup
local searchPopup
local searchPopupRows = {}

local function GetSearchPopup()
	if searchPopup then
		return searchPopup
	end
	local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	f:SetFrameStrata("TOOLTIP")
	f:SetWidth(295)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
	f:SetBackdropBorderColor(0.55, 0.5, 0.35, 0.95)
	f:Hide()
	searchPopup = f
	return f
end

local MakeEditBox

local function AttachSearchBar(canvas, resetBtn)
	local box = MakeEditBox(canvas, 165, 20)
	box:SetPoint("RIGHT", resetBtn, "LEFT", -12, 0)

	local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	placeholder:SetPoint("LEFT", box, "LEFT", 6, 0)
	placeholder:SetText("Search settings...")

	local function HidePopup()
		if searchPopup then
			searchPopup:Hide()
		end
	end

	local function UpdateResults()
		local query = strtrim((box:GetText() or ""):lower())
		placeholder:SetShown(query == "" and not box:HasFocus())

		if query == "" then
			HidePopup()
			return
		end

		local matches = {}
		for _, item in ipairs(CollectSearchItems()) do
			if item.search:find(query, 1, true) then
				matches[#matches + 1] = item
				if #matches >= 10 then
					break
				end
			end
		end

		local popup = GetSearchPopup()
		popup:ClearAllPoints()
		popup:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 2, -2)

		for i = 1, #searchPopupRows do
			searchPopupRows[i]:Hide()
		end

		if #matches == 0 then
			local row = searchPopupRows[1]
			if not row then
				row = CreateFrame("Button", nil, popup)
				row:SetSize(283, 22)
				row.bg = row:CreateTexture(nil, "HIGHLIGHT")
				row.bg:SetAllPoints()
				row.bg:SetColorTexture(1, 0.82, 0, 0.18)
				row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.left:SetPoint("LEFT", row, "LEFT", 6, 0)
				row.left:SetWidth(200)
				row.left:SetJustifyH("LEFT")
				row.left:SetWordWrap(false)
				row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
				row.right:SetJustifyH("RIGHT")
				searchPopupRows[1] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, -6)
			row.left:SetText("|cff888888No matching settings found|r")
			row.right:SetText("")
			row:SetScript("OnClick", nil)
			row:Show()
			popup:SetHeight(34)
			popup:Show()
			return
		end

		local y = -6
		for i, item in ipairs(matches) do
			local row = searchPopupRows[i]
			if not row then
				row = CreateFrame("Button", nil, popup)
				row:SetSize(283, 22)
				row.bg = row:CreateTexture(nil, "HIGHLIGHT")
				row.bg:SetAllPoints()
				row.bg:SetColorTexture(1, 0.82, 0, 0.18)
				row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				row.left:SetPoint("LEFT", row, "LEFT", 6, 0)
				row.left:SetWidth(205)
				row.left:SetJustifyH("LEFT")
				row.left:SetWordWrap(false)
				row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
				row.right:SetJustifyH("RIGHT")
				searchPopupRows[i] = row
			end
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", popup, "TOPLEFT", 6, y)
			row.left:SetText(item.label)
			row.right:SetText("|cff77bbff" .. item.pageLabel .. "|r")
			row:SetScript("OnClick", function()
				box:SetText("")
				box:ClearFocus()
				HidePopup()
				NavigateToSearchItem(item)
			end)
			row:Show()
			y = y - 22
		end

		popup:SetHeight(math.abs(y) + 6)
		popup:Show()
	end

	box:SetScript("OnTextChanged", UpdateResults)
	box:SetScript("OnEditFocusGained", function()
		placeholder:Hide()
		UpdateResults()
	end)
	box:SetScript("OnEditFocusLost", function()
		local query = strtrim(box:GetText() or "")
		placeholder:SetShown(query == "")
		-- Delay hiding slightly so clicking a result button fires OnClick first
		C_Timer.After(0.15, function()
			if not box:HasFocus() then
				HidePopup()
			end
		end)
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		HidePopup()
	end)
	canvas:HookScript("OnHide", function()
		box:SetText("")
		HidePopup()
	end)

	return box
end

-- Native tooltip helper
local function AttachTooltip(widget, title, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 0.82, 0)
		if text then
			GameTooltip:AddLine(text, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- Native Blizzard-styled button (clips text strictly inside button bounds)
local function MakeButton(parent, text, width, height, onClick)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 100, height or 22)
	btn:SetText(text)
	local fs = btn:GetFontString()
	if fs then
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", btn, "LEFT", 8, 0)
		fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
		fs:SetJustifyH("CENTER")
		fs:SetWordWrap(false)
	end
	if onClick then
		btn:SetScript("OnClick", onClick)
	end
	return btn
end

-- Native Blizzard-styled EditBox
function MakeEditBox(parent, width, height)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width or 180, height or 22)
	eb:SetAutoFocus(false)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return eb
end

-- Confirmation dialog for "Reset to Defaults"
StaticPopupDialogs["PUREFADE_CONFIRM_RESET"] = {
	text = "Reset %s settings in profile '%s' back to Default values?",
	button1 = "Reset",
	button2 = "Cancel",
	OnAccept = function(_, data)
		if data and data.pageKey and ns.ResetPageDefaults then
			ns.ResetPageDefaults(data.pageKey)
			RefreshAllPages()
			if ns.ForceRefresh then ns.ForceRefresh() end
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_NEW_PROFILE"] = {
	text = "Enter a name for the new profile\n(copied from your current settings):",
	button1 = "Create",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText("")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self)
		local eb = self.EditBox or self.editBox
		local name = strtrim((eb and eb:GetText()) or "")
		if name ~= "" and ns.CreateProfile and ns.CreateProfile(name, true) then
			RefreshAllPages()
			if ns.ForceRefresh then ns.ForceRefresh() end
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_RENAME_PROFILE"] = {
	text = "Rename profile '%s' to:",
	button1 = "Save",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self, data)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText((data and data.oldName) or "")
			eb:SetFocus()
			eb:HighlightText()
		end
	end,
	OnAccept = function(self, data)
		local eb = self.EditBox or self.editBox
		local newName = strtrim((eb and eb:GetText()) or "")
		if data and data.oldName and newName ~= "" and ns.RenameProfile and ns.RenameProfile(data.oldName, newName) then
			RefreshAllPages()
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_DELETE_PROFILE"] = {
	text = "Delete profile '%s'?\n\nThis cannot be undone.",
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function(_, data)
		if data and data.name and ns.DeleteProfile and ns.DeleteProfile(data.name) then
			RefreshAllPages()
			if ns.ForceRefresh then ns.ForceRefresh() end
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_IMPORT_NAME"] = {
	text = "Enter a name for the imported profile:",
	button1 = "Import",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText("Imported")
			eb:SetFocus()
			eb:HighlightText()
		end
	end,
	OnAccept = function(self, data)
		local eb = self.EditBox or self.editBox
		local name = strtrim((eb and eb:GetText()) or "")
		if data and data.encoded and ns.ImportProfile then
			local ok, result = ns.ImportProfile(data.encoded, name)
			if ok then
				print("|cff66ccffPureFade:|r Imported profile as '|cffffff00" .. result .. "|r'.")
				RefreshAllPages()
				if ns.ForceRefresh then ns.ForceRefresh() end
			else
				print("|cff66ccffPureFade:|r |cffff6666Import failed:|r " .. tostring(result))
			end
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_NEW_GROUP"] = {
	text = "Enter a name for the new group:",
	button1 = "Create",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText("")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self)
		local eb = self.EditBox or self.editBox
		local name = strtrim((eb and eb:GetText()) or "")
		if name == "" or name == "None" then return end
		if ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() and ns.EnsureEditableProfile then
			ns.EnsureEditableProfile()
		end
		local db = ns.GetDB()
		if not db then return end
		db.groups = db.groups or {}
		if not db.groups[name] then
			db.groups[name] = { syncMode = "hover" }
		end
		RefreshAllPages()
		if ns.ForceRefresh then ns.ForceRefresh() end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_RENAME_GROUP"] = {
	text = "Rename group '%s' to:",
	button1 = "Save",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 40,
	OnShow = function(self, data)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText((data and data.oldName) or "")
			eb:SetFocus()
			eb:HighlightText()
		end
	end,
	OnAccept = function(self, data)
		local eb = self.EditBox or self.editBox
		local newName = strtrim((eb and eb:GetText()) or "")
		local oldName = data and data.oldName
		if not oldName or newName == "" or newName == "None" or newName == oldName then return end
		if ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() and ns.EnsureEditableProfile then
			ns.EnsureEditableProfile()
		end
		local db = ns.GetDB()
		if not db or not db.groups or not db.groups[oldName] then return end
		if db.groups[newName] then
			print("|cff66ccffPureFade:|r Group '" .. newName .. "' already exists.")
			return
		end
		db.groups[newName] = db.groups[oldName]
		db.groups[oldName] = nil
		for _, cfg in pairs(db.elements or {}) do
			if cfg.group == oldName then cfg.group = newName end
		end
		for _, cfg in pairs(db.addons or {}) do
			if cfg.group == oldName then cfg.group = newName end
		end
		for _, cfg in pairs(db.customFrames or {}) do
			if cfg.group == oldName then cfg.group = newName end
		end
		RefreshAllPages()
		if ns.ForceRefresh then ns.ForceRefresh() end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["PUREFADE_ADD_CUSTOM_FRAME"] = {
	text = "Enter a global frame name to manage\n(e.g. from /fstack for hidden or non-clickable frames):",
	button1 = "Add",
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 80,
	OnShow = function(self)
		local eb = self.EditBox or self.editBox
		if eb then
			eb:SetText("")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self)
		local eb = self.EditBox or self.editBox
		local name = strtrim((eb and eb:GetText()) or "")
		if name == "" then return end
		if ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() and ns.EnsureEditableProfile then
			ns.EnsureEditableProfile()
		end
		local db = ns.GetDB()
		if not db then return end
		db.customFrames = db.customFrames or {}
		if not db.customFrames[name] then
			db.customFrames[name] = {
				mode = "custom",
				follow = "None",
				group = "None",
				alwaysShow = false,
				hover = true,
				triggers = {},
			}
		end
		if ns.ForceRefresh then ns.ForceRefresh() end
		RefreshAllPages()
		if focusElementCallback then
			focusElementCallback("custom", name)
		end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local btn = parent.button1 or (parent.ButtonContainer and parent.ButtonContainer.Button1)
		if btn and btn:IsEnabled() then btn:Click() end
	end,
	EditBoxOnEscapePressed = function(self)
		self:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function GuardEditable()
	if ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() and ns.EnsureEditableProfile then
		local _, switched = ns.EnsureEditableProfile()
		if switched and C_Timer and C_Timer.After then
			C_Timer.After(0, RefreshAllPages)
		end
	end
	return true
end

local function LaunchFramePicker(returnPage)
	if not ns.StartFramePicker then return end
	ns.StartFramePicker(function(frameName, existingOwner)
		if existingOwner then
			print("|cff66ccffPureFade:|r '|cffffff00" .. existingOwner.label .. "|r' is already managed — opening its settings.")
			if existingOwner.kind == "element" then
				OpenPage("elements")
				if focusElementCallback then
					focusElementCallback(existingOwner.category, existingOwner.key)
				end
			else
				OpenPage("addons")
				RefreshAllPages()
				if focusAddonCallback then
					focusAddonCallback(existingOwner.key)
				end
			end
			return
		end
		if frameName and frameName ~= "" then
			GuardEditable()
			local db = ns.GetDB()
			db.customFrames = db.customFrames or {}
			if not db.customFrames[frameName] then
				db.customFrames[frameName] = {
					mode = "custom",
					follow = "None",
					group = "None",
					alwaysShow = false,
					hover = true,
					triggers = {},
				}
			end
			if ns.ForceRefresh then ns.ForceRefresh() end
			print("|cff66ccffPureFade:|r Added frame '|cffffff00" .. frameName .. "|r'.")
			if returnPage == "elements" then
				OpenPage("elements")
				RefreshAllPages()
				if focusElementCallback then
					focusElementCallback("custom", frameName)
				end
			else
				OpenPage("addons")
				RefreshAllPages()
				if focusAddonCallback then
					focusAddonCallback(frameName)
				end
			end
		else
			OpenPage(returnPage or "addons")
			RefreshAllPages()
		end
	end)
end

-- Native Blizzard-styled checkbox
local function MakeCheckbox(parent, label, tip, getFn, setFn)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	if label and label ~= "" then
		local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		fs:SetText(label)
		cb.label = fs
	end
	cb:SetScript("OnClick", function(self)
		if not GuardEditable() then
			self:SetChecked(getFn() and true or false)
			return
		end
		local checked = self:GetChecked() and true or false
		setFn(checked)
		if ns.ForceRefresh then ns.ForceRefresh() end
	end)
	if tip then
		AttachTooltip(cb, label or "Option", tip)
	end
	cb.Refresh = function(self)
		self:SetChecked(getFn() and true or false)
	end
	return cb
end

-- Clean native-look horizontal slider (no deprecated template dependencies)
local function MakeSlider(parent, label, minVal, maxVal, step, formatFn, tip, getFn, setFn)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(560, 26)

	local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
	nameFS:SetWidth(220)
	nameFS:SetJustifyH("LEFT")
	nameFS:SetText(label)

	local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
	slider:SetOrientation("HORIZONTAL")
	slider:SetSize(210, 16)
	slider:SetPoint("LEFT", nameFS, "RIGHT", 12, 0)
	slider:SetMinMaxValues(minVal, maxVal)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

	local valFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	valFS:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	valFS:SetWidth(90)
	valFS:SetJustifyH("LEFT")

	local updating = false
	slider:SetScript("OnValueChanged", function(_, value)
		if updating then return end
		if not GuardEditable() then
			row.Refresh()
			return
		end
		-- Round cleanly to step
		local snapped = math.floor((value / step) + 0.5) * step
		if snapped < minVal then snapped = minVal end
		if snapped > maxVal then snapped = maxVal end
		valFS:SetText(formatFn(snapped))
		setFn(snapped)
		if ns.ForceRefresh then ns.ForceRefresh() end
	end)

	if tip then
		AttachTooltip(slider, label, tip)
	end

	row.Refresh = function()
		updating = true
		local v = getFn()
		if v == nil then v = minVal end
		slider:SetValue(v)
		valFS:SetText(formatFn(v))
		updating = false
	end

	return row
end

-- Context menu helper using WoW Forever's native MenuUtil
local function OpenDropdownMenu(owner, buildFn)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
			buildFn(rootDescription)
		end)
	end
end

-- Standard page canvas with Title, Subtitle, Top-Right "Reset to Defaults" button, and ScrollFrame
local function CreateSettingsPage(titleText, subtitleText, resetPageKey, hideSearch)
	local canvas = CreateFrame("Frame")
	canvas:Hide()

	local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", canvas, "TOPLEFT", 16, -16)
	title:SetText(titleText)

	local profileBadge
	if resetPageKey ~= "all" then
		profileBadge = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		profileBadge:SetPoint("LEFT", title, "RIGHT", 10, -1)
		profileBadge:SetTextColor(0.75, 0.85, 1.0)
	end

	local resetBtn = MakeButton(canvas, "Reset to Defaults", 130, 22, function()
		if ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() then return end
		local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Custom"
		local pageLabel = (resetPageKey == "all") and "ALL" or titleText
		StaticPopup_Show("PUREFADE_CONFIRM_RESET", pageLabel, active, { pageKey = resetPageKey })
	end)
	resetBtn:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -24, -14)
	AttachTooltip(resetBtn, "Reset to Defaults", "Resets only this page's settings in the current profile back to Default values.")

	local rightAnchor = resetBtn
	if not hideSearch then
		rightAnchor = AttachSearchBar(canvas, resetBtn)
	end

	local sub = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetPoint("RIGHT", rightAnchor, "LEFT", -12, 0)
	sub:SetJustifyH("LEFT")
	sub:SetText(subtitleText)
	sub:SetTextColor(0.75, 0.75, 0.75)

	local divider = canvas:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -8)
	divider:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -24, -52)
	divider:SetColorTexture(0.35, 0.35, 0.35, 0.6)

	local function RefreshPageChrome()
		local ro = ns.IsReadOnlyProfile and ns.IsReadOnlyProfile() or false
		resetBtn:SetEnabled(not ro)
		if profileBadge then
			local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Default"
			profileBadge:SetText("Profile: |cffffff00" .. active .. "|r")
		end
	end
	refreshCallbacks[#refreshCallbacks + 1] = RefreshPageChrome
	canvas:HookScript("OnShow", RefreshPageChrome)
	RefreshPageChrome()

	local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -32, 12)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, 1)
	scroll:SetScrollChild(content)

	canvas.content = content
	canvas.scroll = scroll
	canvas.divider = divider
	return canvas, content
end

local function MakeSectionHeader(parent, text, yOffset)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, yOffset)
	fs:SetText(text)
	return fs
end

--------------------------------------------------------------------------------
-- PAGE 1: GENERAL
--------------------------------------------------------------------------------
local function BuildGeneralPage()
	local canvas, content = CreateSettingsPage(
		"PureFade",
		"Lightweight UI fading for WoW Forever. Configure fade speed, universal delays, thresholds, and interaction triggers.",
		"general"
	)

	local widgets = {}
	local y = -6

	local function Add(widget, height, searchLabel, searchKeywords)
		local posY = math.abs(y)
		widget:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
		y = y - (height or 28)
		widgets[#widgets + 1] = widget
		if searchLabel then
			generalSearchItems[#generalSearchItems + 1] = {
				label = searchLabel,
				search = (searchLabel .. " " .. (searchKeywords or "")):lower(),
				page = "general",
				pageLabel = "General",
				scrollY = posY,
			}
		end
		return widget
	end

	-- Master switch
	Add(MakeCheckbox(content, "Enable PureFade",
		"Master toggle. Uncheck to restore all UI elements to 100% visibility.",
		function() return ns.GetDB().enabled end,
		function(v)
			ns.GetDB().enabled = v
			if not v and ns.RestoreAllFrames then ns.RestoreAllFrames() end
		end
	), 32, "Enable PureFade", "master toggle pause enable disable")

	-- Login Behavior
	MakeSectionHeader(content, "On Player Login", y)
	y = y - 22

	local loginRow = CreateFrame("Frame", nil, content)
	loginRow:SetSize(560, 26)
	local loginLabel = loginRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	loginLabel:SetPoint("LEFT", loginRow, "LEFT", 0, 0)
	loginLabel:SetWidth(220)
	loginLabel:SetJustifyH("LEFT")
	loginLabel:SetText("Login Behavior")

	local function BuildLoginMenu(root)
		root:CreateRadio("Delay Before Fading",
			function() return ns.GetDB().loginBehavior == "delay" end,
			function() GuardEditable(); ns.GetDB().loginBehavior = "delay"; RefreshAllPages() end
		)
		root:CreateRadio("Start Faded Immediately",
			function() return ns.GetDB().loginBehavior == "faded" end,
			function() GuardEditable(); ns.GetDB().loginBehavior = "faded"; RefreshAllPages() end
		)
	end

	local loginDropdown
	local okLD, ld = pcall(CreateFrame, "DropdownButton", nil, loginRow, "WowStyle1DropdownTemplate")
	if okLD and ld and ld.SetupMenu then
		ld:SetWidth(210)
		ld:SetPoint("LEFT", loginLabel, "RIGHT", 12, 0)
		ld:SetupMenu(function(_, root)
			BuildLoginMenu(root)
		end)
		loginDropdown = ld
	else
		local fallbackBtn = MakeButton(loginRow, "", 210, 22, function(self)
			OpenDropdownMenu(self, BuildLoginMenu)
		end)
		fallbackBtn:SetPoint("LEFT", loginLabel, "RIGHT", 12, 0)
		loginDropdown = fallbackBtn
	end

	loginRow.Refresh = function()
		local mode = ns.GetDB().loginBehavior
		local txt = mode == "faded" and "Start Faded Immediately" or "Delay Before Fading"
		if loginDropdown.OverrideText then
			loginDropdown:OverrideText(txt)
		elseif loginDropdown.SetText then
			loginDropdown:SetText(txt)
		end
	end
	Add(loginRow, 28, "Login Behavior", "login start faded delay")

	Add(MakeSlider(content, "Login Delay", 0, 30, 1,
		function(v) return v == 0 and "Instant" or (v .. "s") end,
		"How long the UI stays visible after logging in before fading out (when Delay Before Fading is selected).",
		function() return ns.GetDB().loginDelay end,
		function(v) ns.GetDB().loginDelay = v end
	), 32, "Login Delay", "login delay seconds")

	-- Fade Animation
	y = y - 6
	MakeSectionHeader(content, "Fade Animation", y)
	y = y - 22

	Add(MakeSlider(content, "Fade In Duration", 0, 2.0, 0.05,
		function(v) return v <= 0.001 and "Instant" or string.format("%.2fs", v) end,
		"How fast UI elements appear out of combat. Set to 0 for instant pop-in.",
		function() return ns.GetDB().fadeInTime end,
		function(v) ns.GetDB().fadeInTime = v end
	), 28, "Fade In Duration", "animation speed instant fade in")

	Add(MakeSlider(content, "Combat Fade In Duration", 0, 2.0, 0.05,
		function(v) return v <= 0.001 and "Instant" or string.format("%.2fs", v) end,
		"How fast UI elements appear when entering combat (defaults to same as Fade In Duration).",
		function() return ns.GetDB().combatFadeInTime end,
		function(v) ns.GetDB().combatFadeInTime = v end
	), 28, "Combat Fade In Duration", "combat animation speed instant fade in")

	Add(MakeSlider(content, "Fade Out Duration", 0, 5.0, 0.05,
		function(v) return v <= 0.001 and "Instant" or string.format("%.2fs", v) end,
		"How fast UI elements fade away. Set to 0 for instant hide.",
		function() return ns.GetDB().fadeOutTime end,
		function(v) ns.GetDB().fadeOutTime = v end
	), 28, "Fade Out Duration", "animation speed instant fade out")

	Add(MakeSlider(content, "Faded Opacity", 0, 50, 1,
		function(v) return v == 0 and "0% (Hidden)" or (v .. "%") end,
		"Global opacity of faded UI elements (0% = completely invisible, 15% = dimly visible). Can be overridden per element inside its Triggers menu.",
		function() return math.floor((ns.GetDB().fadedAlpha or 0) * 100 + 0.5) end,
		function(v) ns.GetDB().fadedAlpha = v / 100 end
	), 28, "Faded Opacity", "alpha transparency dim invisible")

	Add(MakeSlider(content, "Hover Reveal Delay", 0, 0.50, 0.05,
		function(v) return v <= 0.001 and "Instant" or string.format("%.2fs", v) end,
		"Optional delay before hovering reveals a faded element (e.g. 0.15s prevents quick cursor sweeps from flashing bars).",
		function() return ns.GetDB().hoverRevealDelay or 0 end,
		function(v) ns.GetDB().hoverRevealDelay = v end
	), 32, "Hover Reveal Delay", "hover delay sweep brush anti accidental")

	-- Universal Delays
	y = y - 6
	MakeSectionHeader(content, "Universal Hold & Fade-Out Delays", y)
	y = y - 22

	Add(MakeSlider(content, "Mouseover Hold Delay", 0, 10, 0.5,
		function(v) return v == 0 and "None" or string.format("%.1fs", v) end,
		"How long hovered elements stay visible after your cursor leaves them.",
		function() return ns.GetDB().mouseoverHold end,
		function(v) ns.GetDB().mouseoverHold = v end
	), 28, "Mouseover Hold Delay", "hover mouse delay")

	Add(MakeSlider(content, "Mouseover Buffer", 0, 80, 5,
		function(v) return v == 0 and "Exact (0px)" or (v .. "px") end,
		"Extra invisible hover margin around UI elements so they reveal as your cursor approaches (~25-35px is about 1cm).",
		function() return ns.GetDB().mouseoverBuffer end,
		function(v) ns.GetDB().mouseoverBuffer = v end
	), 28, "Mouseover Buffer", "hover buffer margin reach padding distance")

	Add(MakeSlider(content, "Combat Fade-Out Delay", 0, 30, 1,
		function(v) return v == 0 and "None" or (v .. "s") end,
		"How long combat-triggered elements stay visible after leaving combat.",
		function() return ns.GetDB().combatFadeOutDelay end,
		function(v) ns.GetDB().combatFadeOutDelay = v end
	), 28, "Combat Fade-Out Delay", "combat calm timer delay")

	Add(MakeSlider(content, "Chat Peek Duration", 2, 20, 1,
		function(v) return v .. "s" end,
		"How long the active chat tab stays visible when a new message arrives.",
		function() return ns.GetDB().chatPeekDuration end,
		function(v) ns.GetDB().chatPeekDuration = v end
	), 28, "Chat Peek Duration", "chat message peek duration")

	Add(MakeSlider(content, "Buff Peek Duration", 2, 20, 1,
		function(v) return v .. "s" end,
		"How long elements with 'Buff Changed (Peek)' stay visible when a buff changes.",
		function() return ns.GetDB().buffPeekDuration end,
		function(v) ns.GetDB().buffPeekDuration = v end
	), 28, "Buff Peek Duration", "buff aura change peek duration")

	Add(MakeSlider(content, "Quest Peek Duration", 2, 20, 1,
		function(v) return v .. "s" end,
		"How long Quest Tracker / Questie stays visible when a quest is accepted, updated, completed, or failed.",
		function() return ns.GetDB().questPeekDuration end,
		function(v) ns.GetDB().questPeekDuration = v end
	), 28, "Quest Peek Duration", "quest tracker questie objective progress peek duration")

	Add(MakeSlider(content, "Minimap Ping Peek", 2, 20, 1,
		function(v) return v .. "s" end,
		"How long the minimap stays visible when a group member pings it.",
		function() return ns.GetDB().minimapPingDuration end,
		function(v) ns.GetDB().minimapPingDuration = v end
	), 32, "Minimap Ping Peek", "minimap ping duration")

	-- Vital Thresholds
	y = y - 6
	MakeSectionHeader(content, "Vitals Thresholds", y)
	y = y - 22

	Add(MakeSlider(content, "Health Not Full Below", 10, 100, 5,
		function(v) return v == 100 and "< 100% (Any)" or ("< " .. v .. "%") end,
		"Triggers 'Health Not Full' and 'Pet Health Not Full' when health drops below this percentage.",
		function() return ns.GetDB().healthThreshold end,
		function(v) ns.GetDB().healthThreshold = v end
	), 28, "Health Not Full Below", "hp health threshold vitals")

	Add(MakeSlider(content, "Power Not Full Below", 10, 100, 5,
		function(v) return v == 100 and "< 100% (Any)" or ("< " .. v .. "%") end,
		"Triggers 'Power Not Full' when Mana/Energy/Focus is below this percentage (Rage/Runic Power stays active while > 0).",
		function() return ns.GetDB().powerThreshold end,
		function(v) ns.GetDB().powerThreshold = v end
	), 28, "Power Not Full Below", "mana rage energy power threshold vitals")

	Add(MakeSlider(content, "Short / Expiring Buff Below", 10, 300, 10,
		function(v)
			local m = math.floor(v / 60)
			local s = v % 60
			if m > 0 and s > 0 then return m .. "m " .. s .. "s"
			elseif m > 0 then return m .. "m"
			else return s .. "s" end
		end,
		"Keeps non-permanent buffs visible when their remaining time is at or below this duration (e.g. 1m 30s).",
		function() return ns.GetDB().buffExpiringThreshold or 90 end,
		function(v) ns.GetDB().buffExpiringThreshold = v end
	), 32, "Short / Expiring Buff Below", "buff expiring short duration remaining time")

	-- Quality-of-Life Interaction Triggers
	y = y - 6
	MakeSectionHeader(content, "Quality-of-Life Interaction Triggers", y)
	y = y - 22

	Add(MakeCheckbox(content, "Reveal Action Bars when Spellbook or Macros are open",
		"Temporarily shows Action Bars so you can drag spells onto them.",
		function() return ns.GetDB().qolSpellbook end,
		function(v) ns.GetDB().qolSpellbook = v end
	), 26, "Reveal Action Bars (Spellbook / Macros)", "spellbook macro action bars")

	Add(MakeCheckbox(content, "Reveal Action Bars & Bags when dragging an item or spell",
		"Temporarily shows Action Bars and Bags Bar while holding something on your cursor.",
		function() return ns.GetDB().qolDrag end,
		function(v) ns.GetDB().qolDrag = v end
	), 26, "Reveal Action Bars & Bags (Dragging)", "drag cursor item spell bags action bars")

	Add(MakeCheckbox(content, "Reveal Bags Bar when Bags are open",
		"Shows the Bags Bar whenever any of your bags are open.",
		function() return ns.GetDB().qolBagsOpen end,
		function(v) ns.GetDB().qolBagsOpen = v end
	), 26, "Reveal Bags Bar (Bags Open)", "bags backpack open")

	Add(MakeCheckbox(content, "Reveal Full Chat when typing (Enter)",
		"Shows the chat window, tabs, and buttons while the chat input box is active.",
		function() return ns.GetDB().qolChatTyping end,
		function(v) ns.GetDB().qolChatTyping = v end
	), 26, "Reveal Full Chat (Typing)", "chat typing enter")

	Add(MakeCheckbox(content, "Chat Peek: Show only new message lines (hide old chat history)",
		"When 'New Chat Message' peeks, floats only the newly arrived line(s) over the chat area. Uncheck to reveal the full chat message history.",
		function() return ns.GetDB().chatPeekLinesOnly ~= false end,
		function(v) ns.GetDB().chatPeekLinesOnly = v end
	), 26, "Chat Peek: Only New Lines", "chat peek single line message history")

	Add(MakeCheckbox(content, "Buff Peek: Show only newly gained/refreshed buff icons (in-place)",
		"When 'Buff Changed' peeks, shows only the newly gained or refreshed buff icon in its current slot while other buffs stay faded.",
		function() return ns.GetDB().buffPeekOnlyNew ~= false end,
		function(v) ns.GetDB().buffPeekOnlyNew = v end
	), 26, "Buff Peek: Only New Buffs", "buff peek single icon new aura")

	Add(MakeCheckbox(content, "Suppress automatic triggers while Dead / Ghost",
		"Fades Mail, Vitals, Debuffs, Tracking, and other automatic triggers during corpse runs (hover, chat peeks, and Always Show elements still work).",
		function() return ns.GetDB().fadeWhenDead ~= false end,
		function(v) ns.GetDB().fadeWhenDead = v end
	), 28, "Suppress Triggers While Dead / Ghost", "dead ghost corpse spirit mail debuff fade")

	-- Hold-to-Peek All UI keybind shortcut (jumps to Options -> Keybindings -> PureFade & flashes row)
	local function FlashKeybindRow(rowFrame)
		if not ns.IsUsableFrame(rowFrame) then return end
		local overlay = rowFrame.pureFadeFlashOverlay
		if not overlay then
			overlay = CreateFrame("Frame", nil, rowFrame)
			overlay:SetAllPoints(rowFrame)
			overlay:SetFrameLevel(rowFrame:GetFrameLevel() + 10)
			local glow = overlay:CreateTexture(nil, "OVERLAY")
			glow:SetAllPoints(overlay)
			glow:SetColorTexture(1.0, 0.82, 0.2, 0.45)
			glow:SetBlendMode("ADD")
			overlay.glow = glow
			rowFrame.pureFadeFlashOverlay = overlay
		end
		overlay:Show()
		local elapsed = 0
		local duration = 2.2
		overlay:SetScript("OnUpdate", function(self, dt)
			elapsed = elapsed + dt
			if elapsed >= duration then
				self:Hide()
				self:SetScript("OnUpdate", nil)
				return
			end
			local wave = math.abs(math.sin((elapsed / duration) * math.pi * 2))
			local fade = 1 - (elapsed / duration) * 0.35
			self.glow:SetAlpha(wave * fade * 0.65)
		end)
	end

	local function FrameContainsText(frame, targetLower)
		if not ns.IsUsableFrame(frame) then return false end
		local function CheckStr(s)
			if type(s) ~= "string" or ns.IsSecret(s) then return false end
			return s:lower():find(targetLower, 1, true) ~= nil
		end
		if frame.Text and frame.Text.GetText and CheckStr(frame.Text:GetText()) then return true end
		if frame.Label and frame.Label.GetText and CheckStr(frame.Label:GetText()) then return true end
		if frame.Button and frame.Button.Text and frame.Button.Text.GetText and CheckStr(frame.Button.Text:GetText()) then return true end
		if frame.GetRegions then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.GetText then
					if CheckStr(region:GetText()) then return true end
				end
			end
		end
		return false
	end

	local function OpenKeybindingsAndFlashPeek()
		local catID = Settings and Settings.KEYBINDINGS_CATEGORY_ID
		if not catID and Settings and Settings.GetCategory then
			local cat = Settings.GetCategory(KEYBINDINGS_LABEL or "Keybindings")
			if cat and cat.GetID then catID = cat:GetID() end
		end
		if catID and Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(catID)
		end
		local function HighlightTarget()
			pcall(function()
				local scrollBox = SettingsPanel and SettingsPanel.Container
					and SettingsPanel.Container.SettingsList
					and SettingsPanel.Container.SettingsList.ScrollBox
				if not scrollBox then return end
				local peekLower = (BINDING_NAME_PUREFADE_PEEK_HOLD or "Hold to Peek All UI"):lower()
				if scrollBox.ScrollToElementDataByPredicate then
					scrollBox:ScrollToElementDataByPredicate(function(elem)
						if type(elem) ~= "table" then return false end
						local d = elem.data or elem
						local name = (type(d.name) == "string" and d.name) or (type(d.categoryName) == "string" and d.categoryName) or ""
						local nl = name:lower()
						return nl:find(peekLower, 1, true) ~= nil or nl == "purefade"
					end)
				end
				C_Timer.After(0.08, function()
					pcall(function()
						if not scrollBox.ForEachFrame then return end
						local foundPeek = false
						local headerFrame = nil
						scrollBox:ForEachFrame(function(frame)
							if FrameContainsText(frame, peekLower) then
								FlashKeybindRow(frame)
								foundPeek = true
							elseif not headerFrame and FrameContainsText(frame, "purefade") then
								headerFrame = frame
							end
						end)
						if not foundPeek and headerFrame then
							-- Expand PureFade category if collapsed, then flash the binding row
							if headerFrame.Button and headerFrame.Button.Click then
								headerFrame.Button:Click()
							elseif headerFrame.Click then
								headerFrame:Click()
							end
							FlashKeybindRow(headerFrame)
							C_Timer.After(0.08, function()
								pcall(function()
									scrollBox:ForEachFrame(function(frame)
										if FrameContainsText(frame, peekLower) then
											FlashKeybindRow(frame)
										end
									end)
								end)
							end)
						end
					end)
				end)
			end)
		end
		C_Timer.After(0.12, HighlightTarget)
	end

	local peekBindRow = CreateFrame("Frame", nil, content)
	peekBindRow:SetSize(560, 26)
	local peekBindFS = peekBindRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	peekBindFS:SetPoint("LEFT", peekBindRow, "LEFT", 0, 0)
	peekBindFS:SetWidth(232)
	peekBindFS:SetJustifyH("LEFT")

	local peekBindBtn = MakeButton(peekBindRow, "Set Keybind", 120, 22, OpenKeybindingsAndFlashPeek)
	peekBindBtn:SetPoint("LEFT", peekBindFS, "RIGHT", 0, 0)
	AttachTooltip(peekBindBtn, "Open Keybindings > PureFade",
		"Jumps straight to Options > Keybindings > PureFade and highlights 'Hold to Peek All UI' so you can bind any key or mouse button to temporarily reveal all faded UI.")

	peekBindRow.Refresh = function()
		local key1 = GetBindingKey and GetBindingKey("PUREFADE_PEEK_HOLD")
		if key1 and key1 ~= "" then
			peekBindFS:SetText("Hold to Peek All UI |cff66ff66(" .. key1 .. ")|r")
		else
			peekBindFS:SetText("Hold to Peek All UI |cff888888(Not Bound)|r")
		end
	end
	Add(peekBindRow, 32, "Hold to Peek All UI Keybind", "keybind hold peek reveal all ui shortcut")

	-- Minimap Button & Addon Compartment
	y = y - 6
	MakeSectionHeader(content, "Minimap Button & Addon Compartment", y)
	y = y - 22

	Add(MakeCheckbox(content, "Show Addon Compartment Button",
		"Show PureFade inside Blizzard's Minimap Addon Compartment dropdown (enabled by default).",
		function() return ns.GetDB().showCompartmentButton ~= false end,
		function(v)
			ns.GetDB().showCompartmentButton = v
			if ns.UpdateCompartmentButton then ns.UpdateCompartmentButton() end
		end
	), 26, "Show Addon Compartment Button", "addon compartment minimap dropdown button hide show")

	Add(MakeCheckbox(content, "Show Minimap Button",
		"Display an optional PureFade button on the Minimap border (Left-Click: Pause/Resume, Right-Click: Open Settings, Drag: Move). Hidden by default.",
		function() return ns.GetDB().showMinimapButton and true or false end,
		function(v)
			ns.GetDB().showMinimapButton = v
			if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		end
	), 26, "Show Minimap Button", "minimap button icon toggle hide show")

	Add(MakeCheckbox(content, "Lock Minimap Button",
		"Prevent dragging the Minimap button around the Minimap border.",
		function() return ns.GetDB().lockMinimapButton and true or false end,
		function(v) ns.GetDB().lockMinimapButton = v end
	), 28, "Lock Minimap Button", "minimap button lock drag position")

	local resetPosRow = CreateFrame("Frame", nil, content)
	resetPosRow:SetSize(560, 26)
	local resetPosBtn = MakeButton(resetPosRow, "Reset Minimap Position", 170, 22, function()
		if ns.ResetMinimapButtonPosition then
			ns.ResetMinimapButtonPosition()
			RefreshAllPages()
		end
	end)
	resetPosBtn:SetPoint("LEFT", resetPosRow, "LEFT", 0, 0)
	AttachTooltip(resetPosBtn, "Reset Minimap Position", "Returns the Minimap button to its default position on the Minimap rim (above PureGrid's button).")
	Add(resetPosRow, 30, "Reset Minimap Position", "minimap button reset position default angle")

	content:SetHeight(math.abs(y) + 20)

	local function Refresh()
		if not ns.GetDB() then return end
		for _, w in ipairs(widgets) do
			if w.Refresh then w:Refresh() end
		end
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		if ns.UpdateCompartmentButton then ns.UpdateCompartmentButton() end
	end
	canvas:HookScript("OnShow", Refresh)
	refreshCallbacks[#refreshCallbacks + 1] = Refresh
	return canvas
end

local ELEMENT_OPACITY_STEPS = { 0, 0.10, 0.20, 0.30, 0.40, 0.50 }

local function AddElementOpacitySubmenu(root, cfg)
	local label = cfg.fadedAlpha ~= nil
		and ("Faded Opacity: " .. math.floor(cfg.fadedAlpha * 100 + 0.5) .. "%")
		or "Faded Opacity: Global"
	local sub = root:CreateButton(label)
	sub:CreateRadio("Use Global Setting",
		function() return cfg.fadedAlpha == nil end,
		function()
			GuardEditable()
			cfg.fadedAlpha = nil
			if ns.ForceRefresh then ns.ForceRefresh() end
		end
	)
	for _, val in ipairs(ELEMENT_OPACITY_STEPS) do
		local pct = math.floor(val * 100 + 0.5)
		local optText = pct == 0 and "0% (Hidden)" or (pct .. "%")
		sub:CreateRadio(optText,
			function() return cfg.fadedAlpha ~= nil and math.abs(cfg.fadedAlpha - val) < 0.005 end,
			function()
				GuardEditable()
				cfg.fadedAlpha = val
				if ns.ForceRefresh then ns.ForceRefresh() end
			end
		)
	end
	root:CreateDivider()
end

--------------------------------------------------------------------------------
-- PAGE 2: ELEMENTS
--------------------------------------------------------------------------------
local function SummarizeTriggers(triggers)
	if not triggers then return "|cff888888None|r" end
	local names = {}
	for _, t in ipairs(ns.TRIGGERS) do
		if triggers[t.key] then
			names[#names + 1] = t.label
		end
	end
	if #names == 0 then return "|cff888888None|r", nil end
	local full = table.concat(names, "\n")
	if #names == 1 then return names[1], full end
	return names[1] .. " (+" .. (#names - 1) .. ")", full
end

local function BuildElementsPage()
	local canvas, content = CreateSettingsPage(
		"Elements",
		"Configure fade behavior, hover, group membership, and triggers for each WoW Forever UI element.",
		"elements"
	)

	local activeCategory = "all"
	local catButtons = {}
	local rowPool = {}

	-- Category filter bar (placed above the scroll frame)
	local filterBar = CreateFrame("Frame", nil, canvas)
	filterBar:SetPoint("TOPLEFT", canvas.divider, "BOTTOMLEFT", 0, -6)
	filterBar:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -24, -60)
	filterBar:SetHeight(52)

	-- Column headers
	local headerBar = CreateFrame("Frame", nil, canvas)
	headerBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
	headerBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -4)
	headerBar:SetHeight(20)

	local function ColHeader(text, x, w)
		local fs = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("LEFT", headerBar, "LEFT", x, 0)
		fs:SetWidth(w)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
	end
	ColHeader("UI Element", 4, 185)
	ColHeader("Group", 192, 110)
	ColHeader("Always", 308, 44)
	ColHeader("Hover", 356, 44)
	ColHeader("Show When (Triggers)", 406, 175)

	-- Bottom bar: 1-click Visual Frame Picker + optional Add by Name popup
	local bottomBar = CreateFrame("Frame", nil, canvas)
	bottomBar:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", 16, 10)
	bottomBar:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -24, 10)
	bottomBar:SetHeight(28)

	local pickElBtn = MakeButton(bottomBar, "Pick Frame on Screen", 165, 24, function()
		LaunchFramePicker("elements")
	end)
	pickElBtn:SetPoint("LEFT", bottomBar, "LEFT", 0, 0)
	AttachTooltip(pickElBtn, "Pick Frame on Screen", "Hides Settings so you can hover over any UI frame and Left-Click to add it or jump straight to its settings.")

	local addByNameBtn = MakeButton(bottomBar, "Add by Name", 105, 24, function()
		StaticPopup_Show("PUREFADE_ADD_CUSTOM_FRAME")
	end)
	addByNameBtn:SetPoint("LEFT", pickElBtn, "RIGHT", 8, 0)
	AttachTooltip(addByNameBtn, "Add Frame by Name", "Manually add a custom frame by its global frame name (useful for hidden or non-clickable frames).")

	local pickElHint = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pickElHint:SetPoint("LEFT", addByNameBtn, "RIGHT", 10, 0)
	pickElHint:SetPoint("RIGHT", bottomBar, "RIGHT", 0, 0)
	pickElHint:SetJustifyH("LEFT")
	pickElHint:SetTextColor(0.75, 0.75, 0.75)
	pickElHint:SetText("Click any frame on screen to manage or jump to it.")

	-- Reposition scroll frame between headerBar and bottomBar
	canvas.scroll:ClearAllPoints()
	canvas.scroll:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
	canvas.scroll:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT", -8, 8)

	local RefreshList

	-- Build category filter buttons (2 compact rows if needed)
	local cx, cy = 0, 0
	for _, cat in ipairs(ns.CATEGORIES) do
		local w = math.max(64, (#cat.label * 7) + 28)
		if cx + w > 580 then
			cx = 0
			cy = cy - 24
		end
		local b = MakeButton(filterBar, cat.label, w, 21, function()
			activeCategory = cat.key
			RefreshList()
		end)
		b:SetPoint("TOPLEFT", filterBar, "TOPLEFT", cx, cy)
		catButtons[cat.key] = b
		cx = cx + w + 4
	end

	local function GetRow(idx)
		if rowPool[idx] then
			return rowPool[idx]
		end
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(580, 26)

		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		if idx % 2 == 0 then
			bg:SetColorTexture(1, 1, 1, 0.04)
		else
			bg:SetColorTexture(0, 0, 0, 0)
		end
		row.bg = bg

		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.label:SetWidth(182)
		row.label:SetJustifyH("LEFT")
		row.label:SetWordWrap(false)

		row.groupBtn = MakeButton(row, "None", 106, 20)
		row.groupBtn:SetPoint("LEFT", row, "LEFT", 190, 0)

		row.alwaysCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.alwaysCB:SetSize(22, 22)
		row.alwaysCB:SetPoint("LEFT", row, "LEFT", 314, 0)

		row.hoverCB = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.hoverCB:SetSize(22, 22)
		row.hoverCB:SetPoint("LEFT", row, "LEFT", 360, 0)

		row.trigBtn = MakeButton(row, "None", 174, 20)
		row.trigBtn:SetPoint("LEFT", row, "LEFT", 404, 0)

		row.delBtn = MakeButton(row, "X", 22, 20)
		row.delBtn:SetPoint("LEFT", row.trigBtn, "RIGHT", 4, 0)
		row.delBtn:Hide()

		rowPool[idx] = row
		return row
	end

	RefreshList = function()
		local db = ns.GetDB()
		if not db then return end

		-- Highlight active category button
		for k, b in pairs(catButtons) do
			if k == activeCategory then
				b:Disable()
			else
				b:Enable()
			end
		end

		-- Collect items to show
		local items = {}
		if activeCategory ~= "custom" then
			for _, el in ipairs(ns.ELEMENTS) do
				if activeCategory == "all" or el.category == activeCategory then
					items[#items + 1] = { key = el.key, label = el.label, isCustom = false }
				end
			end
		end
		if (activeCategory == "all" or activeCategory == "custom") and db.customFrames then
			local names = {}
			for frameName in pairs(db.customFrames) do
				names[#names + 1] = frameName
			end
			table.sort(names)
			for _, frameName in ipairs(names) do
				items[#items + 1] = { key = frameName, label = frameName .. " |cff88ccff(Custom)|r", isCustom = true }
			end
		end

		-- Hide unused rows
		for i = #items + 1, #rowPool do
			rowPool[i]:Hide()
		end

		local y = 0
		for i, item in ipairs(items) do
			local row = GetRow(i)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
			row:Show()
			y = y - 26

			local cfg = item.isCustom and db.customFrames[item.key] or db.elements[item.key]
			if not cfg then
				cfg = { group = "None", alwaysShow = false, hover = true, triggers = {} }
				if item.isCustom then db.customFrames[item.key] = cfg else db.elements[item.key] = cfg end
			end
			cfg.triggers = cfg.triggers or {}

			row.itemKey = item.key
			row.label:SetText(item.label)
			row.groupBtn:SetText(cfg.group or "None")
			local isAlways = cfg.alwaysShow and true or false
			row.alwaysCB:SetChecked(isAlways)
			row.hoverCB:SetChecked(cfg.hover ~= false)
			local trigText, trigFull = SummarizeTriggers(cfg.triggers)
			row.trigBtn:SetWidth(item.isCustom and 148 or 174)
			row.trigBtn:SetText(trigText)
			row.trigBtn:SetEnabled(not isAlways)
			AttachTooltip(row.trigBtn, "Active Triggers",
				isAlways and "Disabled while Always Show is checked." or (trigFull or "None (only fades/reveals on hover or group sync)"))

			row.alwaysCB:SetScript("OnClick", function(self)
				if not GuardEditable() then self:SetChecked(cfg.alwaysShow and true or false); return end
				cfg.alwaysShow = self:GetChecked() and true or false
				row.trigBtn:SetEnabled(not cfg.alwaysShow)
				local _, curFull = SummarizeTriggers(cfg.triggers)
				AttachTooltip(row.trigBtn, "Active Triggers",
					cfg.alwaysShow and "Disabled while Always Show is checked." or (curFull or "None (only fades/reveals on hover or group sync)"))
				if ns.ForceRefresh then ns.ForceRefresh() end
			end)

			row.hoverCB:SetScript("OnClick", function(self)
				if not GuardEditable() then self:SetChecked(cfg.hover ~= false); return end
				cfg.hover = self:GetChecked() and true or false
				if ns.ForceRefresh then ns.ForceRefresh() end
			end)

			row.groupBtn:SetScript("OnClick", function(self)
				OpenDropdownMenu(self, function(root)
					root:CreateRadio("None",
						function() return (cfg.group or "None") == "None" end,
						function()
							GuardEditable()
							cfg.group = "None"
							RefreshAllPages()
							if ns.ForceRefresh then ns.ForceRefresh() end
						end
					)
					local gNames = {}
					for gName in pairs(db.groups or {}) do gNames[#gNames + 1] = gName end
					table.sort(gNames)
					for _, gName in ipairs(gNames) do
						root:CreateRadio(gName,
							function() return cfg.group == gName end,
							function()
								GuardEditable()
								cfg.group = gName
								RefreshAllPages()
								if ns.ForceRefresh then ns.ForceRefresh() end
							end
						)
					end
				end)
			end)

			row.trigBtn:SetScript("OnClick", function(self)
				OpenDropdownMenu(self, function(root)
					AddElementOpacitySubmenu(root, cfg)
					local lastSection
					for _, t in ipairs(ns.TRIGGERS) do
						if t.section ~= lastSection then
							if lastSection then root:CreateDivider() end
							root:CreateTitle(t.section)
							lastSection = t.section
						end
						root:CreateCheckbox(t.label,
							function() return cfg.triggers[t.key] and true or false end,
							function()
								GuardEditable()
								cfg.triggers[t.key] = not cfg.triggers[t.key]
								local newText, newFull = SummarizeTriggers(cfg.triggers)
								row.trigBtn:SetText(newText)
								AttachTooltip(row.trigBtn, "Active Triggers", newFull or "None (only fades/reveals on hover or group sync)")
								if ns.ForceRefresh then ns.ForceRefresh() end
							end
						)
					end
				end)
			end)

			if item.isCustom then
				row.delBtn:Show()
				row.delBtn:SetScript("OnClick", function()
					GuardEditable()
					db.customFrames[item.key] = nil
					if ns.RestoreAllFrames then ns.RestoreAllFrames() end
					if ns.ForceRefresh then ns.ForceRefresh() end
					RefreshAllPages()
				end)
			else
				row.delBtn:Hide()
			end
		end

		content:SetHeight(math.max(1, math.abs(y) + 12))
	end

	focusElementCallback = function(category, elementKey)
		activeCategory = category or "all"
		RefreshList()
		-- Scroll to and briefly highlight matching row
		C_Timer.After(0.03, function()
			for i, row in ipairs(rowPool) do
				if row:IsShown() and row.itemKey == elementKey then
					local targetY = math.max(0, ((i - 1) * 26) - 40)
					if canvas.scroll and canvas.scroll.SetVerticalScroll then
						local maxScroll = canvas.scroll.GetVerticalScrollRange and canvas.scroll:GetVerticalScrollRange() or 0
						canvas.scroll:SetVerticalScroll(math.min(targetY, maxScroll))
					end
					if row.bg then
						row.bg:SetColorTexture(1, 0.82, 0, 0.25)
						C_Timer.After(1.5, function()
							if row.bg then
								if i % 2 == 0 then
									row.bg:SetColorTexture(1, 1, 1, 0.04)
								else
									row.bg:SetColorTexture(0, 0, 0, 0)
								end
							end
						end)
					end
					break
				end
			end
		end)
	end

	canvas:HookScript("OnShow", RefreshList)
	refreshCallbacks[#refreshCallbacks + 1] = RefreshList
	return canvas
end

--------------------------------------------------------------------------------
-- PAGE 3: GROUPS
--------------------------------------------------------------------------------
local function BuildGroupsPage()
	local canvas, content = CreateSettingsPage(
		"Groups",
		"Group UI elements so they fade and reveal together. Assign elements to any group on the Elements page.",
		"groups"
	)

	local rowPool = {}
	local RefreshGroups

	-- Top bar: Create Group button + UI Layout preset selector
	local createBtn = MakeButton(content, "Create Group", 120, 24, function()
		StaticPopup_Show("PUREFADE_NEW_GROUP")
	end)
	createBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
	AttachTooltip(createBtn, "Create Group", "Create a new element group.")

	local function GetGroupMembers(db, groupName)
		local members = {}
		for _, el in ipairs(ns.ELEMENTS) do
			local cfg = db.elements and db.elements[el.key]
			if cfg and cfg.group == groupName then
				members[#members + 1] = el.label
			end
		end
		for _, entry in ipairs(ns.SUPPORTED_ADDONS or {}) do
			if ns.IsAddOnLoadedSafe(entry.addon) then
				local cfg = db.addons and db.addons[entry.key]
				if cfg and cfg.enabled ~= false and cfg.mode == "custom" and cfg.group == groupName then
					members[#members + 1] = entry.label
				end
			end
		end
		for frameName, cfg in pairs(db.customFrames or {}) do
			if (cfg.mode ~= "follow") and cfg.group == groupName then
				members[#members + 1] = frameName
			end
		end
		return members
	end

	local function GetCurrentUILayout(db)
		local microG = db and db.elements and db.elements.micro and db.elements.micro.group
		local bagsG = db and db.elements and db.elements.bags and db.elements.bags.group
		if microG == "Action Bars" and bagsG == "Action Bars" then
			return "blizzard"
		elseif microG == "Menu & Bags" and bagsG == "Menu & Bags" then
			return "separated"
		end
		return "custom"
	end

	local function ApplyUILayout(mode)
		GuardEditable()
		local db = ns.GetDB()
		if not db then return end
		db.groups = db.groups or {}
		db.elements = db.elements or {}
		db.elements.micro = db.elements.micro or { group = "None", alwaysShow = false, hover = true, triggers = {} }
		db.elements.bags = db.elements.bags or { group = "None", alwaysShow = false, hover = true, triggers = {} }

		if mode == "blizzard" then
			db.groups["Action Bars"] = db.groups["Action Bars"] or { syncMode = "all" }
			db.groups["Action Bars"].syncMode = "all"
			db.elements.micro.group = "Action Bars"
			db.elements.bags.group = "Action Bars"
			if db.groups["Menu & Bags"] and #GetGroupMembers(db, "Menu & Bags") == 0 then
				db.groups["Menu & Bags"] = nil
			end
		elseif mode == "separated" then
			db.groups["Menu & Bags"] = db.groups["Menu & Bags"] or { syncMode = "hover" }
			db.groups["Menu & Bags"].syncMode = "hover"
			db.elements.micro.group = "Menu & Bags"
			db.elements.bags.group = "Menu & Bags"
		end
		RefreshAllPages()
		if ns.ForceRefresh then ns.ForceRefresh() end
	end

	local layoutLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	layoutLabel:SetPoint("LEFT", createBtn, "RIGHT", 24, 0)
	layoutLabel:SetText("UI Layout:")

	local function BuildLayoutMenu(root)
		root:CreateRadio("Blizzard Default UI",
			function() return GetCurrentUILayout(ns.GetDB()) == "blizzard" end,
			function() ApplyUILayout("blizzard") end
		)
		root:CreateRadio("Separated Menu & Bags (Custom UI)",
			function() return GetCurrentUILayout(ns.GetDB()) == "separated" end,
			function() ApplyUILayout("separated") end
		)
	end

	local layoutDropdown
	local okLD, ld = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	if okLD and ld and ld.SetupMenu then
		ld:SetWidth(210)
		ld:SetPoint("LEFT", layoutLabel, "RIGHT", 8, 0)
		ld:SetupMenu(function(_, root)
			BuildLayoutMenu(root)
		end)
		layoutDropdown = ld
	else
		local fallbackBtn = MakeButton(content, "Blizzard Default UI", 210, 24, function(self)
			OpenDropdownMenu(self, BuildLayoutMenu)
		end)
		fallbackBtn:SetPoint("LEFT", layoutLabel, "RIGHT", 8, 0)
		layoutDropdown = fallbackBtn
	end
	AttachTooltip(layoutDropdown, "UI Layout Preset",
		"Blizzard Default UI: keeps Micro Menu & Bags Bar inside Action Bars so the bottom bar reveals as one piece.\n\nSeparated Menu & Bags: moves Micro Menu & Bags Bar into their own Hover-Only group (ideal for Edit Mode or Bartender4 corner layouts).")

	local function OpenGroupMembersMenu(owner, db, groupName)
		OpenDropdownMenu(owner, function(root)
			root:CreateTitle("Tick elements in '" .. groupName .. "'")
			for _, cat in ipairs(ns.CATEGORIES) do
				if cat.key ~= "all" and cat.key ~= "custom" then
					local sub = root:CreateButton(cat.label)
					for _, el in ipairs(ns.ELEMENTS) do
						if el.category == cat.key then
							local cfg = db.elements and db.elements[el.key]
							if cfg then
								sub:CreateCheckbox(el.label,
									function() return cfg.group == groupName end,
									function()
										GuardEditable()
										cfg.group = (cfg.group == groupName) and "None" or groupName
										RefreshAllPages()
										if ns.ForceRefresh then ns.ForceRefresh() end
									end
								)
							end
						end
					end
				end
			end
			-- Loaded addons using Custom Rules
			local customAddons = {}
			for _, entry in ipairs(ns.SUPPORTED_ADDONS or {}) do
				if ns.IsAddOnLoadedSafe(entry.addon) then
					local cfg = db.addons and db.addons[entry.key]
					if cfg and cfg.enabled ~= false and cfg.mode == "custom" then
						customAddons[#customAddons + 1] = { label = entry.label, cfg = cfg }
					end
				end
			end
			if #customAddons > 0 then
				root:CreateDivider()
				local sub = root:CreateButton("Addons (Custom Rules)")
				for _, item in ipairs(customAddons) do
					sub:CreateCheckbox(item.label,
						function() return item.cfg.group == groupName end,
						function()
							GuardEditable()
							item.cfg.group = (item.cfg.group == groupName) and "None" or groupName
							RefreshAllPages()
							if ns.ForceRefresh then ns.ForceRefresh() end
						end
					)
				end
			end
			-- Picked / Custom frames
			if db.customFrames and next(db.customFrames) then
				root:CreateDivider()
				local sub = root:CreateButton("Picked / Custom Frames")
				local cNames = {}
				for frameName in pairs(db.customFrames) do cNames[#cNames + 1] = frameName end
				table.sort(cNames)
				for _, frameName in ipairs(cNames) do
					local cfg = db.customFrames[frameName]
					sub:CreateCheckbox(frameName,
						function() return cfg.group == groupName end,
						function()
							GuardEditable()
							cfg.mode = "custom"
							cfg.group = (cfg.group == groupName) and "None" or groupName
							RefreshAllPages()
							if ns.ForceRefresh then ns.ForceRefresh() end
						end
					)
				end
			end
		end)
	end

	local function GetCard(idx)
		if rowPool[idx] then return rowPool[idx] end
		local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
		card:SetSize(565, 66)
		card:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		card:SetBackdropColor(0.08, 0.08, 0.08, 0.55)
		card:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)

		card.delBtn = MakeButton(card, "Delete", 64, 20)
		card.delBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)

		card.renameBtn = MakeButton(card, "Rename", 76, 20)
		card.renameBtn:SetPoint("RIGHT", card.delBtn, "LEFT", -4, 0)

		card.modeBtn = MakeButton(card, "", 176, 20)
		card.modeBtn:SetPoint("RIGHT", card.renameBtn, "LEFT", -4, 0)

		card.membersBtn = MakeButton(card, "Elements", 78, 20)
		card.membersBtn:SetPoint("RIGHT", card.modeBtn, "LEFT", -4, 0)

		card.nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		card.nameFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
		card.nameFS:SetPoint("RIGHT", card.membersBtn, "LEFT", -8, 0)
		card.nameFS:SetJustifyH("LEFT")

		card.membersFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		card.membersFS:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -35)
		card.membersFS:SetPoint("RIGHT", card, "RIGHT", -10, 0)
		card.membersFS:SetJustifyH("LEFT")
		card.membersFS:SetTextColor(0.8, 0.8, 0.8)

		rowPool[idx] = card
		return card
	end

	RefreshGroups = function()
		local db = ns.GetDB()
		if not db then return end

		local curLayout = GetCurrentUILayout(db)
		local layoutText = curLayout == "blizzard" and "Blizzard Default UI"
			or (curLayout == "separated" and "Separated Menu & Bags" or "Custom")
		if layoutDropdown.OverrideText then
			layoutDropdown:OverrideText(layoutText)
		elseif layoutDropdown.SetText then
			layoutDropdown:SetText(layoutText)
		end

		local gNames = {}
		for name in pairs(db.groups or {}) do
			gNames[#gNames + 1] = name
		end
		table.sort(gNames)

		for i = #gNames + 1, #rowPool do
			rowPool[i]:Hide()
		end

		local y = -40
		for i, gName in ipairs(gNames) do
			local gCfg = db.groups[gName]
			local card = GetCard(i)
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
			card:Show()

			card.nameFS:SetText(gName)
			local isHoverOnly = gCfg.syncMode == "hover"
			card.modeBtn:SetText(isHoverOnly and "Sync: Hover Only" or "Sync: Hover + Triggers")

			local members = GetGroupMembers(db, gName)
			if #members > 0 then
				card.membersFS:SetText("Elements: " .. table.concat(members, ", "))
			else
				card.membersFS:SetText("|cff888888No elements assigned yet (use Elements button above).|r")
			end

			local textH = card.membersFS:GetStringHeight() or 14
			local cardH = math.max(64, math.ceil(35 + textH + 12))
			card:SetHeight(cardH)

			card.membersBtn:SetScript("OnClick", function(self)
				OpenGroupMembersMenu(self, db, gName)
			end)

			card.modeBtn:SetScript("OnClick", function(self)
				OpenDropdownMenu(self, function(root)
					root:CreateRadio("Hover + Triggers (Fade Together)",
						function() return gCfg.syncMode ~= "hover" end,
						function()
							GuardEditable()
							gCfg.syncMode = "all"
							RefreshAllPages()
							if ns.ForceRefresh then ns.ForceRefresh() end
						end
					)
					root:CreateRadio("Hover Only",
						function() return gCfg.syncMode == "hover" end,
						function()
							GuardEditable()
							gCfg.syncMode = "hover"
							RefreshAllPages()
							if ns.ForceRefresh then ns.ForceRefresh() end
						end
					)
				end)
			end)

			card.renameBtn:SetScript("OnClick", function()
				StaticPopup_Show("PUREFADE_RENAME_GROUP", gName, nil, { oldName = gName })
			end)

			card.delBtn:SetScript("OnClick", function()
				if not GuardEditable() then return end
				db.groups[gName] = nil
				for _, cfg in pairs(db.elements or {}) do
					if cfg.group == gName then cfg.group = "None" end
				end
				for _, cfg in pairs(db.addons or {}) do
					if cfg.group == gName then cfg.group = "None" end
				end
				for _, cfg in pairs(db.customFrames or {}) do
					if cfg.group == gName then cfg.group = "None" end
				end
				RefreshAllPages()
				if ns.ForceRefresh then ns.ForceRefresh() end
			end)

			y = y - (cardH + 8)
		end

		content:SetHeight(math.max(1, math.abs(y) + 16))
	end

	canvas:HookScript("OnShow", RefreshGroups)
	refreshCallbacks[#refreshCallbacks + 1] = RefreshGroups
	return canvas
end

--------------------------------------------------------------------------------
-- PAGE 4: PROFILES
--------------------------------------------------------------------------------
local profileIOModal

local function ShowProfileIOModal(mode)
	if not profileIOModal then
		local f = CreateFrame("Frame", "PureFadeProfileIOModal", UIParent, "BackdropTemplate")
		f:SetSize(460, 230)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetToplevel(true)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
		f:SetBackdropBorderColor(0.8, 0.65, 0.2, 0.95)
		f:Hide()
		if UISpecialFrames then
			tinsert(UISpecialFrames, "PureFadeProfileIOModal")
		end

		f.titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		f.titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)

		f.hintFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		f.hintFS:SetPoint("TOPLEFT", f.titleFS, "BOTTOMLEFT", 0, -4)
		f.hintFS:SetTextColor(0.75, 0.75, 0.75)

		local boxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
		boxBg:SetPoint("TOPLEFT", f.hintFS, "BOTTOMLEFT", 0, -10)
		boxBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 56)
		boxBg:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 10,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		boxBg:SetBackdropColor(0.02, 0.02, 0.03, 0.95)
		boxBg:SetBackdropBorderColor(0.45, 0.45, 0.45, 0.85)

		local scroll = CreateFrame("ScrollFrame", nil, boxBg, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", boxBg, "TOPLEFT", 8, -6)
		scroll:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -28, 6)

		local eb = CreateFrame("EditBox", nil, scroll)
		eb:SetMultiLine(true)
		eb:SetAutoFocus(false)
		eb:SetFontObject(ChatFontNormal)
		eb:SetWidth(388)
		eb:SetScript("OnEscapePressed", function() f:Hide() end)
		scroll:SetScrollChild(eb)
		boxBg:EnableMouse(true)
		boxBg:SetScript("OnMouseDown", function() eb:SetFocus() end)
		f.editBox = eb

		f.errFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		f.errFS:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 36)
		f.errFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 36)
		f.errFS:SetJustifyH("LEFT")
		f.errFS:SetTextColor(1, 0.35, 0.35)
		f.errFS:Hide()

		f.primaryBtn = MakeButton(f, "Import", 110, 24)
		f.primaryBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)

		f.cancelBtn = MakeButton(f, "Close", 90, 24, function() f:Hide() end)
		f.cancelBtn:SetPoint("RIGHT", f.primaryBtn, "LEFT", -8, 0)

		profileIOModal = f
	end

	local f = profileIOModal
	f.errFS:Hide()
	f.errFS:SetText("")

	if mode == "export" then
		local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Default"
		f.titleFS:SetText("Export Profile: " .. active)
		f.hintFS:SetText("Press Ctrl+C to copy the profile string below.")
		f.primaryBtn:SetText("Close")
		f.primaryBtn:SetScript("OnClick", function() f:Hide() end)
		f.cancelBtn:Hide()
		local str = ns.ExportProfile and ns.ExportProfile() or ""
		f.editBox:SetText(str)
		f:Show()
		f.editBox:SetFocus()
		f.editBox:HighlightText()
	else
		f.titleFS:SetText("Import Profile")
		f.hintFS:SetText("Paste a PureFade profile string (PF1:...) below and click Import.")
		f.primaryBtn:SetText("Import")
		f.cancelBtn:SetText(CANCEL)
		f.cancelBtn:Show()
		f.editBox:SetText("")
		f.primaryBtn:SetScript("OnClick", function()
			local str = strtrim(f.editBox:GetText() or "")
			if str == "" then
				f.errFS:SetText("Please paste a PureFade profile string first.")
				f.errFS:Show()
				return
			end
			if ns.ValidateImportString then
				local ok, err = ns.ValidateImportString(str)
				if not ok then
					f.errFS:SetText(err or "Invalid profile string.")
					f.errFS:Show()
					return
				end
			end
			f:Hide()
			StaticPopup_Show("PUREFADE_IMPORT_NAME", nil, nil, { encoded = str })
		end)
		f:Show()
		f.editBox:SetFocus()
	end
end

local function BuildProfilesPage()
	local canvas, content = CreateSettingsPage(
		"Profiles",
		"Manage saved PureFade profiles. Editing settings while on Default automatically saves to Custom.",
		"all",
		true -- hide search bar on Profiles page
	)

	local y = -12

	-- Row 1: Active Profile dropdown + Rename + Delete
	local activeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	activeLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y - 5)
	activeLabel:SetWidth(120)
	activeLabel:SetJustifyH("LEFT")
	activeLabel:SetText("Active Profile:")

	local function BuildProfileMenu(root)
		for _, name in ipairs(ns.GetProfileNames()) do
			root:CreateRadio(name,
				function() return ns.GetActiveProfileName() == name end,
				function()
					ns.SetProfile(name)
					RefreshAllPages()
					if ns.ForceRefresh then ns.ForceRefresh() end
				end
			)
		end
	end

	local activeDropdown
	local okDD, dd = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	if okDD and dd and dd.SetupMenu then
		dd:SetWidth(210)
		dd:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
		dd:SetupMenu(function(_, root)
			BuildProfileMenu(root)
		end)
		activeDropdown = dd
	else
		local fallbackBtn = MakeButton(content, "Default", 210, 24, function(self)
			OpenDropdownMenu(self, BuildProfileMenu)
		end)
		fallbackBtn:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
		activeDropdown = fallbackBtn
	end

	local renameBtn = MakeButton(content, "Rename", 82, 24, function()
		local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Default"
		if active == "Default" then return end
		StaticPopup_Show("PUREFADE_RENAME_PROFILE", active, nil, { oldName = active })
	end)
	renameBtn:SetPoint("LEFT", activeDropdown, "RIGHT", 8, 0)
	AttachTooltip(renameBtn, "Rename Profile", "Rename the currently active profile (unavailable for Default).")

	local deleteBtn = MakeButton(content, "Delete", 82, 24, function()
		local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Default"
		if active == "Default" then return end
		StaticPopup_Show("PUREFADE_DELETE_PROFILE", active, nil, { name = active })
	end)
	deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 6, 0)
	AttachTooltip(deleteBtn, "Delete Profile", "Delete the currently active profile (unavailable for Default).")
	y = y - 46

	-- Row 2: Create New Profile (from current settings)
	local newBtn = MakeButton(content, "New Profile", 150, 24, function()
		StaticPopup_Show("PUREFADE_NEW_PROFILE")
	end)
	newBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	AttachTooltip(newBtn, "New Profile", "Create a new profile copied from your currently active settings.")
	y = y - 44

	-- Row 3: Export & Import
	local expBtn = MakeButton(content, "Export", 110, 24, function()
		ShowProfileIOModal("export")
	end)
	expBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
	AttachTooltip(expBtn, "Export Profile", "Opens a window with a copyable string for your currently active profile.")

	local impBtn = MakeButton(content, "Import", 110, 24, function()
		ShowProfileIOModal("import")
	end)
	impBtn:SetPoint("LEFT", expBtn, "RIGHT", 8, 0)
	AttachTooltip(impBtn, "Import Profile", "Opens a window to paste a PureFade profile string and save it as a new profile.")
	y = y - 40

	content:SetHeight(math.abs(y) + 20)

	local function RefreshProfiles()
		local active = ns.GetActiveProfileName and ns.GetActiveProfileName() or "Default"
		if activeDropdown.OverrideText then
			activeDropdown:OverrideText(active)
		elseif activeDropdown.SetText then
			activeDropdown:SetText(active)
		end

		local isDefault = (active == "Default")
		renameBtn:SetEnabled(not isDefault)
		deleteBtn:SetEnabled(not isDefault)
	end

	canvas:HookScript("OnShow", RefreshProfiles)
	refreshCallbacks[#refreshCallbacks + 1] = RefreshProfiles
	return canvas
end

--------------------------------------------------------------------------------
-- PAGE 4: ADDONS (3rd-Party Addon Integration + Visual Frame Picker)
--------------------------------------------------------------------------------
local function GetElementLabel(key)
	local el = ns.ELEMENT_BY_KEY and ns.ELEMENT_BY_KEY[key]
	return el and el.label or key or "None"
end

local function OpenFollowMenu(owner, cfg, onChanged)
	OpenDropdownMenu(owner, function(root)
		root:CreateRadio("Custom Rules (Independent)",
			function() return cfg.mode == "custom" end,
			function()
				GuardEditable()
				cfg.mode = "custom"
				cfg.follow = "None"
				onChanged()
			end
		)
		root:CreateDivider()
		root:CreateTitle("Follow a Blizzard Element")
		for _, cat in ipairs(ns.CATEGORIES) do
			if cat.key ~= "all" and cat.key ~= "custom" then
				local sub = root:CreateButton(cat.label)
				for _, el in ipairs(ns.ELEMENTS) do
					if el.category == cat.key then
						sub:CreateRadio(el.label,
							function() return cfg.mode == "follow" and cfg.follow == el.key end,
							function()
								GuardEditable()
								cfg.mode = "follow"
								cfg.follow = el.key
								onChanged()
							end
						)
					end
				end
			end
		end
	end)
end

local function BuildAddonsPage()
	local canvas, content = CreateSettingsPage(
		"Addons",
		"Integrate 3rd-party addons (like Questie) by following a Blizzard element's rules or setting custom rules.",
		"addons"
	)

	local cardPool = {}
	local headerPool = {}
	local expandedAddons = {} -- [sectionName] = true when expanded
	local RefreshAddons

	local function GetSectionHeader(idx)
		if headerPool[idx] then return headerPool[idx] end
		local hdr = CreateFrame("Button", nil, content, "BackdropTemplate")
		hdr:SetSize(565, 28)
		hdr:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		hdr:SetBackdropColor(0.14, 0.13, 0.10, 0.85)
		hdr:SetBackdropBorderColor(0.55, 0.48, 0.30, 0.85)

		local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.12)

		hdr.iconFS = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		hdr.iconFS:SetPoint("LEFT", hdr, "LEFT", 10, 0)
		hdr.iconFS:SetWidth(20)
		hdr.iconFS:SetJustifyH("CENTER")

		hdr.titleFS = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		hdr.titleFS:SetPoint("LEFT", hdr.iconFS, "RIGHT", 4, 0)
		hdr.titleFS:SetJustifyH("LEFT")

		hdr.countFS = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hdr.countFS:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
		hdr.countFS:SetJustifyH("RIGHT")
		hdr.countFS:SetTextColor(0.75, 0.75, 0.75)

		headerPool[idx] = hdr
		return hdr
	end

	local function FocusAddonCard(targetKey)
		-- Auto-expand the addon section containing targetKey
		local entry = ns.SUPPORTED_ADDON_BY_KEY and ns.SUPPORTED_ADDON_BY_KEY[targetKey]
		if entry then
			expandedAddons[entry.addon] = true
		else
			expandedAddons["Picked / Custom Frames"] = true
		end
		if RefreshAddons then RefreshAddons() end
		C_Timer.After(0.04, function()
			for _, card in ipairs(cardPool) do
				if card:IsShown() and card.itemKey == targetKey then
					local targetY = math.max(0, (card.posY or 0) - 40)
					if canvas.scroll and canvas.scroll.SetVerticalScroll then
						local maxScroll = canvas.scroll.GetVerticalScrollRange and canvas.scroll:GetVerticalScrollRange() or 0
						canvas.scroll:SetVerticalScroll(math.min(targetY, maxScroll))
					end
					card:SetBackdropBorderColor(1, 0.82, 0, 1)
					C_Timer.After(1.6, function()
						if card and card.SetBackdropBorderColor then
							card:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)
						end
					end)
					break
				end
			end
		end)
	end

	focusAddonCallback = FocusAddonCard

	-- Top toolbar inside content: Pick Frame on Screen
	local toolBar = CreateFrame("Frame", nil, content)
	toolBar:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
	toolBar:SetSize(565, 30)

	local pickBtn = MakeButton(toolBar, "Pick Frame on Screen", 165, 24, function()
		LaunchFramePicker("addons")
	end)
	pickBtn:SetPoint("LEFT", toolBar, "LEFT", 0, 0)
	AttachTooltip(pickBtn, "Pick Frame on Screen", "Hides Settings so you can hover over any unsupported addon frame and Left-Click to add it to PureFade.")

	local pickHint = toolBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pickHint:SetPoint("LEFT", pickBtn, "RIGHT", 10, 0)
	pickHint:SetPoint("RIGHT", toolBar, "RIGHT", 0, 0)
	pickHint:SetJustifyH("LEFT")
	pickHint:SetTextColor(0.75, 0.75, 0.75)
	pickHint:SetText("Add any unsupported addon frame with 1 click.")

	local emptyNotice = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	emptyNotice:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -64)
	emptyNotice:SetWidth(555)
	emptyNotice:SetJustifyH("LEFT")
	emptyNotice:SetTextColor(0.75, 0.75, 0.75)
	emptyNotice:Hide()

	local footerHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	footerHeader:SetJustifyH("LEFT")
	footerHeader:SetText("Other Built-In Supported Addons (Not Currently Loaded):")

	local footerList = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footerList:SetWidth(555)
	footerList:SetJustifyH("LEFT")
	footerList:SetTextColor(0.65, 0.65, 0.65)

	local function GetAddonCard(idx)
		if cardPool[idx] then return cardPool[idx] end
		local card = CreateFrame("Frame", nil, content, "BackdropTemplate")
		card:SetSize(565, 68)
		card:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		card:SetBackdropColor(0.08, 0.08, 0.08, 0.55)
		card:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)

		-- Top row: Enable checkbox + Name + Mode dropdown + optional Delete button
		card.enableCB = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
		card.enableCB:SetSize(22, 22)
		card.enableCB:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -7)

		card.nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		card.nameFS:SetPoint("LEFT", card.enableCB, "RIGHT", 4, 0)
		card.nameFS:SetWidth(240)
		card.nameFS:SetJustifyH("LEFT")
		card.nameFS:SetWordWrap(false)

		card.delBtn = MakeButton(card, "X", 22, 20)
		card.delBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
		card.delBtn:Hide()

		card.modeBtn = MakeButton(card, "Follow: Quest Tracker", 200, 20)
		card.modeBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)

		-- Bottom row A: Follow summary text
		card.followFS = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		card.followFS:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 10)
		card.followFS:SetPoint("RIGHT", card, "RIGHT", -12, 0)
		card.followFS:SetJustifyH("LEFT")
		card.followFS:SetTextColor(0.75, 0.85, 1)

		-- Bottom row B: Custom rules inline bar
		local bar = CreateFrame("Frame", nil, card)
		bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 6)
		bar:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
		bar:SetHeight(24)

		bar.groupLbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.groupLbl:SetPoint("LEFT", bar, "LEFT", 0, 0)
		bar.groupLbl:SetText("Group:")

		bar.groupBtn = MakeButton(bar, "None", 104, 20)
		bar.groupBtn:SetPoint("LEFT", bar.groupLbl, "RIGHT", 4, 0)

		bar.alwaysCB = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
		bar.alwaysCB:SetSize(22, 22)
		bar.alwaysCB:SetPoint("LEFT", bar.groupBtn, "RIGHT", 12, 0)
		bar.alwaysLbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.alwaysLbl:SetPoint("LEFT", bar.alwaysCB, "RIGHT", 2, 0)
		bar.alwaysLbl:SetText("Always")

		bar.hoverCB = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
		bar.hoverCB:SetSize(22, 22)
		bar.hoverCB:SetPoint("LEFT", bar.alwaysLbl, "RIGHT", 10, 0)
		bar.hoverLbl = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.hoverLbl:SetPoint("LEFT", bar.hoverCB, "RIGHT", 2, 0)
		bar.hoverLbl:SetText("Hover")

		bar.trigBtn = MakeButton(bar, "None", 160, 20)
		bar.trigBtn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)

		card.customBar = bar
		cardPool[idx] = card
		return card
	end

	RefreshAddons = function()
		local db = ns.GetDB()
		if not db then return end
		db.addons = db.addons or {}

		local sectionsByName = {}
		local sectionOrder = {}
		local notLoadedSeen, notLoadedNames = {}, {}

		local function EnsureSection(name)
			if not sectionsByName[name] then
				sectionsByName[name] = {}
				sectionOrder[#sectionOrder + 1] = name
			end
			return sectionsByName[name]
		end

		-- 1. Loaded built-in supported addons grouped by addon name
		for _, entry in ipairs(ns.SUPPORTED_ADDONS or {}) do
			if ns.IsAddOnLoadedSafe(entry.addon) then
				local cfg = db.addons[entry.key]
				if not cfg then
					cfg = {
						enabled = true,
						mode = entry.defaultMode or "follow",
						follow = entry.defaultFollow or "None",
						group = "None",
						alwaysShow = entry.defaultAlwaysShow and true or false,
						hover = true,
						triggers = {},
					}
					db.addons[entry.key] = cfg
				end
				local sec = EnsureSection(entry.addon)
				sec[#sec + 1] = { label = entry.label, cfg = cfg, isCustom = false, key = entry.key }
			else
				if not notLoadedSeen[entry.addon] then
					notLoadedSeen[entry.addon] = true
					notLoadedNames[#notLoadedNames + 1] = entry.addon
				end
			end
		end
		table.sort(sectionOrder)

		-- 2. Custom / Picked addon frames in their own section at the bottom
		if db.customFrames and next(db.customFrames) then
			local cNames = {}
			for frameName in pairs(db.customFrames) do cNames[#cNames + 1] = frameName end
			table.sort(cNames)
			local sec = EnsureSection("Picked / Custom Frames")
			for _, frameName in ipairs(cNames) do
				local cfg = db.customFrames[frameName]
				if cfg.mode == nil then cfg.mode = "custom" end
				if cfg.follow == nil then cfg.follow = "None" end
				sec[#sec + 1] = {
					label = frameName .. " |cff88ccff(Picked/Custom)|r",
					cfg = cfg,
					isCustom = true,
					key = frameName,
				}
			end
		end

		for i = 1, #headerPool do headerPool[i]:Hide() end
		for i = 1, #cardPool do cardPool[i]:Hide() end

		local y = -44
		local headerIdx = 0
		local cardIdx = 0

		if #sectionOrder == 0 then
			emptyNotice:SetText("No built-in supported addons are currently loaded. Use 'Pick Frame on Screen' above to add any addon frame.")
			emptyNotice:Show()
			y = -92
		else
			emptyNotice:Hide()
			for _, secName in ipairs(sectionOrder) do
				local secItems = sectionsByName[secName]
				local isOpen = expandedAddons[secName] and true or false

				headerIdx = headerIdx + 1
				local hdr = GetSectionHeader(headerIdx)
				hdr:ClearAllPoints()
				hdr:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y)
				hdr.iconFS:SetText(isOpen and "-" or "+")
				hdr.titleFS:SetText(secName)

				local enabledCount = 0
				for _, it in ipairs(secItems) do
					if it.isCustom or it.cfg.enabled ~= false then
						enabledCount = enabledCount + 1
					end
				end
				local noun = #secItems == 1 and "element" or "elements"
				hdr.countFS:SetText(("%d %s (%d enabled)"):format(#secItems, noun, enabledCount))
				hdr:SetScript("OnClick", function()
					expandedAddons[secName] = not expandedAddons[secName]
					RefreshAddons()
				end)
				hdr:Show()
				y = y - 34

				if isOpen then
					for _, item in ipairs(secItems) do
						cardIdx = cardIdx + 1
						local cfg = item.cfg
						cfg.triggers = cfg.triggers or {}
						local card = GetAddonCard(cardIdx)
						card:ClearAllPoints()
						card:SetPoint("TOPLEFT", content, "TOPLEFT", 14, y)
						card:SetWidth(555)
						card.posY = math.abs(y)
						card:Show()

						card.itemKey = item.key
						card.nameFS:SetText(item.label)

				if item.isCustom then
					card.enableCB:Hide()
					card.nameFS:ClearAllPoints()
					card.nameFS:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
					card.delBtn:Show()
					card.modeBtn:ClearAllPoints()
					card.modeBtn:SetPoint("RIGHT", card.delBtn, "LEFT", -6, 0)
					card.delBtn:SetScript("OnClick", function()
						GuardEditable()
						db.customFrames[item.key] = nil
						if ns.RestoreAllFrames then ns.RestoreAllFrames() end
						if ns.ForceRefresh then ns.ForceRefresh() end
						RefreshAllPages()
					end)
				else
					card.enableCB:Show()
					card.enableCB:SetChecked(cfg.enabled ~= false)
					card.nameFS:ClearAllPoints()
					card.nameFS:SetPoint("LEFT", card.enableCB, "RIGHT", 4, 0)
					card.delBtn:Hide()
					card.modeBtn:ClearAllPoints()
					card.modeBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
					card.enableCB:SetScript("OnClick", function(self)
						if not GuardEditable() then self:SetChecked(cfg.enabled ~= false); return end
						cfg.enabled = self:GetChecked() and true or false
						if ns.ForceRefresh then ns.ForceRefresh() end
						RefreshAllPages()
					end)
				end

				local isFollow = (cfg.mode == "follow" and cfg.follow and cfg.follow ~= "None")
				if isFollow then
					local elLabel = GetElementLabel(cfg.follow)
					card.modeBtn:SetText("Follow: " .. elLabel)
					card.followFS:SetText("Following |cffffff00" .. elLabel .. "|r — inherits its Group, Always, Hover & Triggers.")
					card.followFS:Show()
					card.customBar:Hide()
				else
					card.modeBtn:SetText("Custom Rules")
					card.followFS:Hide()
					card.customBar:Show()

					local bar = card.customBar
					local isAlways = cfg.alwaysShow and true or false
					bar.groupBtn:SetText(cfg.group or "None")
					bar.alwaysCB:SetChecked(isAlways)
					bar.hoverCB:SetChecked(cfg.hover ~= false)
					local trigText, trigFull = SummarizeTriggers(cfg.triggers)
					bar.trigBtn:SetText(trigText)
					bar.trigBtn:SetEnabled(not isAlways)
					AttachTooltip(bar.trigBtn, "Active Triggers",
						isAlways and "Disabled while Always Show is checked." or (trigFull or "None (only fades/reveals on hover or group sync)"))

					bar.alwaysCB:SetScript("OnClick", function(self)
						if not GuardEditable() then self:SetChecked(cfg.alwaysShow and true or false); return end
						cfg.alwaysShow = self:GetChecked() and true or false
						bar.trigBtn:SetEnabled(not cfg.alwaysShow)
						local _, curFull = SummarizeTriggers(cfg.triggers)
						AttachTooltip(bar.trigBtn, "Active Triggers",
							cfg.alwaysShow and "Disabled while Always Show is checked." or (curFull or "None (only fades/reveals on hover or group sync)"))
						if ns.ForceRefresh then ns.ForceRefresh() end
					end)
					bar.hoverCB:SetScript("OnClick", function(self)
						if not GuardEditable() then self:SetChecked(cfg.hover ~= false); return end
						cfg.hover = self:GetChecked() and true or false
						if ns.ForceRefresh then ns.ForceRefresh() end
					end)
					bar.groupBtn:SetScript("OnClick", function(self)
						OpenDropdownMenu(self, function(root)
							root:CreateRadio("None",
								function() return (cfg.group or "None") == "None" end,
								function()
									GuardEditable()
									cfg.group = "None"
									RefreshAllPages()
									if ns.ForceRefresh then ns.ForceRefresh() end
								end
							)
							local gNames = {}
							for gName in pairs(db.groups or {}) do gNames[#gNames + 1] = gName end
							table.sort(gNames)
							for _, gName in ipairs(gNames) do
								root:CreateRadio(gName,
									function() return cfg.group == gName end,
									function()
										GuardEditable()
										cfg.group = gName
										RefreshAllPages()
										if ns.ForceRefresh then ns.ForceRefresh() end
									end
								)
							end
						end)
					end)
					bar.trigBtn:SetScript("OnClick", function(self)
						OpenDropdownMenu(self, function(root)
							AddElementOpacitySubmenu(root, cfg)
							local lastSection
							for _, t in ipairs(ns.TRIGGERS) do
								if t.section ~= lastSection then
									if lastSection then root:CreateDivider() end
									root:CreateTitle(t.section)
									lastSection = t.section
								end
								root:CreateCheckbox(t.label,
									function() return cfg.triggers[t.key] and true or false end,
									function()
										GuardEditable()
										cfg.triggers[t.key] = not cfg.triggers[t.key]
										local nt, nf = SummarizeTriggers(cfg.triggers)
										bar.trigBtn:SetText(nt)
										AttachTooltip(bar.trigBtn, "Active Triggers", nf or "None")
										if ns.ForceRefresh then ns.ForceRefresh() end
									end
								)
							end
						end)
					end)
				end

				card.modeBtn:SetScript("OnClick", function(self)
					OpenFollowMenu(self, cfg, function()
						RefreshAllPages()
						if ns.ForceRefresh then ns.ForceRefresh() end
					end)
				end)

				y = y - 74
					end
				end
			end
		end

		-- Footer showing other built-in supported addons
		y = y - 8
		footerHeader:ClearAllPoints()
		footerHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
		y = y - 18
		footerList:ClearAllPoints()
		footerList:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
		if #notLoadedNames > 0 then
			table.sort(notLoadedNames)
			footerList:SetText(table.concat(notLoadedNames, ", "))
		else
			footerList:SetText("All built-in supported addons are currently loaded!")
		end

		content:SetHeight(math.max(1, math.abs(y) + 40))
	end

	canvas:HookScript("OnShow", RefreshAddons)
	refreshCallbacks[#refreshCallbacks + 1] = RefreshAddons
	return canvas
end

--------------------------------------------------------------------------------
-- REGISTER IN BLIZZARD OPTIONS -> ADDONS
--------------------------------------------------------------------------------
function ns.InitUI()
	local generalCanvas  = BuildGeneralPage()
	local elementsCanvas = BuildElementsPage()
	local groupsCanvas   = BuildGroupsPage()
	local addonsCanvas   = BuildAddonsPage()
	local profilesCanvas = BuildProfilesPage()

	pageCanvases.general  = generalCanvas
	pageCanvases.elements = elementsCanvas
	pageCanvases.groups   = groupsCanvas
	pageCanvases.addons   = addonsCanvas
	pageCanvases.profiles = profilesCanvas

	if Settings and Settings.RegisterCanvasLayoutCategory then
		mainCategory = Settings.RegisterCanvasLayoutCategory(generalCanvas, "PureFade")
		subCategories.general  = mainCategory
		subCategories.elements = Settings.RegisterCanvasLayoutSubcategory(mainCategory, elementsCanvas, "Elements")
		subCategories.groups   = Settings.RegisterCanvasLayoutSubcategory(mainCategory, groupsCanvas, "Groups")
		subCategories.addons   = Settings.RegisterCanvasLayoutSubcategory(mainCategory, addonsCanvas, "Addons")
		subCategories.profiles = Settings.RegisterCanvasLayoutSubcategory(mainCategory, profilesCanvas, "Profiles")
		Settings.RegisterAddOnCategory(mainCategory)
	end
end

function ns.OpenSettings()
	if InCombatLockdown and InCombatLockdown() then
		print("|cff66ccffPureFade:|r Cannot open Blizzard Settings during combat. Try again after combat.")
		return
	end
	if mainCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(mainCategory:GetID())
	end
end
