-- HUD Fade options: a page in the game's AddOns settings, and the /hudfade command.

local ADDON, ns = ...
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

local function header(text, y)
	local fs = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	dimmable[#dimmable + 1] = fs
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
local function slider(key, label, minV, maxV, step, y, x, fmt, scale)
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
	if HUDFade.RefreshOptions then HUDFade.RefreshOptions() end -- (the switch is on both pages)
end

local SHIFT_TIP = "Moves the whole interface a pixel or two every few minutes, so nothing sits on the same pixels for hours. "
	.. "Everything moves together, so your layout stays as it is. Distance and timing are on the Burn-in protection page under HUD Fade."

-- The settings go on a scrolling page, so on a short settings window the last ones scroll into view instead of
-- spilling over the window's border.
local function scrollPage(page, height)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, page, "ScrollFrameTemplate")
	if not ok then ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, page, "UIPanelScrollFrameTemplate") end
	if not ok then scroll = CreateFrame("ScrollFrame", nil, page) end
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4) -- (room for the scroll bar on the right)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(600, height)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(_, w)
		if type(w) == "number" and w > 0 then content:SetWidth(w) end
	end)
	if not scroll:GetScript("OnMouseWheel") then -- (the templates scroll with the wheel themselves)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local range = self:GetVerticalScrollRange() or 0
			self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	return content
end

local built = false
local function build()
	if built then return end
	built = true
	canvas = scrollPage(panel, 700)
	pageTitle("HUD Fade")
	note("Fades the whole interface at once, Blizzard UI and EllesmereUI together, to protect OLED screens and take clean screenshots. Bind keys under Key Bindings > AddOns > HUD Fade.", -40)

	panel.master = checkbox("enabled", "Enable HUD Fade", "Off: the HUD stays visible, names and minimap stay as they are, and your Hide UI key does its normal job. No reload needed. You can also bind a key for this under Key Bindings > AddOns.",
		-76, 16, function() HUDFade.SetEnabled(db().enabled) end, true)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", SHIFT_TIP, -76, 320, shiftChanged)

	header("Hiding", -120)
	checkbox("replaceAltZ", function()
			-- (your own key for the game's Hide UI, read each time the page opens)
			local key = GetBindingKey("TOGGLEUI")
			local shown = key and (GetBindingText and GetBindingText(key) or key) or "not bound"
			return "Use Hide UI key (" .. shown .. ")"
		end,
		"Your Hide UI key fades the HUD out and back in instead of switching it off, and the HUD still comes back when something needs it.",
		-140, 16, HUDFade.ApplyOverrides)
	checkbox("startHidden", "Start hidden", "Each session starts with the HUD hidden.", -140, 320)
	checkbox("cleanPrintScreen", "HUD-free screenshots (Print Screen)",
		"Your screenshot key hides the HUD for a moment, takes the picture, and brings it back.", -166, 16, HUDFade.ApplyOverrides)

	header("While HUD is hidden, also hide", -206)
	checkbox("hideNames", "Names and chat bubbles",
		"The floating names, chat bubbles and the circle under your target are part of the game world, not the UI, so they are switched off while the HUD is hidden and back on after. Your target's own name is the exception: the game always shows it.", -226)
	checkbox("hideNameplates", "Nameplates",
		"Includes EllesmereUI's name-only plates over other players. Nameplates always come back when combat starts.", -226, 320)
	checkbox("hideMinimap", "Minimap",
		"The game draws minimap icons and your arrow at full strength no matter how faded the UI is, so the minimap is switched off instead.", -252)
	checkbox("hideCursor", "Mouse pointer when still",
		"Experimental. Out of combat, the pointer disappears after 2 seconds without moving the mouse, and moving the mouse brings it back. While it is hidden, mouse look speed is turned down to a tenth, so that first move barely turns the camera (your setting comes back with the pointer). Once HUD Fade has seen that the game reports mouse moves, it turns it down to almost nothing, so the camera stays still, also sitting down and on flight paths. A click or any key on a flight path brings the pointer back too, and dragging looks around as usual. After a left-drag it stays until a right-drag or a short run lines camera and character up again, since hiding it turns your character to the camera; if neither happens it hides anyway once the mouse has been still for your idle time. Flying, swimming and in vehicles it stays, unless Also when flying or swimming is on.", -278)
	checkbox("hideCursorSteer", "Also when flying or swimming",
		"Also hide the pointer while flying, swimming or in a vehicle. There the mouse steers you, as when you hold the right button, and a click or any key brings the pointer back. When the pointer hides, your character turns to where the camera points, up or down too, so if you are moving you may climb or dive a little. Needs Mouse pointer when still.", -278, 320)

	header("While HUD is hidden, bring it back on", -318)
	checkbox("mouseWakes", "Mouse moving",
		"After the HUD hides for being idle, moving the mouse brings it back. Off: only keys bring it back (moving, targeting, opening a window and so on), so a bumped mouse or coming back from alt-tab leaves it hidden. While the HUD is visible, using the mouse always keeps it visible.", -338)
	checkbox("showCombat", "Combat", nil, -338, 320)
	checkbox("showTarget", "Target", nil, -364)
	checkbox("showCasting", "Casting", nil, -364, 320)
	checkbox("showDead", "Death",
		"The HUD comes back the moment you die, then hides again after your idle time, even if you stay dead. As a ghost everything works as usual.", -390)
	checkbox("showWindows", "Windows, popups, bags or typing",
		"Any window you open, a popup, your bags, typing in chat, or arranging your frames (Edit Mode, EllesmereUI unlock mode). Typing also counts as activity, so after you send a message the HUD stays for your idle time. A window or chat box left open keeps the HUD only until Hide anyway when away.", -390, 320)

	header("Timing", -430)
	slider("idleSeconds", "Hide when idle", 0, 120, 5, -450, 16,
		function(v) return v == 0 and "Never" or string.format("after %d s", v) end)
	slider("awayMinutes", "Hide anyway when away", nil, nil, nil, -450, 320,
		function(v) return v >= 60 and "after 1 hour" or string.format("after %d min", v) end, { 2, 5, 10, 15, 20, 30, 45, 60 })
	slider("fadeOut", "Fade out", 0, 3, 0.1, -500, 16, "%.1f s")
	slider("fadeIn", "Fade in", 0, 1, 0.05, -500, 320, "%.2f s")
	slider("hiddenAlpha", "Hidden opacity", 0, 50, 5, -550, 16, "%d%%", 100)
	note("Hide anyway when away: after this long with no input, the HUD hides even over an open window or chat box, and even with Hide when idle set to Never. Combat still brings it back.", -594)

	header("Keep HUD visible during", -640)
	checkbox("activeCamera", "Camera turning", "On: looking around with the mouse keeps the HUD visible and brings it back. Off: you can look around and the HUD stays hidden.", -660)
	checkbox("activeAutorun", "Auto-run or follow", "On: auto-run, follow and flight paths keep the HUD visible. Off: they count as idle, so the HUD hides while your character keeps moving. Holding a movement key always counts as activity.", -660, 320)

	-- Burn-in protection page
	canvas = shiftPanel
	pageTitle("Burn-in protection")
	note("Pixel shift moves the whole interface a pixel or two every few minutes, around a small circle, so the same pixels "
		.. "never show the same shapes for hours. Blizzard UI, EllesmereUI and every other addon move together, so your "
		.. "layout stays exactly as it is and nothing is saved. It never moves during combat and steps aside while Edit Mode or EllesmereUI's unlock mode is open.", -40)
	header("Pixel shift", -110)
	checkbox("pixelShift", "Pixel shift (burn-in protection)", nil, -130, 16, shiftChanged)
	slider("shiftPixels", "Distance", 1, 4, 1, -170, 16, function(v) return string.format("%d px", v) end)
	slider("shiftMinutes", "Move every", 1, 10, 1, -170, 320, function(v) return string.format("%d min", v) end)
	note("The interface is also kept that distance in from the screen edges, so a frame you placed against an edge never goes past it. "
		.. "Nothing is saved: each login starts from your own layout. Many OLED monitors also shift the whole picture on their own; "
		.. "using both is fine. Type /hudfade shift now to see a move straight away.", -230)
	canvas = panel
end

local function refreshAll()
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
	"/hudfade shift [on | off | now] - pixel shift status, switch it, or move now to see it",
	"/hudfade why - what is keeping the HUD visible right now",
	"/hudfade what - name the UI element under the mouse (for reporting something that stays visible)",
	"/hudfade log - what the HUD and the mouse pointer did lately (for reporting a bug)",
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
	elseif cmd == "why" then
		-- (asked a moment later, once the chat box you typed this in has closed)
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
	elseif cmd == "log" then
		local log = HUDFade.Log()
		say(#log > 0 and "the last things the HUD and the pointer did (oldest first):" or "nothing logged yet.")
		for i = math.max(1, #log - 19), #log do print(log[i]) end
	elseif cmd == "reset" then
		local d = db()
		for k, v in pairs(HUDFade.DEFAULTS) do
			if k ~= "welcomed" then d[k] = v end
		end
		HUDFade.ApplyOverrides(true)
		HUDFade.Update()
		say("settings reset.")
	else
		for _, line in ipairs(HELP) do say(line) end
	end
end
