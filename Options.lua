-- HUD Fade options: a page in the game's AddOns settings, the welcome window, and the /hudfade command.

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

local function note(text, y, x, width)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x or 16, y)
	fs:SetWidth(width or 560)
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

local function keyText(key)
	return GetBindingText and GetBindingText(key) or key
end

-- The key bound to a game or HUD Fade action, read each time a page opens.
local function keyName(action, none)
	local key = GetBindingKey(action)
	return key and keyText(key) or none or "not bound"
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

local PRINT_TIP = "Your screenshot key hides the HUD for a moment, takes the picture, and brings it back. "
	.. "There is also a separate key for this under Key Bindings > AddOns.\n\nScreenshots taken by other "
	.. "apps, like NVIDIA's Alt+F1, can't hide the HUD: hide it first with your Hide UI key."

local function idleText(v) return v == 0 and "Never" or string.format("after %d s", v) end
local IDLE_TIP = "After this long with no input, the HUD fades out. Moving, typing and using the mouse count as input"
local function awayText(v) return v >= 60 and "after 1 hour" or string.format("after %d min", v) end
local AWAY_STOPS = { 2, 5, 10, 15, 20, 30, 45, 60 }
local AWAY_TIP = "After this long with no input, the HUD hides even over an open window or chat box, and even with "
	.. "Hide when idle set to Never. Combat still brings it back."

local SHIFT_TIP = "Moves the entire interface a pixel or two every few minutes, so nothing sits on the same pixels "
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

-- Preset menus above the "also hide" checkboxes (the settings page and the welcome window).
local presetWidgets = {}
local function presetName()
	local i = HUDFade.CurrentPreset()
	return i and HUDFade.PRESETS[i].name or "Custom"
end
local function presetChanged()
	for _, w in ipairs(presetWidgets) do w.refresh() end
end
local refreshAll -- defined below
local function choosePreset(i)
	HUDFade.ApplyPreset(i)
	refreshAll()
end

local PRESET_TIP = "Everything: names, nameplates, the target circle and damage numbers all go with the HUD. "
	.. "Blizzard: as with the game's own Hide UI (Alt+Z), names, chat bubbles, the target circle and damage "
	.. "numbers stay; nameplates go. Either way you keep the fade, idle hiding and the rest. "
	.. "Change a box below and it shows as Custom."

local function presetMenu(y, x)
	x = x or 20
	local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOPLEFT", x, y - 6)
	title:SetText("Preset")
	local w
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, canvas, "WowStyle1DropdownTemplate")
	if ok and dd and dd.SetupMenu then
		dd:SetPoint("TOPLEFT", x + 60, y)
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
		w:SetPoint("TOPLEFT", x + 60, y)
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
	presetWidgets[#presetWidgets + 1] = w
	widgets[#widgets + 1] = w
end

local built = false
local function build()
	if built then return end
	built = true
	canvas = scrollPage(panel, 846)
	pageTitle("HUD Fade")
	note("Fade your entire World of Warcraft UI, including addon UIs, all at once. Made for immersion, OLED burn-in "
		.. "care and HUD-free screenshots and recordings. Bind keys under Key Bindings > AddOns > HUD Fade.", -38)

	panel.master = checkbox("enabled", "Enable HUD Fade",
		"Off: the HUD stays visible, names and minimap stay as they are, and your Hide UI key does its normal job. "
		.. "No reload needed. You can also bind a key for this under Key Bindings > AddOns.",
		-76, 16, function() HUDFade.SetEnabled(db().enabled) end, true)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", SHIFT_TIP, -76, 320, shiftChanged)

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
		PRINT_TIP, -166, 16, HUDFade.ApplyOverrides)
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
		"Includes EllesmereUI's name-only plates over other players. They fade out and back in with the HUD, "
		.. "in combat too.",
		-258, 320, presetChanged)
	checkbox("hideMinimap", "Minimap",
		"The game draws minimap icons and your arrow at full strength no matter how faded the UI is, "
		.. "so the minimap is switched off instead.",
		-284, 16, presetChanged)
	checkbox("hideOutline", "Target circle",
		"The circle under your target is switched off while the HUD is hidden and back on after. "
		.. "So is the highlight around your own character, if you use one.",
		-284, 320, presetChanged)
	checkbox("hideDamage", "Damage numbers",
		"The damage and healing numbers over your targets are part of the game world, not the UI, so they are "
		.. "switched off while the HUD is hidden and back on after. Your own scrolling combat text is part of "
		.. "the UI and fades with it.",
		-310, 16, presetChanged)

	header("Idle", -350)
	slider("idleSeconds", "Hide when idle", 0, 120, 5, -370, 16, idleText, nil,
		IDLE_TIP .. ", and so do the boxes below if ticked.")
	slider("awayMinutes", "Always hide when AFK", nil, nil, nil, -370, 320, awayText, AWAY_STOPS, AWAY_TIP)
	note("Also counts as input:", -420)
	checkbox("mouseWakes", "Mouse moving",
		"After the HUD hides for being idle, moving the mouse brings it back. Off: a bumped mouse or coming back "
		.. "from alt-tab leaves it hidden, and keys (and clicks, if ticked) bring it back. While the HUD is "
		.. "visible, moving the mouse always keeps it visible.",
		-436)
	checkbox("mouseClicks", "Mouse clicks",
		"After the HUD hides for being idle, a mouse click brings it back, even without moving the mouse. "
		.. "Holding a button to move the camera doesn't count here, see Camera movement. While the HUD is "
		.. "visible, clicking always keeps it visible.",
		-436, 320)
	checkbox("activeCamera", "Camera movement",
		"On: moving the camera with the mouse keeps the HUD visible and brings it back. "
		.. "Off: you can look around and the HUD stays hidden.",
		-462)
	checkbox("activeAutorun", "Auto-run or follow",
		"On: auto-run, follow and flight paths keep the HUD visible. Off: they count as idle, so the HUD hides "
		.. "while your character keeps moving. Holding a movement key always counts as input.",
		-462, 320)

	header("While HUD is hidden, bring it back on", -502)
	checkbox("showCombat", "Combat",
		"Combat brings the HUD back at once, even while you are idle. If you hide it during a fight, "
		.. "it stays hidden until that fight ends. Off: fights stay HUD-free too, handy for recordings.",
		-522)
	checkbox("showTarget", "Target",
		"Picking a target brings the HUD back while you are playing. Once you have been idle for your idle time, "
		.. "it hides even with a target. After you hide it with your Hide UI key, a target leaves it hidden.",
		-522, 320)
	checkbox("showCasting", "Casting",
		"Casting or channeling brings the HUD back while you are playing. After you hide it with your Hide UI "
		.. "key, casting leaves it hidden.", -548)
	checkbox("showDead", "Death",
		"The HUD comes back the moment you die, then hides again after your idle time, even if you stay dead. "
		.. "As a ghost everything works as usual.",
		-548, 320)
	checkbox("showWindows", "Windows, popups, bags or typing",
		"Any window you open, a popup, your bags, typing in chat, or arranging your frames (Edit Mode, "
		.. "EllesmereUI unlock mode). Opening one and typing also count as input, so after you close it or send a "
		.. "message the HUD stays for your idle time. A window or chat box left open keeps the HUD only until "
		.. "Always hide when AFK.",
		-574)

	header("Fade", -614)
	slider("fadeOut", "Fade out", 0, 3, 0.1, -634, 16, "%.1f s")
	slider("fadeIn", "Fade in", 0, 1, 0.05, -634, 320, "%.2f s")
	slider("hiddenAlpha", "Hidden opacity", 0, 50, 5, -684, 16, "%d%%", 100,
		"How much of the HUD stays visible while hidden: 0% is fully gone (true black on OLED), "
		.. "higher leaves it faintly visible.")

	header("Help and feedback", -738, true)
	note("Click an address and press Ctrl+C to copy it.", -758)
	copyBox("Addon page", "https://www.curseforge.com/wow/addons/hud-fade", -780)
	copyBox("Report a problem", "https://github.com/AdrianMontanes/HUDFade/issues", -808)

	-- Burn-in protection page
	canvas = shiftPanel
	pageTitle("Burn-in protection")
	note("Pixel shift moves the entire interface a pixel or two every few minutes, around a small circle, so the "
		.. "same pixels never show the same shapes for hours. Blizzard UI, EllesmereUI and every other addon move "
		.. "together, so your layout stays exactly as it is and nothing is saved. It never moves during combat "
		.. "and steps aside while Edit Mode or EllesmereUI's unlock mode is open.", -40)
	header("Pixel shift", -110)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", nil, -130, 16, shiftChanged)
	slider("shiftPixels", "Distance", 1, 4, 1, -170, 16, function(v) return string.format("%d px", v) end)
	slider("shiftMinutes", "Move every", 1, 10, 1, -170, 320, function(v) return string.format("%d min", v) end)
	note("The interface is also kept that distance in from the screen edges, so a frame you placed against an "
		.. "edge never goes past it. Nothing is saved: each login starts from your own layout. Many OLED monitors "
		.. "also shift the entire picture on their own; using both is fine. Type /hudfade shift now to see a move "
		.. "straight away.", -230)
	canvas = panel
end

function refreshAll()
	if built then panel.master.refresh() end
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

---------------------------------------------------------------------------
-- Welcome window: the main choices and keys, shown once on the first login with HUD Fade
---------------------------------------------------------------------------
local welcome, welcomeIntro

-- Every key bound to these actions (an action can be false, to skip it).
local function keysOf(...)
	local list = {}
	for i = 1, select("#", ...) do
		local action = select(i, ...)
		if action then
			for _, key in ipairs({ GetBindingKey(action) }) do list[#list + 1] = keyText(key) end
		end
	end
	return list
end

-- An action and the keys that do it. Only shown here: keys are set in the game's Key Bindings, since an addon
-- window that takes key presses keeps every key from the game on some clients.
local function keyRow(label, keysFor, x, y, width)
	local name = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	name:SetPoint("TOPLEFT", x, y)
	name:SetText(label)
	local keys = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	keys:SetPoint("TOPRIGHT", canvas, "TOPLEFT", x + width, y)
	keys:SetJustifyH("RIGHT")
	local row = {}
	row.refresh = function()
		local list = keysFor()
		keys:SetText(#list > 0 and table.concat(list, ", ") or "|cff9d9d9dNot set|r")
	end
	row.setActive = function(on)
		name:SetAlpha(on and 1 or 0.5)
		keys:SetAlpha(on and 1 or 0.5)
	end
	widgets[#widgets + 1] = row
end

-- What brings the HUD back after idle hiding depends on the mouse choices in the settings.
local function wakeText()
	local d = db()
	return "With no mouse, movement keys or typing for this long, the HUD fades out on its own. "
		.. (d.mouseWakes and "Moving the mouse brings it back."
		or d.mouseClicks and "A click or a movement key brings it back."
		or "A movement key or typing brings it back.")
		.. " When you're AFK, it hides even over open windows and chat."
end

local function welcomeText()
	local key = db().replaceAltZ and GetBindingKey("TOGGLEUI")
	local how = key and ("Press " .. keyText(key) .. " (your Hide UI key) to fade the entire HUD out, and again to "
		.. "bring it back.") or "Bind a hide / show key, or use /hudfade toggle, to fade the entire HUD out and back in."
	return how .. " Here are a few choices to start with. You can change these and more at any time with /hudfade."
end

-- The keys note ends 370 px down, then a 14 px gap, the 22 px buttons and 14 px to the bottom edge.
local WELCOME_HEIGHT = 420

local function buildWelcome()
	if welcome then return end
	local ok, f = pcall(CreateFrame, "Frame", "HUDFadeWelcome", UIParent, "BasicFrameTemplateWithInset")
	if not (ok and type(f) == "table") then
		f = CreateFrame("Frame", "HUDFadeWelcome", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if f.SetBackdrop then
			f:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
	end
	welcome = f
	f:Hide()
	f:SetSize(540, WELCOME_HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	-- As an open window it keeps the HUD visible while you read it. It takes no keys, so you can still move.
	-- Don't add it to the game's Escape handlers (RegisterGameMenuEscHandler): that taints Escape and every press
	-- after it shows a "blocked from an action" popup. Taking keys to catch Escape stopped all movement.
	table.insert(UISpecialFrames, "HUDFadeWelcome")
	f:SetScript("OnHide", function() db().welcomeShown = true end)

	local title = f.TitleText
	if type(title) ~= "table" then
		title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		title:SetPoint("TOP", 0, -6)
	end
	title:SetText("Welcome to HUD Fade")

	-- Two columns between 16 px margins; every section is a header, then its content 18 px below.
	local L, R, W = 16, 278, 246 -- left column, right column, column width
	canvas = f
	welcomeIntro = note("", -38, L, 508)
	header("Idle", -74)
	slider("idleSeconds", "Hide when idle", 0, 120, 5, -88, L, idleText, nil, IDLE_TIP .. ".")
	slider("awayMinutes", "Always hide when AFK", nil, nil, nil, -88, R, awayText, AWAY_STOPS, AWAY_TIP)
	local idleNote = note("", -136, L, 508)
	idleNote.refresh = function() idleNote:SetText(wakeText()) end
	idleNote.setActive = function(on) idleNote:SetAlpha(on and 1 or 0.5) end
	widgets[#widgets + 1] = idleNote
	header("While the HUD is hidden, also hide", -174)
	presetMenu(-192, L)
	note("Everything also hides names and nameplates. Blizzard works like the game's own Hide UI.", -220, L, 508)
	header("Screenshots and OLED", -246)
	-- A check box's square sits 6 px in from its frame.
	checkbox("cleanPrintScreen", function() return "HUD-free screenshots (" .. keyName("SCREENSHOT") .. ")" end,
		PRINT_TIP, -264, L - 6, function()
			HUDFade.ApplyOverrides()
			refreshAll()
		end)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", SHIFT_TIP, -264, R - 6, shiftChanged)
	header("Keys", -304)
	keyRow("Hide / show", function() return keysOf(db().replaceAltZ and "TOGGLEUI", "HUDFADE_TOGGLE") end,
		L, -322, W)
	keyRow("Peek (hold)", function() return keysOf("HUDFADE_PEEK") end, R, -322, W)
	keyRow("HUD-free screenshot",
		function() return keysOf(db().cleanPrintScreen and "SCREENSHOT", "HUDFADE_SCREENSHOT") end, L, -340, W)
	keyRow("HUD Fade on / off", function() return keysOf("HUDFADE_ENABLE") end, R, -340, W)
	note("Set or change these in the game's Key Bindings, under AddOns > HUD Fade.", -358, L, 508)
	canvas = panel

	local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	done:SetSize(110, 22)
	done:SetPoint("BOTTOMRIGHT", -L, 14)
	done:SetText("Done")
	done:SetScript("OnClick", function() f:Hide() end)
	local all = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	all:SetSize(130, 22)
	all:SetPoint("RIGHT", done, "LEFT", -8, 0)
	all:SetText("All settings")
	all:SetScript("OnClick", function()
		f:Hide()
		HUDFade.OpenOptions()
	end)
	local again = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	again:SetPoint("LEFT", f, "BOTTOMLEFT", L, 25)
	again:SetText("Open this again with /hudfade welcome.")
end

function HUDFade.ShowWelcome()
	buildWelcome()
	welcomeIntro:SetText(welcomeText())
	refreshAll()
	welcome:Show()
end

-- A moment after the first loading screen, and never in combat.
local function welcomeWhenReady()
	local d = db()
	if d.welcomeShown or not d.enabled then return end
	if InCombatLockdown() then
		C_Timer.After(5, welcomeWhenReady)
		return
	end
	HUDFade.ShowWelcome()
end

local welcomeChecked = false
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		register()
	elseif not welcomeChecked then
		welcomeChecked = true
		C_Timer.After(2, welcomeWhenReady)
	end
end)

---------------------------------------------------------------------------
-- /hudfade
---------------------------------------------------------------------------
local HELP = {
	"/hudfade - open the settings",
	"/hudfade welcome - the welcome window: the main choices and keys",
	"/hudfade toggle | show | hide - hide or show the HUD",
	"/hudfade on | off - turn the entire addon on or off",
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
	elseif cmd == "welcome" or cmd == "setup" then
		HUDFade.ShowWelcome()
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
			if k ~= "welcomeShown" then d[k] = v end
		end
		HUDFade.ApplyOverrides(true)
		HUDFade.UpdateMinimapButton()
		HUDFade.Update()
		say("settings reset.")
	else
		for _, line in ipairs(HELP) do say(line) end
	end
end
