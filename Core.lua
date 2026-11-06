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
	welcomed = false,
}
OLEDHUD.DEFAULTS = DEFAULTS

local GRACE = 1 -- seconds

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
	return not (InCombatLockdown() and f.IsProtected and f:IsProtected())
end

local function hideMinimap()
	local m = Minimap
	if not (m and DB.hideMinimap) or not canTouch(m) then return end
	local okS, isShown = pcall(m.IsShown, m)
	if okS and isShown then
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
	if DB.hideNames then cvarsOff(NAME_CVARS) end
	if DB.hideNameplates and not InCombatLockdown() then cvarsOff(PLATE_CVARS) end
	hideMinimap()
	state.cvarsHidden = true
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
		local ok, p = pcall(f.GetParent, f)
		if not ok or not p then return false end
		if p == UIParent then return true end
		f = p
	end
	return false
end

local function scanModels()
	if not EnumerateFrames then return end
	wipe(models)
	local f = EnumerateFrames()
	while f do
		local ok, kind = pcall(f.GetObjectType, f)
		if ok and MODEL_TYPES[kind] and f.SetModelAlpha and underUIParent(f) then
			models[#models + 1] = f
		end
		f = EnumerateFrames(f)
	end
	lastScan = now()
end

local function applyModels(a)
	for _, m in ipairs(models) do
		if a >= 0.999 then
			local base = baseAlpha[m]
			if base then
				pcall(m.SetModelAlpha, m, base)
				baseAlpha[m] = nil
			end
		else
			local okV, visible = pcall(m.IsVisible, m)
			if okV and visible then
				if baseAlpha[m] == nil then
					local okA, own = pcall(m.GetModelAlpha, m)
					baseAlpha[m] = (okA and type(own) == "number" and not (issecretvalue and issecretvalue(own))) and own or 1
				end
				pcall(m.SetModelAlpha, m, baseAlpha[m] * a)
			end
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
	if cur == tgt then self:Hide() end
end)

local function setTarget(a, instant)
	if a < state.target and a < 0.999 and not state.cvarsHidden then
		-- Starting to hide.
		if now() - lastScan > 5 then scanModels() end
		hideGameText()
	elseif a >= 0.999 and state.cvarsHidden then
		showGameText()
	end
	state.target = a
	if instant then
		apply(a)
		driver:Hide()
	elseif state.current ~= a then
		driver:Show()
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
	if type(f) ~= "table" or not f.IsVisible then return false end
	local ok, s = pcall(f.IsVisible, f)
	return ok and s
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
	if DB.showDead and UnitIsDead("player") then out.dead = true end
	if DB.showWindows then
		local w = windowOpen()
		if w then out.window = w end
	end
end

-- Reasons that bring it back only while you are playing (not idle).
local function softReasons(out)
	if DB.showTarget and UnitExists("target") then out.target = true end
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
		local ok, a = pcall(UIParent.GetAlpha, UIParent)
		if ok and type(a) == "number" and math.abs(a - state.target) > 0.01 then apply(state.target) else applyModels(state.current) end
	end
end
OLEDHUD.Update = update

-- What is keeping the HUD up right now, for /ohud why.
function OLEDHUD.Explain()
	local t = now()
	local idle = isIdle(t)
	local list = {}
	for k, v in pairs(currentReasons(idle)) do
		list[#list + 1] = (v == true) and k or (k .. " (" .. tostring(v) .. ")")
	end
	local mode = state.hudOff and "hidden by you" or "on"
	if idle then mode = mode .. ", idle" end
	return mode, list
end

---------------------------------------------------------------------------
-- Input (for the idle timer)
---------------------------------------------------------------------------
local function input()
	state.lastInput = now()
end

local releaseOnKey -- (set further down, with the mouse pointer)
local keys = CreateFrame("Frame")
local held = {} -- keys held down right now (holding W to run counts as activity the whole time)
local function onKey(_, key)
	if key then held[key] = true end
	input()
	if releaseOnKey then releaseOnKey() end
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

releaseOnKey = function()
	-- Where the facing is secret a mouse move cannot be seen, so any key brings the pointer back there.
	if ours and not facing then releasePointer(true, true) end
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
		releasePointer(false)
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

local lastX, lastY = 0, 0
local function pollMouse()
	local t = now()
	local anyButton = IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
	if not ours then -- (while ours, the pointer is frozen and the watcher above looks for moves)
		local x, y = GetCursorPosition()
		if math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2 then
			lastX, lastY = x, y
			state.lastMouseMove = t
			input()
		else
			local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
			local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
			if left or right or (IsMouselooking and IsMouselooking()) then
				-- (not a pointer move: after a drag the pointer can hide again straight away)
				-- Running with both buttons is moving yourself; turning the camera only counts if you want it to.
				if (left and right) or DB.activeCamera then input() end
			end
		end
	end
	if state.moving then
		-- Moving counts while you hold a key for it. Auto-run, follow and flight paths only count if you want them to.
		if next(held) or DB.activeAutorun then input() end
	end
	-- Pointer hidden only while the HUD is hidden, out of combat, with the mouse still for a moment and nothing open.
	-- Not while moving either: in mouselook the turn keys strafe, so keyboard turners would feel the difference.
	local want = DB.enabled and DB.hideCursor and state.target < 0.999 and not state.peek and not state.inCombat
		and not state.moving and not anyButton and (t - (state.lastMouseMove or 0)) >= 2 and not windowOpen()
	-- (with a button held, the watcher above decides how to hand the mouse back)
	if want then hidePointer() elseif ours and not anyButton then releasePointer(true) end
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
	C_Timer.After(0.15, function()
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
		state.inCombat = InCombatLockdown() and true or false
		state.lastInput = now()
		hookMinimap()
		state.hudOff = DB.startHidden
		if not listenToKeys() then state.pendingKeys = true end
		applyOverrides(true)
		C_Timer.NewTicker(0.1, function()
			pollMouse()
			update()
		end)
		update(true)
		if not DB.welcomed then
			DB.welcomed = true
			local key = GetBindingKey("TOGGLEUI")
			say("installed. " .. (DB.replaceAltZ and key and ("Press " .. key .. " to hide or show the HUD. ") or "")
				.. "Type /ohud for options.")
		end
	elseif event == "PLAYER_LOGOUT" then
		restoreAllCVars()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Runs just before combat lockdown starts: the last moment nameplates can be turned back on.
		state.inCombat = true
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
	elseif event == "PLAYER_TARGET_CHANGED" then
		state.suppressed.target = nil
		if UnitExists("target") then input() end
		update()
	elseif event == "PLAYER_STARTED_MOVING" then
		state.moving = true
		releasePointer(true)
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
		update()
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		state.casting = false
		update()
	end
end)
