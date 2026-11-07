-- HUD Fade: fades the whole interface as one layer.
--
-- Why one layer: EllesmereUI (and other UI addons) keep setting the opacity of their own frames for their
-- mouseover and visibility rules. Fade addons that set the opacity of those same frames end up fighting them.
-- HUD Fade never touches a single frame's opacity. It only changes UIParent's, which multiplies with whatever
-- each addon does underneath, so both keep working. The few things that ignore UIParent's opacity (3D models,
-- floating unit names, nameplates) are handled on their own below.

local ADDON, ns = ...

local HUDFade = {}
_G.HUDFade = HUDFade
ns.core = HUDFade

BINDING_HEADER_HUDFADE = "HUD Fade"
BINDING_NAME_HUDFADE_TOGGLE = "Hide / show the HUD"
BINDING_NAME_HUDFADE_PEEK = "Show the HUD while held"
BINDING_NAME_HUDFADE_SCREENSHOT = "Take a screenshot without the HUD"
BINDING_NAME_HUDFADE_ENABLE = "Turn HUD Fade on / off"

local DEFAULTS = {
	enabled = true,        -- the whole addon; off = the game behaves as if HUD Fade were not installed
	startHidden = false,   -- begin each session with the HUD hidden
	idleSeconds = 30,      -- hide after this long with no input at all (0 = never)
	awayMinutes = 10,      -- after this long with no input, hide even over an open window or chat box
	hiddenAlpha = 0,       -- opacity while hidden (0 = true black)
	fadeOut = 1.0,         -- seconds to fade out
	fadeIn = 0.2,          -- seconds to fade back in
	showCombat = true,
	showTarget = true,
	showCasting = false,
	showWindows = true,    -- bags, map, popups, chat typing, any window you open
	showDead = true,
	hideNames = true,      -- floating player/NPC names and chat bubbles
	hideNameplates = true,
	hideCursor = false,    -- hide the mouse pointer while the HUD is hidden and the mouse is still (experimental)
	hideCursorSteer = false, -- ...also while flying, swimming or in a vehicle, where the mouse then steers you
	mouseWakes = true,     -- moving the mouse brings the HUD back after it hid for being idle (it always keeps it up)
	activeCamera = false,  -- turning the camera counts as activity for the idle timer
	activeAutorun = false, -- auto-run, follow and flight paths count as activity for the idle timer
	hideMinimap = true,    -- the minimap's icons and arrow ignore the UI's opacity, so the map is hidden instead
	replaceAltZ = true,    -- the game's own "hide UI" key (Alt+Z) does HUD Fade's toggle instead
	cleanPrintScreen = false, -- the game's screenshot key leaves the HUD out
	pixelShift = false,    -- burn-in protection: move the whole UI a pixel or two every few minutes
	shiftPixels = 2,       -- how far, in screen pixels
	shiftMinutes = 3,      -- how often
	welcomed = false,
}
HUDFade.DEFAULTS = DEFAULTS

local GRACE = 1 -- seconds
local held = {} -- movement keys held down right now (holding W to run counts as activity the whole time)

local DB
local state = {
	current = 1,        -- the opacity HUD Fade last gave UIParent
	target = 1,         -- where the fade is heading
	hudOff = false,     -- the toggle
	peek = false,
	shot = false,       -- a clean screenshot is being taken
	inCombat = false,
	casting = false,
	moving = false,
	lastInput = 0,
	lastWanted = -math.huge, -- last time a reason to show the HUD was active (for the short grace below)
	suppressed = {},    -- reasons that were active when you pressed hide; ignored until they end
	cvarsHidden = false,
}
HUDFade.state = state

local function now() return GetTime() end

local function say(msg)
	print("|cff7fd4ffHUD Fade|r: " .. msg)
end
HUDFade.Print = say

-- Since 12.0 the game hands addons some values as "secrets" (a target frame's range fade, for one). Comparing a
-- secret or doing maths on it is an error, so anything read from a frame goes through ask(): it calls the method
-- safely and gives back nil for an error or a secret, which the code below treats as "could not tell".
local function readable(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function ask(f, method, arg)
	local fn = f and f[method]
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, f, arg)
	if not ok then return nil end
	return readable(v)
end

-- The same for yes/no game questions such as UnitExists("target"): an error or a secret answers "no".
local function is(fn, arg)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, arg)
	return ok and readable(v) and true or false
end

---------------------------------------------------------------------------
-- Game settings changed while hidden (unit names, nameplates)
---------------------------------------------------------------------------
local NAME_CVARS = {
	"UnitNameOwn", "UnitNameNPC", "UnitNameInteractiveNPC", "UnitNameHostleNPC", "UnitNameFriendlySpecialNPCName",
	"UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
	"UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
	"UnitNameFriendlyTotemName", "UnitNameEnemyTotemName", "UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
	"chatBubbles", "chatBubblesParty", -- (chat bubbles float in the game world too, like the names)
	"ObjectSelectionCircle", -- (the circle under your target; an old setting that may be gone, skipped if so)
}
-- (Your target's own name is not among these: the game shows it whatever the settings say.)
-- nameplateShowFriendlyPlayers drives EllesmereUI's name-only plates over other players.
local PLATE_CVARS = { "nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs" }

local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- Turns a list of CVars off, remembering what they were (in the saved variables, so a crash or logout while
-- hidden still gets them back next login).
local function cvarsOff(list)
	for _, name in ipairs(list) do
		local okGet, value = pcall(getCVar, name)
		if okGet and value ~= nil and value ~= "0" and DB.restore[name] == nil then
			if pcall(setCVar, name, "0") then DB.restore[name] = value end
		end
	end
end

local function cvarsBack(list)
	for _, name in ipairs(list) do
		local value = DB.restore[name]
		if value ~= nil and pcall(setCVar, name, value) then DB.restore[name] = nil end
	end
end

---------------------------------------------------------------------------
-- Minimap: the game draws its icons and the player arrow at full strength whatever the UI's opacity, and at
-- partial opacity it can draw a blank map indoors. So it is hidden outright while the HUD is hidden.
---------------------------------------------------------------------------
local minimapHiddenByUs = false
local minimapBusy = false

local function canTouch(f)
	return not (InCombatLockdown() and ask(f, "IsProtected"))
end

local function hideMinimap()
	local m = Minimap
	if not (m and DB.hideMinimap) or not canTouch(m) then return end
	if ask(m, "IsShown") then
		minimapBusy = true
		if pcall(m.Hide, m) then minimapHiddenByUs = true end
		minimapBusy = false
	end
end

local function showMinimap()
	local m = Minimap
	if not (m and minimapHiddenByUs) or not canTouch(m) then return end
	minimapHiddenByUs = false
	minimapBusy = true
	pcall(m.Show, m)
	minimapBusy = false
end

local function hookMinimap()
	if not Minimap or not hooksecurefunc then return end
	-- Another addon showing the map again while the HUD is hidden: hide it straight away, before it is drawn.
	hooksecurefunc(Minimap, "Show", function(m)
		if minimapBusy or not minimapHiddenByUs or not canTouch(m) then return end
		minimapBusy = true
		pcall(m.Hide, m)
		minimapBusy = false
	end)
end

local function hideGameText()
	state.cvarsHidden = true
	if DB.hideNames then cvarsOff(NAME_CVARS) end
	hideMinimap()
	-- Nameplates a moment later: dropping every plate is the heaviest part, so it gets a frame of its own.
	if DB.hideNameplates then
		C_Timer.After(0.1, function()
			if state.cvarsHidden and DB.hideNameplates and not InCombatLockdown() then cvarsOff(PLATE_CVARS) end
		end)
	end
end

local function showGameText()
	cvarsBack(NAME_CVARS)
	cvarsBack(PLATE_CVARS)
	showMinimap()
	state.cvarsHidden = false
end

local function restoreAllCVars()
	for name, value in pairs(DB.restore) do
		pcall(setCVar, name, value)
	end
	wipe(DB.restore)
	state.cvarsHidden = false
end

---------------------------------------------------------------------------
-- 3D models: they draw at full strength even when their parent is see-through, so they get their own opacity.
---------------------------------------------------------------------------
local MODEL_TYPES = { Model = true, PlayerModel = true, DressUpModel = true, CinematicModel = true, TabardModel = true }
local models = {}                                  -- every model found under UIParent
local baseAlpha = setmetatable({}, { __mode = "k" }) -- model -> its own opacity before we changed it
local lastScan = -100

local function underUIParent(f)
	for _ = 1, 25 do
		local p = ask(f, "GetParent")
		if type(p) ~= "table" then return false end
		if p == UIParent then return true end
		f = p
	end
	return false
end

-- Frames set to ignore their parent's opacity (the game's own vehicle and flight "leave" button is one) would
-- stay fully visible too, so they get their own opacity the same way.
local loners = {}
local lonerBase = setmetatable({}, { __mode = "k" })
local lonerWritten = setmetatable({}, { __mode = "k" })

local function sortFrame(f, ms, ls)
	local kind = ask(f, "GetObjectType")
	if kind and MODEL_TYPES[kind] and f.SetModelAlpha then
		if underUIParent(f) then ms[#ms + 1] = f end
	elseif ask(f, "IsIgnoringParentAlpha") == true and underUIParent(f) then
		-- (a frame that keeps this secret is left alone: we cannot tell, and guessing could leave it invisible)
		ls[#ls + 1] = f
	end
end

-- Named here too in case the game draws it some other way: alpha on a normal child is harmless.
local function addNamedLoners(ls)
	for _, name in ipairs({ "MainMenuBarVehicleLeaveButton" }) do
		local b = _G[name]
		if type(b) == "table" and b.SetAlpha then
			local dup = false
			for _, x in ipairs(ls) do if x == b then dup = true end end
			if not dup then ls[#ls + 1] = b end
		end
	end
end

-- All frames at once: only at login, while the loading screen is up.
local function scanModels()
	if not EnumerateFrames then return end
	lastScan = now()
	local ms, ls = {}, {}
	local f = EnumerateFrames()
	while f do
		pcall(sortFrame, f, ms, ls) -- (one odd frame never stops the scan)
		f = EnumerateFrames(f)
	end
	addNamedLoners(ls)
	models, loners = ms, ls
end

-- After that, a few hundred frames a tick in the background. (Walking through every frame in the game at the start
-- of each hide caused a visible hitch.) Addons create some 3D portraits only when first needed (EllesmereUI's target
-- portrait), so a target or focus change asks for a pass soon.
local SCAN_BATCH, SCAN_EVERY = 300, 15
local scan = {}
local function scanSoon()
	if lastScan > now() - SCAN_EVERY + 1 then lastScan = now() - SCAN_EVERY + 1 end
end
local function scanStep()
	if not EnumerateFrames then return end
	if not scan.next then
		if now() - lastScan < SCAN_EVERY then return end
		local ok, first = pcall(EnumerateFrames)
		if not (ok and first) then lastScan = now() return end
		scan.next, scan.models, scan.loners = first, {}, {}
	end
	local f = scan.next
	for _ = 1, SCAN_BATCH do
		pcall(sortFrame, f, scan.models, scan.loners)
		local ok, nxt = pcall(EnumerateFrames, f)
		f = ok and nxt or nil
		if not f then break end
	end
	scan.next = f
	if not f then
		addNamedLoners(scan.loners)
		models, loners = scan.models, scan.loners
		scan.models, scan.loners = nil, nil
		lastScan = now()
	end
end

-- For /hudfade what: the frame under the mouse and how it relates to UIParent.
function HUDFade.DescribeMouseFrame()
	local f
	if GetMouseFoci then f = (GetMouseFoci() or {})[1] elseif GetMouseFocus then f = GetMouseFocus() end
	if not f then return "nothing (the 3D world)" end
	local chain, x = {}, f
	for _ = 1, 8 do
		if type(x) ~= "table" then break end
		local name = ask(x, "GetName")
		chain[#chain + 1] = tostring(name or ask(x, "GetObjectType") or "?")
		if x == UIParent then break end
		x = ask(x, "GetParent")
	end
	local ign = ask(f, "IsIgnoringParentAlpha")
	return table.concat(chain, " < ") .. ((ign == true) and " (ignores the UI's opacity)" or "")
end

local function applyLoners(a)
	for _, f in ipairs(loners) do
		if a >= 0.999 then
			if lonerBase[f] then
				pcall(f.SetAlpha, f, lonerBase[f])
				lonerBase[f], lonerWritten[f] = nil, nil
			end
		elseif ask(f, "IsVisible") then
			local cur = ask(f, "GetAlpha")
			-- Its owner changed it since we last wrote: take that as its own opacity from now on.
			if type(cur) == "number" and (lonerBase[f] == nil or math.abs(cur - (lonerWritten[f] or -1)) > 0.01) then
				lonerBase[f] = cur
			end
			-- Only fade it if we know what to put back afterwards.
			if lonerBase[f] then
				local want = lonerBase[f] * a
				if pcall(f.SetAlpha, f, want) then lonerWritten[f] = want end
			end
		end
	end
end

local function fadeModel(m, a)
	if a >= 0.999 then
		local base = baseAlpha[m]
		if base then
			pcall(m.SetModelAlpha, m, base)
			baseAlpha[m] = nil
		end
	else
		-- (hidden ones too: harmless, and a portrait that appears while hidden is already faded)
		if baseAlpha[m] == nil then
			local own = ask(m, "GetModelAlpha")
			baseAlpha[m] = type(own) == "number" and own or 1
		end
		pcall(m.SetModelAlpha, m, baseAlpha[m] * a)
	end
end

-- Models seen being given something to show (see hookModels), on top of what the scans found.
local seenModels = setmetatable({}, { __mode = "k" })

local function applyModels(a)
	applyLoners(a)
	for _, m in ipairs(models) do fadeModel(m, a) end
	for m in pairs(seenModels) do fadeModel(m, a) end
end

-- The background scan takes a while to walk every frame in a big UI (half a minute or more with many addons), and
-- a portrait an addon creates on first use (EllesmereUI's target portrait) stayed solid until it got there. Every
-- model is given a unit or a model to show before it shows anything, so watching those calls finds it at once.
local function noteModel(m)
	if seenModels[m] or not underUIParent(m) then return end
	seenModels[m] = true
	if state.current < 0.999 then fadeModel(m, state.current) end
end

local function hookModels()
	if not hooksecurefunc then return end
	local hooked = {}
	for kind in pairs(MODEL_TYPES) do
		local ok, f = pcall(CreateFrame, kind)
		local mt = ok and type(f) == "table" and getmetatable(f)
		local methods = type(mt) == "table" and mt.__index
		if type(methods) == "table" and not hooked[methods] then
			hooked[methods] = true
			for _, name in ipairs({ "SetUnit", "SetDisplayInfo", "SetCreature", "SetModel" }) do
				if type(methods[name]) == "function" then
					pcall(hooksecurefunc, methods, name, function(m) pcall(noteModel, m) end)
				end
			end
		end
		if ok and type(f) == "table" then pcall(f.Hide, f) end
	end
end

---------------------------------------------------------------------------
-- The fade
---------------------------------------------------------------------------
local applyFailed = false
local function apply(a)
	state.current = a
	local ok, err = pcall(UIParent.SetAlpha, UIParent, a)
	if not ok and not applyFailed then
		applyFailed = true
		say("the game refused to change the UI's opacity (" .. tostring(err) .. ").")
	end
	applyModels(a)
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
	local cur, tgt = state.current, state.target
	local span = math.max(1 - (DB.hiddenAlpha or 0), 0.01)
	if tgt < cur then
		local secs = math.max(DB.fadeOut, 0.01)
		cur = math.max(tgt, cur - elapsed * span / secs)
	else
		local secs = math.max(DB.fadeIn, 0.01)
		cur = math.min(tgt, cur + elapsed * span / secs)
	end
	apply(cur)
	if cur == tgt then
		self:Hide()
		if state.textPending and tgt < 0.999 then
			state.textPending = false
			hideGameText()
		end
	end
end)

local function setTarget(a, instant)
	if a < state.target and a < 0.999 and not state.cvarsHidden then
		-- Starting to hide. Names, nameplates and the minimap go once the fade has finished: each makes the game
		-- rebuild things, and doing all of it on the first frame of the fade was a visible hitch.
		state.textPending = true
	elseif a >= 0.999 then
		state.textPending = false
		if state.cvarsHidden then showGameText() end
	end
	state.target = a
	if instant then
		apply(a)
		driver:Hide()
	elseif state.current ~= a then
		driver:Show()
	end
	if state.textPending and a < 0.999 and (instant or state.current == a) then
		state.textPending = false
		hideGameText()
	end
end

---------------------------------------------------------------------------
-- Reasons to show the HUD
---------------------------------------------------------------------------
local WINDOWS = {
	"GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame", "VideoOptionsFrame", "WorldMapFrame",
	"CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "PlayerTalentFrame", "TalentFrame", "ClassTalentFrame",
	"QuestFrame", "QuestLogFrame", "GossipFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "LootFrame",
	"TradeFrame", "AuctionHouseFrame", "AuctionFrame", "BankFrame", "GuildBankFrame", "ClassTrainerFrame",
	"FriendsFrame", "PVEFrame", "CollectionsJournal", "EncounterJournal", "AchievementFrame", "ProfessionsFrame",
	"TradeSkillFrame", "MacroFrame", "KeyBindingFrame", "ReadyCheckFrame", "LFGDungeonReadyPopup", "TaxiFrame",
	"FlightMapFrame", "ItemTextFrame", "BarberShopFrame", "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
	"ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
	"ContainerFrame5", "ContainerFrame6",
	-- EllesmereUI
	"EUI_MainBagFrame", "EUI_BagsWindowFrame", "EUI_ReagentBagFrame",
}

local function shown(name)
	local f = _G[name]
	if type(f) ~= "table" then return false end
	if f.which == "DEATH" then return false end -- (see "dying" below)
	return ask(f, "IsVisible") == true
end

-- Arranging your frames in the game's Edit Mode or EllesmereUI's unlock mode: what is open, or nil.
local function arranging()
	if EditModeManagerFrame and ask(EditModeManagerFrame, "IsShown") == true then return "Edit Mode" end
	local eui = _G.EllesmereUI
	if type(eui) == "table" and type(eui.IsUnlockModeActive) == "function" then
		local ok, on = pcall(eui.IsUnlockModeActive, eui)
		if ok and readable(on) == true then return "EllesmereUI unlock mode" end
	end
	return nil
end

-- Returns what is open (for /hudfade why), or nil. Arranging your frames counts too, so the HUD stays visible
-- while you do it, until the away time.
local function windowOpen()
	if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return "typing" end
	if GetCursorInfo and GetCursorInfo() then return "holding something on the cursor" end
	local layout = arranging()
	if layout then return layout end
	for _, name in ipairs(WINDOWS) do
		if shown(name) then return name end
	end
	if UISpecialFrames then -- every window that closes with Escape, including other addons'
		for _, name in ipairs(UISpecialFrames) do
			if shown(name) then return name end
		end
	end
	return nil
end

-- Away: the safety net over the idle time. After this long with no input at all the HUD hides even over an open
-- window or chat box, and even with Hide when idle set to Never, so a window left open while you are away from the
-- keyboard never keeps it on screen for hours. Combat still brings it back.
local function isAway(t)
	local minutes = tonumber(DB.awayMinutes) or 10
	return minutes > 0 and (t - state.lastInput) >= minutes * 60
end

-- Reasons that bring the HUD back even while you are idle.
local function urgentReasons(out)
	if state.peek then out.peek = true end
	if DB.showCombat and state.inCombat then out.combat = true end
	if DB.showWindows and not isAway(now()) then
		local w = windowOpen()
		if w then out.window = w end
	end
end

-- Reasons that bring it back only while you are playing (not idle).
-- Dying counts as activity the moment it happens (see PLAYER_DEAD), so the HUD comes up and then hides again after
-- your idle time, even if you stay dead: lying dead while away must not leave the HUD on screen for hours. For the
-- same reason the Release Spirit popup, which stays up the whole time, does not count as an open window.
local function softReasons(out)
	if DB.showDead and is(UnitIsDead, "player") then out.dead = true end
	if DB.showTarget and is(UnitExists, "target") then out.target = true end
	if DB.showCasting and state.casting then out.casting = true end
end

local reasons = {}
local function currentReasons(idle)
	wipe(reasons)
	urgentReasons(reasons)
	if not idle then softReasons(reasons) end
	-- A reason you hid the HUD over stays ignored until it ends.
	for r in pairs(state.suppressed) do
		if not reasons[r] then state.suppressed[r] = nil else reasons[r] = nil end
	end
	return reasons
end

local function isIdle(t)
	return (DB.idleSeconds > 0 and (t - state.lastInput) >= DB.idleSeconds) or isAway(t)
end

-- Typing (chat and the like) is activity: once you send, the idle timer starts from there. A chat box left open
-- without typing is not.
local function typing(t)
	local box = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
	if not box then
		state.typingIn, state.typed = nil, nil
		return
	end
	local text = ask(box, "GetText")
	if box ~= state.typingIn or text ~= state.typed then state.lastInput = t end
	state.typingIn, state.typed = box, text
end

local function update(instant)
	if not DB then return end
	local t = now()
	if state.shot then
		setTarget(0, true)
		return
	end
	if not DB.enabled then
		if state.target < 0.999 or state.current < 0.999 or state.cvarsHidden then setTarget(1, true) end
		return
	end
	if DB.showWindows then typing(t) end
	local idle = isIdle(t)
	local base = not state.hudOff and not idle
	local reason = next(currentReasons(idle)) ~= nil
	if reason then state.lastWanted = t end
	-- A short grace after a reason ends (a target cleared between two pulls, a window closed), so the HUD does not
	-- blink. None when you go idle or press hide: those happen exactly when you set them.
	local show = base or reason or (not idle and (t - state.lastWanted) < GRACE)
	setTarget(show and 1 or DB.hiddenAlpha, instant)
	-- While hidden and still: put our opacity back if something else changed it, and catch models that just appeared.
	if state.target < 0.999 and not driver:IsShown() then
		local a = ask(UIParent, "GetAlpha")
		if type(a) == "number" and math.abs(a - state.target) > 0.01 then apply(state.target) else applyModels(state.current) end
	end
end
HUDFade.Update = update

-- Why the HUD is up or hidden right now, for /hudfade why. Returns the lines to print, first one without the
-- "HUD Fade:" label.
local REASON_ORDER = { "peek", "combat", "dead", "window", "target", "casting" }
local REASON_TEXT = {
	peek = "Peek key held", combat = "Combat", dead = "Death",
	target = "Target", casting = "Casting",
}

local function windowText(v)
	if v == "typing" then return "Typing" end
	if v == "holding something on the cursor" then return "Holding something on the cursor" end
	if v == "Edit Mode" or v == "EllesmereUI unlock mode" then return v end
	return "Window open (" .. tostring(v) .. ")"
end

local function listLines(lines, label, items)
	if #items == 1 then
		lines[#lines + 1] = label .. " " .. items[1]
	else
		lines[#lines + 1] = label
		for _, item in ipairs(items) do lines[#lines + 1] = "   - " .. item end
	end
end

function HUDFade.Explain(skipTyping)
	if not DB.enabled then
		return { "|cffff4040Disabled|r", "The HUD stays visible while HUD Fade is off. Turn it on with /hudfade on." }
	end
	local lines = { "|cff40ff40Enabled|r" }
	local t = now()
	local idle = isIdle(t)
	local idleFor = math.max(0, math.floor(t - state.lastInput))

	if state.target < 0.999 then
		local why = {}
		if state.hudOff then why[#why + 1] = "You hid it" end
		if isAway(t) then
			why[#why + 1] = string.format("Away for %d min (open windows no longer keep it visible)", math.floor(idleFor / 60))
		elseif idle then
			why[#why + 1] = string.format("Idle for %ds", idleFor)
		end
		if state.shot then why[#why + 1] = "Taking a screenshot" end
		if #why == 0 then why[1] = "Something just ended, so it is hiding again" end
		listLines(lines, "HUD hidden due to:", why)
		local p = HUDFade.PointerWhy()
		if p then lines[#lines + 1] = (p == "hidden" or p == "about to hide") and ("Pointer: " .. p) or ("Pointer visible due to: " .. p) end
		return lines
	end

	local causes = {}
	local reasons = currentReasons(idle)
	for _, k in ipairs(REASON_ORDER) do
		local v = reasons[k]
		if v and k == "window" then
			if not (skipTyping and v == "typing") then causes[#causes + 1] = windowText(v) end
		elseif v then
			causes[#causes + 1] = REASON_TEXT[k]
		end
	end
	if not state.hudOff and not idle then
		if DB.idleSeconds <= 0 then
			causes[#causes + 1] = "Hide when idle is set to Never"
		else
			local detail = string.format("%d/%ds", idleFor, DB.idleSeconds)
			local keysHeld = {}
			for k in pairs(held) do keysHeld[#keysHeld + 1] = k end
			if #keysHeld > 0 then
				detail = detail .. ", holding " .. table.concat(keysHeld, " ")
			elseif state.moving and DB.activeAutorun then
				detail = detail .. ", auto-running counts as active"
			end
			causes[#causes + 1] = "Not enough time idling (" .. detail .. ")"
		end
	end
	if #causes == 0 then causes[1] = "Something just ended, it hides in a moment" end
	listLines(lines, "HUD visible due to:", causes)
	return lines
end

---------------------------------------------------------------------------
-- Input (for the idle timer)
---------------------------------------------------------------------------
local function input()
	state.lastInput = now()
end

local releaseOnKey -- (set further down, with the mouse pointer)
local keys = CreateFrame("Frame")
-- Only movement keys count as you being active. Any other key acts through what it does: Tab gives you a target
-- (shown if "You have a target" is ticked), an ability starts a cast or a fight, B opens your bags, and so on.
local MOVE_ACTIONS = {
	MOVEFORWARD = true, MOVEBACKWARD = true, STRAFELEFT = true, STRAFERIGHT = true, TURNLEFT = true,
	TURNRIGHT = true, JUMP = true, SITORSTAND = true, MOVEANDSTEER = true, PITCHUP = true, PITCHDOWN = true,
	TOGGLEAUTORUN = true,
}
local function isMoveKey(key)
	if not (key and GetBindingAction) then return false end
	local ok, action = pcall(GetBindingAction, key, true)
	return ok and action and MOVE_ACTIONS[action] or false
end
local TURN_ACTIONS = { TURNLEFT = true, TURNRIGHT = true }
local function isTurnKey(key)
	if not (key and GetBindingAction) then return false end
	local ok, action = pcall(GetBindingAction, key, true)
	return ok and TURN_ACTIONS[action] or false
end
local function turnKeyHeld()
	for k in pairs(held) do if isTurnKey(k) then return true end end
	return false
end

local function onKey(_, key)
	if isMoveKey(key) then
		if key ~= GetBindingKey("TOGGLEAUTORUN") then held[key] = true end
		input()
	end
	if releaseOnKey then releaseOnKey(key) end
end
local function onKeyUp(_, key)
	if key then held[key] = nil end
end
local function listenToKeys()
	-- Only take keyboard events if they can pass straight through to the game; otherwise we would swallow keys.
	if keys.SetPropagateKeyboardInput and pcall(keys.SetPropagateKeyboardInput, keys, true) then
		keys:EnableKeyboard(true)
		keys:SetScript("OnKeyDown", onKey)
		keys:SetScript("OnKeyUp", onKeyUp)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Mouse pointer (opt-in, experimental). Addons cannot give the pointer an invisible picture (the game draws a
-- black square), but the game hides the pointer itself while the mouse steers the view ("mouselook"). So a still
-- pointer is hidden by switching mouselook on. Moving the mouse then turns your character a touch, which is how
-- the move is noticed: mouselook goes off at once and the pointer comes back.
---------------------------------------------------------------------------
local ours = false -- mouselook was started by HUD Fade
local facing       -- the character's facing when it started (nil where the game keeps it secret, e.g. instances)
local startedAt = 0
-- Starting mouselook turns the character to where the camera points. That turn is not you moving the mouse, so the
-- facing is only watched once it has settled; and only a turn above about a third of a degree counts.
local SETTLE, TURN = 0.4, 0.006

-- That turn is also why the camera moved a little before the pointer came back. So while the pointer is hidden,
-- mouse look speed is turned down to a tenth: the turn is too small to see but still enough to notice (the turn is
-- the one sure way to see the mouse move while the pointer is hidden). On a flight path the route turns you anyway,
-- so the turn is not watched there and the speed goes down to almost nothing: the camera stays still until you
-- click or drag. The real speeds wait in the saved variables like the names above, so even a crash gets them back at
-- the next login. Right-drags and steering while flying keep the normal speed.
local LOOK_CVARS = { "cameraYawMoveSpeed", "cameraPitchMoveSpeed" }
local LOOK_SLOW, TURN_SLOW, LOOK_TAXI = 0.1, 0.0008, 0.001
local mouseSlowed = false -- (the share of your mouse look speed in use while hidden, or false for all of it)

local function slowMouse(share)
	share = share or false
	if share == mouseSlowed or not DB then return end
	if share then
		for _, name in ipairs(LOOK_CVARS) do
			local saved = DB.restore[name]
			local value = saved
			if value == nil then
				local ok, v = pcall(getCVar, name)
				value = ok and readable(v) or nil
			end
			local n = tonumber(value)
			if n and n > 0 and pcall(setCVar, name, tostring(n * share)) and saved == nil then
				DB.restore[name] = value
			end
		end
	else
		cvarsBack(LOOK_CVARS)
	end
	mouseSlowed = share
end

local function lookShare()
	if state.steering then return false end
	return state.onTaxi and LOOK_TAXI or LOOK_SLOW
end

-- How far the mouse moved since the last frame, where the game can tell (nil where it cannot).
local function cursorDelta()
	if not GetCursorDelta then return nil end
	local ok, dx, dy = pcall(GetCursorDelta)
	dx, dy = readable(dx), readable(dy)
	if not ok or type(dx) ~= "number" or type(dy) ~= "number" then return nil end
	return math.abs(dx) + math.abs(dy)
end
local taxiMoved, taxiStill = 0, 0

local function getFacing()
	if not GetPlayerFacing then return nil end
	local ok, f = pcall(GetPlayerFacing)
	if ok and type(f) == "number" and not (issecretvalue and issecretvalue(f)) then return f end
	return nil
end

-- While you auto-run with the pointer hidden, a left press counts as both buttons (the game's run-with-the-mouse),
-- which ends auto-run and stops you as you let go. So while you move with the pointer hidden, the left button points
-- at this invisible button instead: the first press only brings the pointer back and you keep running. Standing
-- still the left button is left alone, so a left-drag turns the camera straight away.
local wake = CreateFrame("Button", "HUDFadeWakeButton", UIParent)
wake:SetSize(1, 1)
wake:EnableMouse(false)
if wake.RegisterForClicks then wake:RegisterForClicks("AnyDown", "AnyUp") end
local WAKE_BIND = "CLICK HUDFadeWakeButton:LeftButton"
local leftOverridden = false

local function syncLeftOverride()
	local want = (ours and state.moving) and true or false
	if want == leftOverridden or not SetMouselookOverrideBinding then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if pcall(SetMouselookOverrideBinding, "BUTTON1", want and WAKE_BIND or nil) then leftOverridden = want end
end

local function releasePointer(stop, moved)
	if not ours then return end
	ours = false
	slowMouse(false)
	if stop and MouselookStop then pcall(MouselookStop) end
	syncLeftOverride()
	if moved then state.lastMouseMove = now() end
end

wake:SetScript("OnClick", function()
	if not ours then return end
	state.wakeClick = true -- (this press turned nothing, so it is no camera drag: see cameraFree below)
	releasePointer(true, true)
end)

local function hidePointer()
	if ours or not MouselookStart then return end
	if IsMouselooking and IsMouselooking() then return end -- (you are already steering)
	-- The left button's override has to be in place before mouselook starts, or the game may not use it.
	ours = true
	syncLeftOverride()
	if not pcall(MouselookStart) then
		ours = false
		syncLeftOverride()
		return
	end
	slowMouse(lookShare())
	taxiMoved = 0
	facing = getFacing()
	startedAt = now()
	state.cameraFree = false -- (hiding turned your character to the camera)
end

-- After a right-drag the game shows the pointer again as you let go. This checks every frame for a moment after a
-- drag, so the pointer is taken back straight away instead of flashing up until the next regular check.
local dragEnd = CreateFrame("Frame")
dragEnd:Hide()

releaseOnKey = function(key)
	if not ours then return end
	-- With the pointer hidden, the turn keys would strafe instead of turn: give it back first (this runs before the
	-- game acts on the key). Where a mouse move does not bring it back (secret facing, a flight path, steering with
	-- the mouse), any key does.
	if isTurnKey(key) or not facing or state.onTaxi or state.steering then releasePointer(true, true) end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	if not ours then return end
	local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
	local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
	if right then
		releasePointer(false) -- (right drag steers anyway: the game's own drag carries on from here)
		dragEnd:Show()
		return
	elseif left then
		-- Left drag only turns the camera, but with our mouselook still on it would steer your character too.
		-- Switch ours off so the game's own camera drag takes over.
		releasePointer(true)
		return
	end
	if IsMouselooking and not IsMouselooking() then
		-- Something else ended it (alt-tab, the game, another addon). Wait for a real mouse move before trying again:
		-- trying while WoW is in the background can move the pointer on your other screens.
		releasePointer(false)
		state.pointerRefused = true
		return
	end
	-- On a flight path the route turns you, so the facing says nothing about the mouse, and the camera stays still
	-- (see LOOK_TAXI). A click or a key brings the pointer back, and so does moving the mouse where the game reports
	-- the mouse's own movement.
	if state.onTaxi then
		local d = cursorDelta()
		if not d then return end
		local t = now()
		if d > 0 then
			taxiMoved, taxiStill = taxiMoved + d, t
		elseif t - taxiStill > 0.3 then
			taxiMoved = 0
		end
		if taxiMoved > 8 and t - startedAt >= SETTLE then releasePointer(true, true) end
		return
	end
	local f = getFacing()
	if not f then return end
	if not facing or now() - startedAt < SETTLE then
		facing = f
		return
	end
	local d = math.abs(f - facing)
	if d > math.pi then d = 2 * math.pi - d end -- (the facing wraps around at a full turn)
	if d <= (mouseSlowed and TURN_SLOW or TURN) then return end
	if state.steering then
		-- Flying, swimming or in a vehicle with "even when flying" on: the mouse steers you and the pointer stays
		-- hidden. Steering counts like turning the camera with the right button, so only if you want it to.
		facing = f
		if DB.activeCamera then input() end
	else
		releasePointer(true, true)
	end
end)

-- An open window keeps the pointer only while it is also what keeps the HUD up. Once you hide the HUD over a
-- window (or windows are set not to bring the HUD back), the pointer can go as well. An item held on the pointer
-- always keeps it; typing keeps it until you have been away (see isAway).
local function windowKeepsPointer()
	local w = windowOpen()
	if not w then return false end
	if w == "holding something on the cursor" then return true end
	if isAway(now()) then return false end -- (a window or chat box left open while you are away)
	if w == "typing" then return true end
	return DB.showWindows and not state.suppressed.window
end

-- The camera can point somewhere other than where your character faces (after a left-drag). Hiding the pointer
-- switches on the same mode as a right-drag, which turns your character to face the camera. So after a left-drag the
-- pointer stays until the two line up again: a right-drag lines them up, and so does moving for a moment with the
-- game's camera following on (Camera Following Style other than Never).
local function cameraFollows()
	local ok, v = pcall(getCVar, "cameraSmoothStyle")
	return not (ok and v == "0")
end

local function mouseOverWorld()
	local f
	if GetMouseFoci then
		local ok, list = pcall(GetMouseFoci)
		f = ok and type(list) == "table" and list[1] or nil
	elseif GetMouseFocus then
		local ok, x = pcall(GetMouseFocus)
		f = ok and x or nil
	end
	return f == nil or f == WorldFrame
end

local lastX, lastY = 0, 0
local leftSince, leftOnWorld, followSince

-- Flying or swimming the mouse sets your pitch as well as your facing, and in a vehicle it often steers or aims the
-- vehicle. Hiding the pointer there turns you to where the camera points, up and down included, and moving the mouse
-- then steers you as with the right button held. So the pointer only hides there if you ask for it.
local function steerPlace()
	if is(IsFlying) then return "flying" end
	if is(IsSwimming) then return "swimming" end
	if is(UnitInVehicle, "player") then return "in a vehicle" end
	return nil
end

-- Why the pointer has to stay visible right now (nil = it can hide). Also used by /hudfade why.
local function pointerBlock(t, anyButton)
	if not (DB.enabled and DB.hideCursor) then return "pointer hiding is off" end
	if state.target >= 0.999 then return "the HUD is visible" end
	if state.peek then return "peek key held" end
	if state.inCombat then return "in combat" end
	if anyButton then return "a mouse button is held" end
	-- (on a flight path you cannot steer, so there it is fine; elsewhere only if you asked for it)
	if not (state.onTaxi or state.steering) then
		local place = steerPlace()
		if place then return place .. " (see Also when flying or swimming)" end
	end
	if turnKeyHeld() then return "turning with the keyboard" end
	if windowKeepsPointer() then return "a window is open, or you are typing" end
	if state.cameraFree then
		-- After a left-drag. Once the mouse has been still for your idle time the pointer goes anyway, turning your
		-- character to the camera, so a pointer never sits on screen for hours.
		local wait = DB.idleSeconds > 0 and DB.idleSeconds or 30
		local still = t - math.max(state.cameraFreeSince or 0, state.lastMouseMove or 0)
		if still < wait then
			return string.format("the camera points away from your character (a right-drag or moving lines them up, or it hides anyway after %d s without moving the mouse)", wait)
		end
	end
	if state.pointerRefused then return "the game took the mouse back, e.g. alt-tab (move the mouse to try again)" end
	if (t - (state.lastMouseMove or 0)) < 2 then return "the mouse moved less than 2 s ago" end
	return nil
end

local function pollMouse()
	local t = now()
	local taxi = is(UnitOnTaxi, "player")
	local steer = not taxi and DB.hideCursorSteer and steerPlace() ~= nil
	if state.onTaxi and not taxi then
		-- Landed. The mouse was turning the camera, not you: hand it back, and since the camera may now point anywhere,
		-- wait for it to line up with your character before hiding again (see cameraFollows above).
		releasePointer(true)
		state.cameraFree, state.cameraFreeSince = true, t
	elseif state.steering and not steer and ours then
		-- Landed, or out of the water or the vehicle. Camera and character are lined up (the mouse was steering), so
		-- the pointer can stay hidden: from here a mouse move brings it back again.
		facing, startedAt = getFacing(), t
	end
	state.onTaxi, state.steering = taxi, steer
	if ours then slowMouse(lookShare()) end
	local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
	local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
	local anyButton = left or right
	if not ours then -- (while ours, the pointer is frozen and the watcher above looks for moves)
		local x, y = GetCursorPosition()
		if anyButton or (IsMouselooking and IsMouselooking()) then
			-- A button is turning the camera or steering, so the pointer is parked: where the game puts it back as you
			-- let go is not you moving the mouse. Running with both buttons is moving yourself; turning the camera only
			-- counts if you want it to.
			lastX, lastY, state.dragAt = x, y, t
			if (left and right) or DB.activeCamera then input() end
		elseif t - (state.dragAt or -1) < 0.3 then
			lastX, lastY = x, y
		elseif math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2 then
			lastX, lastY = x, y
			state.lastMouseMove = t
			state.pointerRefused = false
			-- While the HUD is up, using the mouse keeps it up. Once it has hidden for being idle, the mouse only brings it
			-- back if you want it to (otherwise keys do, e.g. coming back from alt-tab).
			if DB.mouseWakes or not isIdle(t) then input() end
		end
	end
	-- Camera and character lined up or not (see cameraFollows above).
	-- (any left press on the 3D world may turn the camera, even a tiny tweak)
	if left and not right then
		if not leftSince then leftSince, leftOnWorld = t, mouseOverWorld() end
		if leftOnWorld and not state.wakeClick then state.cameraFree, state.cameraFreeSince = true, t end
	else
		leftSince = nil
		if not left then state.wakeClick = false end
	end
	-- You started or stopped moving with the pointer hidden. Starting to move points the left button at the wake
	-- button, and mouselook is restarted around it so the game picks the change up (within one frame: the pointer
	-- does not show).
	if ours and (state.moving and true or false) ~= leftOverridden then
		local was = leftOverridden
		if not was and MouselookStop then pcall(MouselookStop) end
		syncLeftOverride()
		if not was and MouselookStart then pcall(MouselookStart) end
	end
	if right then state.cameraFree = false end
	if state.cameraFree and state.moving and not anyButton and cameraFollows() then
		followSince = followSince or t
		if t - followSince >= 2 then state.cameraFree = false end
	else
		followSince = nil
	end
	if IsKeyDown then -- (drop keys whose release never reached us)
		for k in pairs(held) do
			local ok, down = pcall(IsKeyDown, k)
			if ok and readable(down) == false then held[k] = nil end
		end
	end
	if state.moving then
		-- Moving counts while you hold a key for it. Auto-run, follow and flight paths only count if you want them to.
		if next(held) or DB.activeAutorun then input() end
	end
	-- (with a button held, the watcher above decides how to hand the mouse back)
	if anyButton and DB.hideCursor then dragEnd:Show() end
	if not pointerBlock(t, anyButton) then hidePointer() elseif ours and not anyButton then releasePointer(true) end
end

local dragGone
dragEnd:SetScript("OnUpdate", function(self)
	if ours or not DB then self:Hide() return end
	if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
		dragGone = nil
		return
	end
	local t = now()
	dragGone = dragGone or t
	if t - dragGone > 0.5 then
		dragGone = nil
		self:Hide()
		return
	end
	if IsMouselooking and IsMouselooking() then return end -- (the game is still letting go)
	if not pointerBlock(t, false) then hidePointer() end
end)

function HUDFade.PointerWhy()
	if not (DB.enabled and DB.hideCursor) then return nil end
	if ours then return leftOverridden and "hidden (moving: a left click only brings it back)" or "hidden" end
	local anyButton = IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
	return pointerBlock(now(), anyButton) or "about to hide"
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function suppressCurrent()
	wipe(state.suppressed)
	local r = {}
	urgentReasons(r)
	softReasons(r)
	r.peek = nil
	for k in pairs(r) do state.suppressed[k] = true end
end

function HUDFade.IsHidden()
	return state.target < 0.999
end

function HUDFade.Hide()
	state.hudOff = true
	suppressCurrent()
	state.lastWanted = -math.huge
	update()
end

function HUDFade.Show()
	state.hudOff = false
	wipe(state.suppressed)
	input()
	update()
end

function HUDFade.Toggle()
	if not DB.enabled then
		say("is turned off. Turn it on in /hudfade options, with your on/off key, or with /hudfade on.")
		return
	end
	if HUDFade.IsHidden() then HUDFade.Show() else HUDFade.Hide() end
end

-- The switch for the whole addon. Off: HUD fully back, names and minimap back, your Hide UI key does its normal job.
function HUDFade.SetEnabled(on)
	DB.enabled = on and true or false
	releasePointer(true)
	state.hudOff = false
	state.peek = false
	wipe(state.suppressed)
	input()
	HUDFade.ApplyOverrides(true)
	update(true)
	HUDFade.UpdateShift()
	if HUDFade.RefreshOptions then HUDFade.RefreshOptions() end
	say(DB.enabled and "on." or "off. The HUD stays visible and your Hide UI key works as normal.")
end

function HUDFade.ToggleEnabled()
	HUDFade.SetEnabled(not DB.enabled)
end

function HUDFade.Peek(down)
	if not DB.enabled then return end
	state.peek = down and true or false
	if down then input() else state.lastWanted = -math.huge end
	update(down)
end

function HUDFade.CleanScreenshot()
	if not Screenshot then return end
	state.shot = true
	update(true)
	-- Names and nameplates go away on the next frame; wait a moment so they are out of the picture.
	C_Timer.After(0.25, function()
		Screenshot()
		-- In case the game never tells us the screenshot finished.
		C_Timer.After(2, function()
			if state.shot then state.shot = false; update() end
		end)
	end)
end

function HUDFade_OnCompartmentClick()
	if HUDFade.OpenOptions then HUDFade.OpenOptions() end
end

---------------------------------------------------------------------------
-- Key overrides (Alt+Z and Print Screen)
---------------------------------------------------------------------------
local bindOwner = CreateFrame("Frame")
local boundSignature
local function applyOverrides(force)
	if InCombatLockdown() then
		state.pendingBinds = true
		return
	end
	local parts = {}
	local plan = {}
	if DB.enabled and DB.replaceAltZ then
		for _, key in ipairs({ GetBindingKey("TOGGLEUI") }) do plan[#plan + 1] = { key, "HUDFADE_TOGGLE" } end
	end
	if DB.enabled and DB.cleanPrintScreen then
		for _, key in ipairs({ GetBindingKey("SCREENSHOT") }) do plan[#plan + 1] = { key, "HUDFADE_SCREENSHOT" } end
	end
	for _, p in ipairs(plan) do parts[#parts + 1] = p[1] .. "=" .. p[2] end
	local signature = table.concat(parts, ",")
	if signature == boundSignature and not force then return end
	boundSignature = signature
	ClearOverrideBindings(bindOwner)
	for _, p in ipairs(plan) do SetOverrideBinding(bindOwner, true, p[1], p[2]) end
	state.pendingBinds = false
end
HUDFade.ApplyOverrides = applyOverrides

---------------------------------------------------------------------------
-- Pixel shift (burn-in protection). Every few minutes the whole interface moves a pixel or two around a small
-- circle, so the same pixels never show the same shapes for hours. Like the fade, it moves the one layer every
-- frame hangs from (UIParent): Blizzard UI, EllesmereUI and every other addon move together and keep their layout.
-- Nothing is saved. The normal position is remembered and put back when the option or the addon is turned off and
-- while Edit Mode is open. Nothing moves during combat (the game forbids it, and a jump mid-fight would be rude).
---------------------------------------------------------------------------
local SHIFT_STEPS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local shift = {
	index = (math.random and math.random(#SHIFT_STEPS)) or 1, -- (each session starts somewhere else on the circle)
	nextAt = 0,
	base = nil,     -- UIParent's own anchors, while we have it moved
	sig = nil,      -- what its anchors looked like right after our last move
	px = 0, py = 0, -- current offset, in pixels
	inset = 0,      -- how far in from every screen edge the interface is kept, in pixels
	ex = 0, ey = 0, -- how far that took the interface's bottom-left corner, in its own units
	fights = 0, since = 0, gaveUp = false,
	lastSync = -100,
}

local function readAnchors(f)
	local n = ask(f, "GetNumPoints")
	if type(n) ~= "number" or n < 1 then return nil end
	local t = {}
	for i = 1, n do
		local ok, point, rel, relPoint, x, y = pcall(f.GetPoint, f, i)
		x, y = readable(x), readable(y)
		if not ok or type(point) ~= "string" or type(x) ~= "number" or type(y) ~= "number" then return nil end
		t[i] = { point, rel, relPoint, x, y }
	end
	return t
end

local function anchorSig(t)
	if not t then return "" end
	local parts = {}
	for i, a in ipairs(t) do
		parts[i] = string.format("%s|%s|%s|%.2f|%.2f", a[1], tostring(a[2]), tostring(a[3]), a[4], a[5])
	end
	return table.concat(parts, ";")
end

-- Moves the interface by dx, dy, kept "inset" in from every screen edge. With the inset as large as the furthest
-- move, a frame you placed against an edge never goes past it: at most it comes back to exactly where you put it.
local function placeUI(t, dx, dy, inset)
	UIParent:ClearAllPoints()
	for _, a in ipairs(t) do
		local point, x, y = a[1], a[4] + dx, a[5] + dy
		if point:find("LEFT") then x = x + inset elseif point:find("RIGHT") then x = x - inset end
		if point:find("TOP") then y = y - inset elseif point:find("BOTTOM") then y = y + inset end
		UIParent:SetPoint(point, a[2], a[3], x, y)
	end
end

-- How far a move takes the interface's bottom-left corner (EllesmereUI counts from there, see below).
local function cornerMove(t, dx, dy, inset)
	local x, y
	for _, a in ipairs(t) do
		local point = a[1]
		if point:find("LEFT") then x = dx + inset elseif not x and point:find("RIGHT") then x = dx - inset end
		if point:find("BOTTOM") then y = dy + inset elseif not y and point:find("TOP") then y = dy - inset end
	end
	return x or dx, y or dy
end

-- One screen pixel in UIParent's own units.
local function pixelUnit()
	local factor
	if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
		local ok, f = pcall(PixelUtil.GetPixelToUIUnitFactor)
		factor = ok and readable(f) or nil
	end
	if type(factor) ~= "number" and GetPhysicalScreenSize then
		local ok, _, h = pcall(GetPhysicalScreenSize)
		h = ok and readable(h) or nil
		if type(h) == "number" and h > 0 then factor = 768 / h end
	end
	local scale = ask(UIParent, "GetScale")
	if type(factor) ~= "number" or type(scale) ~= "number" or scale <= 0 then return nil end
	return factor / scale
end

-- While you arrange your frames (the game's Edit Mode, EllesmereUI's unlock mode) the interface goes back to its
-- exact place, so the positions you save are never off by the shift.
local function layoutModeOpen()
	return arranging() ~= nil
end

local hookEUI

local function syncShift(force)
	local t = now()
	if not force and t - shift.lastSync < 1 then return end
	shift.lastSync = t
	hookEUI()
	if not DB or InCombatLockdown() then return end
	local cur = readAnchors(UIParent)
	if not cur then return end
	-- Something else moved the interface since our last move (an ultrawide addon, the game): that is the new normal.
	-- If it keeps happening, step aside instead of fighting over it.
	if shift.base and anchorSig(cur) ~= shift.sig then
		shift.base, shift.px, shift.py, shift.inset, shift.ex, shift.ey = nil, 0, 0, 0, 0, 0
		if t - shift.since > 10 then shift.since, shift.fights = t, 0 end
		shift.fights = shift.fights + 1
		if shift.fights >= 3 and not shift.gaveUp then
			shift.gaveUp = true
			say("pixel shift stopped: another addon keeps moving the interface back. /hudfade shift on tries again.")
		end
	end
	local px, py, inset = 0, 0, 0
	if DB.enabled and DB.pixelShift and not shift.gaveUp and not layoutModeOpen() then
		if t >= shift.nextAt then
			shift.index = shift.index % #SHIFT_STEPS + 1
			shift.nextAt = t + math.max(DB.shiftMinutes or 3, 0.5) * 60
		end
		local step = SHIFT_STEPS[shift.index]
		local d = DB.shiftPixels or 2
		px, py, inset = step[1] * d, step[2] * d, d
	end
	local unit = pixelUnit()
	if not unit then return end
	-- (a changed UI scale changes what a pixel is, so that counts as a change too)
	if px == shift.px and py == shift.py and inset == shift.inset and (unit == shift.unit or inset == 0) then return end
	local base = shift.base or cur
	if not pcall(placeUI, base, px * unit, py * unit, inset * unit) then
		-- Never leave the interface without a position.
		pcall(placeUI, base, 0, 0, 0)
		shift.base, shift.px, shift.py, shift.inset, shift.ex, shift.ey, shift.gaveUp = nil, 0, 0, 0, 0, 0, true
		say("pixel shift stopped: the game refused to move the interface.")
		return
	end
	if inset == 0 then -- (back in its own place: nothing of ours to keep)
		shift.base, shift.sig, shift.ex, shift.ey = nil, nil, 0, 0
	else
		shift.base, shift.sig = base, anchorSig(readAnchors(UIParent))
		shift.ex, shift.ey = cornerMove(base, px * unit, py * unit, inset * unit)
	end
	shift.px, shift.py, shift.inset, shift.unit = px, py, inset, unit
end

-- EllesmereUI places an element you anchored to another one (its cast bar under the player frame, a bar on top of
-- another) from where that one is on screen, counting from the screen's corner as if the interface started there.
-- With the interface moved, that puts the element off by the move a second time. It shows on anything placed again
-- while shifted, like a cast bar appearing for a cast. Those placements go through EllesmereUI.SetFramePoint, so for
-- anchored elements we take our move back out of what it asks for. Its unlock mode gets the interface back in place
-- the moment it opens, before any mover reads a position.
local euiHook, euiListening

local function euiAnchored(eui, frame)
	local db = _G.EllesmereUIDB
	local anchors = type(db) == "table" and db.unlockAnchors
	local elements = eui._unlockRegisteredElements
	if type(anchors) ~= "table" or type(elements) ~= "table" then return false end
	for key, info in pairs(anchors) do
		local element = type(info) == "table" and info.target and elements[key]
		if type(element) == "table" and type(element.getFrame) == "function" then
			local ok, f = pcall(element.getFrame, key)
			if ok and f == frame then return true end
		end
	end
	return false
end

local function euiPlace(eui, frame, rel, relPoint, x, y)
	if rel ~= UIParent or relPoint ~= "CENTER" then return x, y end
	if type(readable(x)) ~= "number" or type(readable(y)) ~= "number" then return x, y end
	if not euiAnchored(eui, frame) then return x, y end
	local fs, us = ask(frame, "GetEffectiveScale"), ask(UIParent, "GetEffectiveScale")
	if type(fs) ~= "number" or type(us) ~= "number" or fs <= 0 or us <= 0 then return x, y end
	return x - shift.ex * us / fs, y - shift.ey * us / fs
end

hookEUI = function()
	local eui = _G.EllesmereUI
	if type(eui) ~= "table" then return end
	local set = eui.SetFramePoint
	if not euiHook and type(set) == "function" then -- (once: every addon has loaded by now)
		euiHook = function(frame, point, rel, relPoint, x, y, ...)
			if shift.ex ~= 0 or shift.ey ~= 0 then
				local ok, px, py = pcall(euiPlace, eui, frame, rel, relPoint, x, y)
				if ok then x, y = px, py end
			end
			return set(frame, point, rel, relPoint, x, y, ...)
		end
		eui.SetFramePoint = euiHook
	end
	if not euiListening and type(eui.RegisterUnlockModeListener) == "function" then
		euiListening = true
		pcall(eui.RegisterUnlockModeListener, eui, "HUDFade", function(active)
			if active then syncShift(true) end
		end)
	end
end

-- Nothing of the shift is saved: put the interface back in its own place before logging out or reloading, in case
-- another addon saves frame positions from where they are on screen.
local function restoreShift()
	if shift.base and not InCombatLockdown() then pcall(placeUI, shift.base, 0, 0, 0) end
	shift.base, shift.sig, shift.px, shift.py, shift.inset, shift.ex, shift.ey = nil, nil, 0, 0, 0, 0, 0
end

function HUDFade.UpdateShift()
	if DB and DB.pixelShift and shift.gaveUp then shift.gaveUp, shift.fights = false, 0 end
	syncShift(true)
end

function HUDFade.ShiftNow()
	shift.nextAt = 0
	syncShift(true)
end

function HUDFade.ShiftStatus()
	if not DB.pixelShift then return "pixel shift is off." end
	local text = "pixel shift is on: " .. DB.shiftPixels .. " px every " .. DB.shiftMinutes .. " min"
	if not DB.enabled then return text .. ", but HUD Fade is turned off." end
	if shift.gaveUp then return text .. ", stopped because another addon keeps moving the interface back." end
	text = text .. ". Offset now " .. shift.px .. "," .. shift.py .. " px, kept " .. shift.inset .. " px in from the screen edges"
	if InCombatLockdown() then return text .. ", waiting for combat to end." end
	return text .. string.format(", next move in %d s.", math.max(0, shift.nextAt - now()))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_DEAD")
pcall(events.RegisterEvent, events, "PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_STARTED_MOVING")
events:RegisterEvent("PLAYER_STOPPED_MOVING")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("SCREENSHOT_SUCCEEDED")
events:RegisterEvent("SCREENSHOT_FAILED")
events:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")

local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if dst[k] == nil then dst[k] = v end
	end
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		HUDFadeDB = HUDFadeDB or {}
		DB = HUDFadeDB
		copyDefaults(DEFAULTS, DB)
		DB.restore = DB.restore or {}
		HUDFade.db = DB
	elseif event == "PLAYER_LOGIN" then
		-- Logged out or crashed while hidden last time: put the names and nameplates back first.
		restoreAllCVars()
		pcall(scanModels) -- (the one full scan, under the loading screen)
		pcall(hookModels)
		state.inCombat = InCombatLockdown() and true or false
		state.lastInput = now()
		hookMinimap()
		state.hudOff = DB.startHidden
		if not listenToKeys() then state.pendingKeys = true end
		applyOverrides(true)
		C_Timer.NewTicker(0.1, function()
			pollMouse()
			update()
			syncShift()
			scanStep()
		end)
		update(true)
		if not DB.welcomed then
			DB.welcomed = true
			local key = GetBindingKey("TOGGLEUI")
			say("installed. " .. (DB.replaceAltZ and key and ("Press " .. key .. " to hide or show the HUD. ") or "")
				.. "Type /hudfade for settings.")
		end
	elseif event == "PLAYER_LOGOUT" then
		restoreAllCVars()
		restoreShift()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Runs just before combat lockdown starts: the last moment nameplates can be turned back on.
		state.inCombat = true
		releasePointer(true)
		cvarsBack(PLATE_CVARS)
		update(DB.showCombat)
	elseif event == "PLAYER_REGEN_ENABLED" then
		state.inCombat = false
		if state.pendingKeys and listenToKeys() then state.pendingKeys = false end
		if state.pendingBinds then applyOverrides(true) end
		if state.cvarsHidden then
			if DB.hideNameplates then cvarsOff(PLATE_CVARS) end
			hideMinimap()
		else
			showMinimap() -- (in case combat stopped it coming back)
		end
		update()
		syncShift(true)
	elseif event == "PLAYER_FOCUS_CHANGED" then
		scanSoon()
	elseif event == "PLAYER_TARGET_CHANGED" then
		scanSoon()
		state.suppressed.target = nil
		if DB.showTarget and is(UnitExists, "target") then input() end
		update()
	elseif event == "PLAYER_DEAD" then
		state.suppressed.dead = nil
		if DB.showDead then input() end
		update()
	elseif event == "PLAYER_STARTED_MOVING" then
		state.moving = true
	elseif event == "PLAYER_STOPPED_MOVING" then
		state.moving = false
		wipe(held) -- (a key whose release the game never passed on, e.g. after Alt+Tab, cannot keep you "active")
	elseif event == "UPDATE_BINDINGS" then
		applyOverrides()
	elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		if state.shot then
			C_Timer.After(0.1, function()
				state.shot = false
				update()
			end)
		end
	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
		state.casting = true
		state.suppressed.casting = nil
		if DB.showCasting then input() end
		update()
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		state.casting = false
		update()
	end
end)
