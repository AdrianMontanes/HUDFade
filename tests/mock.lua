-- Runs HUD Fade against a tiny fake WoW API: lua5.1 tests/mock.lua .
-- Minimal WoW API mock to run HUD Fade's logic outside the game.
local T = 0
function GetTime() return T end
local cvars = { UnitNameNPC="1", UnitNameOwn="0", nameplateShowEnemies="1", nameplateShowFriends="1", nameplateShowFriendlyPlayers="1" }
C_CVar = { GetCVar=function(n) return cvars[n] end, SetCVar=function(n,v) if lockdown and n:find("nameplate") then error("blocked") end cvars[n]=v end }
lockdown=false
function InCombatLockdown() return lockdown end
local frames = {}
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
  setmetatable(f, {__index=function(t,k) return function() end end})
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
local function uiOffset() local a = UIParent.points[1]; return a and a[4] or 0, a and a[5] or 0 end
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
flying=false
function IsFlying() return flying end
onTaxi=false
function UnitOnTaxi() return onTaxi end
swimming=false
function IsSwimming() return swimming end
function EnumerateFrames(f) if not f then return frames[1] end for i,x in ipairs(frames) do if x==f then return frames[i+1] end end end
C_Timer = { After=function(d,fn) table.insert(timers,{T+d,fn}) end, NewTicker=function(d,fn) ticker=fn end }
timers = {}
function GetBindingKey(c) if c=="TOGGLEUI" then return "ALT-Z" end if c=="TOGGLEAUTORUN" then return "NUMLOCK" end end
function GetBindingAction(k) local m={W="MOVEFORWARD", D="TURNRIGHT", NUMLOCK="TOGGLEAUTORUN", TAB="TARGETNEARESTENEMY"}; return m[k] or "" end
binds = {}
function SetOverrideBinding(o,p,k,c) binds[k]=c end
function ClearOverrideBindings() binds={} end
function GetCurrentKeyBoardFocus() return nil end
function GetCursorInfo() return nil end
local cx=0
function GetCursorPosition() return cx, 0 end
buttons={}
function IsMouseButtonDown(b) return buttons[b] or false end
local target=false
function UnitExists(u) return target end
dead=false
function UnitIsDead() return dead end
mouselook=false; facingV=1.0
function MouselookStart() mouselook=true end
mlBinds = {}
function SetMouselookOverrideBinding(k, b) if lockdown then error("blocked") end mlBinds[k]=b end
-- A left press: while mouselooking with the override set, the game runs that binding instead (a CLICK on our button).
function pressLeft()
  buttons.LeftButton=true
  if mouselook and mlBinds.BUTTON1 then local b=_G.HUDFadeWakeButton; b.scripts.OnClick(b, "LeftButton", true) end
end
function MouselookStop() mouselook=false end
function IsMouselooking() return mouselook end
function GetPlayerFacing() return facingV end
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
fire("ADDON_LOADED","HUDFade"); fire("PLAYER_LOGIN")
local function check(label, cond) print((cond and "PASS " or "FAIL ")..label) ; if not cond then failed=true end end
step(1)
check("starts visible", UIParent.alpha==1)
check("Alt+Z overridden", binds["ALT-Z"]=="HUDFADE_TOGGLE")
HUDFade.Toggle(); step(1.5)
check("toggle hides", UIParent.alpha==0)
check("NPC names off", cvars.UnitNameNPC=="0" and HUDFadeDB.restore.UnitNameNPC=="1")
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
check("model back", model.malpha==1)
check("that frame back", lone.alpha==1)
check("minimap back", Minimap.shown==true)
target=false; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("short grace after the target clears", UIParent.alpha==1)
step(2)
check("hides after the grace", UIParent.alpha==0)
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
HUDFadeDB.hideCursor = true
HUDFade.Hide(); step(4)
check("pointer hidden when still", mouselook==true)
step(1); check("idle timer not reset by our own mouselook", HUDFade.state.lastInput < GetTime() - 0.9)
step(1); facingV=1.0004; step(0.2); check("tiny drift does not count as a move", mouselook==true)
facingV=1.2; step(0.2)
check("pointer back when the mouse moves", mouselook==false)
step(3); check("hidden again after 2 s still", mouselook==true)
fire("PLAYER_REGEN_DISABLED"); step(0.2)
check("pointer back in combat", mouselook==false)
fire("PLAYER_REGEN_ENABLED")
step(5); check("hidden again out of combat", mouselook==true)
local keyFrame; for _,f in ipairs(frames) do if f.scripts.OnKeyDown then keyFrame=f end end
fire("PLAYER_STARTED_MOVING"); step(3); check("auto-run keeps the pointer hidden", mouselook==true)
keyFrame.scripts.OnKeyDown(keyFrame, "D"); check("a turn key gives the pointer back before the game sees it", mouselook==false)
step(3); check("not hidden while turning with keys", mouselook==false)
keyFrame.scripts.OnKeyUp(keyFrame, "D"); step(0.2); check("hidden again after turning", mouselook==true)
flying=true; step(0.2); check("pointer back while flying (the camera sets your pitch)", mouselook==false)
flying=false; step(0.2); check("hidden again after landing", mouselook==true)
fire("PLAYER_STOPPED_MOVING");HUDFade.Hide(); step(2)
check("hidden before turning off", UIParent.alpha==0)
SlashCmdList.HUDFADE("off")
check("off shows everything at once", UIParent.alpha==1 and cvars.UnitNameNPC=="1" and Minimap.shown==true and mouselook==false)
check("off gives the Hide UI key back", binds["ALT-Z"]==nil)
HUDFade.Toggle(); step(2); check("toggle does nothing while off", UIParent.alpha==1)
step(70); check("no idle hiding while off", UIParent.alpha==1)
SlashCmdList.HUDFADE("on")
check("on takes the key again", binds["ALT-Z"]=="HUDFADE_TOGGLE")
HUDFade.Toggle(); step(2); check("toggle works again", UIParent.alpha==0)
-- Dragging while the pointer is hidden
HUDFade.Toggle(); step(0.5); HUDFadeDB.hideCursor = true; HUDFade.Hide(); step(4)
check("pointer hidden before the drag", mouselook==true)
pressLeft(); step(0.1)
check("left drag hands over to the game's camera drag", mouselook==false)
step(1); check("no re-hide while a button is held", mouselook==false)
buttons.LeftButton=nil; step(3)
check("after a left-drag the pointer stays (hiding would turn you to the camera)", mouselook==false)
buttons.RightButton=true; step(0.1); buttons.RightButton=nil; step(0.2)
check("a right-drag lines camera and character up: pointer hides again", mouselook==true)
buttons.RightButton=true; step(0.1)
check("right drag keeps the game's steering", mouselook==true)
buttons.RightButton=nil; mouselook=false; step(0.2)
check("pointer hides again right after a right drag", mouselook==true)
pressLeft(); step(0.3); buttons.LeftButton=nil; step(0.2)
fire("PLAYER_STARTED_MOVING"); step(1); check("after a drag, still visible at the start of a run", mouselook==false)
step(1.5); check("moving with the camera following lines them up: hidden", mouselook==true)
fire("PLAYER_STOPPED_MOVING")
fire("PLAYER_REGEN_DISABLED"); check("pointer back as combat starts", mouselook==false)
fire("PLAYER_REGEN_ENABLED"); step(0.3)
-- Flight paths: the route turns you, so only a click or a key brings the pointer back
buttons.RightButton=nil; MouselookStop(); cx=cx+40; step(0.2); onTaxi=true; flying=true; step(2.5)
check("pointer hides on a flight path (even though it counts as flying)", mouselook==true)
for i=1,20 do facingV=facingV+0.05; step(0.1) end
check("the route turning you does not bring it back", mouselook==true)
keyFrame.scripts.OnKeyDown(keyFrame, "TAB"); check("any key brings it back on a flight path", mouselook==false)
step(2.5); check("hidden again when still", mouselook==true)
pressLeft(); step(0.1); check("a click brings it back", mouselook==false)
buttons.LeftButton=nil; buttons.RightButton=true; step(0.1); buttons.RightButton=nil; step(2.5)
check("hidden again before landing", mouselook==true)
onTaxi=false; flying=false; step(0.1)
check("landing hands the mouse back", mouselook==false)
step(3); check("and waits for camera and character to line up", mouselook==false)
buttons.RightButton=true; step(0.1); buttons.RightButton=nil; mouselook=false; step(0.2)
check("lined up by a right-drag: hides again", mouselook==true)
-- Flying, swimming and vehicles: only if asked, and then the mouse steers
flying=true; step(0.2); check("not hidden while flying unless asked", mouselook==false)
check("why names the setting", HUDFade.PointerWhy():find("Even when flying") ~= nil)
HUDFadeDB.hideCursorSteer=true; step(0.2); check("even when flying: hidden", mouselook==true)
for i=1,20 do facingV=facingV+0.05; step(0.1) end
check("steering with the mouse keeps it hidden, and the HUD too", mouselook==true and UIParent.alpha==0)
keyFrame.scripts.OnKeyDown(keyFrame, "TAB"); check("any key brings it back while flying", mouselook==false)
step(2.5); check("hidden again when still", mouselook==true)
flying=false; step(0.2); check("still hidden after landing", mouselook==true)
step(0.5); facingV=facingV+0.2; step(0.2); check("on the ground a mouse move brings it back again", mouselook==false)
swimming=true; step(2.5); check("hidden while swimming too", mouselook==true)
facingV=facingV+0.2; step(0.2); check("steering while swimming keeps it hidden", mouselook==true)
HUDFadeDB.activeCamera=true; facingV=facingV+0.2; step(0.2)
check("steering counts as activity when turning the camera does", HUDFade.state.lastInput >= GetTime() - 0.25)
HUDFadeDB.activeCamera=false; swimming=false; HUDFadeDB.hideCursorSteer=false; step(0.2)
-- After a left-drag the pointer still goes once the mouse has been still for the idle time
step(0.5); check("hidden before the left-drag", mouselook==true)
pressLeft(); step(0.3); buttons.LeftButton=nil; step(3)
check("left-drag: the pointer stays for now", mouselook==false)
step(28); check("and hides after the idle time without moving the mouse", mouselook==true)
-- A right-drag hands it straight back, even if the game parked the pointer somewhere else meanwhile
buttons.RightButton=true; step(0.2); cx=cx+300; step(0.5)
buttons.RightButton=nil; mouselook=false; cx=cx-300
for _,f in ipairs(frames) do if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.01) end end
check("right-drag release: hidden again the same frame", mouselook==true)
step(0.5); check("and the HUD stays hidden", mouselook==true and UIParent.alpha==0)
-- Hiding over an open window takes the pointer too
cx=cx+40; HUDFade.Show(); step(0.5)
local map = CreateFrame("Frame", "WorldMapFrame"); step(0.5)
check("an open window keeps the HUD up", UIParent.alpha==1 and mouselook==false)
HUDFade.Hide(); step(3)
check("hide over an open window hides the pointer too", UIParent.alpha==0 and mouselook==true)
facingV=facingV+0.2; step(0.2); check("pointer back on the first move over the window", mouselook==false)
step(3); check("and hides again when still", mouselook==true)
map:Hide(); step(0.5)
-- Something else ends our mouselook (alt-tab): no retry until the mouse really moves
MouselookStop(); step(4); check("no retry after the game ends it (safe while alt-tabbed)", mouselook==false)
cx=cx+40; step(3); check("retries after a real mouse move", mouselook==true)
-- A stuck non-movement key must not keep you "active" (Tab used to)
-- Idle and what counts as activity
HUDFade.Toggle(); step(0.5); check("shown for the idle tests", UIParent.alpha==1)
HUDFadeDB.idleSeconds = 5; HUDFadeDB.hideCursor = false
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
check("why lists it", table.concat(HUDFade.Explain(), "\n"):find("You died") ~= nil)
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
HUDFadeDB.hideCursor=true; buttons.RightButton=true; step(0.1); buttons.RightButton=nil; mouselook=false; step(5); w = why()
check("why: hidden by idle", w:find("HUD hidden due to: Idle for", 1, true))
check("why: pointer line", w:find("Pointer: hidden", 1, true))
HUDFadeDB.hideCursor=false
HUDFadeDB.showTarget=true; target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5); w = why()
check("why: several causes on their own lines", w:find("HUD visible due to:\n   - You have a target\n   - Not enough time idling", 1, true))
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
-- Pixel shift
check("pixel shift off by default", select(1, uiOffset())==0 and select(2, uiOffset())==0)
SlashCmdList.HUDFADE("shift on"); step(1.1)
local visited, nonzero = {}, false
for i=1,9 do HUDFade.ShiftNow(); local x,y = uiOffset(); visited[x..","..y]=true; if x~=0 or y~=0 then nonzero=true end end
local n=0; for _ in pairs(visited) do n=n+1 end
check("shift walks the 9 spots of the circle", n==9 and nonzero and visited["2,0"] and visited["-2,-2"])
check("both anchors move together", UIParent.points[1][4]==UIParent.points[2][4] and #UIParent.points==2)
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
SlashCmdList.HUDFADE("off")
check("addon off puts the interface back", select(1, uiOffset())==0 and select(2, uiOffset())==0)
SlashCmdList.HUDFADE("on"); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
-- Another addon keeps putting it back: step aside
for i=1,3 do UIParent.points = { {"TOPLEFT", nil, "TOPLEFT", 0, 0}, {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0} }; HUDFade.ShiftNow() end
UIParent.points = { {"TOPLEFT", nil, "TOPLEFT", 0, 0}, {"BOTTOMRIGHT", nil, "BOTTOMRIGHT", 0, 0} }; step(1.1)
check("gives up after another addon fights it 3 times", select(1, uiOffset())==0 and HUDFade.ShiftStatus():find("stopped", 1, true))
SlashCmdList.HUDFADE("shift on"); repeat HUDFade.ShiftNow() until select(1, uiOffset())~=0
check("/hudfade shift on tries again", select(1, uiOffset())~=0)
SlashCmdList.HUDFADE("shift off")
check("turning it off puts the interface back exactly", #UIParent.points==2 and UIParent.points[1][4]==0 and UIParent.points[1][5]==0 and UIParent.points[2][4]==0)
fire("PLAYER_LOGOUT")
check("logout restores cvars", cvars.UnitNameNPC=="1" and cvars.nameplateShowEnemies=="1" and next(HUDFadeDB.restore)==nil)
SlashCmdList.HUDFADE("reset")
-- The settings pages build (font strings and templates are stubs here)
local function stub() return setmetatable({}, {__index=function() return function() end end}) end
for _,f in ipairs(frames) do rawset(f, "CreateFontString", stub) end
local realCreate = CreateFrame
local templates = {}
CreateFrame = function(kind, name, parent, template)
  if template then templates[#templates+1] = template end
  if template == "ScrollFrameTemplate" then error("no such template") end -- (the fallback must cope)
  local f = realCreate(kind, name, parent); rawset(f, "CreateFontString", stub); return f
end
local pages = {}
for _,f in ipairs(frames) do if f.scripts.OnShow then pages[#pages+1]=f end end
local ok, err = pcall(function() for _,f in ipairs(pages) do f.scripts.OnShow(f) end end)
check("settings pages build without errors ("..tostring(err)..")", ok and #pages==2)
check("the main page scrolls (falls back to the older scroll template)", table.concat(templates, " "):find("UIPanelScrollFrameTemplate") ~= nil)
CreateFrame = realCreate
os.exit(failed and 1 or 0)
