-- HUD Fade: fades the whole interface as one layer.
--
-- UI addons like EllesmereUI set their own frames' alpha for mouseover and visibility rules, so fading those
-- frames one by one fights them. We only change UIParent's alpha, which multiplies with whatever they do.
-- The few things that ignore UIParent's alpha (3D models, world names, nameplates) are handled separately.

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
	enabled = true,        -- master switch
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
	hideOutline = true,    -- target selection circle and Outline Mode glow
	mouseWakes = true,     -- mouse movement ends idle hiding (it always counts while the HUD is visible)
	activeCamera = false,  -- turning the camera counts as activity for the idle timer
	activeAutorun = false, -- auto-run, follow and flight paths count as activity for the idle timer
	hideMinimap = true,    -- minimap icons ignore UIParent's alpha, so the map is hidden instead
	replaceAltZ = true,    -- the game's Hide UI key (Alt+Z) runs our toggle instead
	cleanPrintScreen = false, -- the game's screenshot key leaves the HUD out
	pixelShift = false,    -- burn-in protection, see Pixel shift below
	shiftPixels = 2,       -- screen pixels
	shiftMinutes = 3,      -- minutes between moves
	welcomed = false,
}
HUDFade.DEFAULTS = DEFAULTS

local GRACE = 1 -- seconds
local held = {} -- movement keys currently held down (holding W counts as input the whole time)

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
	lastWanted = -math.huge, -- last time any reason to show the HUD was active (for GRACE)
	suppressed = {},    -- reasons active when the user hid the HUD; ignored until they end
	cvarsHidden = false,
}
HUDFade.state = state

local function now() return GetTime() end

local function say(msg)
	print("|cff7fd4ffHUD Fade|r: " .. msg)
end
HUDFade.Print = say

-- Since 12.0 some values are "secrets" (e.g. a target frame's range fade) and comparing one is an error.
-- Frame reads go through ask(), which returns nil on an error or a secret.
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

-- Same for boolean API calls like UnitExists("target"): an error or a secret counts as false.
local function is(fn, arg)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, arg)
	return ok and readable(v) and true or false
end

---------------------------------------------------------------------------
-- CVars turned off while hidden (world names, target outline, nameplates)
---------------------------------------------------------------------------
local NAME_CVARS = {
	"UnitNameOwn", "UnitNameNPC", "UnitNameInteractiveNPC", "UnitNameHostleNPC", "UnitNameFriendlySpecialNPCName",
	"UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName", "UnitNameEnemyPlayerName",
	"UnitNameFriendlyPetName", "UnitNameEnemyPetName", "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName",
	"UnitNameFriendlyTotemName", "UnitNameEnemyTotemName", "UnitNameFriendlyMinionName", "UnitNameEnemyMinionName",
	"chatBubbles", "chatBubblesParty", -- chat bubbles are world text too
}
-- There is no CVar for the target's own name: the game always shows it.

-- Target selection circle, Outline Mode glow, and the "find yourself" highlight. CVars the client lacks are skipped.
local OUTLINE_CVARS = {
	"ObjectSelectionCircle", "Outline", "findYourselfAnywhere", "findYourselfInBG", "findYourselfInRaid",
}
-- nameplateShowFriendlyPlayers also drives EllesmereUI's name-only plates.
local PLATE_CVARS = {
	"nameplateShowEnemies", "nameplateShowFriends", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyNPCs",
}

local getCVar = (C_CVar and C_CVar.GetCVar) or GetCVar
local setCVar = (C_CVar and C_CVar.SetCVar) or SetCVar

-- Old values are kept in the saved variables, so a crash while hidden still restores them at the next login.
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
-- Minimap: its icons and player arrow ignore UIParent's alpha, and a partly faded map can render blank indoors,
-- so it is hidden outright.
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
	-- Re-hide it right away if another addon shows it while we have it hidden.
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
	if DB.hideOutline then cvarsOff(OUTLINE_CVARS) end
	hideMinimap()
	-- Nameplates on a later frame: removing every plate is the most expensive part.
	if DB.hideNameplates then
		C_Timer.After(0.1, function()
			if state.cvarsHidden and DB.hideNameplates and not InCombatLockdown() then cvarsOff(PLATE_CVARS) end
		end)
	end
end

local function showGameText()
	cvarsBack(NAME_CVARS)
	cvarsBack(OUTLINE_CVARS)
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
-- 3D models ignore their parent's alpha, so they are faded directly with SetModelAlpha.
---------------------------------------------------------------------------
local MODEL_TYPES = { Model = true, PlayerModel = true, DressUpModel = true, CinematicModel = true, TabardModel = true }
local models = {}                                  -- every model found under UIParent
local baseAlpha = setmetatable({}, { __mode = "k" }) -- model -> its alpha before we changed it
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

-- Frames that ignore their parent's alpha (like the vehicle leave button) are faded one by one too.
local loners = {}
local lonerBase = setmetatable({}, { __mode = "k" })
local lonerWritten = setmetatable({}, { __mode = "k" })

local function sortFrame(f, ms, ls)
	local kind = ask(f, "GetObjectType")
	if kind and MODEL_TYPES[kind] and f.SetModelAlpha then
		if underUIParent(f) then ms[#ms + 1] = f end
	elseif ask(f, "IsIgnoringParentAlpha") == true and underUIParent(f) then
		-- A secret answer is left alone: guessing wrong could leave the frame invisible.
		ls[#ls + 1] = f
	end
end

-- Listed by name as a fallback; setting alpha on a normal child frame is harmless.
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

-- Full scan, only at login while the loading screen hides the cost.
local function scanModels()
	if not EnumerateFrames then return end
	lastScan = now()
	local ms, ls = {}, {}
	local f = EnumerateFrames()
	while f do
		pcall(sortFrame, f, ms, ls)
		f = EnumerateFrames(f)
	end
	addNamedLoners(ls)
	models, loners = ms, ls
end

-- After login, rescan in small batches in the background (a full scan at hide time hitches). Target and focus
-- changes ask for an early pass, since some addons create portraits on first use.
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
			-- Its owner changed it since our last write: use that as its base alpha from now on.
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
		-- Hidden models too, so one that appears while the HUD is hidden is already faded.
		if baseAlpha[m] == nil then
			local own = ask(m, "GetModelAlpha")
			baseAlpha[m] = type(own) == "number" and own or 1
		end
		pcall(m.SetModelAlpha, m, baseAlpha[m] * a)
	end
end

-- Models caught by hookModels, on top of the ones the scans found.
local seenModels = setmetatable({}, { __mode = "k" })

local function applyModels(a)
	applyLoners(a)
	for _, m in ipairs(models) do fadeModel(m, a) end
	for m in pairs(seenModels) do fadeModel(m, a) end
end

-- The background scan can take a while in a big UI, and a portrait created on first use (EllesmereUI's target
-- portrait) would stay solid until it got there. Every model gets SetUnit or similar before it draws anything,
-- so hooking those methods catches new models right away.
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
		-- Starting to hide. CVars and the minimap change once the fade ends: doing it on the first frame hitches.
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
	"FlightMapFrame", "ItemTextFrame", "BarberShopFrame",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4",
	"ContainerFrameCombinedBags", "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4",
	"ContainerFrame5", "ContainerFrame6",
	-- EllesmereUI
	"EUI_MainBagFrame", "EUI_BagsWindowFrame", "EUI_ReagentBagFrame",
}

local function shown(name)
	local f = _G[name]
	if type(f) ~= "table" then return false end
	if f.which == "DEATH" then return false end -- the Release Spirit popup, see softReasons
	return ask(f, "IsVisible") == true
end

-- Edit Mode or EllesmereUI's unlock mode: returns which one is open, or nil.
local function arranging()
	if EditModeManagerFrame and ask(EditModeManagerFrame, "IsShown") == true then return "Edit Mode" end
	local eui = _G.EllesmereUI
	if type(eui) == "table" and type(eui.IsUnlockModeActive) == "function" then
		local ok, on = pcall(eui.IsUnlockModeActive, eui)
		if ok and readable(on) == true then return "EllesmereUI unlock mode" end
	end
	return nil
end

-- Returns what is open (for /hudfade why), or nil. Layout modes count as open windows.
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

-- Away: after awayMinutes with no input the HUD hides even over open windows and with idle hiding set to Never,
-- so a window left open while AFK can't keep it on screen for hours. Combat still shows it.
local function isAway(t)
	local minutes = tonumber(DB.awayMinutes) or 10
	return minutes > 0 and (t - state.lastInput) >= minutes * 60
end

-- Reasons that show the HUD even while idle.
local function urgentReasons(out)
	if state.peek then out.peek = true end
	if DB.showCombat and state.inCombat then out.combat = true end
	if DB.showWindows and not isAway(now()) then
		local w = windowOpen()
		if w then out.window = w end
	end
end

-- Reasons that show the HUD only while not idle. Death counts as input once (PLAYER_DEAD), so lying dead while
-- AFK still hides the HUD after the idle time. That is also why the Release Spirit popup is not a window.
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
	-- A reason that was active when the user hid the HUD stays ignored until it ends.
	for r in pairs(state.suppressed) do
		if not reasons[r] then state.suppressed[r] = nil else reasons[r] = nil end
	end
	return reasons
end

local function isIdle(t)
	return (DB.idleSeconds > 0 and (t - state.lastInput) >= DB.idleSeconds) or isAway(t)
end

-- Typing counts as input; an edit box left open without typing does not.
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
	-- Short grace after a reason ends so the HUD doesn't blink between pulls. Idle and the hide key act at once.
	local show = base or reason or (not idle and (t - state.lastWanted) < GRACE)
	setTarget(show and 1 or DB.hiddenAlpha, instant)
	-- While hidden: reapply our alpha if something changed it, and fade models that just appeared.
	if state.target < 0.999 and not driver:IsShown() then
		local a = ask(UIParent, "GetAlpha")
		if type(a) == "number" and math.abs(a - state.target) > 0.01 then
			apply(state.target)
		else
			applyModels(state.current)
		end
	end
end
HUDFade.Update = update

-- Presets for the "also hide" options. The active one is derived from the settings, so a change by hand shows
-- as Custom. Both hide the minimap, as the game's own Hide UI does.
local PRESETS = {
	{
		name = "Everything",
		values = { hideNames = true, hideNameplates = true, hideMinimap = true, hideOutline = true },
	},
	{
		-- Same as the game's Hide UI (Alt+Z): world names and the target outline stay.
		name = "Blizzard",
		values = { hideNames = false, hideNameplates = true, hideMinimap = true, hideOutline = false },
	},
}
HUDFade.PRESETS = PRESETS

function HUDFade.CurrentPreset()
	for i, p in ipairs(PRESETS) do
		local same = true
		for k, v in pairs(p.values) do
			if (DB[k] and true or false) ~= v then same = false break end
		end
		if same then return i end
	end
	return nil
end

function HUDFade.ApplyPreset(i)
	local p = PRESETS[i]
	if not p then return end
	for k, v in pairs(p.values) do DB[k] = v end
	update()
end

-- /hudfade why: returns the lines to print (the first one goes after the "HUD Fade:" prefix).
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
			why[#why + 1] = string.format("Away for %d min (open windows no longer keep it visible)",
				math.floor(idleFor / 60))
		elseif idle then
			why[#why + 1] = string.format("Idle for %ds", idleFor)
		end
		if state.shot then why[#why + 1] = "Taking a screenshot" end
		if #why == 0 then why[1] = "Something just ended, so it is hiding again" end
		listLines(lines, "HUD hidden due to:", why)
		return lines
	end

	local causes = {}
	local active = currentReasons(idle)
	for _, k in ipairs(REASON_ORDER) do
		local v = active[k]
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

local keys = CreateFrame("Frame")
-- Only movement keys count as input. Other keys act through their effects instead (a target, a cast, a window).
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

local function onKey(_, key)
	if isMoveKey(key) then
		if key ~= GetBindingKey("TOGGLEAUTORUN") then held[key] = true end
		input()
	end
end
local function onKeyUp(_, key)
	if key then held[key] = nil end
end
local function listenToKeys()
	-- Only listen if keys can propagate to the game, otherwise we would swallow them.
	if keys.SetPropagateKeyboardInput and pcall(keys.SetPropagateKeyboardInput, keys, true) then
		keys:EnableKeyboard(true)
		keys:SetScript("OnKeyDown", onKey)
		keys:SetScript("OnKeyUp", onKeyUp)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Mouse (for the idle timer), checked a few times a second
---------------------------------------------------------------------------
local lastX, lastY, dragAt = 0, 0, -1

local function pollMouse()
	local t = now()
	local left = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
	local right = IsMouseButtonDown and IsMouseButtonDown("RightButton")
	local x, y = GetCursorPosition()
	if left or right or (IsMouselooking and IsMouselooking()) then
		-- Mouselook: the cursor jump on release is not real movement. Both buttons means running; turning the
		-- camera only counts with activeCamera.
		lastX, lastY, dragAt = x, y, t
		if (left and right) or DB.activeCamera then input() end
	elseif t - dragAt < 0.3 then
		lastX, lastY = x, y
	elseif math.abs(x - lastX) > 2 or math.abs(y - lastY) > 2 then
		lastX, lastY = x, y
		-- Always counts while visible; after idle hiding only with mouseWakes (so alt-tabbing back can't wake it).
		if DB.mouseWakes or not isIdle(t) then input() end
	end
	if IsKeyDown then -- drop keys whose release we missed
		for k in pairs(held) do
			local ok, down = pcall(IsKeyDown, k)
			if ok and readable(down) == false then held[k] = nil end
		end
	end
	if state.moving then
		-- Held movement keys count; auto-run, follow and flight paths only with activeAutorun.
		if next(held) or DB.activeAutorun then input() end
	end
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

-- Master switch. Off restores everything and gives the Hide UI key back to the game.
function HUDFade.SetEnabled(on)
	DB.enabled = on and true or false
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
	-- CVar changes take a frame to show, so wait before taking the shot.
	C_Timer.After(0.25, function()
		Screenshot()
		-- Fallback in case SCREENSHOT_SUCCEEDED/FAILED never fires.
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
-- Pixel shift (burn-in protection): every few minutes, move UIParent a pixel or two around a small circle.
-- All frames move together and no layout is saved. The original anchors come back when it is turned off, in
-- layout modes and at logout. Never moves in combat (UIParent is protected then).
---------------------------------------------------------------------------
local SHIFT_STEPS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
local shift = {
	index = (math.random and math.random(#SHIFT_STEPS)) or 1, -- random start point each session
	nextAt = 0,
	base = nil,     -- UIParent's own anchors, while we have it moved
	sig = nil,      -- what its anchors looked like right after our last move
	px = 0, py = 0, -- current offset, in pixels
	inset = 0,      -- how far in from every screen edge the interface is kept, in pixels
	ex = 0, ey = 0, -- resulting move of the bottom-left corner, in UI units
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

-- Moves UIParent by dx, dy and insets it from every screen edge. With the inset as large as the largest move,
-- a frame placed against an edge never goes past it.
local function placeUI(t, dx, dy, inset)
	UIParent:ClearAllPoints()
	for _, a in ipairs(t) do
		local point, x, y = a[1], a[4] + dx, a[5] + dy
		if point:find("LEFT") then x = x + inset elseif point:find("RIGHT") then x = x - inset end
		if point:find("TOP") then y = y - inset elseif point:find("BOTTOM") then y = y + inset end
		UIParent:SetPoint(point, a[2], a[3], x, y)
	end
end

-- How far a move takes the bottom-left corner (EllesmereUI positions from there, see below).
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

-- Unshift while a layout mode is open, so saved positions never include the offset.
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
	-- Something else moved UIParent (an ultrawide addon, the game): adopt that, and give up if it keeps happening.
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
	-- A UI scale change changes the size of a pixel, so it counts as a change too.
	if px == shift.px and py == shift.py and inset == shift.inset and (unit == shift.unit or inset == 0) then return end
	local base = shift.base or cur
	if not pcall(placeUI, base, px * unit, py * unit, inset * unit) then
		-- Never leave the interface without a position.
		pcall(placeUI, base, 0, 0, 0)
		shift.base, shift.px, shift.py, shift.inset, shift.ex, shift.ey, shift.gaveUp = nil, 0, 0, 0, 0, 0, true
		say("pixel shift stopped: the game refused to move the interface.")
		return
	end
	if inset == 0 then -- back at the original anchors
		shift.base, shift.sig, shift.ex, shift.ey = nil, nil, 0, 0
	else
		shift.base, shift.sig = base, anchorSig(readAnchors(UIParent))
		shift.ex, shift.ey = cornerMove(base, px * unit, py * unit, inset * unit)
	end
	shift.px, shift.py, shift.inset, shift.unit = px, py, inset, unit
end

-- EllesmereUI positions elements anchored to other elements (like the cast bar under the player frame) from
-- screen coordinates, so under a shift they would move twice. Its SetFramePoint is wrapped to take our offset
-- back out for those. Its unlock mode listener unshifts before any mover reads a position.
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
	if not euiHook and type(set) == "function" then -- once; every addon has loaded by now
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

-- Unshift before logout or reload, in case another addon saves frame positions from the screen.
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
	text = text .. ". Offset now " .. shift.px .. "," .. shift.py .. " px, kept " .. shift.inset
		.. " px in from the screen edges"
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
		-- Leftovers of the removed pointer option (its CVars come back through restoreAllCVars).
		DB.hideCursor, DB.hideCursorSteer, DB.mouseReported, DB.log = nil, nil, nil, nil
		HUDFade.db = DB
	elseif event == "PLAYER_LOGIN" then
		-- CVars left off by a crash while hidden.
		restoreAllCVars()
		pcall(scanModels)
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
		-- Fires just before combat lockdown: the last chance to turn nameplates back on.
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
			showMinimap() -- in case combat blocked it
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
		wipe(held) -- a missed key release (e.g. after Alt+Tab) must not count as held forever
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
