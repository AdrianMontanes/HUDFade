-- HUD Fade's minimap button (LibDBIcon) and its entry in the game's addon compartment.

local _, ns = ...
local HUDFade = ns.core

local ICON = "Interface\\AddOns\\HUDFade\\media\\icon"

local function click(button)
	if button == "RightButton" then
		HUDFade.ToggleEnabled()
	elseif IsShiftKeyDown() then
		HUDFade.CleanScreenshot()
	else
		HUDFade.OpenOptions()
	end
end

local function fillTooltip(tt, onMinimap)
	local on = HUDFade.db.enabled
	tt:AddDoubleLine("HUD Fade", on and "On" or "Off", 1, 1, 1, on and 0.3 or 0.6, on and 1 or 0.6, on and 0.3 or 0.6)
	tt:AddDoubleLine("Left-click", "Settings", 1, 0.82, 0, 1, 1, 1)
	tt:AddDoubleLine("Right-click", on and "Turn off" or "Turn on", 1, 0.82, 0, 1, 1, 1)
	tt:AddDoubleLine("Shift-click", "Screenshot without the HUD", 1, 0.82, 0, 1, 1, 1)
	if onMinimap then tt:AddDoubleLine("Drag", "Move this button", 1, 0.82, 0, 1, 1, 1) end
end

-- The compartment passes the mouse button as a string in older clients and inside a table in newer ones.
function HUDFade_OnCompartmentClick(_, input)
	click(type(input) == "table" and input.buttonName or input)
end

function HUDFade_OnCompartmentEnter(_, frame)
	GameTooltip:SetOwner(type(frame) == "table" and frame.GetObjectType and frame or UIParent, "ANCHOR_LEFT")
	fillTooltip(GameTooltip)
	GameTooltip:Show()
end

function HUDFade_OnCompartmentLeave()
	GameTooltip:Hide()
end

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

function HUDFade.UpdateMinimapButton()
	local db = HUDFade.db
	if not (DBIcon and db and db.minimap) then return end
	db.minimap.hide = not db.minimapButton
	if db.minimapButton then DBIcon:Show("HUDFade") else DBIcon:Hide("HUDFade") end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	if not (LDB and DBIcon) then return end
	local db = HUDFade.db
	db.minimap = db.minimap or {} -- the button's position, kept by LibDBIcon
	db.minimap.hide = not db.minimapButton
	local launcher = LDB:NewDataObject("HUDFade", {
		type = "launcher",
		label = "HUD Fade",
		icon = ICON,
		OnClick = function(_, button) click(button) end,
		OnTooltipShow = function(tt) fillTooltip(tt, true) end,
	})
	DBIcon:Register("HUDFade", launcher, db.minimap)
end)
