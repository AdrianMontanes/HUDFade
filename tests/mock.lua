-- Runs HUD Fade against a tiny fake WoW API: lua5.1 tests/mock.lua .
-- Minimal WoW API mock to run HUD Fade's logic outside the game.
local T = 0
function GetTime() return T end
local cvars = { chatBubbles="1", cameraYawMoveSpeed="180", cameraPitchMoveSpeed="90", UnitNameNPC="1", UnitNameOwn="0", ObjectSelectionCircle="1", Outline="2", nameplateShowEnemies="1", nameplateShowFriends="1", nameplateShowFriendlyPlayers="1" }
C_CVar = { GetCVar=function(n) return cvars[n] end, SetCVar=function(n,v) if lockdown and n:find("nameplate") then error("blocked") end cvars[n]=v end }
lockdown=false
function InCombatLockdown() return lockdown end
local frames = {}
-- What every model shares (the game keeps a widget type's methods in one table, so a hook there sees every model).
modelMethods = setmetatable({ SetUnit=function() end }, {__index=function(t,k) return function() end end})
local function newFrame(kind)
  local f = { scripts={}, shown=true, alpha=1, events={}, kind=kind or "Frame" }
  function f:SetScript(n, fn) self.scripts[n]=fn end
  function f:Hide() self.shown=false end
  function f:Show() self.shown=true end
  function f:IsShown() return self.shown end
  function f:IsVisible() return self.shown end
  function f:RegisterEvent(e) self.events[e]=true end
  function f:RegisterUnitEvent(e) self.events[e]=true end
  function f:SetAlpha(a) self.alpha=a end
  function f:GetAlpha() return self.alpha end
  function f:EnableKeyboard() end
  function f:SetPropagateKeyboardInput() end
  function f:GetObjectType() return self.kind end
  function f:GetParent() return self.parent end
  function f:GetEffectiveScale() return 1 end
  setmetatable(f, {__index=(kind=="PlayerModel" or kind=="Model") and modelMethods or function(t,k) return function() end end})
  frames[#frames+1]=f
  return f
end
UIParent = newFrame()
UIParent.points = { {"TOPLEFT", nil, "TOPLEFT", 0, 0}, {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0} }
function UIParent:GetNumPoints() return #self.points end
function UIParent:GetPoint(i) local a = self.points[i]; return a[1], a[2], a[3], a[4], a[5] end
function UIParent:ClearAllPoints() if lockdown then error("blocked") end self.points = {} end
function UIParent:SetPoint(p, r, rp, x, y) if lockdown then error("blocked") end table.insert(self.points, {p, r, rp, x, y}) end
function UIParent:GetScale() return 0.5 end
function GetPhysicalScreenSize() return 2560, 1536 end -- (768/1536 = 0.5 units a pixel at scale 1, so 1 px = 1 unit here)
-- Where the middle of the interface is (its offset), and how far in from the screen edges it is kept.
local function uiOffset() local a, b = UIParent.points[1], UIParent.points[2]; return (a[4] + b[4]) / 2, (a[5] + b[5]) / 2 end
local function uiInset() local a, b = UIParent.points[1], UIParent.points[2]; return (a[4] - b[4]) / 2, (b[5] - a[5]) / 2 end
Minimap = newFrame(); Minimap.parent = UIParent
function hooksecurefunc(t, name, fn) local orig=t[name]; rawset(t, name, function(...) local r=orig(...); fn(...); return r end) end
function CreateFrame(kind, name, parent) local f=newFrame(kind); f.parent=parent; if name then _G[name]=f end; return f end
local model = newFrame("PlayerModel"); model.parent = UIParent; model.malpha=1
function model:SetModelAlpha(a) self.malpha=a end
function model:GetModelAlpha() return self.malpha end
local lone = newFrame(); lone.parent = UIParent
function lone:IsIgnoringParentAlpha() return true end
-- Secret values (game 12.0): the game hides some values from addons. Here, maths or indexing on one errors.
SECRET = newproxy(true)
getmetatable(SECRET).__index = function() error("attempt to index a secret value") end
function issecretvalue(v) return rawequal(v, SECRET) end
-- A frame (like EllesmereUI's target frame with its range fade) where even "ignores parent opacity" is secret.
local secretFrame = newFrame(); secretFrame.parent = UIParent
function secretFrame:IsIgnoringParentAlpha() return SECRET end
function secretFrame:GetAlpha() return SECRET end
function secretFrame:IsVisible() return SECRET end
-- A frame that ignores its parent's opacity but keeps its own opacity secret: must never be left invisible.
local secretLoner = newFrame(); secretLoner.parent = UIParent
function secretLoner:IsIgnoringParentAlpha() return true end
function secretLoner:GetAlpha() return SECRET end
-- A frame whose every check errors.
local brokenFrame = newFrame(); brokenFrame.parent = UIParent
function brokenFrame:GetObjectType() error("forbidden") end
function brokenFrame:IsIgnoringParentAlpha() error("forbidden") end
function EnumerateFrames(f) if not f then return frames[1] end for i,x in ipairs(frames) do if x==f then return frames[i+1] end end end
C_Timer = { After=function(d,fn) table.insert(timers,{T+d,fn}) end, NewTicker=function(d,fn) ticker=fn end }
timers = {}
function GetBindingKey(c) if c=="TOGGLEUI" then return "ALT-Z" end if c=="TOGGLEAUTORUN" then return "NUMLOCK" end end
function GetBindingAction(k) local m={W="MOVEFORWARD", D="TURNRIGHT", NUMLOCK="TOGGLEAUTORUN", TAB="TARGETNEARESTENEMY"}; return m[k] or "" end
binds = {}
function SetOverrideBinding(o,p,k,c) binds[k]=c end
function ClearOverrideBindings() binds={} end
typingIn=nil
function GetCurrentKeyBoardFocus() return typingIn end
function GetCursorInfo() return nil end
local cx=0
function GetCursorPosition() return cx, 0 end
buttons={}
function IsMouseButtonDown(b) return buttons[b] or false end
local target=false
function UnitExists(u) return target end
dead=false
function UnitIsDead() return dead end
mouselook=false
function IsMouselooking() return mouselook end
-- (HUD Fade no longer hides the pointer: these must stay untouched)
mlBinds = {}
function MouselookStart() mouselookStarted=true end
function SetMouselookOverrideBinding(k, b) mlBinds[k]=b end
function Screenshot() shots=(shots or 0)+1 end
UISpecialFrames = {}
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
SlashCmdList = {}
local function fire(e, ...) for _,f in ipairs(frames) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
local function step(secs) -- advance time, run ticker and fades
  local n = math.floor(secs/0.1+0.5)
  for i=1,n do
    T=T+0.1
    for j=#timers,1,-1 do local t=timers[j]; if t[1]<=T then table.remove(timers,j); t[2]() end end
    if ticker then ticker() end
    for _,f in ipairs(frames) do if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f,0.1) end end
  end
end
local function load(file) local fn=assert(loadfile(file)); fn("HUDFade", ns) end
ns = {}
load(arg[1].."/Core.lua"); load(arg[1].."/Options.lua")
-- Saved by 0.2.x with the pointer hidden at logout: the option is gone, and the look speed must come back.
HUDFadeDB = { hideCursor=true, hideCursorSteer=true, mouseReported=true, log={"x"}, restore={ cameraYawMoveSpeed="180" } }
cvars.cameraYawMoveSpeed="18"
fire("ADDON_LOADED","HUDFade"); fire("PLAYER_LOGIN")
local function check(label, cond) print((cond and "PASS " or "FAIL ")..label) ; if not cond then failed=true end end
check("the old pointer option's settings are dropped", HUDFadeDB.hideCursor==nil and HUDFadeDB.hideCursorSteer==nil and HUDFadeDB.mouseReported==nil and HUDFadeDB.log==nil)
check("and the mouse look speed it had lowered comes back", cvars.cameraYawMoveSpeed=="180" and next(HUDFadeDB.restore)==nil)
step(1)
check("starts visible", UIParent.alpha==1)
check("Alt+Z overridden", binds["ALT-Z"]=="HUDFADE_TOGGLE")
HUDFade.Toggle(); step(1.5)
check("toggle hides", UIParent.alpha==0)
check("NPC names off", cvars.UnitNameNPC=="0" and HUDFadeDB.restore.UnitNameNPC=="1")
check("target circle and glow off", cvars.ObjectSelectionCircle=="0" and HUDFadeDB.restore.ObjectSelectionCircle=="1" and cvars.Outline=="0" and HUDFadeDB.restore.Outline=="2")
check("a setting the game lacks is skipped", HUDFadeDB.restore.UnitNameHostleNPC==nil and cvars.UnitNameHostleNPC==nil)
check("own name untouched (was 0)", cvars.UnitNameOwn=="0" and HUDFadeDB.restore.UnitNameOwn==nil)
check("plates off", cvars.nameplateShowEnemies=="0")
check("model faded", model.malpha==0)
check("frame that ignores parent opacity faded", lone.alpha==0)
check("frames with secret values left alone", secretFrame.alpha==1 and secretLoner.alpha==1)
check("minimap hidden", Minimap.shown==false)
Minimap:Show(); check("minimap stays hidden if another addon shows it", Minimap.shown==false)
check("friendly player plates off", cvars.nameplateShowFriendlyPlayers=="0")
target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("target shows", UIParent.alpha==1 and cvars.UnitNameNPC=="1")
check("target circle and glow back", cvars.ObjectSelectionCircle=="1" and cvars.Outline=="2")
check("model back", model.malpha==1)
check("that frame back", lone.alpha==1)
check("minimap back", Minimap.shown==true)
target=false; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("short grace after the target clears", UIParent.alpha==1)
step(2)
check("hides after the grace", UIParent.alpha==0)
HUDFadeDB.hideOutline=false; target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5); target=false; fire("PLAYER_TARGET_CHANGED"); step(3)
check("with Target circle and glow off, the glow stays", UIParent.alpha==0 and cvars.Outline=="2" and cvars.UnitNameNPC=="0")
HUDFadeDB.hideOutline=true
fire("PLAYER_REGEN_DISABLED"); lockdown=true
check("combat shows instantly", UIParent.alpha==1 and cvars.nameplateShowEnemies=="1")
step(1); lockdown=false; fire("PLAYER_REGEN_ENABLED")
step(5)
check("hidden again after combat", UIParent.alpha==0)
target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5)
HUDFade.Toggle(); step(1.5)
check("hide with target suppresses target", UIParent.alpha==0)
HUDFade.Toggle(); step(0.5)
check("toggle shows", UIParent.alpha==1)
target=false; fire("PLAYER_TARGET_CHANGED")
step(30.3)
check("idle starts hiding right at 30 s (no extra delay)", HUDFade.state.target==0)
step(1.2)
check("idle hides", UIParent.alpha==0)
cx=50; step(0.5)
check("mouse wakes", UIParent.alpha==1)
HUDFade.Peek(true); check("peek instant", UIParent.alpha==1)
HUDFade.CleanScreenshot(); check("shot hides instantly", UIParent.alpha==0 and cvars.UnitNameNPC=="0")
step(0.3); check("screenshot taken", shots==1)
fire("SCREENSHOT_SUCCEEDED"); step(0.5)
check("back after shot", UIParent.alpha==1)
HUDFade.Peek(false)
local keyFrame; for _,f in ipairs(frames) do if f.scripts.OnKeyDown then keyFrame=f end end
HUDFade.Hide(); step(4)
check("the mouse pointer is left alone (that option is gone)", mouselookStarted==nil and next(mlBinds)==nil)
check("hidden before turning off", UIParent.alpha==0)
SlashCmdList.HUDFADE("off")
check("off shows everything at once", UIParent.alpha==1 and cvars.UnitNameNPC=="1" and Minimap.shown==true)
check("off gives the Hide UI key back", binds["ALT-Z"]==nil)
HUDFade.Toggle(); step(2); check("toggle does nothing while off", UIParent.alpha==1)
step(70); check("no idle hiding while off", UIParent.alpha==1)
SlashCmdList.HUDFADE("on")
check("on takes the key again", binds["ALT-Z"]=="HUDFADE_TOGGLE")
HUDFade.Toggle(); step(2); check("toggle works again", UIParent.alpha==0)
-- A stuck non-movement key must not keep you "active" (Tab used to)
-- Idle and what counts as activity
HUDFade.Toggle(); step(0.5); check("shown for the idle tests", UIParent.alpha==1)
HUDFadeDB.idleSeconds = 5
keyFrame.scripts.OnKeyDown(keyFrame, "TAB"); step(0.2)
keyFrame.scripts.OnKeyDown(keyFrame, "NUMLOCK"); fire("PLAYER_STARTED_MOVING"); step(7)
check("auto-run after Tab (key-up never seen) still goes idle", UIParent.alpha==0)
fire("PLAYER_STOPPED_MOVING"); cx=cx+40; step(0.5)
keyFrame.scripts.OnKeyDown(keyFrame, "W"); fire("PLAYER_STARTED_MOVING"); step(8)
check("holding W keeps the HUD up", UIParent.alpha==1)
keyFrame.scripts.OnKeyUp(keyFrame, "W"); step(7)
check("auto-run (moving, no key held) goes idle", UIParent.alpha==0)
fire("PLAYER_STOPPED_MOVING")
cx=cx+40; step(0.5); check("pointer move wakes", UIParent.alpha==1)
buttons.LeftButton=true; step(7)
check("turning the camera does not keep the HUD up", UIParent.alpha==0)
buttons.LeftButton=nil
HUDFadeDB.activeCamera=true; cx=cx+40; step(0.5); buttons.LeftButton=true; step(7)
check("unless that option is on", UIParent.alpha==1)
buttons.LeftButton=nil; HUDFadeDB.activeCamera=false
step(7); check("idle again", UIParent.alpha==0)
HUDFadeDB.showTarget=false; keyFrame.scripts.OnKeyDown(keyFrame, "TAB"); target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("Tab while idle-hidden, 'target' off: stays hidden", UIParent.alpha==0)
target=false; fire("PLAYER_TARGET_CHANGED"); HUDFadeDB.showTarget=true
keyFrame.scripts.OnKeyDown(keyFrame, "TAB"); target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("Tab while idle-hidden, 'target' on: shows", UIParent.alpha==1)
target=false; fire("PLAYER_TARGET_CHANGED")
-- Typing in chat counts as activity: after sending, the idle time starts over
step(7); check("idle-hidden before chatting", UIParent.alpha==0 and cvars.chatBubbles=="0")
local chatBox = { text = "" }; function chatBox:GetText() return self.text end
typingIn=chatBox; step(0.5); check("typing brings the HUD and chat bubbles back", UIParent.alpha==1 and cvars.chatBubbles=="1")
step(9.5); chatBox.text="hi"; step(0.5); typingIn=nil; step(1.5); check("after sending, it stays up for the idle time", UIParent.alpha==1)
step(5); check("then hides again", UIParent.alpha==0)
-- A chat box or window left open keeps the HUD only until you have been away for a while
chatBox.text=""; typingIn=chatBox; step(0.5); check("opening the chat box brings it back", UIParent.alpha==1)
step(30); check("left open without typing, it stays like any open window", UIParent.alpha==1)
HUDFadeDB.awayMinutes=2; step(91); check("but hides once you have been away 2 min", UIParent.alpha==0)
check("/hudfade why says you are away", table.concat(HUDFade.Explain(), " "):find("Away for 2 min", 1, true) ~= nil)
typingIn=nil; HUDFadeDB.idleSeconds=0
keyFrame.scripts.OnKeyDown(keyFrame, "W"); keyFrame.scripts.OnKeyUp(keyFrame, "W"); step(0.5)
check("a key brings it back", UIParent.alpha==1)
step(119); check("with Hide when idle at Never, it stays until the away time", UIParent.alpha==1)
step(2); check("and hides once you have been away", UIParent.alpha==0)
HUDFadeDB.idleSeconds=5; HUDFadeDB.awayMinutes=10
-- "You move the mouse" off: the mouse keeps the HUD up, but only keys bring it back once idle
HUDFadeDB.mouseWakes=false; step(7); check("idle-hidden", UIParent.alpha==0)
cx=cx+40; step(0.5); check("mouse wake off: moving the mouse leaves it hidden", UIParent.alpha==0)
keyFrame.scripts.OnKeyDown(keyFrame, "W"); keyFrame.scripts.OnKeyUp(keyFrame, "W"); step(0.5)
check("a movement key brings it back", UIParent.alpha==1)
for i=1,8 do cx=cx+40; step(1) end
check("while it is up, using the mouse keeps it up", UIParent.alpha==1)
HUDFadeDB.mouseWakes=true
-- Dying brings the HUD up once, then idle hides it again while you stay dead
step(7); check("idle-hidden before dying", UIParent.alpha==0)
dead=true; local deathPopup = CreateFrame("Frame", "StaticPopup1"); deathPopup.which="DEATH"; fire("PLAYER_DEAD"); step(0.5)
check("dying brings the HUD back", UIParent.alpha==1)
check("why says you died", table.concat(HUDFade.Explain(), "\n"):find("idling") ~= nil)
step(6); check("still dead, Release Spirit popup up: hides again after the idle time", UIParent.alpha==0)
cx=cx+40; step(0.5); check("a mouse move while dead shows it as usual", UIParent.alpha==1)
deathPopup:Hide(); dead=false; step(6); check("as a ghost idle works as usual", UIParent.alpha==0)
HUDFade.Show(); step(0.5); HUDFade.Hide(); step(2); check("hidden with the key", UIParent.alpha==0)
dead=true; deathPopup:Show(); fire("PLAYER_DEAD"); step(0.5)
check("dying shows it even after hiding it with the key", UIParent.alpha==1)
check("why lists it", table.concat(HUDFade.Explain(), "\n"):find("Death") ~= nil)
step(6); check("and it hides again after the idle time", UIParent.alpha==0)
HUDFadeDB.showDead=false; dead=false; deathPopup:Hide(); HUDFade.Show(); step(7)
dead=true; fire("PLAYER_DEAD"); step(0.5); check("'You die' off: dying while idle-hidden keeps it hidden", UIParent.alpha==0)
dead=false; HUDFadeDB.showDead=true; cx=cx+40; step(0.5)
-- /hudfade why
local realPrint, out = print, {}
local function why()
  out = {}; print = function(s) out[#out+1] = s end
  SlashCmdList.HUDFADE("why"); step(0.6); print = realPrint
  return table.concat(out, "\n")
end
cx=cx+40; step(2.4); local w = why()
check("why: enabled, idle progress", w:find("Enabled", 1, true) and w:find("HUD visible due to: Not enough time idling (2/5s)", 1, true))
step(5); w = why()
check("why: hidden by idle", w:find("HUD hidden due to: Idle for", 1, true) and not w:find("Pointer", 1, true))
HUDFadeDB.showTarget=true; target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5); w = why()
check("why: several causes on their own lines", w:find("HUD visible due to:\n   - Target\n   - Not enough time idling", 1, true))
target=false; fire("PLAYER_TARGET_CHANGED")
HUDFadeDB.idleSeconds=0; step(0.2); w = why()
check("why: idle set to Never", w:find("HUD visible due to: Hide when idle is set to Never", 1, true))
HUDFadeDB.idleSeconds=5
HUDFade.SetEnabled(false); w = why()
check("why: disabled", w:find("Disabled", 1, true) and not w:find("visible due to", 1, true))
HUDFade.SetEnabled(true)
-- Hide without a hitch: names go at the end of the fade, frames are scanned in the background
HUDFade.Show(); step(0.5)
local late = CreateFrame("PlayerModel", nil, UIParent); late.malpha=1
function late:SetModelAlpha(a) self.malpha=a end
function late:GetModelAlpha() return self.malpha end
HUDFade.Hide(); step(0.3)
check("names stay on during the fade", cvars.UnitNameNPC=="1")
step(1.0); check("names off once the fade ends", cvars.UnitNameNPC=="0")
step(0.2); check("nameplates off a moment after", cvars.nameplateShowEnemies=="0")
check("hiding does not scan every frame at once (new model not seen yet)", late.malpha==1)
HUDFade.Show(); step(20); HUDFade.Hide(); step(1.5)
check("background scan finds frames made later", late.malpha==0)
-- A portrait an addon creates only when first needed, while the HUD is hidden (EllesmereUI's target portrait)
HUDFade.Hide(); step(1.5)
local lazy = CreateFrame("PlayerModel", nil, UIParent); lazy.malpha=1
function lazy:SetModelAlpha(a) self.malpha=a end
function lazy:GetModelAlpha() return self.malpha end
fire("PLAYER_TARGET_CHANGED"); step(2)
check("a portrait made while hidden is found and faded within seconds", lazy.malpha==0)
HUDFade.Show(); step(0.5)
check("and restored when the HUD comes back", lazy.malpha==1)
-- Faded the moment it is given a unit, without waiting for a scan
HUDFade.Hide(); step(1.5)
local late = CreateFrame("PlayerModel", nil, UIParent); late.malpha=1
function late:SetModelAlpha(a) self.malpha=a end
function late:GetModelAlpha() return self.malpha end
late:SetUnit("target")
check("a portrait given a unit while hidden is faded at once", late.malpha==0)
local loose = CreateFrame("PlayerModel"); loose.malpha=1
function loose:SetModelAlpha(a) self.malpha=a end
loose:SetUnit("target"); check("a model outside the UI is left alone", loose.malpha==1)
HUDFade.Show(); step(0.5)
check("and restored when the HUD comes back", late.malpha==1)
-- Pixel shift
check("pixel shift off by default", select(1, uiOffset())==0 and select(2, uiOffset())==0)
SlashCmdList.HUDFADE("shift on"); step(1.1)
local visited, nonzero = {}, false
for i=1,9 do HUDFade.ShiftNow(); local x,y = uiOffset(); visited[x..","..y]=true; if x~=0 or y~=0 then nonzero=true end end
local n=0; for _ in pairs(visited) do n=n+1 end
check("shift walks the 9 spots of the circle", n==9 and nonzero and visited["2,0"] and visited["-2,-2"])
check("kept the distance in from every edge", select(1, uiInset())==2 and select(2, uiInset())==2 and #UIParent.points==2)
local inside = true
for i=1,9 do HUDFade.ShiftNow(); local a, b = UIParent.points[1], UIParent.points[2]
  if a[4] < 0 or a[5] > 0 or b[4] > 0 or b[5] < 0 then inside = false end end
check("never past a screen edge on any spot", inside)
repeat HUDFade.ShiftNow() until select(1, uiOffset())==2
lockdown=true; HUDFade.ShiftNow(); step(1.1)
check("no move during combat", select(1, uiOffset())==2)
lockdown=false; fire("PLAYER_REGEN_ENABLED"); step(0.1)
check("moves on after combat", select(1, uiOffset())~=2 or select(2, uiOffset())~=0)
HUDFadeDB.shiftPixels=1; step(1.1); local x1, y1 = uiOffset()
check("distance follows the setting", math.abs(x1)<=1 and math.abs(y1)<=1)
EditModeManagerFrame = CreateFrame("Frame", "EditModeManagerFrame"); step(1.1)
check("back in place while Edit Mode is open", select(1, uiOffset())==0 and select(2, uiOffset())==0)
EditModeManagerFrame:Hide(); HUDFade.ShiftNow(); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
EllesmereUI = { _unlockModeSessionActive = true }
function EllesmereUI:IsUnlockModeActive() return self._unlockModeSessionActive == true end
step(1.1); check("back in place while EllesmereUI's unlock mode is open", select(1, uiOffset())==0 and select(1, uiInset())==0)
EllesmereUI._unlockModeSessionActive = false; repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
-- EllesmereUI places an anchored element (its cast bar under the player frame) counting from the screen corner
local placed, listeners = {}, {}
EllesmereUI.SetFramePoint = function(f, p, rel, rp, x, y) placed[f] = { p, rel, rp, x, y } end
function EllesmereUI:RegisterUnlockModeListener(owner, fn) listeners[owner] = fn end
local castbar, freeBar, playerFrame = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame")
function castbar:GetEffectiveScale() return 0.5 end
EllesmereUI._unlockRegisteredElements = { playerCastbar = { getFrame = function() return castbar end },
  freeBar = { getFrame = function() return freeBar end } }
EllesmereUIDB = { unlockAnchors = { playerCastbar = { target = "player", side = "BOTTOM" } } }
repeat HUDFade.ShiftNow() until select(1, uiOffset())==1 and select(2, uiOffset())==1
EllesmereUI.SetFramePoint(castbar, "CENTER", UIParent, "CENTER", 100, -50)
EllesmereUI.SetFramePoint(freeBar, "CENTER", UIParent, "CENTER", 100, -50)
check("an anchored EllesmereUI element doesn't get the shift twice", placed[castbar][4]==96 and placed[castbar][5]==-54)
check("other EllesmereUI placements are left as asked", placed[freeBar][4]==100 and placed[freeBar][5]==-50)
EllesmereUI.SetFramePoint(castbar, "TOP", playerFrame, "BOTTOM", 3, 4)
check("an element hung off another frame is left as asked", placed[castbar][4]==3 and placed[castbar][5]==4)
EllesmereUI._unlockModeSessionActive = true; if listeners.HUDFade then listeners.HUDFade(true) end
check("EllesmereUI's unlock mode gets the interface back the moment it opens", select(1, uiOffset())==0 and select(1, uiInset())==0)
EllesmereUI.SetFramePoint(castbar, "CENTER", UIParent, "CENTER", 100, -50)
check("nothing taken out while the interface is in its place", placed[castbar][4]==100 and placed[castbar][5]==-50)
EllesmereUI._unlockModeSessionActive = false; repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
SlashCmdList.HUDFADE("off")
check("addon off puts the interface back", select(1, uiOffset())==0 and select(2, uiOffset())==0)
SlashCmdList.HUDFADE("on"); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
-- Another addon keeps putting it back: step aside
for i=1,3 do UIParent.points = { {"TOPLEFT", nil, "TOPLEFT", 0, 0}, {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0} }; HUDFade.ShiftNow() end
UIParent.points = { {"TOPLEFT", nil, "TOPLEFT", 0, 0}, {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0} }; step(1.1)
check("gives up after another addon fights it 3 times", select(1, uiOffset())==0 and HUDFade.ShiftStatus():find("stopped", 1, true))
SlashCmdList.HUDFADE("shift on"); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
check("/hudfade shift on tries again", select(1, uiOffset())~=0)
-- Arranging frames counts as an open window: only the away time hides the HUD then
step(7); check("idle-hidden before arranging frames", UIParent.alpha==0)
EllesmereUI._unlockModeSessionActive = true; step(0.5)
check("EllesmereUI's unlock mode brings the HUD back like a window", UIParent.alpha==1)
step(30); check("and keeps it visible while you arrange frames", UIParent.alpha==1)
check("/hudfade why names unlock mode", table.concat(HUDFade.Explain(), " "):find("EllesmereUI unlock mode", 1, true) ~= nil)
HUDFadeDB.awayMinutes=2; step(91); check("until the away time", UIParent.alpha==0)
EllesmereUI._unlockModeSessionActive = false; HUDFadeDB.awayMinutes=10
HUDFade.Hide(); cx=cx+40; step(3)
fire("PLAYER_LOGOUT")
check("logout puts the interface back exactly", #UIParent.points==2 and UIParent.points[1][4]==0 and UIParent.points[1][5]==0 and UIParent.points[2][4]==0 and UIParent.points[2][5]==0)
step(1.1); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
SlashCmdList.HUDFADE("shift off")
check("turning it off puts the interface back exactly", #UIParent.points==2 and UIParent.points[1][4]==0 and UIParent.points[1][5]==0 and UIParent.points[2][4]==0)
fire("PLAYER_LOGOUT")
check("logout restores cvars", cvars.UnitNameNPC=="1" and cvars.nameplateShowEnemies=="1" and next(HUDFadeDB.restore)==nil)
SlashCmdList.HUDFADE("reset")
-- Presets
check("defaults are the Everything preset", HUDFade.CurrentPreset()==1 and HUDFade.PRESETS[1].name=="Everything")
HUDFade.ApplyPreset(2)
check("Like the game's Hide UI: names and glow stay, nameplates and minimap go", HUDFadeDB.hideNames==false and HUDFadeDB.hideOutline==false and HUDFadeDB.hideNameplates==true and HUDFadeDB.hideMinimap==true and HUDFade.CurrentPreset()==2)
HUDFade.Show(); step(0.5); HUDFade.Hide(); step(2)
check("with it, hiding leaves names and the glow but takes nameplates", UIParent.alpha==0 and cvars.UnitNameNPC=="1" and cvars.Outline=="2" and cvars.nameplateShowEnemies=="0")
HUDFade.Show(); step(0.5)
HUDFadeDB.hideNameplates=false
check("changing a box by hand makes it Custom", HUDFade.CurrentPreset()==nil)
SlashCmdList.HUDFADE("reset")
check("reset is the Everything preset again", HUDFade.CurrentPreset()==1)
-- The settings pages build (font strings and templates are stubs here)
local function stub() return setmetatable({}, {__index=function() return function() end end}) end
for _,f in ipairs(frames) do rawset(f, "CreateFontString", stub) end
local realCreate = CreateFrame
local templates = {}
local presetMenu
CreateFrame = function(kind, name, parent, template)
  if template then templates[#templates+1] = template end
  if template == "ScrollFrameTemplate" then error("no such template") end -- (the fallback must cope)
  local f = realCreate(kind, name, parent); rawset(f, "CreateFontString", stub)
  if template == "WowStyle1DropdownTemplate" then presetMenu = f; rawset(f, "SetupMenu", function(self, gen) self.gen = gen end) end
  return f
end
local pages = {}
for _,f in ipairs(frames) do if f.scripts.OnShow then pages[#pages+1]=f end end
local ok, err = pcall(function() for _,f in ipairs(pages) do f.scripts.OnShow(f) end end)
check("settings pages build without errors ("..tostring(err)..")", ok and #pages==2)
check("the main page scrolls (falls back to the older scroll template)", table.concat(templates, " "):find("UIPanelScrollFrameTemplate") ~= nil)
local radios = {}
if presetMenu and presetMenu.gen then
  presetMenu.gen(presetMenu, { CreateRadio=function(_, text, isSel, setSel) radios[#radios+1]={ text=text, isSel=isSel, setSel=setSel } end })
end
check("the preset menu lists both presets", #radios==2 and radios[1].text=="Everything" and radios[1].isSel()==true)
if #radios==2 then radios[2].setSel() end
check("choosing one in the menu applies it", HUDFade.CurrentPreset()==2 and HUDFadeDB.hideNames==false and radios[2].isSel()==true)
SlashCmdList.HUDFADE("reset")
CreateFrame = realCreate
-- The away slider stops at 2, 5, 10, 15, 20, 30, 45 and 60 minutes
local sliders = {}
for _,f in ipairs(frames) do if f.scripts.OnValueChanged then sliders[#sliders+1]=f end end
for _,f in ipairs(sliders) do f.scripts.OnValueChanged(f, 8) end
local top = HUDFadeDB.awayMinutes
for _,f in ipairs(sliders) do f.scripts.OnValueChanged(f, 3) end
check("the away slider goes up to an hour in bigger steps", top==60 and HUDFadeDB.awayMinutes==10)
os.exit(failed and 1 or 0)
