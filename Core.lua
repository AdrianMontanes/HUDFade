-- OLED HUD: fades the whole interface as one layer.
--
-- Why one layer: EllesmereUI (and other UI addons) keep setting the opacity of their own frames for their
-- mouseover and visibility rules. Fade addons that set the opacity of those same frames end up fighting them.
-- OLED HUD never touches a single frame's opacity. It only changes UIParent's, which multiplies with whatever
-- each addon does underneath, so both keep working. The few things that ignore UIParent's opacity (3D models,
-- floating unit names, nameplates) are handled on their own below.

local ADDON, ns = ...

local OLEDHUD = {}
_G.OLEDHUD = OLEDHUD
ns.core = OLEDHUD

BINDING_HEADER_OLEDHUD = "OLED HUD"
BINDING_NAME_OLEDHUD_TOGGLE = "Hide / show the HUD"
BINDING_NAME_OLEDHUD_PEEK = "Show the HUD while held"
BINDING_NAME_OLEDHUD_SCREENSHOT = "Take a screenshot without the HUD"
BINDING_NAME_OLEDHUD_ENABLE = "Turn OLED HUD on / off"

local DEFAULTS = {
	enabled = true,        -- the whole addon; off = the game behaves as if OLED HUD were not installed
	startHidden = false,   -- begin each session with the HUD hidden
	idleSeconds = 30,      -- hide after this long with no input at all (0 = never)
	hiddenAlpha = 0,       -- opacity while hidden (0 = true black)
	fadeOut = 1.0,         -- seconds to fade out
	fadeIn = 0.2,          -- seconds to fade back in
	showCombat = true,
	showTarget = true,
	showCasting = false,
	showWindows = true,    -- bags, map, popups, chat typing, any window you open
	showDead = true,
	hideNames = true,      -- floating player/NPC names
	hideNameplates = true,
	hideCursor = false,    -- hide the mouse pointer while the HUD is hidden and the mouse is still (experimental)
	activeCamera = false,  -- turning the camera counts as activity for the idle timer
	activeAutorun = false, -- auto-run, follow and flight paths count as activity for the idle timer
	hideMinimap = true,    -- the minimap's icons and arrow ignore the UI's opacity, so the map is hidden instead
	replaceAltZ = true,    -- the game's own "hide UI" key (Alt+Z) does OLED HUD's toggle instead
	cleanPrintScreen = false, -- the game's screenshot key leaves the HUD out
	pixelShift = false,    -- burn-in protection: move the whole UI a pixel or two every few minutes
	shiftPixels = 2,       -- how far, in screen pixels
	shiftMinutes = 3,      -- how often
	welcomed = false,
}
OLEDHUD.DEFAULTS = DEFAULTS

local GRACE = 1 -- seconds
local held = {} -- movement keys held down right now (holding W to run counts as activity the whole time)

local DB
local state = {
	current = 1,        -- the opacity OLED HUD last gave UIParent
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
OLEDHUD.state = state

local function now() return GetTime() end

local function say(msg)
	print("|cff7fd4ffOLED HUD|r: " .. msg)
end
OLEDHUD.Print = say

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
}
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

-- After that, a few hundred frames a tick in the background, and only while the HUD is fully up. (Walking through
-- every frame in the game at the start of each hide caused a visible hitch.)
local SCAN_BATCH, SCAN_EVERY = 300, 15
local scan = {}
local function scanStep()
	if not EnumerateFrames or state.target < 0.999 or state.current < 0.999 then return end
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

-- For /ohud what: the frame under the mouse and how it relates to UIParent.
function OLEDHUD.DescribeMouseFrame()
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

local function applyModels(a)
	applyLoners(a)
	for _, m in ipairs(models) do
		if a >= 0.999 then
			local base = baseAlpha[m]
			if base then
				pcall(m.SetModelAlpha, m, base)
				baseAlpha[m] = nil
			end
		elseif ask(m, "IsVisible") then
			if baseAlpha[m] == nil then
				local own = ask(m, "GetModelAlpha")
				baseAlpha[m] = type(own) == "number" and own or 1
			end
			pcall(m.SetModelAlpha, m, baseAlpha[m] * a)
		end
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
	return ask(f, "IsVisible") == true
end

-- Returns what is open (for /ohud why), or nil.
local function windowOpen()
	if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return "typing" end
	if GetCursorInfo and GetCursorInfo() then return "holding something on the cursor" end
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

-- Reasons that always bring the HUD back, even when you are away.
local function urgentReasons(out)
	if state.peek then out.peek = true end
	if DB.showCombat and state.inCombat then out.combat = true end
	if DB.showDead and is(UnitIsDead, "player") then out.dead = true end
	if DB.showWindows then
		local w = windowOpen()
		if w then out.window = w end
	end
end

-- Reasons that bring it back only while you are playing (not idle).
local function softReasons(out)
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
	return DB.idleSeconds > 0 and (t - state.lastInput) >= DB.idleSeconds
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
OLEDHUD.Update = update

-- Why the HUD is up or hidden right now, for /ohud why. Returns the lines to print, first one without the
-- "OLED HUD:" label.
local REASON_ORDER = { "peek", "combat", "dead", "window", "target", "casting" }
local REASON_TEXT = {
	peek = "Peek key held", combat = "In combat", dead = "You are dead",
	target = "You have a target", casting = "Casting",
}

local function windowText(v)
	if v == "typing" then return "Typing" end
	if v == "holding something on the cursor" then return "Holding something on the cursor" end
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

function OLEDHUD.Explain(skipTyping)
	if not DB.enabled then
		return { "|cffff4040Disabled|r", "The HUD stays up while OLED HUD is off. Turn it on with /ohud on." }
	end
	local lines = { "|cff40ff40Enabled|r" }
	local t = now()
	local idle = isIdle(t)
	local idleFor = math.max(0, math.floor(t - state.lastInput))

	if state.target < 0.999 then
		local why = {}
		if state.hudOff then why[#why + 1] = "You hid it" end
		if idle then why[#why + 1] = string.format("Idle for %ds", idleFor) end
		if state.shot then why[#why + 1] = "Taking a screenshot" end
		if #why == 0 then why[1] = "Something just ended, so it is hiding again" end
		listLines(lines, "HUD hidden due to:", why)
		local p = OLEDHUD.PointerWhy()
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
local ours = false -- mouselook was started by OLED HUD
local facing       -- the character's facing when it started (nil where the game keeps it secret, e.g. instances)
local startedAt = 0
-- Starting mouselook turns the character to where the camera points. That turn is not you moving the mouse, so the
-- facing is only watched once it has settled; and only a turn above about a third of a degree counts.
local SETTLE, TURN = 0.4, 0.006

local function getFacing()
	if not GetPlayerFacing then return nil end
	local ok, f = pcall(GetPlayerFacing)
	if ok and type(f) == "number" and not (issecretvalue and issecretvalue(f)) then return f end
	return nil
end

local function releasePointer(stop, moved)
	if not ours then return end
	ours = false
	if stop and MouselookStop then pcall(MouselookStop) end
	if moved then state.lastMouseMove = now() end
end

local function hidePointer()
	if ours or not MouselookStart then return end
	if IsMouselooking and IsMouselooking() then return end -- (you are already steering)
	if pcall(MouselookStart) then
		ours = true
		facing = getFacing()
		startedAt = now()
	end
end

releaseOnKey = function(key)
	if not ours then return end
	-- With the pointer hidden, the turn keys would strafe instead of turn: give it back first (this runs before the
	-- game acts on the key). And where the facing is secret a mouse move cannot be seen, so any key brings it back.
	if isTurnKey(key) or not facing then releasePointer(true, true) end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	if not ours then return end
	local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
	local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
	if right then
		releasePointer(false) -- (right drag steers anyway: the game's own drag carries on from here)
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
	local f = getFacing()
	if not f then return end
	if not facing or now() - startedAt < SETTLE then
		facing = f
		return
	end
	local d = math.abs(f - facing)
	if d > math.pi then d = 2 * math.pi - d end -- (the facing wraps around at a full turn)
	if d > TURN then releasePointer(true, true) end
end)

-- An open window keeps the pointer only while it is also what keeps the HUD up. Once you hide the HUD over a
-- window (or windows are set not to bring the HUD back), the pointer can go as well. Typing and an item held on
-- the pointer always keep it.
local function windowKeepsPointer()
	local w = windowOpen()
	if not w then return false end
	if w == "typing" or w == "holding something on the cursor" then return true end
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

-- Why the pointer has to stay visible right now (nil = it can hide). Also used by /ohud why.
local function pointerBlock(t, anyButton)
	if not (DB.enabled and DB.hideCursor) then return "pointer hiding is off" end
	if state.target >= 0.999 then return "the HUD is visible" end
	if state.peek then return "peek key held" end
	if state.inCombat then return "in combat" end
	if anyButton then return "a mouse button is held" end
	-- (in the air or in water the camera also sets your pitch, so hiding could tip your character up or down)
	if is(IsFlying) then return "flying" end
	if is(IsSwimming) then return "swimming" end
	-- (on a flight path or in a vehicle the view turns by itself, which would read as you moving the mouse)
	if is(UnitOnTaxi, "player") then return "on a flight path" end
	if is(UnitInVehicle, "player") then return "in a vehicle" end
	if turnKeyHeld() then return "turning with the keyboard" end
	if windowKeepsPointer() then return "a window is open, or you are typing" end
	if state.cameraFree then return "the camera points away from your character (a right-drag or moving lines them up)" end
	if state.pointerRefused then return "the game took the mouse back, e.g. alt-tab (move the mouse to try again)" end
	if (t - (state.lastMouseMove or 0)) < 2 then return "the mouse moved less than 2 s ago" end
	return nil
end

local function pollMouse()
	local t = now()
	local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
	local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
	local anyButton = left or right
	if not ours then -- (while ours, the pointer is frozen and the watcher above looks for moves)
		local x, y = GetCursorPosition()
		if math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2 then
			lastX, lastY = x, y
			state.lastMouseMove = t
			state.pointerRefused = false
			input()
		elseif anyButton or (IsMouselooking and IsMouselooking()) then
			-- Running with both buttons is moving yourself; turning the camera only counts if you want it to.
			if (left and right) or DB.activeCamera then input() end
		end
	end
	-- Camera and character lined up or not (see cameraFollows above).
	-- (any left press on the 3D world may turn the camera, even a tiny tweak)
	if left and not right then
		if not leftSince then leftSince, leftOnWorld = t, mouseOverWorld() end
		if leftOnWorld then state.cameraFree = true end
	else
		leftSince = nil
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
	if not pointerBlock(t, anyButton) then hidePointer() elseif ours and not anyButton then releasePointer(true) end
end

function OLEDHUD.PointerWhy()
	if not (DB.enabled and DB.hideCursor) then return nil end
	if ours then return "hidden" end
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

function OLEDHUD.IsHidden()
	return state.target < 0.999
end

function OLEDHUD.Hide()
	state.hudOff = true
	suppressCurrent()
	state.lastWanted = -math.huge
	update()
end

function OLEDHUD.Show()
	state.hudOff = false
	wipe(state.suppressed)
	input()
	update()
end

function OLEDHUD.Toggle()
	if not DB.enabled then
		say("is turned off. Turn it on in /ohud options, with your on/off key, or with /ohud on.")
		return
	end
	if OLEDHUD.IsHidden() then OLEDHUD.Show() else OLEDHUD.Hide() end
end

-- The switch for the whole addon. Off: HUD fully back, names and minimap back, your Hide UI key does its normal job.
function OLEDHUD.SetEnabled(on)
	DB.enabled = on and true or false
	releasePointer(true)
	state.hudOff = false
	state.peek = false
	wipe(state.suppressed)
	input()
	OLEDHUD.ApplyOverrides(true)
	update(true)
	OLEDHUD.UpdateShift()
	if OLEDHUD.RefreshOptions then OLEDHUD.RefreshOptions() end
	say(DB.enabled and "on." or "off. The HUD stays up and your Hide UI key works as normal.")
end

function OLEDHUD.ToggleEnabled()
	OLEDHUD.SetEnabled(not DB.enabled)
end

function OLEDHUD.Peek(down)
	if not DB.enabled then return end
	state.peek = down and true or false
	if down then input() else state.lastWanted = -math.huge end
	update(down)
end

function OLEDHUD.CleanScreenshot()
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

function OLEDHUD_OnCompartmentClick()
	if OLEDHUD.OpenOptions then OLEDHUD.OpenOptions() end
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
		for _, key in ipairs({ GetBindingKey("TOGGLEUI") }) do plan[#plan + 1] = { key, "OLEDHUD_TOGGLE" } end
	end
	if DB.enabled and DB.cleanPrintScreen then
		for _, key in ipairs({ GetBindingKey("SCREENSHOT") }) do plan[#plan + 1] = { key, "OLEDHUD_SCREENSHOT" } end
	end
	for _, p in ipairs(plan) do parts[#parts + 1] = p[1] .. "=" .. p[2] end
	local signature = table.concat(parts, ",")
	if signature == boundSignature and not force then return end
	boundSignature = signature
	ClearOverrideBindings(bindOwner)
	for _, p in ipairs(plan) do SetOverrideBinding(bindOwner, true, p[1], p[2]) end
	state.pendingBinds = false
end
OLEDHUD.ApplyOverrides = applyOverrides

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

local function placeUI(t, dx, dy)
	UIParent:ClearAllPoints()
	for _, a in ipairs(t) do UIParent:SetPoint(a[1], a[2], a[3], a[4] + dx, a[5] + dy) end
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

local function editModeOpen()
	return EditModeManagerFrame and ask(EditModeManagerFrame, "IsShown") == true
end

local function syncShift(force)
	local t = now()
	if not force and t - shift.lastSync < 1 then return end
	shift.lastSync = t
	if not DB or InCombatLockdown() then return end
	local cur = readAnchors(UIParent)
	if not cur then return end
	-- Something else moved the interface since our last move (an ultrawide addon, the game): that is the new normal.
	-- If it keeps happening, step aside instead of fighting over it.
	if shift.base and anchorSig(cur) ~= shift.sig then
		shift.base, shift.px, shift.py = nil, 0, 0
		if t - shift.since > 10 then shift.since, shift.fights = t, 0 end
		shift.fights = shift.fights + 1
		if shift.fights >= 3 and not shift.gaveUp then
			shift.gaveUp = true
			say("pixel shift stopped: another addon keeps moving the interface back. /ohud shift on tries again.")
		end
	end
	local px, py = 0, 0
	if DB.enabled and DB.pixelShift and not shift.gaveUp and not editModeOpen() then
		if t >= shift.nextAt then
			shift.index = shift.index % #SHIFT_STEPS + 1
			shift.nextAt = t + math.max(DB.shiftMinutes or 3, 0.5) * 60
		end
		local step = SHIFT_STEPS[shift.index]
		local d = DB.shiftPixels or 2
		px, py = step[1] * d, step[2] * d
	end
	local unit = pixelUnit()
	if not unit then return end
	-- (a changed UI scale changes what a pixel is, so that counts as a change too)
	if px == shift.px and py == shift.py and (unit == shift.unit or (px == 0 and py == 0)) then return end
	local base = shift.base or cur
	if not pcall(placeUI, base, px * unit, py * unit) then
		-- Never leave the interface without a position.
		pcall(placeUI, base, 0, 0)
		shift.base, shift.px, shift.py, shift.gaveUp = nil, 0, 0, true
		say("pixel shift stopped: the game refused to move the interface.")
		return
	end
	if px == 0 and py == 0 then
		shift.base, shift.sig = nil, nil
	else
		shift.base, shift.sig = base, anchorSig(readAnchors(UIParent))
	end
	shift.px, shift.py, shift.unit = px, py, unit
end

function OLEDHUD.UpdateShift()
	if DB and DB.pixelShift and shift.gaveUp then shift.gaveUp, shift.fights = false, 0 end
	syncShift(true)
end

function OLEDHUD.ShiftNow()
	shift.nextAt = 0
	syncShift(true)
end

function OLEDHUD.ShiftStatus()
	if not DB.pixelShift then return "pixel shift is off." end
	local text = "pixel shift is on: " .. DB.shiftPixels .. " px every " .. DB.shiftMinutes .. " min"
	if not DB.enabled then return text .. ", but OLED HUD is turned off." end
	if shift.gaveUp then return text .. ", stopped because another addon keeps moving the interface back." end
	text = text .. ". Offset now " .. shift.px .. "," .. shift.py .. " px"
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
		OLEDHUDDB = OLEDHUDDB or {}
		DB = OLEDHUDDB
		copyDefaults(DEFAULTS, DB)
		DB.restore = DB.restore or {}
		OLEDHUD.db = DB
	elseif event == "PLAYER_LOGIN" then
		-- Logged out or crashed while hidden last time: put the names and nameplates back first.
		restoreAllCVars()
		pcall(scanModels) -- (the one full scan, under the loading screen)
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
				.. "Type /ohud for settings.")
		end
	elseif event == "PLAYER_LOGOUT" then
		restoreAllCVars()
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
	elseif event == "PLAYER_TARGET_CHANGED" then
		state.suppressed.target = nil
		if DB.showTarget and is(UnitExists, "target") then input() end
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
