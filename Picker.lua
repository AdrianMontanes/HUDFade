-- HUD Fade frame picker: the Elements page's "Select an element" button. A box outlines the part of the UI under the
-- mouse with its name, and a click adds it to the Elements page.
--
-- The settings window stays open but invisible meanwhile: the game can't be made to reopen it on the Elements page.

local _, ns = ...
local HUDFade = ns.core
local core = ns.internal
local Elements = ns.elements
local say = HUDFade.Print

local RESCAN = 2   -- seconds between looking for frames again, for ones that appear while picking
local HUGE = 0.4   -- a frame covering more of the screen than this holds the UI rather than being a part of it
local STRATA = {
	BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local picker = CreateFrame("Frame", "HUDFadeFramePicker", UIParent)
picker:Hide()
picker:SetAllPoints(UIParent)
picker:SetFrameStrata("FULLSCREEN_DIALOG")
picker:EnableMouse(true)
picker:EnableMouseWheel(true)
picker:EnableKeyboard(true) -- for Escape, which must not reach the settings window and close it

local outline = CreateFrame("Frame", nil, picker)
outline:Hide()
local fill = outline:CreateTexture(nil, "BACKGROUND")
fill:SetAllPoints()
fill:SetColorTexture(0.5, 0.83, 1, 0.2)
local EDGES = {
	{ "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 },
	{ "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 },
}
for _, e in ipairs(EDGES) do
	local t = outline:CreateTexture(nil, "BORDER")
	t:SetColorTexture(0.5, 0.83, 1, 0.9)
	t:SetPoint(e[1])
	t:SetPoint(e[2])
	if e[3] > 0 then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
end

local named = {}           -- frame -> its global name, for every named frame on screen
local scannedAt = -100
local chain, index = {}, 0 -- the parts the one under the mouse belongs to, smallest first, and the one chosen
local top                  -- the frame right under the mouse
local picked               -- the name of the frame clicked
local done                 -- told what happened once picking ends
local quiet = false        -- picking ended by a fight
local away = {}            -- settings windows made invisible -> their own opacity

local function ours(f)
	return f == picker or f == outline or f == UIParent or f == GameTooltip
end

-- Whether a frame is part of a settings window made invisible.
local function inAway(f)
	if not next(away) then return false end
	for _ = 1, 50 do
		if type(f) ~= "table" then return false end
		if away[f] then return true end
		f = core.ask(f, "GetParent")
	end
	return false
end

-- Whether _G[k] is a frame by that name. The game's frames carry their userdata at [0]: anything else isn't one.
local function isFrame(k, v)
	return type(k) == "string" and type(v) == "table" and type(rawget(v, 0)) == "userdata" and not ours(v)
		and type(v.GetChildren) == "function" and type(v.SetIgnoreParentAlpha) == "function"
		and core.ask(v, "GetName") == k
end

local function scan()
	wipe(named)
	for k, v in pairs(_G) do
		if isFrame(k, v) and core.ask(v, "IsVisible") == true then named[v] = k end
	end
	scannedAt = core.now()
end

-- The names of every frame, shown or not, in order: the Elements page suggests them as a name is typed.
function HUDFade.FrameNames()
	local out = {}
	for k, v in pairs(_G) do
		if isFrame(k, v) then out[#out + 1] = k end
	end
	table.sort(out)
	return out
end

-- Its size on screen, or nil if the game won't say.
local function area(f)
	local w, h, s = core.ask(f, "GetWidth"), core.ask(f, "GetHeight"), core.ask(f, "GetEffectiveScale")
	if type(w) ~= "number" or type(h) ~= "number" or type(s) ~= "number" then return nil end
	return w * h * s * s
end

local function huge(f)
	local a, screen = area(f), area(UIParent)
	return a ~= nil and screen ~= nil and a > screen * HUGE
end

-- The named frame drawn on top under the mouse: the highest strata and level, then the smallest.
local function underMouse()
	local best, bs, bl, ba
	for f in pairs(named) do
		if core.ask(f, "IsMouseOver") == true and core.ask(f, "IsVisible") == true and not huge(f)
			and Elements.InHUD(f) and not inAway(f) then
			local s = STRATA[core.ask(f, "GetFrameStrata")] or 0
			local l = core.ask(f, "GetFrameLevel") or 0
			local a = area(f) or math.huge
			if not best or s > bs or s == bs and (l > bl or l == bl and a < ba) then best, bs, bl, ba = f, s, l, a end
		end
	end
	return best
end

-- The frame and the named frames around it that could be added instead, smallest first.
local function chainOf(f)
	local out = {}
	for _ = 1, 50 do
		if type(f) ~= "table" or f == UIParent then break end
		local name = core.ask(f, "GetName")
		if type(name) == "string" and _G[name] == f and not huge(f) then out[#out + 1] = f end
		f = core.ask(f, "GetParent")
	end
	return out
end

local function chosen()
	local f = chain[index]
	return f, f and core.ask(f, "GetName")
end

local function show()
	local f, name = chosen()
	outline:ClearAllPoints()
	if f and pcall(outline.SetAllPoints, outline, f) then outline:Show() else outline:Hide() end
	GameTooltip:SetOwner(picker, "ANCHOR_CURSOR")
	if f then
		GameTooltip:SetText(name, 1, 1, 1)
		local why = Elements.Refusal(name, f)
		if why then
			GameTooltip:AddLine(why, 1, 0.5, 0.25, true)
		else
			GameTooltip:AddLine("Left-click: add it to the Elements page", 0.5, 1, 0.5)
		end
		if #chain > 1 then
			GameTooltip:AddLine(string.format("Mouse wheel: a bigger or smaller part (%d of %d)", index, #chain))
		end
	else
		GameTooltip:SetText("Move your mouse over a part of your UI", 1, 1, 1)
		GameTooltip:AddLine("Only parts with a name can be added.", nil, nil, nil, true)
	end
	GameTooltip:AddLine("Right-click or Escape: cancel", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local wait, lastX, lastY = 0, nil, nil
picker:SetScript("OnUpdate", function(_, elapsed)
	wait = wait - elapsed
	if wait > 0 then return end
	wait = 0.1
	local again = false
	if core.now() - scannedAt > RESCAN then
		scan()
		again = true
	end
	local x, y = GetCursorPosition()
	if x == lastX and y == lastY and not again then return end
	lastX, lastY = x, y
	local f = underMouse()
	if f ~= top then
		top = f
		chain = f and chainOf(f) or {}
		index = #chain -- the biggest part to begin with: a whole bar or window rather than one button in it
	end
	show()
end)

picker:SetScript("OnMouseWheel", function(_, delta)
	if #chain == 0 then return end
	index = math.max(1, math.min(#chain, index + (delta > 0 and 1 or -1)))
	show()
end)

picker:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" then
		self:Hide()
	elseif button == "LeftButton" then
		local f, name = chosen()
		if not f or Elements.Refusal(name, f) then return end -- the tooltip says why
		picked = name
		self:Hide()
	end
end)

picker:SetScript("OnKeyDown", function(self, key)
	pcall(self.SetPropagateKeyboardInput, self, key ~= "ESCAPE")
	if key == "ESCAPE" then self:Hide() end
end)

picker:SetScript("OnHide", function(self)
	self:Hide() -- hidden with the whole UI by another addon, it must not come back on its own after
	if core.ask(GameTooltip, "GetOwner") == picker then GameTooltip:Hide() end
	outline:Hide()
	wipe(named)
	chain, index, top = {}, 0, nil
	local back = next(away) ~= nil
	for f, a in pairs(away) do pcall(f.SetAlpha, f, a) end
	wipe(away)
	local name, tell, inFight = picked, done, quiet
	picked, done, quiet = nil, nil, false
	local msg
	if name then
		local _, m = Elements.AddFrame(name)
		msg = m
	elseif inFight then
		msg = "stopped selecting an element: you are in combat."
	else
		msg = "nothing added."
	end
	say(msg)
	if tell then tell(msg) end
	if HUDFade.RefreshOptions then HUDFade.RefreshOptions() end
	if not back and not inFight then HUDFade.OpenOptions("elements") end
end)

picker:RegisterEvent("PLAYER_REGEN_DISABLED")
picker:SetScript("OnEvent", function(self)
	if self:IsShown() then
		quiet = true
		self:Hide()
	end
end)

-- The overlay takes every click, so the invisible window can't be clicked by mistake.
local function settingsAway()
	for _, name in ipairs({ "SettingsPanel", "InterfaceOptionsFrame" }) do
		local f = _G[name]
		local a = f and core.ask(f, "IsShown") and core.ask(f, "GetAlpha")
		if type(a) == "number" and pcall(f.SetAlpha, f, 0) then away[f] = a end
	end
end

-- tell(msg): what happened, once picking ends.
function HUDFade.PickFrame(tell)
	if InCombatLockdown() then
		local msg = "leave combat first, then select an element."
		say(msg)
		if tell then tell(msg) end
		return
	end
	done = tell
	settingsAway()
	scan()
	chain, index, top = {}, 0, nil
	wait, lastX, lastY = 0, nil, nil
	picker:Show()
end
