-- Runs OLED HUD against a tiny fake WoW API: lua5.1 tests/mock.lua .
-- Minimal WoW API mock to run OLED HUD's logic outside the game.
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
Minimap = newFrame(); Minimap.parent = UIParent
function hooksecurefunc(t, name, fn) local orig=t[name]; rawset(t, name, function(...) local r=orig(...); fn(...); return r end) end
function CreateFrame(kind, name, parent) local f=newFrame(kind); f.parent=parent; if name then _G[name]=f end; return f end
local model = newFrame("PlayerModel"); model.parent = UIParent; model.malpha=1
function model:SetModelAlpha(a) self.malpha=a end
function model:GetModelAlpha() return self.malpha end
function EnumerateFrames(f) if not f then return frames[1] end for i,x in ipairs(frames) do if x==f then return frames[i+1] end end end
C_Timer = { After=function(d,fn) table.insert(timers,{T+d,fn}) end, NewTicker=function(d,fn) ticker=fn end }
timers = {}
function GetBindingKey(c) if c=="TOGGLEUI" then return "ALT-Z" end end
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
function UnitIsDead() return false end
mouselook=false; facingV=1.0
function MouselookStart() mouselook=true end
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
local function load(file) local fn=assert(loadfile(file)); fn("OLEDHUD", ns) end
ns = {}
load(arg[1].."/Core.lua"); load(arg[1].."/Options.lua")
fire("ADDON_LOADED","OLEDHUD"); fire("PLAYER_LOGIN")
local function check(label, cond) print((cond and "PASS " or "FAIL ")..label) ; if not cond then failed=true end end
step(1)
check("starts visible", UIParent.alpha==1)
check("Alt+Z overridden", binds["ALT-Z"]=="OLEDHUD_TOGGLE")
OLEDHUD.Toggle(); step(1.5)
check("toggle hides", UIParent.alpha==0)
check("NPC names off", cvars.UnitNameNPC=="0" and OLEDHUDDB.restore.UnitNameNPC=="1")
check("own name untouched (was 0)", cvars.UnitNameOwn=="0" and OLEDHUDDB.restore.UnitNameOwn==nil)
check("plates off", cvars.nameplateShowEnemies=="0")
check("model faded", model.malpha==0)
check("minimap hidden", Minimap.shown==false)
Minimap:Show(); check("minimap stays hidden if another addon shows it", Minimap.shown==false)
check("friendly player plates off", cvars.nameplateShowFriendlyPlayers=="0")
target=true; fire("PLAYER_TARGET_CHANGED"); step(0.5)
check("target shows", UIParent.alpha==1 and cvars.UnitNameNPC=="1")
check("model back", model.malpha==1)
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
OLEDHUD.Toggle(); step(1.5)
check("hide with target suppresses target", UIParent.alpha==0)
OLEDHUD.Toggle(); step(0.5)
check("toggle shows", UIParent.alpha==1)
target=false; fire("PLAYER_TARGET_CHANGED")
step(30.3)
check("idle starts hiding right at 30 s (no extra delay)", OLEDHUD.state.target==0)
step(1.2)
check("idle hides", UIParent.alpha==0)
cx=50; step(0.5)
check("mouse wakes", UIParent.alpha==1)
OLEDHUD.Peek(true); check("peek instant", UIParent.alpha==1)
OLEDHUD.CleanScreenshot(); check("shot hides instantly", UIParent.alpha==0 and cvars.UnitNameNPC=="0")
step(0.3); check("screenshot taken", shots==1)
fire("SCREENSHOT_SUCCEEDED"); step(0.5)
check("back after shot", UIParent.alpha==1)
OLEDHUD.Peek(false)
OLEDHUDDB.hideCursor = true
OLEDHUD.Hide(); step(4)
check("pointer hidden when still", mouselook==true)
step(1); check("idle timer not reset by our own mouselook", OLEDHUD.state.lastInput < GetTime() - 0.9)
step(1); facingV=1.0004; step(0.2); check("tiny drift does not count as a move", mouselook==true)
facingV=1.2; step(0.2)
check("pointer back when the mouse moves", mouselook==false)
step(3); check("hidden again after 2 s still", mouselook==true)
fire("PLAYER_REGEN_DISABLED"); step(0.2)
check("pointer back in combat", mouselook==false)
fire("PLAYER_REGEN_ENABLED")
step(5); check("hidden again out of combat", mouselook==true)
fire("PLAYER_STARTED_MOVING"); check("pointer back when moving", mouselook==false)
step(3); check("stays while moving", mouselook==false)
fire("PLAYER_STOPPED_MOVING");OLEDHUD.Hide(); step(2)
check("hidden before turning off", UIParent.alpha==0)
SlashCmdList.OLEDHUD("off")
check("off shows everything at once", UIParent.alpha==1 and cvars.UnitNameNPC=="1" and Minimap.shown==true and mouselook==false)
check("off gives the Hide UI key back", binds["ALT-Z"]==nil)
OLEDHUD.Toggle(); step(2); check("toggle does nothing while off", UIParent.alpha==1)
step(70); check("no idle hiding while off", UIParent.alpha==1)
SlashCmdList.OLEDHUD("on")
check("on takes the key again", binds["ALT-Z"]=="OLEDHUD_TOGGLE")
OLEDHUD.Toggle(); step(2); check("toggle works again", UIParent.alpha==0)
-- Idle and what counts as activity
OLEDHUD.Toggle(); step(0.5); check("shown for the idle tests", UIParent.alpha==1)
OLEDHUDDB.idleSeconds = 5; OLEDHUDDB.hideCursor = false
local keyFrame; for _,f in ipairs(frames) do if f.scripts.OnKeyDown then keyFrame=f end end
keyFrame.scripts.OnKeyDown(keyFrame, "W"); fire("PLAYER_STARTED_MOVING"); step(8)
check("holding W keeps the HUD up", UIParent.alpha==1)
keyFrame.scripts.OnKeyUp(keyFrame, "W"); step(7)
check("auto-run (moving, no key held) goes idle", UIParent.alpha==0)
fire("PLAYER_STOPPED_MOVING")
cx=cx+40; step(0.5); check("pointer move wakes", UIParent.alpha==1)
buttons.LeftButton=true; step(7)
check("turning the camera does not keep the HUD up", UIParent.alpha==0)
buttons.LeftButton=nil
OLEDHUDDB.activeCamera=true; cx=cx+40; step(0.5); buttons.LeftButton=true; step(7)
check("unless that option is on", UIParent.alpha==1)
buttons.LeftButton=nil; OLEDHUDDB.activeCamera=false
fire("PLAYER_LOGOUT")
check("logout restores cvars", cvars.UnitNameNPC=="1" and cvars.nameplateShowEnemies=="1" and next(OLEDHUDDB.restore)==nil)
SlashCmdList.OLEDHUD("why")
SlashCmdList.OLEDHUD("reset")
os.exit(failed and 1 or 0)
