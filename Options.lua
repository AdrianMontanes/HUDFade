-- OLED HUD options: a page in the game's AddOns settings, and the /ohud command.

local ADDON, ns = ...
local OLEDHUD = ns.core
local say = OLEDHUD.Print

local panel = CreateFrame("Frame")
panel.name = "OLED HUD"
panel:Hide()

local widgets = {}  -- every setting below the on/off switch
local dimmable = {} -- headers, greyed out with them while the addon is off

local function db() return OLEDHUD.db end

local function header(text, y)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", 16, y)
	fs:SetText(text)
	dimmable[#dimmable + 1] = fs
	return fs
end

local function note(text, y, x)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x or 16, y)
	fs:SetWidth(560)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

local function checkbox(key, label, tip, y, x, onChange, master)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetPoint("TOPLEFT", x or 16, y)
	cb:SetSize(26, 26)
	local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetText(label)
	cb:SetScript("OnClick", function(self)
		db()[key] = self:GetChecked() and true or false
		if onChange then onChange() end
		OLEDHUD.Update()
	end)
	if tip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	cb.refresh = function() cb:SetChecked(db()[key] and true or false) end
	cb.setActive = function(on)
		if on then cb:Enable() else cb:Disable() end
		fs:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
	end
	if not master then widgets[#widgets + 1] = cb end
	return cb
end

local function slider(key, label, minV, maxV, step, y, x, fmt, scale)
	scale = scale or 1
	local s = CreateFrame("Slider", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
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
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", -4, 4)
	local function show(v)
		local text = type(fmt) == "function" and fmt(v) or string.format(fmt, v)
		title:SetText(label .. ": |cffffffff" .. text .. "|r")
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = math.floor(v / step + 0.5) * step
		db()[key] = v / scale
		show(v)
		OLEDHUD.Update()
	end)
	s.refresh = function()
		local v = (db()[key] or 0) * scale
		s:SetValue(v)
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

local built = false
local function build()
	if built then return end
	built = true
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("OLED HUD")
	note("Fades the whole interface at once, Blizzard UI and EllesmereUI together, to protect OLED screens and take clean screenshots. Bind keys under Key Bindings > AddOns > OLED HUD.", -40)

	panel.master = checkbox("enabled", "Enable OLED HUD", "Off: the HUD stays up, names and minimap stay as they are, and your Hide UI key does its normal job. No reload needed. You can also bind a key for this under Key Bindings > AddOns.",
		-76, 16, function() OLEDHUD.SetEnabled(db().enabled) end, true)

	header("Hiding", -120)
	checkbox("replaceAltZ", "Use the game's Hide UI key (" .. (GetBindingKey("TOGGLEUI") or "unbound") .. ") for OLED HUD",
		"Your Hide UI key fades the HUD out and back in instead of switching it off, and the HUD still comes back when something needs it.",
		-140, 16, OLEDHUD.ApplyOverrides)
	checkbox("cleanPrintScreen", "Leave the HUD out of screenshots (Print Screen)",
		"Your screenshot key hides the HUD for a moment, takes the picture, and brings it back.", -166, 16, OLEDHUD.ApplyOverrides)
	checkbox("startHidden", "Start each session with the HUD hidden", nil, -192)
	checkbox("hideNames", "Hide player and NPC names while hidden",
		"The floating names above characters are part of the game world, not the UI, so they are switched off while the HUD is hidden and back on after.", -218)
	checkbox("hideNameplates", "Hide nameplates while hidden",
		"Includes EllesmereUI's name-only plates over other players. Nameplates always come back when combat starts.", -244)
	checkbox("hideMinimap", "Hide the minimap while hidden",
		"The game draws minimap icons and your arrow at full strength no matter how faded the UI is, so the minimap is switched off instead.", -270)
	checkbox("hideCursor", "Hide the mouse pointer when it is still (experimental)",
		"While the HUD is hidden and you are out of combat, the pointer disappears after 2 seconds without moving the mouse, the same way it does while you drag the camera. The first move brings it back, and turns your character very slightly.", -296)

	header("While hidden, show the HUD when", -336)
	checkbox("showCombat", "In combat", nil, -356)
	checkbox("showTarget", "You have a target", nil, -356, 320)
	checkbox("showCasting", "Casting", nil, -382)
	checkbox("showDead", "You are dead", nil, -382, 320)
	checkbox("showWindows", "A window, popup or bag is open, or you are typing", nil, -408)

	header("Timing", -448)
	slider("idleSeconds", "Hide when away", 0, 300, 5, -468, 16,
		function(v) return v == 0 and "Never" or string.format("after %d s", v) end)
	slider("linger", "Hide after", 0, 10, 0.5, -468, 320, "%.1f s")
	slider("fadeOut", "Fade out", 0, 3, 0.1, -518, 16, "%.1f s")
	slider("fadeIn", "Fade in", 0, 1, 0.05, -518, 320, "%.2f s")
	slider("hiddenAlpha", "Opacity while hidden", 0, 50, 5, -568, 16, "%d%%", 100)
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
OLEDHUD.RefreshOptions = refreshAll

panel:SetScript("OnShow", function()
	build()
	refreshAll()
end)

local category
local function register()
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, "OLED HUD")
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function OLEDHUD.OpenOptions()
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
-- /ohud
---------------------------------------------------------------------------
local HELP = {
	"/ohud - hide or show the HUD",
	"/ohud show | hide",
	"/ohud on | off - turn the whole addon on or off",
	"/ohud shot - screenshot without the HUD",
	"/ohud why - what is keeping the HUD up right now",
	"/ohud options - open the settings",
	"/ohud reset - back to default settings",
}

SLASH_OLEDHUD1 = "/ohud"
SLASH_OLEDHUD2 = "/oledhud"
SlashCmdList.OLEDHUD = function(msg)
	local cmd = (msg or ""):lower():match("^%s*(%S*)")
	if cmd == "" or cmd == "toggle" then
		OLEDHUD.Toggle()
	elseif cmd == "on" or cmd == "off" then
		OLEDHUD.SetEnabled(cmd == "on")
	elseif cmd == "show" then
		OLEDHUD.Show()
	elseif cmd == "hide" then
		OLEDHUD.Hide()
	elseif cmd == "shot" or cmd == "screenshot" then
		OLEDHUD.CleanScreenshot()
	elseif cmd == "why" then
		local mode, list = OLEDHUD.Explain()
		say("mode: " .. mode .. ". Showing because: " .. (#list > 0 and table.concat(list, ", ") or "nothing"))
	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		OLEDHUD.OpenOptions()
	elseif cmd == "reset" then
		local d = db()
		for k, v in pairs(OLEDHUD.DEFAULTS) do
			if k ~= "welcomed" then d[k] = v end
		end
		OLEDHUD.ApplyOverrides(true)
		OLEDHUD.Update()
		say("settings reset.")
	else
		for _, line in ipairs(HELP) do say(line) end
	end
end
