-- Runs HUD Fade against a small fake WoW API, outside the game:
--   lua5.1 tests/mock.lua .
-- The scenario runs top to bottom, and each check builds on the state the earlier ones left.

---------------------------------------------------------------------------
-- Fake WoW API
---------------------------------------------------------------------------
local T = 0 -- game time, in seconds
local lockdown = false
local timers, ticker = {}, nil
local binds = {}
local typingIn = nil
local cx = 0 -- cursor x
local buttons = {}
local target = false
local dead = false
local mouselook = false
local mlBinds, mouselookStarted = {}, nil
local shots = 0
local shiftDown = false
local failed = false

function GetTime() return T end
function InCombatLockdown() return lockdown end

local cvars = {
	chatBubbles = "1", cameraYawMoveSpeed = "180", cameraPitchMoveSpeed = "90",
	UnitNameNPC = "1", UnitNameOwn = "0", ObjectSelectionCircle = "1", Outline = "2",
	nameplateShowEnemies = "1", nameplateShowFriends = "1", nameplateShowFriendlyPlayers = "1",
	floatingCombatTextCombatDamage_v2 = "1", floatingCombatTextCombatHealing_v2 = "1",
}
local refuseDamage = false -- the game ignoring a change without an error
C_CVar = {
	GetCVar = function(n) return cvars[n] end,
	SetCVar = function(n, v)
		if lockdown and n:find("nameplate") then error("blocked") end
		if refuseDamage and n:find("floatingCombatText") then return end
		cvars[n] = v
	end,
}

-- Any method a fake frame doesn't define exists and does nothing.
local function stubMethod() return function() end end

-- Models share one method table, like the game's widget method tables, so a hook there sees every model.
local modelMethods = setmetatable({
	SetUnit = function() end,
	SetModelAlpha = function(self, a) self.malpha = a end,
	GetModelAlpha = function(self) return self.malpha or 1 end,
}, { __index = stubMethod })

local frames = {}
local function newFrame(kind)
	local f = { scripts = {}, shown = true, alpha = 1, events = {}, kind = kind or "Frame" }
	function f:SetScript(n, fn) self.scripts[n] = fn end
	function f:Hide() self.shown = false end
	function f:Show() self.shown = true end
	function f:IsShown() return self.shown end
	function f:IsVisible() return self.shown end
	function f:RegisterEvent(e) self.events[e] = true end
	function f:RegisterUnitEvent(e) self.events[e] = true end
	function f:SetAlpha(a) self.alpha = a end
	function f:GetAlpha() return self.alpha end
	function f:EnableKeyboard(on) self.keyboard = on end
	function f:SetPropagateKeyboardInput() end
	function f:GetObjectType() return self.kind end
	function f:GetParent() return self.parent end
	function f:GetEffectiveScale() return 1 end
	local isModel = kind == "PlayerModel" or kind == "Model"
	setmetatable(f, { __index = isModel and modelMethods or stubMethod })
	frames[#frames + 1] = f
	return f
end

UIParent = newFrame()
UIParent.points = { { "TOPLEFT", nil, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 } }
function UIParent:GetNumPoints() return #self.points end
function UIParent:GetPoint(i)
	local a = self.points[i]
	return a[1], a[2], a[3], a[4], a[5]
end
function UIParent:ClearAllPoints()
	if lockdown then error("blocked") end
	self.points = {}
end
function UIParent:SetPoint(p, r, rp, x, y)
	if lockdown then error("blocked") end
	table.insert(self.points, { p, r, rp, x, y })
end
function UIParent:GetScale() return 0.5 end

-- 768 / 1536 = 0.5 UI units per pixel at scale 1, so at UIParent's 0.5 scale 1 px = 1 unit.
function GetPhysicalScreenSize() return 2560, 1536 end

-- The interface's offset from its normal place, and how far in from the screen edges it is kept.
local function uiOffset()
	local a, b = UIParent.points[1], UIParent.points[2]
	return (a[4] + b[4]) / 2, (a[5] + b[5]) / 2
end
local function uiInset()
	local a, b = UIParent.points[1], UIParent.points[2]
	return (a[4] - b[4]) / 2, (b[5] - a[5]) / 2
end

Minimap = newFrame()
Minimap.parent = UIParent

function hooksecurefunc(t, name, fn)
	local orig = t[name]
	rawset(t, name, function(...)
		local r = orig(...)
		fn(...)
		return r
	end)
end

-- DynamicCam's hook, which loads before HUD Fade: while it fades the UI, it puts its own opacity back.
hooksecurefunc(UIParent, "SetAlpha", function(self, a)
	local held = rawget(self, "ludius_intendedUIParentAlpha")
	if held ~= nil and held ~= a then self:SetAlpha(held) end
end)

function CreateFrame(kind, name, parent)
	local f = newFrame(kind)
	f.parent = parent
	if name then _G[name] = f end
	return f
end

function EnumerateFrames(f)
	if not f then return frames[1] end
	for i, x in ipairs(frames) do
		if x == f then return frames[i + 1] end
	end
end

-- Frames the model scan should find
local model = newFrame("PlayerModel")
model.parent = UIParent
model.malpha = 1
function model:SetModelAlpha(a) self.malpha = a end
function model:GetModelAlpha() return self.malpha end

local lone = newFrame() -- ignores its parent's alpha
lone.parent = UIParent
function lone:IsIgnoringParentAlpha() return true end

-- Secret values (12.0): here indexing one errors, like math on one does in the game.
local SECRET = newproxy(true)
getmetatable(SECRET).__index = function() error("attempt to index a secret value") end
function issecretvalue(v) return rawequal(v, SECRET) end

-- Like EllesmereUI's target frame with its range fade: even "ignores parent alpha" is secret.
local secretFrame = newFrame()
secretFrame.parent = UIParent
function secretFrame:IsIgnoringParentAlpha() return SECRET end
function secretFrame:GetAlpha() return SECRET end
function secretFrame:IsVisible() return SECRET end

-- Ignores its parent's alpha but keeps its own alpha secret: must never be left invisible.
local secretLoner = newFrame()
secretLoner.parent = UIParent
function secretLoner:IsIgnoringParentAlpha() return true end
function secretLoner:GetAlpha() return SECRET end

-- Every check on this one errors.
local brokenFrame = newFrame()
brokenFrame.parent = UIParent
function brokenFrame:GetObjectType() error("forbidden") end
function brokenFrame:IsIgnoringParentAlpha() error("forbidden") end

C_Timer = {
	After = function(d, fn) table.insert(timers, { T + d, fn }) end,
	NewTicker = function(_, fn) ticker = fn end,
}

local BINDINGS = {
	W = "MOVEFORWARD", D = "TURNRIGHT", NUMLOCK = "TOGGLEAUTORUN", TAB = "TARGETNEARESTENEMY",
	PAD1 = "JUMP", PAD2 = "INTERACTTARGET",
}
function GetBindingKey(command)
	if command == "TOGGLEUI" then return "ALT-Z" end
	for key, action in pairs(BINDINGS) do
		if action == command then return key end
	end
end
function GetBindingAction(key) return BINDINGS[key] or "" end
function SetOverrideBinding(_, _, key, command) binds[key] = command end
function ClearOverrideBindings() binds = {} end

function GetCurrentKeyBoardFocus() return typingIn end
function GetCursorInfo() return nil end
function GetCursorPosition() return cx, 0 end
function IsMouseButtonDown(b) return buttons[b] or false end
function IsMouselooking() return mouselook end
function IsShiftKeyDown() return shiftDown end
function UnitExists() return target end
function UnitIsDead() return dead end

-- HUD Fade no longer hides the pointer: these must stay untouched.
function MouselookStart() mouselookStarted = true end
function SetMouselookOverrideBinding(key, binding) mlBinds[key] = binding end

function Screenshot() shots = shots + 1 end
function GetBuildInfo() return "1.60.1", "1", "Nov 1 2026", 16001 end
UISpecialFrames = {}
local escHandlers = {}
GameMenuEscPriority = { Dialog = 1, AddOn = 8 }
function RegisterGameMenuEscHandler(priority, handler)
	escHandlers[#escHandlers + 1] = { priority = priority, handler = handler }
end
local function closeSpecialWindows() -- what the game runs on Escape
	for _, frameName in ipairs(UISpecialFrames) do
		local f = _G[frameName]
		if f and f.shown then f:Hide() end
	end
end
SlashCmdList = {}
function wipe(t)
	for k in pairs(t) do t[k] = nil end
	return t
end

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- Advances game time in 0.1 s ticks, running timers, the ticker and OnUpdate scripts.
local function step(secs)
	for _ = 1, math.floor(secs / 0.1 + 0.5) do
		T = T + 0.1
		for j = #timers, 1, -1 do
			local t = timers[j]
			if t[1] <= T then
				table.remove(timers, j)
				t[2]()
			end
		end
		if ticker then ticker() end
		for _, f in ipairs(frames) do
			if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end
		end
	end
end

local function setTarget(on)
	target = on
	fire("PLAYER_TARGET_CHANGED")
end

local function moveMouse() cx = cx + 40 end

local keyFrame -- the addon's keyboard listener, looked up once it exists
local function keyDown(key) keyFrame.scripts.OnKeyDown(keyFrame, key) end
local function keyUp(key) keyFrame.scripts.OnKeyUp(keyFrame, key) end

local function check(label, cond)
	print((cond and "PASS " or "FAIL ") .. label)
	if not cond then failed = true end
end

local namePlates = {}
C_NamePlate = {}
function C_NamePlate.GetNamePlateForUnit(unit) return namePlates[unit] end

-- Just enough of LibStub, LibDataBroker and LibDBIcon for the minimap button
local icon = {}
function icon:Register(name, obj, db)
	self.name, self.obj, self.db, self.shown = name, obj, db, not db.hide
end
function icon:Show() self.shown = true end
function icon:Hide() self.shown = false end
local broker = {}
function broker:NewDataObject(_, obj) return obj end
LibStub = setmetatable({}, {
	__call = function(_, lib) return lib == "LibDBIcon-1.0" and icon or broker end,
})

-- The game tooltip, which DynamicCam's Keep Tooltip makes ignore the UI's opacity
GameTooltip = newFrame()
GameTooltip.parent = UIParent
GameTooltip.shown = false
GameTooltip.ignoring = false
function GameTooltip:IsIgnoringParentAlpha() return self.ignoring end
function GameTooltip:HookScript(n, fn)
	local old = self.scripts[n]
	self.scripts[n] = function(...)
		if old then old(...) end
		fn(...)
	end
end
function GameTooltip:Show()
	self.shown = true
	if self.scripts.OnShow then self.scripts.OnShow(self) end
end

local ns = {}
local function load(file) assert(loadfile(arg[1] .. "/" .. file))("HUDFade", ns) end
load("Core.lua")
load("Elements.lua")
load("Options.lua")
load("MinimapButton.lua")

---------------------------------------------------------------------------
-- Scenario
---------------------------------------------------------------------------

-- Upgrading from 0.2.x with the pointer hidden at logout: the old settings go and the look speed comes back
HUDFadeDB = {
	hideCursor = true, hideCursorSteer = true, mouseReported = true, log = { "x" },
	restore = { cameraYawMoveSpeed = "180" },
}
cvars.cameraYawMoveSpeed = "18"
fire("ADDON_LOADED", "HUDFade")
fire("PLAYER_LOGIN")
check("the old pointer option's settings are dropped", HUDFadeDB.hideCursor == nil
	and HUDFadeDB.hideCursorSteer == nil and HUDFadeDB.mouseReported == nil and HUDFadeDB.log == nil)
check("and the mouse look speed it had lowered comes back",
	cvars.cameraYawMoveSpeed == "180" and next(HUDFadeDB.restore) == nil)

-- Hide and show
step(1)
check("starts visible", UIParent.alpha == 1)
check("Alt+Z overridden", binds["ALT-Z"] == "HUDFADE_TOGGLE")
HUDFade.Toggle()
step(1.5)
check("toggle hides", UIParent.alpha == 0)
check("NPC names off", cvars.UnitNameNPC == "0" and HUDFadeDB.restore.UnitNameNPC == "1")
check("target circle and outlines off", cvars.ObjectSelectionCircle == "0"
	and HUDFadeDB.restore.ObjectSelectionCircle == "1" and cvars.Outline == "0" and HUDFadeDB.restore.Outline == "2")
check("a setting the game lacks is skipped",
	HUDFadeDB.restore.UnitNameHostleNPC == nil and cvars.UnitNameHostleNPC == nil)
check("own name untouched (was 0)", cvars.UnitNameOwn == "0" and HUDFadeDB.restore.UnitNameOwn == nil)
check("plates off", cvars.nameplateShowEnemies == "0")
check("model faded", model.malpha == 0)
check("frame that ignores parent opacity faded", lone.alpha == 0)
check("frames with secret values left alone", secretFrame.alpha == 1 and secretLoner.alpha == 1)
check("minimap hidden", Minimap.shown == false)
Minimap:Show()
check("minimap stays hidden if another addon shows it", Minimap.shown == false)
check("friendly player plates off", cvars.nameplateShowFriendlyPlayers == "0")
check("damage numbers off", cvars.floatingCombatTextCombatDamage_v2 == "0"
	and HUDFadeDB.restore.floatingCombatTextCombatDamage_v2 == "1" and cvars.floatingCombatTextCombatHealing_v2 == "0")
check("older damage number settings the game lacks are skipped",
	HUDFadeDB.restore.floatingCombatTextCombatDamage == nil)

-- After the hide key, a new target leaves the HUD hidden, but a window brings it back for a moment
setTarget(true)
step(0.5)
check("after the hide key, a new target leaves it hidden", UIParent.alpha == 0 and cvars.UnitNameNPC == "0")
setTarget(false)
local bag = CreateFrame("Frame", "ContainerFrame1")
step(0.5)
check("a window shows", UIParent.alpha == 1 and cvars.UnitNameNPC == "1")
check("target circle and outlines back", cvars.ObjectSelectionCircle == "1" and cvars.Outline == "2")
check("damage numbers back", cvars.floatingCombatTextCombatDamage_v2 == "1"
	and HUDFadeDB.restore.floatingCombatTextCombatDamage_v2 == nil)
check("model back", model.malpha == 1)
check("that frame back", lone.alpha == 1)
check("minimap back", Minimap.shown == true)
bag:Hide()
step(0.5)
check("short grace after the window closes", UIParent.alpha == 1)
step(2)
check("hides after the grace", UIParent.alpha == 0)

-- Combat, toggle, peek and screenshot
HUDFadeDB.hideOutline = false
bag:Show()
step(0.5)
bag:Hide()
step(3)
check("with Target circle off, the outlines stay",
	UIParent.alpha == 0 and cvars.Outline == "2" and cvars.UnitNameNPC == "0")
HUDFadeDB.hideOutline = true

fire("PLAYER_REGEN_DISABLED")
lockdown = true
check("combat shows instantly", UIParent.alpha == 1 and cvars.nameplateShowEnemies == "1")
step(1)
lockdown = false
fire("PLAYER_REGEN_ENABLED")
step(5)
check("hidden again after combat", UIParent.alpha == 0)

HUDFade.Toggle()
step(0.5)
setTarget(true)
step(0.5)
HUDFade.Toggle()
step(1.5)
check("the hide key works with a target", UIParent.alpha == 0)
HUDFade.Toggle()
step(0.5)
check("toggle shows", UIParent.alpha == 1)
setTarget(false)
step(30.3)
check("idle starts hiding right at 30 s (no extra delay)", HUDFade.state.target == 0)
step(1.2)
check("idle hides", UIParent.alpha == 0)
cx = 50
step(0.5)
check("mouse wakes", UIParent.alpha == 1)

HUDFade.Peek(true)
check("peek instant", UIParent.alpha == 1)
HUDFade.CleanScreenshot()
check("shot hides instantly", UIParent.alpha == 0 and cvars.UnitNameNPC == "0")
step(0.3)
check("screenshot taken", shots == 1)
local realPrint = print
local function shotSays(event)
	local out = {}
	print = function(s) out[#out + 1] = s end
	fire(event)
	step(0.5)
	print = realPrint
	return table.concat(out, "\n")
end
local said = shotSays("SCREENSHOT_SUCCEEDED")
check("back after shot", UIParent.alpha == 1)
check("the first screenshot names the folder",
	said:find("screenshot saved to World of Warcraft\\_forever_\\Screenshots.", 1, true))
HUDFade.CleanScreenshot()
step(0.3)
said = shotSays("SCREENSHOT_SUCCEEDED")
check("later ones just say saved", said:find("screenshot saved.", 1, true) and not said:find("Screenshots", 1, true))
HUDFade.CleanScreenshot()
step(0.3)
said = shotSays("SCREENSHOT_FAILED")
check("a failed one says so", said:find("the screenshot failed.", 1, true))
HUDFade.Peek(false)

for _, f in ipairs(frames) do
	if f.scripts.OnKeyDown then keyFrame = f end
end
HUDFade.Hide()
step(4)
check("the mouse pointer is left alone (that option is gone)", mouselookStarted == nil and next(mlBinds) == nil)

-- The on/off switch
check("hidden before turning off", UIParent.alpha == 0)
SlashCmdList.HUDFADE("off")
check("off shows everything at once", UIParent.alpha == 1 and cvars.UnitNameNPC == "1" and Minimap.shown == true)
check("off gives the Hide UI key back", binds["ALT-Z"] == nil)
HUDFade.Toggle()
step(2)
check("toggle does nothing while off", UIParent.alpha == 1)
step(70)
check("no idle hiding while off", UIParent.alpha == 1)
SlashCmdList.HUDFADE("on")
check("on takes the key again", binds["ALT-Z"] == "HUDFADE_TOGGLE")
HUDFade.Toggle()
step(2)
check("toggle works again", UIParent.alpha == 0)

-- What counts as input for the idle timer
HUDFade.Toggle()
step(0.5)
check("shown for the idle tests", UIParent.alpha == 1)
HUDFadeDB.idleSeconds = 5
keyDown("TAB") -- a non-movement key whose release is never seen must not keep the HUD up
step(0.2)
keyDown("NUMLOCK")
fire("PLAYER_STARTED_MOVING")
step(7)
check("auto-run after Tab (key-up never seen) still goes idle", UIParent.alpha == 0)
fire("PLAYER_STOPPED_MOVING")
moveMouse()
step(0.5)
keyDown("W")
fire("PLAYER_STARTED_MOVING")
step(8)
check("holding W keeps the HUD up", UIParent.alpha == 1)
keyUp("W")
step(7)
check("auto-run (moving, no key held) goes idle", UIParent.alpha == 0)
fire("PLAYER_STOPPED_MOVING")
moveMouse()
step(0.5)
check("pointer move wakes", UIParent.alpha == 1)

buttons.LeftButton = true
step(7)
check("turning the camera does not keep the HUD up", UIParent.alpha == 0)
buttons.LeftButton = nil
HUDFadeDB.activeCamera = true
moveMouse()
step(0.5)
buttons.LeftButton = true
step(7)
check("unless that option is on", UIParent.alpha == 1)
buttons.LeftButton = nil
HUDFadeDB.activeCamera = false
step(7)
check("idle again", UIParent.alpha == 0)

-- A controller: the movement stick and a jump button count, the camera stick only with Camera movement
local padSticks = { { x = 0, y = 0, len = 0 }, { x = 0, y = 0, len = 0 } }
local padButtons = { false, false }
local padOn = true
C_GamePad = {
	IsEnabled = function() return padOn end,
	GetDeviceMappedState = function() return { sticks = padSticks, buttons = padButtons } end,
	StickIndexToConfigName = function(i) return ({ [0] = "Movement", [1] = "Camera" })[i] end,
	ButtonIndexToBinding = function(i) return ({ [0] = "PAD1", [1] = "PAD2" })[i] end,
}
padSticks[1].len = 0.8
fire("PLAYER_STARTED_MOVING")
step(0.5)
check("pushing the movement stick brings the HUD back", UIParent.alpha == 1)
step(8)
check("and keeps it up while you run with it", UIParent.alpha == 1)
padSticks[1].len = 0
fire("PLAYER_STOPPED_MOVING")
step(7)
check("idle once you let go", UIParent.alpha == 0)
padSticks[2].len = 1
step(0.5)
check("the camera stick alone leaves it hidden", UIParent.alpha == 0)
HUDFadeDB.activeCamera = true
step(0.5)
check("unless Camera movement is on", UIParent.alpha == 1)
HUDFadeDB.activeCamera = false
padSticks[2].len = 0
step(7)
padButtons[2] = true
step(0.5)
check("a button for an action, not movement, leaves it hidden", UIParent.alpha == 0)
padButtons[2] = false
padButtons[1] = true
step(0.5)
check("the jump button brings it back", UIParent.alpha == 1)
padButtons[1] = false
padSticks[1].len = 0.1
step(7)
check("a stick resting a little off center doesn't count", UIParent.alpha == 0)
padSticks[1].len = 0.8
padOn = false
step(0.5)
check("with the game's controller support off, the controller is not read", UIParent.alpha == 0)
padSticks[1].len = 0
padOn = true

-- A quick click counts as input; holding a button to move the camera does not
fire("GLOBAL_MOUSE_DOWN", "LeftButton")
step(0.1)
fire("GLOBAL_MOUSE_UP", "LeftButton")
step(0.5)
check("a click brings it back", UIParent.alpha == 1)
step(7)
HUDFadeDB.mouseClicks = false
fire("GLOBAL_MOUSE_DOWN", "LeftButton")
fire("GLOBAL_MOUSE_UP", "LeftButton")
step(0.5)
check("with Mouse clicks off, a click leaves it hidden", UIParent.alpha == 0)
HUDFadeDB.mouseClicks = true
fire("GLOBAL_MOUSE_DOWN", "RightButton")
buttons.RightButton = true
step(1)
buttons.RightButton = nil
fire("GLOBAL_MOUSE_UP", "RightButton")
step(0.5)
check("holding a button to move the camera is not a click", UIParent.alpha == 0)
fire("GLOBAL_MOUSE_DOWN", "MiddleButton")
step(0.5)
check("other mouse buttons count when pressed", UIParent.alpha == 1)
step(7)
check("idle again after clicking", UIParent.alpha == 0)

HUDFadeDB.showTarget = false
keyDown("TAB")
setTarget(true)
step(0.5)
check("Tab while idle-hidden, 'target' off: stays hidden", UIParent.alpha == 0)
setTarget(false)
HUDFadeDB.showTarget = true
keyDown("TAB")
setTarget(true)
step(0.5)
check("Tab while idle-hidden, 'target' on: shows", UIParent.alpha == 1)
setTarget(false)

-- Typing in chat counts as input: after sending, the idle time starts over
step(7)
check("idle-hidden before chatting", UIParent.alpha == 0 and cvars.chatBubbles == "0")
local chatBox = { text = "" }
function chatBox:GetText() return self.text end
typingIn = chatBox
step(0.5)
check("typing brings the HUD and chat bubbles back", UIParent.alpha == 1 and cvars.chatBubbles == "1")
step(9.5)
chatBox.text = "hi"
step(0.5)
typingIn = nil
step(1.5)
check("after sending, it stays up for the idle time", UIParent.alpha == 1)
step(5)
check("then hides again", UIParent.alpha == 0)

-- A chat box or window left open keeps the HUD only until the away time
chatBox.text = ""
typingIn = chatBox
step(0.5)
check("opening the chat box brings it back", UIParent.alpha == 1)
step(30)
check("left open without typing, it stays like any open window", UIParent.alpha == 1)
HUDFadeDB.awayMinutes = 2
step(91)
check("but hides once you have been away 2 min", UIParent.alpha == 0)
check("/hudfade why says you are away",
	table.concat(HUDFade.Explain(), " "):find("Away for 2 min", 1, true) ~= nil)
typingIn = nil
HUDFadeDB.idleSeconds = 0
keyDown("W")
keyUp("W")
step(0.5)
check("a key brings it back", UIParent.alpha == 1)
step(119)
check("with Hide when idle at Never, it stays until the away time", UIParent.alpha == 1)
step(2)
check("and hides once you have been away", UIParent.alpha == 0)
HUDFadeDB.idleSeconds = 5
HUDFadeDB.awayMinutes = 10

-- Opening a window counts as input, so the HUD stays for the idle time after it closes
step(1)
local map = CreateFrame("Frame", "WorldMapFrame")
step(0.5)
check("opening the map brings the HUD back", UIParent.alpha == 1)
step(2)
map:Hide()
step(2)
check("after closing it, the HUD stays for the idle time", UIParent.alpha == 1)
step(4)
check("then hides", UIParent.alpha == 0)
HUDFadeDB.awayMinutes = 2
step(120)
map:Show()
step(0.5)
check("a window that opens while you are away leaves it hidden", UIParent.alpha == 0)
map:Hide()
HUDFadeDB.awayMinutes = 10
step(0.5)

-- Windows the list doesn't name: any the game's window manager places, and Immersion's dialogue
UIPanelWindows = { NewBlizzardFrame = { area = "left" }, NotLoadedFrame = { area = "center" } }
local panel = CreateFrame("Frame", "NewBlizzardFrame")
step(0.5)
check("a window the game places itself brings the HUD back", UIParent.alpha == 1)
panel:Hide()
step(7)
check("hidden again after it closes", UIParent.alpha == 0)
local immersion = CreateFrame("Frame", "ImmersionFrame", UIParent)
step(0.5)
check("Immersion's dialogue counts as a window", UIParent.alpha == 1)
immersion:Hide()
step(7)
check("hidden again after the dialogue", UIParent.alpha == 0)
ImmersionSetup = { hideui = true }
immersion:Show()
UIParent:SetAlpha(0) -- Immersion's own fade of the UI, still running
step(0.1)
UIParent:SetAlpha(0) -- its last step
step(1)
check("with Immersion's Hide interface on, its own fade keeps the UI hidden while you talk", UIParent.alpha == 0)
immersion:Hide()
UIParent:SetAlpha(1) -- Immersion fading the UI back in
ImmersionSetup = nil
step(2)
check("and the UI is back after the dialogue", UIParent.alpha == 1)
step(5)
check("until the idle time", UIParent.alpha == 0)

-- DynamicCam fading the UI in a situation, here at a mailbox: it eases UIParent, holding each step with its hook
local function dcEase(to)
	local from, peak = UIParent.alpha, 0
	if from == to then return peak end
	for i = 1, 5 do
		local x = from + (to - from) * i / 5
		UIParent.ludius_intendedUIParentAlpha = x ~= 1 and x or nil
		UIParent:SetAlpha(x)
		peak = math.max(peak, UIParent.alpha)
		step(0.1)
		peak = math.max(peak, UIParent.alpha)
	end
	return peak
end
local function dcEnter(opacity)
	if rawget(UIParent, "ludius_alphaBeforeFadeOut") == nil then UIParent.ludius_alphaBeforeFadeOut = UIParent.alpha end
	dcEase(opacity)
end
local function dcLeave() -- returns the highest opacity the UI showed on the way
	local peak = dcEase(rawget(UIParent, "ludius_alphaBeforeFadeOut"))
	UIParent.ludius_alphaBeforeFadeOut, UIParent.ludius_intendedUIParentAlpha = nil, nil
	return peak
end
local function near(a, b) return math.abs(a - b) < 0.01 end

local mail = CreateFrame("Frame", "MailFrame")
step(0.5)
dcEnter(0.3)
step(1)
check("DynamicCam: its dim applies while the HUD is up", near(UIParent.alpha, 0.3))
check("DynamicCam: portraits dim with it", near(model.malpha, 0.3))
check("DynamicCam: why says it dims the HUD",
	table.concat(HUDFade.Explain(), "\n"):find("dims it to 30%", 1, true) ~= nil)
mail:Hide()
dcLeave()
step(0.5)
check("DynamicCam: the HUD is fully back after its situation", UIParent.alpha == 1 and model.malpha == 1)
step(7)
check("DynamicCam: and idle hides it as usual", UIParent.alpha == 0)
mail:Show()
dcEnter(0.3) -- DynamicCam reacting first remembers the hidden UI as where to return
step(1)
check("DynamicCam: mailbox opened while hidden comes up to its dim", near(UIParent.alpha, 0.3))
mail:Hide()
dcLeave()
step(0.2)
check("DynamicCam: and the HUD is back after, not left hidden", UIParent.alpha == 1)
mail:Show()
step(0.5)
dcEnter(0.3)
step(1)
HUDFade.Hide()
step(2)
check("DynamicCam: the hide key takes the UI below its dim", UIParent.alpha == 0 and model.malpha == 0)
GameTooltip.ignoring = true
GameTooltip:Show()
check("DynamicCam: a tooltip it keeps stays closed while the HUD is hidden", GameTooltip.shown == false)
HUDFade.Show()
step(0.5)
check("DynamicCam: showing again comes back to its dim, not above it",
	near(UIParent.alpha, 0.3) and near(model.malpha, 0.3))
GameTooltip:Show()
check("DynamicCam: and its tooltip opens as usual", GameTooltip.shown == true)
GameTooltip:Hide()
GameTooltip.ignoring = false
HUDFade.Hide()
step(2)
mail:Hide()
local peak = dcLeave()
check("DynamicCam: no flash when its situation ends while hidden", peak < 0.01 and UIParent.alpha == 0)
HUDFade.Show()
step(0.5)
check("DynamicCam: the key brings the HUD back after", UIParent.alpha == 1)
step(7)

-- Mouse moving off: the mouse keeps the HUD up, but only keys bring it back once idle
HUDFadeDB.mouseWakes = false
step(7)
check("idle-hidden", UIParent.alpha == 0)
moveMouse()
step(0.5)
check("mouse wake off: moving the mouse leaves it hidden", UIParent.alpha == 0)
keyDown("W")
keyUp("W")
step(0.5)
check("a movement key brings it back", UIParent.alpha == 1)
for _ = 1, 8 do
	moveMouse()
	step(1)
end
check("while it is up, using the mouse keeps it up", UIParent.alpha == 1)
HUDFadeDB.mouseWakes = true

-- Dying brings the HUD up once, then idle hides it again while you stay dead
step(7)
check("idle-hidden before dying", UIParent.alpha == 0)
dead = true
local deathPopup = CreateFrame("Frame", "StaticPopup1")
deathPopup.which = "DEATH"
fire("PLAYER_DEAD")
step(0.5)
check("dying brings the HUD back", UIParent.alpha == 1)
check("why says you died", table.concat(HUDFade.Explain(), "\n"):find("idling") ~= nil)
step(6)
check("still dead, Release Spirit popup up: hides again after the idle time", UIParent.alpha == 0)
moveMouse()
step(0.5)
check("a mouse move while dead shows it as usual", UIParent.alpha == 1)
deathPopup:Hide()
dead = false
step(6)
check("as a ghost idle works as usual", UIParent.alpha == 0)

HUDFade.Show()
step(0.5)
HUDFade.Hide()
step(2)
check("hidden with the key", UIParent.alpha == 0)
dead = true
deathPopup:Show()
fire("PLAYER_DEAD")
step(0.5)
check("dying shows it even after hiding it with the key", UIParent.alpha == 1)
check("why lists it", table.concat(HUDFade.Explain(), "\n"):find("Death") ~= nil)
step(6)
check("and it hides again after the idle time", UIParent.alpha == 0)

HUDFadeDB.showDead = false
dead = false
deathPopup:Hide()
HUDFade.Show()
step(7)
dead = true
fire("PLAYER_DEAD")
step(0.5)
check("'You die' off: dying while idle-hidden keeps it hidden", UIParent.alpha == 0)
dead = false
HUDFadeDB.showDead = true
moveMouse()
step(0.5)

-- /hudfade why
local function why()
	local out = {}
	print = function(s) out[#out + 1] = s end
	SlashCmdList.HUDFADE("why")
	step(0.6)
	print = realPrint
	return table.concat(out, "\n")
end
moveMouse()
step(2.4)
local w = why()
check("why: enabled, idle progress", w:find("Enabled", 1, true)
	and w:find("HUD visible due to: Not enough time idling (2/5s)", 1, true))
step(5)
w = why()
check("why: hidden by idle", w:find("HUD hidden due to: Idle for", 1, true) and not w:find("Pointer", 1, true))
HUDFadeDB.showTarget = true
setTarget(true)
step(0.5)
w = why()
check("why: several causes on their own lines",
	w:find("HUD visible due to:\n   - Target\n   - Not enough time idling", 1, true))
setTarget(false)
HUDFadeDB.idleSeconds = 0
step(0.2)
w = why()
check("why: idle set to Never", w:find("HUD visible due to: Hide when idle is set to Never", 1, true))
HUDFadeDB.idleSeconds = 5
HUDFade.SetEnabled(false)
w = why()
check("why: disabled", w:find("Disabled", 1, true) and not w:find("visible due to", 1, true))
HUDFade.SetEnabled(true)

-- Hiding without a hitch: names go at the end of the fade, frames are scanned in the background
local function newModel(parent)
	local m = CreateFrame("PlayerModel", nil, parent)
	m.malpha = 1
	function m:SetModelAlpha(a) self.malpha = a end
	function m:GetModelAlpha() return self.malpha end
	return m
end

HUDFade.Show()
step(0.5)
local late = newModel(UIParent)
HUDFade.Hide()
step(0.3)
check("names stay on during the fade", cvars.UnitNameNPC == "1")
step(1.0)
check("names off once the fade ends", cvars.UnitNameNPC == "0")
step(0.2)
check("nameplates off a moment after", cvars.nameplateShowEnemies == "0")
check("hiding does not scan every frame at once (new model not seen yet)", late.malpha == 1)
HUDFade.Show()
step(20)
HUDFade.Hide()
step(1.5)
check("background scan finds frames made later", late.malpha == 0)

-- A portrait an addon creates on first use while the HUD is hidden (EllesmereUI's target portrait)
HUDFade.Hide()
step(1.5)
local lazy = newModel(UIParent)
fire("PLAYER_TARGET_CHANGED")
step(2)
check("a portrait made while hidden is found and faded within seconds", lazy.malpha == 0)
HUDFade.Show()
step(0.5)
check("and restored when the HUD comes back", lazy.malpha == 1)

-- Faded the moment it is given a unit, without waiting for a scan
HUDFade.Hide()
step(1.5)
local given = newModel(UIParent)
given:SetUnit("target")
check("a portrait given a unit while hidden is faded at once", given.malpha == 0)
local loose = newModel(nil)
loose:SetUnit("target")
check("a model outside the UI is left alone", loose.malpha == 1)
HUDFade.Show()
step(0.5)
check("and restored when the HUD comes back", given.malpha == 1)

-- A portrait whose addon sets its alpha while the HUD is hidden (ElvUI, whenever its unit frame's alpha changes)
HUDFade.Hide()
step(1.5)
local elvPortrait = CreateFrame("PlayerModel", nil, UIParent)
elvPortrait:SetUnit("player")
elvPortrait:SetModelAlpha(0.8)
check("a portrait its addon resets while hidden is faded again at once, without a blink", elvPortrait.malpha == 0)
HUDFade.Show()
step(0.5)
check("and comes back at the alpha its addon gave it", elvPortrait.malpha == 0.8)

-- Pixel shift
local function atRest() return select(1, uiOffset()) == 0 and select(2, uiOffset()) == 0 end
local function shiftUntil(done) repeat HUDFade.ShiftNow() until done() end
local function shifted() return select(1, uiOffset()) ~= 0 end
local DEFAULT_POINTS = { { "TOPLEFT", nil, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0 } }
local function exactlyBack()
	local p = UIParent.points
	return #p == 2 and p[1][4] == 0 and p[1][5] == 0 and p[2][4] == 0 and p[2][5] == 0
end

check("pixel shift off by default", atRest())
SlashCmdList.HUDFADE("shift on")
step(1.1)
local visited, nonzero = {}, false
for _ = 1, 9 do
	HUDFade.ShiftNow()
	local x, y = uiOffset()
	visited[x .. "," .. y] = true
	if x ~= 0 or y ~= 0 then nonzero = true end
end
local spots = 0
for _ in pairs(visited) do spots = spots + 1 end
check("shift walks the 9 spots of the circle", spots == 9 and nonzero and visited["2,0"] and visited["-2,-2"])
check("kept the distance in from every edge",
	select(1, uiInset()) == 2 and select(2, uiInset()) == 2 and #UIParent.points == 2)
local inside = true
for _ = 1, 9 do
	HUDFade.ShiftNow()
	local a, b = UIParent.points[1], UIParent.points[2]
	if a[4] < 0 or a[5] > 0 or b[4] > 0 or b[5] < 0 then inside = false end
end
check("never past a screen edge on any spot", inside)

shiftUntil(function() return select(1, uiOffset()) == 2 end)
lockdown = true
HUDFade.ShiftNow()
step(1.1)
check("no move during combat", select(1, uiOffset()) == 2)
lockdown = false
fire("PLAYER_REGEN_ENABLED")
step(0.1)
check("moves on after combat", select(1, uiOffset()) ~= 2 or select(2, uiOffset()) ~= 0)
HUDFadeDB.shiftPixels = 1
step(1.1)
local x1, y1 = uiOffset()
check("distance follows the setting", math.abs(x1) <= 1 and math.abs(y1) <= 1)

EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame")
step(1.1)
check("back in place while Edit Mode is open", atRest())
EditModeManagerFrame:Hide()
HUDFade.ShiftNow()
shiftUntil(shifted)
EllesmereUI = { _unlockModeSessionActive = true }
function EllesmereUI:IsUnlockModeActive() return self._unlockModeSessionActive == true end
step(1.1)
check("back in place while EllesmereUI's unlock mode is open", select(1, uiOffset()) == 0 and select(1, uiInset()) == 0)
EllesmereUI._unlockModeSessionActive = false
shiftUntil(shifted)
ElvUI = { { ConfigurationMode = true } }
step(1.1)
check("back in place while ElvUI's movers are out", select(1, uiOffset()) == 0 and select(1, uiInset()) == 0)
check("/hudfade why names ElvUI's movers", table.concat(HUDFade.Explain(), " "):find("ElvUI movers", 1, true) ~= nil)
ElvUI[1].ConfigurationMode = false
shiftUntil(shifted)
Bartender4 = { Locked = false }
step(1.1)
check("back in place while Bartender4's bars are unlocked", select(1, uiOffset()) == 0 and select(1, uiInset()) == 0)
Bartender4.Locked = true
shiftUntil(shifted)
Dominos = { locked = false }
function Dominos:Locked() return self.locked end
step(1.1)
check("back in place while Dominos' bars are unlocked", select(1, uiOffset()) == 0 and select(1, uiInset()) == 0)
Dominos.locked = true
shiftUntil(shifted)

-- EllesmereUI places an anchored element (its cast bar under the player frame) counting from the screen corner
local placed, listeners = {}, {}
EllesmereUI.SetFramePoint = function(f, p, rel, rp, x, y) placed[f] = { p, rel, rp, x, y } end
function EllesmereUI:RegisterUnlockModeListener(owner, fn) listeners[owner] = fn end
local castbar, freeBar, playerFrame = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
function castbar:GetEffectiveScale() return 0.5 end
EllesmereUI._unlockRegisteredElements = {
	playerCastbar = { getFrame = function() return castbar end },
	freeBar = { getFrame = function() return freeBar end },
}
EllesmereUIDB = { unlockAnchors = { playerCastbar = { target = "player", side = "BOTTOM" } } }
shiftUntil(function() return select(1, uiOffset()) == 1 and select(2, uiOffset()) == 1 end)
EllesmereUI.SetFramePoint(castbar, "CENTER", UIParent, "CENTER", 100, -50)
EllesmereUI.SetFramePoint(freeBar, "CENTER", UIParent, "CENTER", 100, -50)
check("an anchored EllesmereUI element doesn't get the shift twice",
	placed[castbar][4] == 96 and placed[castbar][5] == -54)
check("other EllesmereUI placements are left as asked", placed[freeBar][4] == 100 and placed[freeBar][5] == -50)
EllesmereUI.SetFramePoint(castbar, "TOP", playerFrame, "BOTTOM", 3, 4)
check("an element hung off another frame is left as asked", placed[castbar][4] == 3 and placed[castbar][5] == 4)
EllesmereUI._unlockModeSessionActive = true
if listeners.HUDFade then listeners.HUDFade(true) end
check("EllesmereUI's unlock mode gets the interface back the moment it opens",
	select(1, uiOffset()) == 0 and select(1, uiInset()) == 0)
EllesmereUI.SetFramePoint(castbar, "CENTER", UIParent, "CENTER", 100, -50)
check("nothing taken out while the interface is in its place",
	placed[castbar][4] == 100 and placed[castbar][5] == -50)
EllesmereUI._unlockModeSessionActive = false
shiftUntil(shifted)
SlashCmdList.HUDFADE("off")
check("addon off puts the interface back", atRest())
SlashCmdList.HUDFADE("on")
shiftUntil(shifted)

-- Another addon keeps putting it back: step aside
for _ = 1, 3 do
	UIParent.points = { DEFAULT_POINTS[1], DEFAULT_POINTS[2] }
	HUDFade.ShiftNow()
end
UIParent.points = { DEFAULT_POINTS[1], DEFAULT_POINTS[2] }
step(1.1)
check("gives up after another addon fights it 3 times",
	select(1, uiOffset()) == 0 and HUDFade.ShiftStatus():find("stopped", 1, true))
SlashCmdList.HUDFADE("shift on")
shiftUntil(shifted)
check("/hudfade shift on tries again", shifted())

-- Arranging frames counts as an open window: only the away time hides the HUD then
step(7)
check("idle-hidden before arranging frames", UIParent.alpha == 0)
EllesmereUI._unlockModeSessionActive = true
step(0.5)
check("EllesmereUI's unlock mode brings the HUD back like a window", UIParent.alpha == 1)
step(30)
check("and keeps it visible while you arrange frames", UIParent.alpha == 1)
check("/hudfade why names unlock mode",
	table.concat(HUDFade.Explain(), " "):find("EllesmereUI unlock mode", 1, true) ~= nil)
HUDFadeDB.awayMinutes = 2
step(91)
check("until the away time", UIParent.alpha == 0)
EllesmereUI._unlockModeSessionActive = false
HUDFadeDB.awayMinutes = 10

-- Logout and turning pixel shift off put everything back
HUDFade.Hide()
moveMouse()
step(3)
fire("PLAYER_LOGOUT")
check("logout puts the interface back exactly", exactlyBack())
step(1.1)
shiftUntil(shifted)
SlashCmdList.HUDFADE("shift off")
check("turning it off puts the interface back exactly", exactlyBack())
fire("PLAYER_LOGOUT")
check("logout restores cvars",
	cvars.UnitNameNPC == "1" and cvars.nameplateShowEnemies == "1" and next(HUDFadeDB.restore) == nil)
SlashCmdList.HUDFADE("reset")

-- Presets
check("defaults are the Everything preset", HUDFade.CurrentPreset() == 1 and HUDFade.PRESETS[1].name == "Everything")
HUDFade.ApplyPreset(2)
check("Blizzard: names and the circle stay, nameplates go",
	HUDFadeDB.hideNames == false and HUDFadeDB.hideOutline == false and HUDFadeDB.hideNameplates == true
	and HUDFade.CurrentPreset() == 2)
HUDFade.Show()
step(0.5)
HUDFade.Hide()
step(2)
check("with it, hiding leaves names, the circle and damage numbers but takes nameplates", UIParent.alpha == 0
	and cvars.UnitNameNPC == "1" and cvars.Outline == "2" and cvars.floatingCombatTextCombatDamage_v2 == "1"
	and cvars.nameplateShowEnemies == "0")
HUDFade.Show()
step(0.5)
HUDFadeDB.hideNameplates = false
check("changing a box by hand makes it Custom", HUDFade.CurrentPreset() == nil)
SlashCmdList.HUDFADE("reset")
check("reset is the Everything preset again", HUDFade.CurrentPreset() == 1)

-- The settings pages build (font strings and templates are stubs here)
local function stubObject() return setmetatable({}, { __index = stubMethod }) end
for _, f in ipairs(frames) do rawset(f, "CreateFontString", stubObject) end
local realCreate = CreateFrame
local templates = {}
local presetMenu
local dropdowns = {}
local copyBoxes = {}
CreateFrame = function(kind, name, parent, template)
	if template then templates[#templates + 1] = template end
	if template == "ScrollFrameTemplate" then error("no such template") end -- the fallback must cope
	local f = realCreate(kind, name, parent)
	rawset(f, "CreateFontString", stubObject)
	if template == "WowStyle1DropdownTemplate" then
		presetMenu = presetMenu or f -- the main page's comes first
		dropdowns[#dropdowns + 1] = f
		rawset(f, "SetupMenu", function(self, gen) self.gen = gen end)
	end
	if template == "InputBoxTemplate" then
		copyBoxes[#copyBoxes + 1] = f
		rawset(f, "SetText", function(self, text) self.text = text end)
	end
	return f
end
local pages = {}
for _, f in ipairs(frames) do
	if f.scripts.OnShow and f ~= GameTooltip then pages[#pages + 1] = f end
end
local ok, err = pcall(function()
	for _, f in ipairs(pages) do f.scripts.OnShow(f) end
end)
check("settings pages build without errors (" .. tostring(err) .. ")", ok and #pages == 3)
check("the main page scrolls (falls back to the older scroll template)",
	table.concat(templates, " "):find("UIPanelScrollFrameTemplate") ~= nil)

local radios = {}
if presetMenu and presetMenu.gen then
	presetMenu.gen(presetMenu, {
		CreateRadio = function(_, text, isSel, setSel)
			radios[#radios + 1] = { text = text, isSel = isSel, setSel = setSel }
		end,
	})
end
check("the preset menu lists both presets",
	#radios == 2 and radios[1].text == "Everything" and radios[1].isSel() == true)
if #radios == 2 then radios[2].setSel() end
check("choosing one in the menu applies it",
	HUDFade.CurrentPreset() == 2 and HUDFadeDB.hideNames == false and radios[2].isSel() == true)
SlashCmdList.HUDFADE("reset")

-- The Elements page: a menu per element
local function radiosOf(dd)
	local list = {}
	dd.gen(dd, {
		CreateRadio = function(_, text, isSel, setSel) list[#list + 1] = { text = text, isSel = isSel, setSel = setSel } end,
	})
	return list
end
local barMenu, noticeMenu
for _, dd in ipairs(dropdowns) do
	local r = dd.gen and radiosOf(dd) or {}
	if not barMenu and #r == 3 and r[2].text == "Shown on mouseover" then barMenu = r end
	if not noticeMenu and #r == 2 and r[2].text == "Always visible" then noticeMenu = r end
end
check("element menus offer Hidden, Shown on mouseover and Always visible",
	barMenu and barMenu[1].text == "Hidden" and barMenu[1].isSel() == true and barMenu[3].text == "Always visible")
check("notifications offer only Hidden and Always visible", noticeMenu ~= nil)
if barMenu then barMenu[2].setSel() end
check("choosing one saves it for that element", HUDFadeDB.elements.bars == "hover" and barMenu[2].isSel() == true)
SlashCmdList.HUDFADE("reset")
check("reset puts every element back to Hidden", next(HUDFadeDB.elements) == nil)

-- Help and feedback addresses
local pageBox = copyBoxes[1]
check("the settings show the addon page and issues addresses",
	#copyBoxes == 2 and pageBox.text:find("curseforge") ~= nil and copyBoxes[2].text:find("/issues") ~= nil)
pageBox:SetText("typed over")
pageBox.scripts.OnTextChanged(pageBox, true)
check("typing in an address box puts the address back", pageBox.text:find("curseforge") ~= nil)
CreateFrame = realCreate

-- The away slider stops at 2, 5, 10, 15, 20, 30, 45 and 60 minutes
local sliders = {}
for _, f in ipairs(frames) do
	if f.scripts.OnValueChanged then sliders[#sliders + 1] = f end
end
for _, f in ipairs(sliders) do f.scripts.OnValueChanged(f, 8) end
local top = HUDFadeDB.awayMinutes
for _, f in ipairs(sliders) do f.scripts.OnValueChanged(f, 3) end
check("the away slider goes up to an hour in bigger steps", top == 60 and HUDFadeDB.awayMinutes == 10)

-- Minimap button and addon compartment
check("the minimap button is registered and shown",
	icon.name == "HUDFade" and icon.shown and icon.db == HUDFadeDB.minimap)
local tipLines = {}
local fakeTip = {}
function fakeTip:AddDoubleLine(left, right) tipLines[#tipLines + 1] = left .. ": " .. right end
icon.obj.OnTooltipShow(fakeTip)
check("its tooltip lists the clicks", table.concat(tipLines, ", "):find("Right-click: Turn off", 1, true) ~= nil)
local opened = 0
local realOpen = HUDFade.OpenOptions
HUDFade.OpenOptions = function() opened = opened + 1 end
icon.obj.OnClick(nil, "LeftButton")
check("left-click opens the settings", opened == 1)
tipLines = {}
local minimapButton = newFrame()
function minimapButton:IsMouseOver() return true end
function minimapButton:GetScript() return function() icon.obj.OnTooltipShow(fakeTip) end end
icon.obj.OnClick(minimapButton, "RightButton")
check("right-click turns HUD Fade off", HUDFadeDB.enabled == false)
check("and the tooltip under the mouse shows it", table.concat(tipLines, ", "):find("HUD Fade: Off", 1, true) ~= nil)
HUDFade_OnCompartmentClick("HUDFade", { buttonName = "RightButton" })
check("right-click in the addon compartment turns it back on", HUDFadeDB.enabled == true)
HUDFade_OnCompartmentClick("HUDFade", "LeftButton")
check("the addon compartment opens the settings too", opened == 2)
HUDFade.OpenOptions = realOpen
local shotsBefore = shots
shiftDown = true
icon.obj.OnClick(nil, "LeftButton")
shiftDown = false
step(0.3)
check("shift-click takes a screenshot without the HUD", shots == shotsBefore + 1)
fire("SCREENSHOT_SUCCEEDED")
step(0.5)
SlashCmdList.HUDFADE("minimap")
check("/hudfade minimap hides the button", not icon.shown and HUDFadeDB.minimap.hide == true)
SlashCmdList.HUDFADE("reset")
check("reset shows it again", icon.shown and HUDFadeDB.minimap.hide == false)

-- Nameplates (EllesmereUI's names among them) follow the fade, then the nameplate CVars take them away.
-- The game owns each nameplate's own opacity (distance fade), so the frames inside it are faded.
HUDFade.Show()
step(1)
local plate = newFrame()
plate.alpha = 0.6 -- set by the game for distance
local name, dimmed = newFrame(), newFrame() -- e.g. Blizzard's name-only frame, an addon plate at 50%
dimmed.alpha = 0.5
plate.kids = { name, dimmed }
function plate:GetChildren() return unpack(self.kids) end
namePlates.nameplate1 = plate
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check("a nameplate starts at full opacity", name.alpha == 1 and dimmed.alpha == 0.5)
HUDFade.Hide()
step(0.5)
check("halfway through the fade its frames are half faded", name.alpha > 0.2 and name.alpha < 0.8
	and math.abs(dimmed.alpha - name.alpha * 0.5) < 0.001)
check("the nameplate's own opacity is left to the game", plate.alpha == 0.6)
local latePart = newFrame() -- an addon builds its plate after we first saw the unit
plate.kids[3] = latePart
step(0.05)
check("a frame added mid-fade fades too", latePart.alpha > 0 and latePart.alpha < 0.8)
step(1)
check("it fades out with the HUD before the CVars take it away",
	name.alpha == 0 and dimmed.alpha == 0 and latePart.alpha == 0 and cvars.nameplateShowEnemies == "0")
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check("the game reuses it at its own opacity", name.alpha == 1 and dimmed.alpha == 0.5 and latePart.alpha == 1)
plate.kids[3] = nil
HUDFadeDB.showCombat = false
fire("PLAYER_REGEN_DISABLED")
lockdown = true
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check("in combat the nameplate CVars come back, but with the HUD hidden the plates stay faded out",
	cvars.nameplateShowEnemies == "1" and name.alpha == 0 and dimmed.alpha == 0)
local castBar = newFrame() -- e.g. a cast bar an addon parents to the plate mid-fight
plate.kids[3] = castBar
step(0.2)
check("parts added to a plate while hidden are faded out too", castBar.alpha == 0)
name.alpha = 1 -- its addon resets it
step(0.2)
check("and a part its addon resets goes back to faded", name.alpha == 0)
HUDFade.Show()
step(0.1)
check("showing the HUD in combat fades the plates in with it", name.alpha > 0 and name.alpha < 1)
step(0.5)
check("and ends at full opacity", name.alpha == 1 and dimmed.alpha == 0.5 and castBar.alpha == 1)
lockdown = false
fire("PLAYER_REGEN_ENABLED")
plate.kids[3] = nil
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
HUDFadeDB.showCombat = true
HUDFade.Hide()
step(2)
HUDFade.Show()
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
step(0.1)
check("a nameplate coming back fades in with the HUD", name.alpha > 0 and name.alpha < 1)
step(0.5)
check("and ends at full opacity", name.alpha == 1 and dimmed.alpha == 0.5)
local forbidden = newFrame()
function forbidden:IsForbidden() return true end
plate.kids[3] = forbidden
HUDFadeDB.hideNameplates = false
HUDFade.Hide()
step(0.5)
check("with nameplates not hidden, they don't fade", name.alpha == 1)
HUDFadeDB.hideNameplates = true
HUDFade.Show()
step(1)
HUDFade.Hide()
step(0.5)
check("a frame the game forbids is left alone", forbidden.alpha == 1 and name.alpha < 1)

-- Elements: parts of the HUD lifted out of its fade, always or while the mouse is over them or in a fight
plate.kids[3] = nil
HUDFade.Show()
step(1)
local E = HUDFade.Elements
local function elementFrame(frameName, parent)
	local f = CreateFrame("Frame", frameName, parent or UIParent)
	f.ignoring = false
	function f:IsIgnoringParentAlpha() return self.ignoring end
	function f:SetIgnoreParentAlpha(on) self.ignoring = on end
	function f:IsMouseOver() return self.over == true end
	return f
end
local chat = elementFrame("ChatFrame1")
local chatTab = elementFrame("ChatFrame1Tab", chat) -- inside the chat frame, so it goes with it
local bar = elementFrame("MultiBarBottomLeft")
local barModel = newFrame("PlayerModel") -- a 3D model inside the bar
barModel.parent = bar
barModel.malpha = 1
barModel:SetUnit("player")
local euiBar, euiChat = elementFrame("EABBar_Bar2"), elementFrame()
local euiElements = EllesmereUI._unlockRegisteredElements
euiElements.Bar2 = { group = "Action Bars", getFrame = function() return euiBar end }
euiElements.ECHAT_MainChat = { group = "Chat", getFrame = function() return euiChat end }
-- EllesmereUI draws chat on a panel beside the chat frame, and places its tabs and border by other frames
local chatPanel, dock = elementFrame(), elementFrame("GeneralDockManager")
local tabStrip, panelBorder, barGlow = elementFrame(), elementFrame(), elementFrame()
local function placeBy(f, rel)
	function f:GetNumPoints() return 1 end
	function f:GetPoint() return "TOPLEFT", rel, "TOPLEFT", 0, 0 end
end
placeBy(tabStrip, dock)
placeBy(panelBorder, chatPanel)
placeBy(barGlow, bar)
EllesmereUI._chatCFD = function(cf) return cf == chat and { bg = chatPanel } or {} end
function UIParent:GetChildren() return chat, bar, euiBar, euiChat, chatPanel, dock, tabStrip, panelBorder, barGlow end
E.Refresh()

E.SetMode("chat", "show")
HUDFade.Hide()
check("an always visible element is lifted out before the fade starts",
	chat.ignoring == true and chat.alpha == 1 and euiChat.ignoring == true)
check("a frame inside it is left to follow it", chatTab.ignoring == false)
check("EllesmereUI's chat panel stays too", chatPanel.ignoring == true)
check("and so do its tabs and border, placed beside it", tabStrip.ignoring == true and panelBorder.ignoring == true)
check("but not a frame placed by another element", barGlow.ignoring == false)
check("other elements fade with the HUD", bar.ignoring == false and euiBar.ignoring == false)
step(1.5)
check("it stays while the rest of the HUD is hidden", UIParent.alpha == 0 and chat.ignoring == true and chat.alpha == 1)
local apart = table.concat(HUDFade.Explain(), " ")
check("/hudfade why lists it", apart:find("Chat (always visible)", 1, true) ~= nil)
HUDFade.Show()
step(0.1)
check("while the HUD fades back in it stays lifted",
	chat.ignoring == true and UIParent.alpha > 0 and UIParent.alpha < 1)
step(0.3)
check("once the HUD is back it follows the HUD again",
	chat.ignoring == false and chat.alpha == 1 and UIParent.alpha == 1)

E.SetMode("chat", "hide")
E.SetMode("bars", "hover")
HUDFade.Hide()
step(1.5)
check("a mouseover element is hidden until the mouse is over it",
	bar.ignoring == false and UIParent.alpha == 0 and barModel.malpha == 0)
bar.over = true
step(0.1)
check("with the mouse over its spot it fades in", bar.ignoring == true and bar.alpha > 0 and bar.alpha < 1)
check("only the bar under the mouse comes back", euiBar.ignoring == false)
step(0.2)
check("to its own look, 3D models inside it too", bar.alpha == 1 and barModel.malpha == 1)
local button = newFrame()
button.parent = bar
GameTooltip.owner = button
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetIgnoreParentAlpha(on) self.ignoring = on end
GameTooltip:Show()
step(0.2)
check("a tooltip for a button in it shows too", GameTooltip.shown == true and GameTooltip.ignoring == true)
GameTooltip:Hide()
GameTooltip.scripts.OnHide(GameTooltip)
check("and goes back to normal when it closes", GameTooltip.ignoring == false)
GameTooltip.ignoring = true -- DynamicCam's Keep Tooltip
GameTooltip:Show()
check("a tooltip that already ignores the UI's opacity stays open over it too", GameTooltip.shown == true)
GameTooltip:Hide()
GameTooltip.ignoring = false
GameTooltip.owner = nil
bar.over = false
euiBar.over = true
step(0.5)
check("moving to another bar brings that one back", euiBar.ignoring == true and euiBar.alpha == 1)
check("while the first stays a moment after the mouse leaves", bar.ignoring == true and bar.alpha == 1)
step(1.0)
check("then fades out", bar.ignoring == true and bar.alpha < 1)
step(1.0)
check("and goes back to following the HUD, at its own opacity",
	bar.ignoring == false and bar.alpha == 1 and UIParent.alpha == 0 and barModel.malpha == 0)
check("the bar under the mouse stays", euiBar.ignoring == true and euiBar.alpha == 1)
euiBar.over = false
step(3)
check("until the mouse leaves it too", euiBar.ignoring == false and euiBar.alpha == 1)
HUDFadeDB.oneBarAtATime = false
bar.over = true
step(0.5)
check("with One bar at a time unticked, every bar comes back together",
	bar.ignoring == true and euiBar.ignoring == true)
bar.over = false
step(3)
check("and goes together", bar.ignoring == false and euiBar.ignoring == false)
HUDFadeDB.oneBarAtATime = true

-- In combat: untick an element and a fight brings back only the ticked ones
E.SetMode("bars", "hide")
E.SetInCombat("chat", false)
check("unticking one makes fights bring back only some elements", E.PartialCombat() == true)
fire("PLAYER_REGEN_DISABLED")
lockdown = true
check("the HUD stays hidden but the ticked elements come back at once",
	UIParent.alpha == 0 and bar.ignoring == true and bar.alpha == 1 and chat.ignoring == false)
check("nameplates come back too while ticked", cvars.nameplateShowEnemies == "1" and name.alpha == 1)
apart = table.concat(HUDFade.Explain(), " ")
check("/hudfade why says why", apart:find("only the elements ticked under In combat", 1, true) ~= nil)
E.SetInCombat("nameplates", false)
check("unticked, they stay hidden", name.alpha == 0)
lockdown = false
fire("PLAYER_REGEN_ENABLED")
step(0.5)
check("a moment after the fight it is still like that", bar.ignoring == true and UIParent.alpha == 0)
step(2.5)
check("then the elements fade out again", bar.ignoring == false and bar.alpha == 1 and UIParent.alpha == 0)
E.SetInCombat("chat", true)
check("with every element ticked, fights bring back the entire HUD again", E.PartialCombat() == false)
fire("PLAYER_REGEN_DISABLED")
lockdown = true
check("the HUD comes back, but unticked nameplates stay hidden", UIParent.alpha == 1 and name.alpha == 0)
lockdown = false
fire("PLAYER_REGEN_ENABLED")
HUDFade.Show()
step(0.5)
check("after the fight the nameplates follow the HUD again", name.alpha == 1)
E.SetInCombat("nameplates", true)

-- The minimap is switched off while hidden, so its row shows and hides it
Minimap.ignoring = false
function Minimap:IsIgnoringParentAlpha() return self.ignoring end
function Minimap:SetIgnoreParentAlpha(on) self.ignoring = on end
function Minimap:IsMouseOver() return self.over == true end
E.SetMode("minimap", "show")
E.Refresh()
HUDFade.Hide()
step(1.5)
check("an always visible minimap stays on and lifted", Minimap.shown == true and Minimap.ignoring == true)
HUDFade.Show()
step(0.5)
E.SetMode("minimap", "hover")
HUDFade.Hide()
step(1.5)
check("on mouseover it is switched off while hidden", Minimap.shown == false)
Minimap.over = true
step(0.1)
check("and comes back with the mouse over its spot", Minimap.shown == true and Minimap.ignoring == true)
Minimap.over = false
step(1.5)
check("and goes again once the mouse leaves", Minimap.shown == false and Minimap.ignoring == false)
E.SetMode("minimap", "hide")

-- A HUD-free screenshot leaves everything out
E.SetMode("chat", "show")
step(0.5)
check("chat kept while hidden", chat.ignoring == true)
HUDFade.CleanScreenshot()
check("a HUD-free screenshot takes it too", chat.ignoring == false)
step(0.3)
fire("SCREENSHOT_SUCCEEDED")
step(0.5)
check("and it comes back after", chat.ignoring == true and chat.alpha == 1)
E.SetMode("chat", "hide")
HUDFade.Show()
step(1)

-- 1.3.0 turned the Minimap box under "also hide" into the Minimap element
local saved = HUDFadeDB
HUDFadeDB = { hideMinimap = false }
fire("ADDON_LOADED", "HUDFade")
check("an unticked Minimap box becomes an always visible minimap",
	HUDFadeDB.elements.minimap == "show" and HUDFadeDB.hideMinimap == nil)
HUDFadeDB = saved
fire("ADDON_LOADED", "HUDFade")

-- A change the game refuses in combat is made once combat ends
HUDFade.Show()
step(1)
HUDFadeDB.showCombat = false
fire("PLAYER_REGEN_DISABLED")
lockdown = true
refuseDamage = true
HUDFade.Hide()
step(2)
check("hidden in combat: damage numbers the game won't change yet are not marked as off",
	cvars.floatingCombatTextCombatDamage_v2 == "1" and HUDFadeDB.restore.floatingCombatTextCombatDamage_v2 == nil)
refuseDamage = false
lockdown = false
fire("PLAYER_REGEN_ENABLED")
check("they go off when combat ends", cvars.floatingCombatTextCombatDamage_v2 == "0")
fire("PLAYER_REGEN_DISABLED")
lockdown = true
refuseDamage = true
HUDFade.Show()
step(1)
check("shown in combat: a refused change back is kept to try again",
	cvars.floatingCombatTextCombatDamage_v2 == "0" and HUDFadeDB.restore.floatingCombatTextCombatDamage_v2 == "1")
refuseDamage = false
lockdown = false
fire("PLAYER_REGEN_ENABLED")
check("and they come back when combat ends", cvars.floatingCombatTextCombatDamage_v2 == "1"
	and HUDFadeDB.restore.floatingCombatTextCombatDamage_v2 == nil)
HUDFadeDB.showCombat = true

-- Welcome window: once, after the first loading screen; it shows the keys but leaves setting them to the game
HUDFadeDB.idleSeconds = 5
HUDFade.Show()
step(7)
check("idle-hidden before the welcome window", UIParent.alpha == 0 and HUDFadeDB.welcomeShown == false)
local welcomeTexts = {}
local function recordText(self, text) self.text = text end
CreateFrame = function(kind, frameName, parent)
	local f = realCreate(kind, frameName, parent)
	rawset(f, "CreateFontString", function()
		local fs = stubObject()
		rawset(fs, "SetText", recordText)
		welcomeTexts[#welcomeTexts + 1] = fs
		return fs
	end)
	return f
end
fire("PLAYER_ENTERING_WORLD")
step(2.5)
CreateFrame = realCreate
local welcome = HUDFadeWelcome
check("the welcome window opens after the first loading screen", welcome ~= nil and welcome.shown == true)
check("and keeps the HUD up like any window", UIParent.alpha == 1)
local function shown(text)
	for _, fs in ipairs(welcomeTexts) do
		if type(fs.text) == "string" and fs.text:find(text, 1, true) then return true end
	end
	return false
end
check("hide / show lists the Hide UI key", shown("ALT-Z"))
check("a key that isn't bound says Not set", shown("Not set"))
check("the screenshot key isn't listed while it takes plain screenshots", not shown("PRINTSCREEN"))
BINDINGS.PRINTSCREEN, HUDFadeDB.cleanPrintScreen = "SCREENSHOT", true
BINDINGS["SHIFT-P"] = "HUDFADE_PEEK"
SlashCmdList.HUDFADE("welcome")
check("it is once HUD-free screenshots is ticked", shown("PRINTSCREEN"))
check("keys bound in Key Bindings show up", shown("SHIFT-P"))
BINDINGS.PRINTSCREEN, BINDINGS["SHIFT-P"], HUDFadeDB.cleanPrintScreen = nil, nil, false
check("the idle line says the mouse brings it back", shown("Moving the mouse brings it back."))
check("both idle timers are there", shown("Hide when idle: ") and shown("Always hide when AFK: "))
HUDFadeDB.mouseWakes = false
SlashCmdList.HUDFADE("welcome")
check("with mouse moving off, it says a click does", shown("A click or a movement key brings it back."))
HUDFadeDB.mouseWakes = true

check("the window takes no keys, so you can still move",
	welcome.scripts.OnKeyDown == nil and not rawget(welcome, "keyboard"))
check("it stays out of the game's Escape handlers, which would taint Escape", #escHandlers == 0)
closeSpecialWindows()
check("Escape closes it like other windows", welcome.shown == false)
welcome.scripts.OnHide(welcome)
check("closing it marks it seen", HUDFadeDB.welcomeShown == true)
fire("PLAYER_ENTERING_WORLD")
step(2.5)
check("later loading screens don't open it again", welcome.shown == false)
SlashCmdList.HUDFADE("welcome")
check("/hudfade welcome opens it again", welcome.shown == true)
welcome:Hide()
SlashCmdList.HUDFADE("reset")
check("reset doesn't bring it back at the next login", HUDFadeDB.welcomeShown == true)

os.exit(failed and 1 or 0)
