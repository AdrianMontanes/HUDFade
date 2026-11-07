-- HUD Fade options: a page in the game's AddOns settings, and the /hudfade command.

local _, ns = ...
local HUDFade = ns.core
local say = HUDFade.Print

local panel = CreateFrame("Frame")
panel.name = "HUD Fade"
panel:Hide()

-- A second page, listed under HUD Fade in the game's settings.
local shiftPanel = CreateFrame("Frame")
shiftPanel.name = "Burn-in protection"
shiftPanel:Hide()

local canvas = panel -- the page the helpers below draw on

local widgets = {}  -- every setting below the on/off switch
local dimmable = {} -- headers, greyed out with them while the addon is off

local function db() return HUDFade.db end

local function header(text, y, alwaysOn)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	if not alwaysOn then dimmable[#dimmable + 1] = fs end
	return fs
end

local function note(text, y, x)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x or 16, y)
	fs:SetWidth(560)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- Addons can't open web pages, so an address goes in a read-only box that selects itself for Ctrl+C.
local function copyBox(label, url, y)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", 20, y - 3)
	fs:SetText(label)
	local box = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
	box:SetPoint("TOPLEFT", 150, y)
	box:SetSize(360, 20)
	box:SetAutoFocus(false)
	local function reset(self)
		self:SetText(url)
		self:SetCursorPosition(0)
	end
	reset(box)
	box:SetScript("OnTextChanged", function(self, typed)
		if typed then
			reset(self)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return box
end

local function checkbox(key, label, tip, y, x, onChange, master)
	local cb = CreateFrame("CheckButton", nil, canvas, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x or 16, y)
	cb:SetSize(26, 26)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	local function text() return type(label) == "function" and label() or label end
	fs:SetText(text())
	cb:SetScript("OnClick", function(self)
		db()[key] = self:GetChecked() and true or false
		if onChange then onChange() end
		HUDFade.Update()
	end)
	if tip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(text(), 1, 1, 1)
			GameTooltip:AddLine(tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	cb.refresh = function()
		cb:SetChecked(db()[key] and true or false)
		fs:SetText(text())
	end
	cb.setActive = function(on)
		if on then cb:Enable() else cb:Disable() end
		fs:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
	end
	if not master then widgets[#widgets + 1] = cb end
	return cb
end

-- scale: the setting is the slider's value divided by this. Or a list of the values the slider stops at, in order
-- (then minV, maxV and step are ignored).
local function slider(key, label, minV, maxV, step, y, x, fmt, scale, tip)
	local stops = type(scale) == "table" and scale or nil
	if stops then minV, maxV, step, scale = 1, #stops, 1, 1 end
	scale = scale or 1
	local s = CreateFrame("Slider", nil, canvas, BackdropTemplateMixin and "BackdropTemplate" or nil)
	s:SetPoint("TOPLEFT", (x or 16) + 4, y - 18)
	s:SetSize(220, 16)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	if s.SetBackdrop then
		s:SetBackdrop({
			bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
			edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 3, right = 3, top = 6, bottom = 6 },
		})
	end
	local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", -4, 4)
	local function show(v)
		local text = type(fmt) == "function" and fmt(v) or string.format(fmt, v)
		title:SetText(label .. ": |cffffffff" .. text .. "|r")
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		if stops then v = stops[math.max(1, math.min(#stops, v))] end
		db()[key] = v / scale
		show(v)
		HUDFade.Update()
	end)
	s.refresh = function()
		local v = (db()[key] or 0) * scale
		if stops then
			local best = 1
			for i, stop in ipairs(stops) do
				if math.abs(stop - v) < math.abs(stops[best] - v) then best = i end
			end
			s:SetValue(best)
		else
			s:SetValue(v)
		end
		show(v)
	end
	if tip then
		s:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	s.setActive = function(on)
		if s.SetEnabled then s:SetEnabled(on) end
		s:EnableMouse(on)
		s:SetAlpha(on and 1 or 0.5)
		title:SetAlpha(on and 1 or 0.5)
	end
	widgets[#widgets + 1] = s
	return s
end

local function pageTitle(text)
	local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(text)
end

local function shiftChanged()
	HUDFade.UpdateShift()
	if HUDFade.RefreshOptions then HUDFade.RefreshOptions() end -- the switch is on both pages
end

local SHIFT_TIP = "Moves the whole interface a pixel or two every few minutes, so nothing sits on the same pixels "
	.. "for hours. Everything moves together, so your layout stays as it is. Distance and timing are on the "
	.. "Burn-in protection page under HUD Fade."

-- A scrolling page, so the last settings don't spill past the bottom of a short settings window.
local function scrollPage(page, height)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, page, "ScrollFrameTemplate")
	if not ok then ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, page, "UIPanelScrollFrameTemplate") end
	if not ok then scroll = CreateFrame("ScrollFrame", nil, page) end
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4) -- room for the scroll bar
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, height)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(_, w)
		if type(w) == "number" and w > 0 then content:SetWidth(w) end
	end)
	if not scroll:GetScript("OnMouseWheel") then -- the templates handle the wheel themselves
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	return content
end

-- Preset menu above the "also hide" checkboxes.
local presetWidget
local function presetName()
	local i = HUDFade.CurrentPreset()
	return i and HUDFade.PRESETS[i].name or "Custom"
end
local function presetChanged()
	if presetWidget then presetWidget.refresh() end
end
local refreshAll -- defined below
local function choosePreset(i)
	HUDFade.ApplyPreset(i)
	refreshAll()
end

local PRESET_TIP = "Everything: names, nameplates, the target circle and glow all go with the HUD. "
	.. "Blizzard: as with the game's own Hide UI (Alt+Z), names, chat bubbles, the target circle and glow stay; "
	.. "nameplates go. Either way you keep the fade, idle hiding and the rest. "
	.. "Change a box below and it shows as Custom."

local function presetMenu(y)
	local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", 20, y - 6)
	title:SetText("Preset")
	local w
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, canvas, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetPoint("TOPLEFT", 80, y)
		dd:SetWidth(240)
		if dd.SetDefaultText then dd:SetDefaultText("Custom") end -- shown when the boxes match no preset
		dd:SetupMenu(function(_, root)
			for i, p in ipairs(HUDFade.PRESETS) do
				local function isSelected() return HUDFade.CurrentPreset() == i end
				root:CreateRadio(p.name, isSelected, function() choosePreset(i) end)
			end
		end)
		w = dd
		w.refresh = function() if dd.GenerateMenu then dd:GenerateMenu() end end
	else
		-- No dropdown template in this client: a button that cycles through the presets.
		w = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
		w:SetPoint("TOPLEFT", 80, y)
		w:SetSize(240, 22)
		w:SetScript("OnClick", function() choosePreset((HUDFade.CurrentPreset() or 0) % #HUDFade.PRESETS + 1) end)
		w.refresh = function() w:SetText(presetName()) end
	end
	local hook = w.HookScript or w.SetScript
	hook(w, "OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Preset: " .. presetName(), 1, 1, 1)
		GameTooltip:AddLine(PRESET_TIP, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	hook(w, "OnLeave", function() GameTooltip:Hide() end)
	w.setActive = function(on)
		if w.SetEnabled then w:SetEnabled(on) end
		title:SetAlpha(on and 1 or 0.5)
	end
	presetWidget = w
	widgets[#widgets + 1] = w
end

local built = false
local function build()
	if built then return end
	built = true
	canvas = scrollPage(panel, 820)
	pageTitle("HUD Fade")
	note("Fades the whole interface at once, Blizzard UI and EllesmereUI together, to protect OLED screens and "
		.. "take clean screenshots. Bind keys under Key Bindings > AddOns > HUD Fade.", -40)

	panel.master = checkbox("enabled", "Enable HUD Fade",
		"Off: the HUD stays visible, names and minimap stay as they are, and your Hide UI key does its normal job. "
		.. "No reload needed. You can also bind a key for this under Key Bindings > AddOns.",
		-76, 16, function() HUDFade.SetEnabled(db().enabled) end, true)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", SHIFT_TIP, -76, 320, shiftChanged)

	-- The player's own Hide UI and screenshot keys, read each time the page opens.
	local function keyName(action)
		local key = GetBindingKey(action)
		return key and (GetBindingText and GetBindingText(key) or key) or "not bound"
	end

	header("General", -120)
	checkbox("replaceAltZ", function() return "Use Hide UI key (" .. keyName("TOGGLEUI") .. ")" end,
		"Your Hide UI key fades the HUD out and back in instead of switching it off. While hidden this way it "
		.. "stays hidden until you press the key again, except for a moment when combat, a window, typing or "
		.. "dying needs it (if ticked below). A new target or a cast doesn't bring it back.\n\nThe NVIDIA "
		.. "overlay uses Alt+Z too. If Alt+Z opens it, change the overlay's shortcut in the NVIDIA app, or bind "
		.. "Hide UI to another key.",
		-140, 16, HUDFade.ApplyOverrides)
	checkbox("startHidden", "Start hidden", "Each session starts with the HUD hidden.", -140, 320)
	checkbox("cleanPrintScreen", function() return "HUD-free screenshots (" .. keyName("SCREENSHOT") .. ")" end,
		"Your screenshot key hides the HUD for a moment, takes the picture, and brings it back. "
		.. "There is also a separate key for this under Key Bindings > AddOns.\n\nScreenshots taken by other "
		.. "apps, like NVIDIA's Alt+F1, can't hide the HUD: hide it first with your Hide UI key.",
		-166, 16, HUDFade.ApplyOverrides)
	checkbox("minimapButton", "Minimap button",
		"Left-click it for these settings, right-click to turn HUD Fade on or off, and shift-click for a "
		.. "screenshot without the HUD. Drag it to move it around the minimap.",
		-166, 320, function() HUDFade.UpdateMinimapButton() end)

	header("While HUD is hidden, also hide", -206)
	presetMenu(-226)
	checkbox("hideNames", "Names and chat bubbles",
		"The floating names and chat bubbles above characters are part of the game world, not the UI, so they are "
		.. "switched off while the HUD is hidden and back on after. Your target's own name is the exception: "
		.. "the game always shows it.",
		-258, 16, presetChanged)
	checkbox("hideNameplates", "Nameplates",
		"Includes EllesmereUI's name-only plates over other players. Nameplates always come back when combat starts.",
		-258, 320, presetChanged)
	checkbox("hideMinimap", "Minimap",
		"The game draws minimap icons and your arrow at full strength no matter how faded the UI is, "
		.. "so the minimap is switched off instead.",
		-284, 16, presetChanged)
	checkbox("hideOutline", "Target circle and glow",
		"The circle under your target and the glow around it and around whatever is under the mouse "
		.. "(the game's Outline Mode) are switched off while the HUD is hidden and back on after. "
		.. "So is the highlight around your own character, if you use one.",
		-284, 320, presetChanged)

	header("Idle", -324)
	slider("idleSeconds", "Hide when idle", 0, 120, 5, -344, 16,
		function(v) return v == 0 and "Never" or string.format("after %d s", v) end, nil,
		"After this long with no input, the HUD fades out. Moving, typing and using the mouse count as input, "
		.. "and so do the boxes below if ticked.")
	slider("awayMinutes", "Hide anyway when away", nil, nil, nil, -344, 320,
		function(v) return v >= 60 and "after 1 hour" or string.format("after %d min", v) end,
		{ 2, 5, 10, 15, 20, 30, 45, 60 },
		"After this long with no input, the HUD hides even over an open window or chat box, and even with "
		.. "Hide when idle set to Never. Combat still brings it back.")
	note("Also counts as input:", -394)
	checkbox("mouseWakes", "Mouse moving",
		"After the HUD hides for being idle, moving the mouse brings it back. Off: a bumped mouse or coming back "
		.. "from alt-tab leaves it hidden, and keys (and clicks, if ticked) bring it back. While the HUD is "
		.. "visible, moving the mouse always keeps it visible.",
		-410)
	checkbox("mouseClicks", "Mouse clicks",
		"After the HUD hides for being idle, a mouse click brings it back, even without moving the mouse. "
		.. "Holding a button to move the camera doesn't count here, see Camera movement. While the HUD is "
		.. "visible, clicking always keeps it visible.",
		-410, 320)
	checkbox("activeCamera", "Camera movement",
		"On: moving the camera with the mouse keeps the HUD visible and brings it back. "
		.. "Off: you can look around and the HUD stays hidden.",
		-436)
	checkbox("activeAutorun", "Auto-run or follow",
		"On: auto-run, follow and flight paths keep the HUD visible. Off: they count as idle, so the HUD hides "
		.. "while your character keeps moving. Holding a movement key always counts as input.",
		-436, 320)

	header("While HUD is hidden, bring it back on", -476)
	checkbox("showCombat", "Combat",
		"Combat brings the HUD back at once, even while you are idle. If you hide it during a fight, "
		.. "it stays hidden until that fight ends.",
		-496)
	checkbox("showTarget", "Target",
		"Picking a target brings the HUD back while you are playing. Once you have been idle for your idle time, "
		.. "it hides even with a target. After you hide it with your Hide UI key, a target leaves it hidden.",
		-496, 320)
	checkbox("showCasting", "Casting",
		"Casting or channeling brings the HUD back while you are playing. After you hide it with your Hide UI "
		.. "key, casting leaves it hidden.", -522)
	checkbox("showDead", "Death",
		"The HUD comes back the moment you die, then hides again after your idle time, even if you stay dead. "
		.. "As a ghost everything works as usual.",
		-522, 320)
	checkbox("showWindows", "Windows, popups, bags or typing",
		"Any window you open, a popup, your bags, typing in chat, or arranging your frames (Edit Mode, "
		.. "EllesmereUI unlock mode). Typing also counts as input, so after you send a message the HUD stays for "
		.. "your idle time. A window or chat box left open keeps the HUD only until Hide anyway when away.",
		-548)

	header("Fade", -588)
	slider("fadeOut", "Fade out", 0, 3, 0.1, -608, 16, "%.1f s")
	slider("fadeIn", "Fade in", 0, 1, 0.05, -608, 320, "%.2f s")
	slider("hiddenAlpha", "Hidden opacity", 0, 50, 5, -658, 16, "%d%%", 100,
		"How much of the HUD stays visible while hidden: 0% is fully gone (true black on OLED), "
		.. "higher leaves it faintly visible.")

	header("Help and feedback", -712, true)
	note("Click an address and press Ctrl+C to copy it.", -732)
	copyBox("Addon page", "https://www.curseforge.com/wow/addons/hud-fade", -754)
	copyBox("Report a problem", "https://github.com/AdrianMontanes/HUDFade/issues", -782)

	-- Burn-in protection page
	canvas = shiftPanel
	pageTitle("Burn-in protection")
	note("Pixel shift moves the whole interface a pixel or two every few minutes, around a small circle, so the "
		.. "same pixels never show the same shapes for hours. Blizzard UI, EllesmereUI and every other addon move "
		.. "together, so your layout stays exactly as it is and nothing is saved. It never moves during combat "
		.. "and steps aside while Edit Mode or EllesmereUI's unlock mode is open.", -40)
	header("Pixel shift", -110)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", nil, -130, 16, shiftChanged)
	slider("shiftPixels", "Distance", 1, 4, 1, -170, 16, function(v) return string.format("%d px", v) end)
	slider("shiftMinutes", "Move every", 1, 10, 1, -170, 320, function(v) return string.format("%d min", v) end)
	note("The interface is also kept that distance in from the screen edges, so a frame you placed against an "
		.. "edge never goes past it. Nothing is saved: each login starts from your own layout. Many OLED monitors "
		.. "also shift the whole picture on their own; using both is fine. Type /hudfade shift now to see a move "
		.. "straight away.", -230)
	canvas = panel
end

function refreshAll()
	if not built then return end
	if panel.master then panel.master.refresh() end
	local on = db().enabled and true or false
	for _, w in ipairs(widgets) do
		w.refresh()
		w.setActive(on)
	end
	for _, fs in ipairs(dimmable) do fs:SetAlpha(on and 1 or 0.5) end
end
HUDFade.RefreshOptions = refreshAll

local function onShow()
	build()
	refreshAll()
end
panel:SetScript("OnShow", onShow)
shiftPanel:SetScript("OnShow", onShow)

local category
local function register()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "HUD Fade")
		if Settings.RegisterCanvasLayoutSubcategory then
			Settings.RegisterCanvasLayoutSubcategory(category, shiftPanel, "Burn-in protection")
		end
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
		shiftPanel.parent = panel.name
		InterfaceOptions_AddCategory(shiftPanel)
	end
end

function HUDFade.OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory then
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", register)

---------------------------------------------------------------------------
-- /hudfade
---------------------------------------------------------------------------
local HELP = {
	"/hudfade - open the settings",
	"/hudfade toggle | show | hide - hide or show the HUD",
	"/hudfade on | off - turn the whole addon on or off",
	"/hudfade shot - screenshot without the HUD",
	"/hudfade minimap - show or hide the minimap button",
	"/hudfade shift [on | off | now] - pixel shift status, switch it, or move now to see it",
	"/hudfade why - what is keeping the HUD visible right now",
	"/hudfade what - name the UI element under the mouse (for reporting something that stays visible)",
	"/hudfade reset - back to default settings",
}

SLASH_HUDFADE1 = "/hudfade"
SLASH_HUDFADE2 = "/hfade"
SlashCmdList.HUDFADE = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" then
		HUDFade.OpenOptions()
	elseif cmd == "toggle" then
		HUDFade.Toggle()
	elseif cmd == "on" or cmd == "off" then
		HUDFade.SetEnabled(cmd == "on")
	elseif cmd == "show" then
		HUDFade.Show()
	elseif cmd == "hide" then
		HUDFade.Hide()
	elseif cmd == "shot" or cmd == "screenshot" then
		HUDFade.CleanScreenshot()
	elseif cmd == "minimap" then
		db().minimapButton = not db().minimapButton
		HUDFade.UpdateMinimapButton()
		refreshAll()
		say(db().minimapButton and "minimap button shown." or "minimap button hidden. /hudfade minimap brings it back.")
	elseif cmd == "why" then
		-- Wait for the chat box this was typed in to close, so it doesn't count as typing.
		C_Timer.After(0.5, function()
			local lines = HUDFade.Explain(true)
			say(lines[1])
			for i = 2, #lines do print(lines[i]) end
		end)
	elseif cmd == "shift" then
		local arg = (msg or ""):lower():match("^%s*%S+%s+(%S+)")
		if arg == "on" or arg == "off" then
			db().pixelShift = (arg == "on")
			shiftChanged()
		elseif arg == "now" then
			if not db().pixelShift then
				db().pixelShift = true
				shiftChanged()
			end
			HUDFade.ShiftNow()
		end
		say(HUDFade.ShiftStatus())
	elseif cmd == "what" then
		say("under the mouse: " .. HUDFade.DescribeMouseFrame())
	elseif cmd == "reset" then
		local d = db()
		for k, v in pairs(HUDFade.DEFAULTS) do
			if k ~= "welcomed" then d[k] = v end
		end
		HUDFade.ApplyOverrides(true)
		HUDFade.UpdateMinimapButton()
		HUDFade.Update()
		say("settings reset.")
	else
		for _, line in ipairs(HELP) do say(line) end
	end
end
