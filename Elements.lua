-- HUD Fade elements: parts of the HUD that stay visible, come back under the mouse, or come back in a fight
-- while the rest of the HUD is hidden.
--
-- The HUD still fades as one layer (UIParent). An element is lifted out of that layer with SetIgnoreParentAlpha,
-- so it is drawn with its own opacity alone. UI addons like EllesmereUI keep setting that opacity for their own
-- fades, so nothing fights them. Its opacity is only written while it fades in or out.

local _, ns = ...
local HUDFade = ns.core
local core = ns.internal -- helpers shared by Core.lua

local Elements = {}
ns.elements = Elements
HUDFade.Elements = Elements

local LINGER = 1         -- seconds an element stays after the mouse leaves it
local RESOLVE_EVERY = 5  -- seconds between looking up the frames again while the HUD is hidden

local function db() return HUDFade.db end

local function numbered(list, prefix, first, last, suffix)
	for i = first, last do list[#list + 1] = prefix .. i .. (suffix or "") end
	return list
end

-- Frames of the game, ElvUI, Bartender4 and Dominos by name (a name the client or setup lacks is skipped).
-- EllesmereUI's are found through its list of movable elements, see euiRow.
local BAR_NAMES = {
	"MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
	"MultiBar5", "MultiBar6", "MultiBar7", "MultiBar8", "StanceBar", "PetActionBar", "PossessActionBar",
	"MultiCastActionBarFrame", "ExtraActionBarFrame", "ZoneAbilityFrame", "MainMenuBarVehicleLeaveButton",
	"OverrideActionBar", "ForeverClassicUIBar",
	"Elv_ABFade", "ElvUI_StanceBar", "ElvUI_BarPet", "ElvUI_ExtraActionBarHolder", "ElvUI_ZoneAbilityHolder",
	"VehicleLeaveButtonHolder",
	"BT4BarStanceBar", "BT4BarPetBar", "BT4BarVehicle", "BT4BarExtraActionBar", "BT4BarZoneAbilityBar",
	"BT4BarBlizzardArt",
	"DominosFramepet", "DominosFrameclass", "DominosFramepossess", "DominosFrameextra", "DominosFramevehicle",
	"DominosFrameencounter",
}
numbered(BAR_NAMES, "ElvUI_Bar", 1, 15)
numbered(BAR_NAMES, "BT4Bar", 1, 15)
numbered(BAR_NAMES, "DominosFrame", 1, 14)

local CHAT_NAMES = {
	"GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
	"ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "ChatAlertFrame", "CombatLogQuickButtonFrame_Custom",
	"LeftChatPanel", "RightChatPanel", "LeftChatToggleButton", "RightChatToggleButton", "LeftChatDataPanel",
	"RightChatDataPanel",
}
numbered(CHAT_NAMES, "ChatFrame", 1, 10)
numbered(CHAT_NAMES, "ChatFrame", 1, 10, "Tab")

local METER_NAMES = { "DamageMeter", "Recount_MainWindow", "SkadaBarWindowSkada" }
numbered(METER_NAMES, "DetailsBaseFrame", 1, 10)
numbered(METER_NAMES, "DetailsRowFrame", 1, 10)
numbered(METER_NAMES, "EllesmereUIDMFrame", 1, 10)

local BOSS_NAMES = { "BossTargetFrameContainer", "ArenaEnemyFramesContainer", "ArenaEnemyMatchFramesContainer",
	"CompactArenaFrame" }
numbered(BOSS_NAMES, "Boss", 1, 5, "TargetFrame")
numbered(BOSS_NAMES, "ElvUF_Boss", 1, 8)
numbered(BOSS_NAMES, "ElvUF_Arena", 1, 5)

-- Toasts (achievements, loot) are separate frames the game hands to AlertFrame one by one.
local toasts = setmetatable({}, { __mode = "k" })

-- Rows of the Elements page. modes: what its State menu offers. instant: shows and hides without a fade.
-- each: whether on mouseover its frames come back one by one. follow: frames placed beside its frames go with it.
-- tip: what it covers, for its tooltip.
local SECTIONS = {
	{ name = "Bars", rows = {
		{ id = "bars", label = "Action bars", names = BAR_NAMES,
			each = function() return db().oneBarAtATime ~= false end,
			tip = "Every action bar, the stance and pet bars, and the extra action and vehicle buttons." },
		{ id = "menu", label = "Menu and bags bar",
			names = { "MicroMenuContainer", "MicroButtonAndBagsBar", "BagsBar", "QueueStatusButton", "ElvUI_MicroBar",
				"ElvUIBagBar", "BT4BarMicroMenu", "BT4BarBagBar", "BT4BarQueueStatus", "DominosFramemenu",
				"DominosFramebags" },
			tip = "The game menu buttons, the bag buttons and the group finder eye." },
		{ id = "xp", label = "XP, reputation and data bars",
			names = { "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
				"ElvUI_ExperienceBar", "ElvUI_ReputationBar", "ElvUI_HonorBar", "ElvUI_AzeriteBar", "ElvUI_ThreatBar",
				"ElvUI_PetExperienceBar", "BT4BarStatusTrackingBar", "DominosFrameexp", "DominosFrameartifact" },
			tip = "Experience and reputation bars, and EllesmereUI's data bars." },
		{ id = "cooldowns", label = "Cooldown manager",
			names = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer",
				"BuffBarCooldownViewer" },
			tip = "The game's cooldown manager and EllesmereUI's cooldown and tracking bars." },
		{ id = "cast", label = "Cast bar",
			names = { "PlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame", "OverlayPlayerCastingBarFrame",
				"ElvUF_Player_CastBar", "DominosFramecast" },
			tip = "Your own cast bar and your pet's. Target and focus cast bars go with Target and focus." },
	} },
	{ name = "Unit frames", rows = {
		{ id = "player", label = "Player and pet",
			names = { "PlayerFrame", "PetFrame", "TotemFrame", "PlayerPowerBarAlt", "ElvUF_Player", "ElvUF_Pet",
				"ElvUF_PetTarget" },
			tip = "Your own frame, your pet's, your class resource and EllesmereUI's resource bars." },
		{ id = "target", label = "Target and focus",
			names = { "TargetFrame", "FocusFrame", "TargetFrameToT", "FocusFrameToT", "ElvUF_Target",
				"ElvUF_TargetTarget", "ElvUF_TargetTargetTarget", "ElvUF_Focus", "ElvUF_FocusTarget" },
			tip = "Your target, your focus, their targets and their cast bars." },
		{ id = "party", label = "Party and raid",
			names = { "PartyFrame", "CompactPartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager",
				"ElvUF_Party", "ElvUF_Raid1", "ElvUF_Raid2", "ElvUF_Raid3", "ElvUF_Raidpet", "ElvUF_Tank",
				"ElvUF_Assist" },
			tip = "Party and raid frames." },
		{ id = "boss", label = "Boss and arena frames", names = BOSS_NAMES,
			tip = "The frames for bosses and arena opponents." },
		{ id = "buffs", label = "Buffs and debuffs",
			names = { "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame", "ExternalDefensivesFrame", "ElvUIPlayerBuffs",
				"ElvUIPlayerDebuffs" },
			tip = "Your buffs and debuffs, and EllesmereUI's buff reminders." },
	} },
	{ name = "Info", rows = {
		{ id = "chat", label = "Chat", names = CHAT_NAMES, follow = true,
			more = function(add)
				-- EllesmereUI hides the chat frames' own text and draws chat on panels of its own beside them.
				local eui = _G.EllesmereUI
				local panels = type(eui) == "table" and eui._chatCFD
				if type(panels) ~= "function" then return end
				for i = 1, 10 do
					local cf = _G["ChatFrame" .. i]
					local ok, d = false, nil
					if cf then ok, d = pcall(panels, cf) end
					if ok and type(d) == "table" then
						add(d.bg)
						add(d.sidebar)
						add(d.scrollBtn)
					end
				end
			end,
			tip = "The chat windows, their tabs and buttons." },
		{ id = "minimap", label = "Minimap", instant = true,
			names = { "MinimapCluster", "Minimap", "ElvUI_MinimapHolder", "ElvUI_MinimapClusterHolder", "MinimapPanel" },
			tip = "The minimap and the buttons around it. Its icons ignore the HUD's opacity, so while hidden it is "
				.. "switched off rather than faded." },
		{ id = "quests", label = "Quest tracker",
			names = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame", "Questie_BaseFrame" },
			tip = "The quest and objective tracker, Questie's included." },
		{ id = "meters", label = "Damage and threat meters", names = METER_NAMES,
			tip = "The game's damage meter, Details!, Recount, Skada, and EllesmereUI's damage and threat meters." },
		{ id = "bossmods", label = "Boss mod timers",
			names = { "DBMInfoFrame", "DBMRangeCheck", "DBMRangeCheckRadar" },
			more = function(add)
				-- DBM's bars sit in anchors without a name: take the anchors from the bars that exist.
				for i = 1, 500 do
					local bar = _G["DBT_Bar_" .. i]
					if not bar then break end
					add(core.ask(bar, "GetParent"))
				end
			end,
			tip = "Deadly Boss Mods' timer bars, info frame and range check." },
	} },
	{ name = "Notifications", notify = true, rows = {
		{ id = "zone", label = "Zone names", names = { "ZoneTextFrame", "SubZoneTextFrame" },
			tip = "The zone and area name that shows as you enter a place." },
		{ id = "warnings", label = "Raid warnings and boss emotes", names = { "RaidWarningFrame", "RaidBossEmoteFrame" },
			tip = "Raid warnings and boss emotes in the middle of the screen." },
		{ id = "errors", label = "Errors and quest progress", names = { "UIErrorsFrame" },
			tip = "The red error text (out of range, not enough mana) and the yellow quest progress lines." },
		{ id = "toasts", label = "Toasts and banners",
			names = { "AlertFrame", "EventToastManagerFrame", "BossBanner", "LevelUpDisplay" },
			more = function(add)
				for f in pairs(toasts) do add(f) end
			end,
			tip = "Achievement, loot and level up toasts, and banners like a boss's loot." },
		{ id = "breath", label = "Breath and fatigue bars",
			names = { "MirrorTimerContainer", "MirrorTimer1", "MirrorTimer2", "MirrorTimer3" },
			tip = "The breath bar underwater and the fatigue bar." },
		{ id = "control", label = "Loss of control", names = { "LossOfControlFrame" },
			tip = "The alert that shows while you are stunned, feared or silenced." },
		{ id = "talking", label = "Talking heads", names = { "TalkingHeadFrame" },
			tip = "The box where a quest character talks to you." },
	} },
}

local ROWS, BY_ID = {}, {}
for _, section in ipairs(SECTIONS) do
	for _, row in ipairs(section.rows) do
		row.modes = section.notify and { "hide", "show" } or { "hide", "hover", "show" }
		ROWS[#ROWS + 1] = row
		BY_ID[row.id] = row
	end
end
Elements.SECTIONS = SECTIONS

-- EllesmereUI lists every element you can move in unlock mode, by group: which row each one belongs to.
local EUI_GROUPS = {
	["Cooldown Manager"] = "cooldowns", ["Raid & Party Frames"] = "party", ["AuraBuff Reminders"] = "buffs",
	["Chat"] = "chat", ["Minimap"] = "minimap", ["Quest Tracker"] = "quests", ["DataBars"] = "xp",
}
local EUI_KEYS = {
	MicroBar = "menu", BagBar = "menu", QueueStatus = "menu", XPBar = "xp", RepBar = "xp", FavorBar = "xp",
	player = "player", pet = "player", classPower = "player", boss = "boss", playerCastbar = "cast",
	petCastbar = "cast", ERB_CastBar = "cast", EUI_ThreatMeter = "meters",
}

local function euiRow(key, group)
	if EUI_KEYS[key] then return EUI_KEYS[key] end
	if key:sub(1, 4) == "EDM_" then return "meters" end
	if group == "Action Bars" then return "bars" end
	if group == "Unit Frames" then return "target" end -- target, focus, their targets and cast bars
	if group == "Resource Bars" then return "player" end
	return EUI_GROUPS[group]
end

---------------------------------------------------------------------------
-- Settings: DB.elements[id] is "hover" or "show" (absent: hide), DB.elementCombat[id] is false when unticked.
---------------------------------------------------------------------------
local roots = {}                                       -- row id -> the frames lifted for it
local rowOf = setmetatable({}, { __mode = "k" })       -- frame in roots -> row id
local resolvedAt, dirty = -100, true

function Elements.Mode(id)
	local m = db().elements[id]
	return (m == "hover" or m == "show") and m or "hide"
end

function Elements.SetMode(id, mode)
	db().elements[id] = (mode == "hover" or mode == "show") and mode or nil
	dirty = true
	HUDFade.Update()
end

-- The In combat column. The nameplates have one too, kept with the rest.
function Elements.InCombat(id)
	return db().elementCombat[id] ~= false
end

function Elements.SetInCombat(id, on)
	-- Only an unticked box is saved, so new elements start ticked.
	if on then db().elementCombat[id] = nil else db().elementCombat[id] = false end
	dirty = true
	HUDFade.Update()
end

-- A fight brings back only some elements: the rest of the HUD stays hidden.
function Elements.PartialCombat()
	for _, row in ipairs(ROWS) do
		if not Elements.InCombat(row.id) and Elements.Mode(row.id) ~= "show" then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Finding each element's frames
---------------------------------------------------------------------------
local function parentOf(f)
	local p = core.ask(f, "GetParent")
	return type(p) == "table" and p or nil
end

local function within(f, set)
	for _ = 1, 25 do
		if type(f) ~= "table" or f == UIParent then return false end
		if set[f] then return true end
		f = parentOf(f)
	end
	return false
end

local function placedBy(f, set)
	for i = 1, core.ask(f, "GetNumPoints") or 0 do
		local ok, _, rel = pcall(f.GetPoint, f, i)
		if ok and not (issecretvalue and issecretvalue(rel)) and within(rel, set) then return true end
	end
	return false
end

-- Frames placed beside a row's frames rather than inside them go with it, like EllesmereUI's chat tabs and borders.
local function addFollowers(id, list)
	local ok, kids = pcall(function() return { UIParent:GetChildren() } end)
	if not ok then return end
	local mine = {}
	for _, f in ipairs(list) do mine[f] = true end
	for _ = 1, 2 do -- and frames placed beside those
		for _, f in ipairs(kids) do
			if type(f) == "table" and not mine[f] and not rowOf[f] and type(f.SetIgnoreParentAlpha) == "function"
				and placedBy(f, mine) then
				mine[f] = true
				list[#list + 1] = f
				rowOf[f] = id
			end
		end
	end
end

-- Whether a row needs its frames placed beside it: only while it can be on without the rest of the HUD.
local function followed(row)
	return row.follow and (Elements.Mode(row.id) ~= "hide" or Elements.PartialCombat() and Elements.InCombat(row.id))
end

local function resolve()
	resolvedAt, dirty = core.now(), false
	local found = {}
	for _, row in ipairs(ROWS) do found[row.id] = {} end
	local function adder(id)
		return function(f)
			if type(f) == "table" and f ~= UIParent and type(f.SetIgnoreParentAlpha) == "function" then
				found[id][f] = true
			end
		end
	end
	for _, row in ipairs(ROWS) do
		local add = adder(row.id)
		for _, name in ipairs(row.names) do add(_G[name]) end
		if row.more then pcall(row.more, add) end
	end
	local eui = _G.EllesmereUI
	local list = type(eui) == "table" and eui._unlockRegisteredElements
	if type(list) == "table" then
		for key, info in pairs(list) do
			local id = type(key) == "string" and type(info) == "table" and type(info.getFrame) == "function"
				and euiRow(key, info.group)
			if id and found[id] then
				local ok, f = pcall(info.getFrame, key)
				if ok then adder(id)(f) end
			end
		end
	end
	wipe(rowOf)
	for _, row in ipairs(ROWS) do
		local set, list2 = found[row.id], {}
		for f in pairs(set) do
			-- Lift only the outermost frame: one inside it follows it anyway, and lifting it too would cut it off
			-- from its addon's own fade on the outer one.
			local inside, p = false, parentOf(f)
			for _ = 1, 25 do
				if not p or p == UIParent then break end
				if set[p] then
					inside = true
					break
				end
				p = parentOf(p)
			end
			if not inside and p == UIParent and not rowOf[f] then
				list2[#list2 + 1] = f
				rowOf[f] = row.id
			end
		end
		roots[row.id] = list2
	end
	-- After every row has its own frames, so none is taken by a neighbour.
	for _, row in ipairs(ROWS) do
		if followed(row) then addFollowers(row.id, roots[row.id]) end
	end
end

function Elements.Refresh()
	dirty = true
	HUDFade.Update()
end

---------------------------------------------------------------------------
-- Lifting frames out of the HUD's fade. Each frame in roots has its own state, so one bar can come back alone.
---------------------------------------------------------------------------
local weak = { __mode = "k" }
local want = setmetatable({}, weak)       -- frame -> true while it should be visible
local level = setmetatable({}, weak)      -- frame -> the opacity it is drawn at while apart from the HUD (1: its own)
local quick = setmetatable({}, weak)      -- frame -> true to jump to its goal without a fade
local cameFor = setmetatable({}, weak)    -- frame -> the row it came back for
local hoverUntil = setmetatable({}, weak) -- row id, or frame in a row of separate bars -> when it may go again
local rowOn = {}                          -- row id -> why it is on screen, for /hudfade why
local holding = false -- the HUD is coming back: keep lifted frames up until it is fully back, then let go

local lifted = setmetatable({}, weak)  -- frames we set to ignore the UI's opacity
local base = setmetatable({}, weak)    -- frame -> its own opacity, while we write one
local written = setmetatable({}, weak) -- frame -> what we last wrote

local function restoreAlpha(f)
	if base[f] == nil then return end
	local cur = core.ask(f, "GetAlpha")
	-- If its owner changed it since our last write, that is its opacity now.
	if type(cur) == "number" and written[f] and math.abs(cur - written[f]) <= 0.01 then pcall(f.SetAlpha, f, base[f]) end
	base[f], written[f] = nil, nil
end

local function setLevel(f, lv)
	if lv >= 0.999 then
		restoreAlpha(f)
		return
	end
	local cur = core.ask(f, "GetAlpha")
	if type(cur) ~= "number" then return end -- a secret opacity: no fade, it just appears
	if base[f] == nil or math.abs(cur - (written[f] or -1)) > 0.01 then base[f] = cur end
	local a = base[f] * lv
	if pcall(f.SetAlpha, f, a) then written[f] = a end
end

local function liftFrame(f)
	if lifted[f] then return end
	-- A frame that already ignores the UI's opacity (or won't say) is left to Core's fade, which asks LevelFor.
	if core.ask(f, "IsIgnoringParentAlpha") ~= false then return end
	if pcall(f.SetIgnoreParentAlpha, f, true) then lifted[f] = true end
end

local function drop(f)
	local id = cameFor[f]
	want[f], level[f], quick[f], cameFor[f] = nil, nil, nil, nil
	if lifted[f] then
		lifted[f] = nil
		restoreAlpha(f)
		pcall(f.SetIgnoreParentAlpha, f, false)
	end
	if id == "minimap" and core.state.cvarsHidden then core.hideMinimap() end
end

local function dropAll()
	for f in pairs(level) do drop(f) end
end

-- The opacity the rest of the UI is drawn at right now.
local function uiLevel()
	return math.max(0, math.min(1, core.state.current))
end

local animator = CreateFrame("Frame")
animator:Hide()

local function step(elapsed)
	local ui = uiLevel()
	if holding and ui >= 0.999 then
		dropAll()
		holding = false
	end
	local busy = false
	for f, lv in pairs(level) do
		local goal = (want[f] or holding) and 1 or ui
		if quick[f] then
			lv = goal
		elseif lv < goal then
			lv = math.min(goal, lv + elapsed / math.max(db().fadeIn or 0.2, 0.01))
		elseif lv > goal then
			lv = math.max(goal, lv - elapsed / math.max(db().fadeOut or 1, 0.01))
		end
		if not want[f] and not holding and lv <= ui + 0.001 then
			drop(f)
		else
			level[f] = lv
			if lifted[f] then setLevel(f, lv) end
			if lv ~= goal or holding then busy = true end
		end
	end
	core.refade() -- portraits and other frames inside the rows
	if not busy then animator:Hide() end
end
animator:SetScript("OnUpdate", function(_, elapsed) step(elapsed) end)

local function over(f, row)
	-- The minimap is hidden outright, so its own spot counts even then.
	return (row.instant or core.ask(f, "IsVisible") == true) and core.ask(f, "IsMouseOver") == true
end

-- Called whenever the HUD's goal is set. goal: the opacity the HUD is heading for. combat: a fight alone is
-- what shows it. clean: a HUD-free screenshot, so nothing stays.
function Elements.Decide(goal, combat, instant, clean)
	if goal >= 0.999 or clean then
		wipe(want)
		wipe(rowOn)
		if clean then
			dropAll()
		elseif next(level) then
			holding = true
			animator:Show()
		end
		return
	end
	holding = false
	local t = core.now()
	if dirty or t - resolvedAt > RESOLVE_EVERY then
		resolve()
		-- Frames that left their row (a toast that went back to the game's pool) go back to normal.
		for f in pairs(level) do
			if rowOf[f] ~= cameFor[f] then drop(f) end
		end
	end
	local ui = uiLevel()
	for _, row in ipairs(ROWS) do
		local id, mode, list = row.id, Elements.Mode(row.id), roots[row.id] or {}
		local all = mode == "show" or (combat and Elements.InCombat(id))
		-- A row of separate bars can bring back only the bar under the mouse.
		local each = row.each and row.each()
		local function hovering(f) return (hoverUntil[each and f or id] or 0) > t end
		if not all and mode == "hover" then
			for _, f in ipairs(list) do
				if over(f, row) then hoverUntil[each and f or id] = t + LINGER end
			end
		end
		local why
		if all then
			why = mode == "show" and "always visible" or "in combat"
		elseif mode == "hover" then
			for _, f in ipairs(list) do
				if hovering(f) then
					why = "mouse over it"
					break
				end
			end
		end
		if why and not rowOn[id] and id == "minimap" then core.showMinimap() end
		rowOn[id] = why
		for _, f in ipairs(list) do
			if all or mode == "hover" and hovering(f) then
				if not want[f] then
					want[f] = true
					quick[f] = instant or row.instant or ui >= 0.999
				end
				if level[f] == nil then level[f], cameFor[f] = quick[f] and 1 or ui, id end
				if not lifted[f] then
					liftFrame(f)
					if lifted[f] then setLevel(f, level[f]) end
				end
				animator:Show()
			elseif want[f] then
				want[f] = nil
				quick[f] = row.instant or instant
				animator:Show()
			end
		end
	end
end

-- The opacity a frame inside a lifted row is drawn at, or nil if it follows the HUD.
function Elements.LevelFor(f)
	if not next(level) then return nil end
	for _ = 1, 25 do
		if type(f) ~= "table" then return nil end
		if level[f] then return level[f] end
		if f == UIParent then return nil end
		f = parentOf(f)
	end
	return nil
end

-- Frames we set to ignore the UI's opacity ourselves: Core's fade of such frames must leave them alone.
function Elements.Owns(f)
	return lifted[f] ~= nil
end

-- Whether the minimap is switched off while the HUD is hidden.
function Elements.HidesMinimap()
	return Elements.Mode("minimap") ~= "show" and not rowOn.minimap
end

-- For /hudfade what: the row a frame belongs to.
function Elements.RowFor(f)
	if dirty or core.now() - resolvedAt > RESOLVE_EVERY then resolve() end
	for _ = 1, 25 do
		if type(f) ~= "table" then return nil end
		local id = rowOf[f]
		if id then return BY_ID[id] end
		if f == UIParent then return nil end
		f = parentOf(f)
	end
	return nil
end

-- For /hudfade why: the rows on screen apart from the rest of the HUD.
function Elements.Describe()
	local out = {}
	for _, row in ipairs(ROWS) do
		if rowOn[row.id] then out[#out + 1] = row.label .. " (" .. rowOn[row.id] .. ")" end
	end
	return out
end

---------------------------------------------------------------------------
-- Tooltips: one for a button in a lifted row (an action button under the mouse) is lifted with it.
---------------------------------------------------------------------------
local tipLifted = false

-- Whether a tooltip belongs to a button in a lifted row, so Core's fade leaves it open.
function Elements.KeepsTooltip(tip)
	local owner = core.ask(tip, "GetOwner")
	local lv = type(owner) == "table" and Elements.LevelFor(owner)
	return lv and lv > 0.5 or false
end

local function tipCheck(tip)
	if Elements.KeepsTooltip(tip) then
		if not tipLifted and core.ask(tip, "IsIgnoringParentAlpha") == false
			and pcall(tip.SetIgnoreParentAlpha, tip, true) then
			tipLifted = true
		end
	elseif tipLifted then
		tipLifted = false
		pcall(tip.SetIgnoreParentAlpha, tip, false)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	if GameTooltip and GameTooltip.HookScript then
		pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function(tip) pcall(tipCheck, tip) end)
		pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function(tip)
			if tipLifted then
				tipLifted = false
				pcall(tip.SetIgnoreParentAlpha, tip, false)
			end
		end)
	end
	if hooksecurefunc and type(AlertFrame) == "table" and type(AlertFrame.AddAlertFrame) == "function" then
		pcall(hooksecurefunc, AlertFrame, "AddAlertFrame", function(_, frame)
			if type(frame) == "table" and not toasts[frame] then
				toasts[frame] = true
				dirty = true
				if Elements.Mode("toasts") == "show" then HUDFade.Update() end
			end
		end)
	end
end)
