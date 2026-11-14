-- luacheck config: https://luacheck.readthedocs.io
std = "lua51"
max_line_length = 120
exclude_files = { ".release/", "Libs/" }

ignore = {
	"212/self", -- unused self in methods
}

-- Globals the addon defines
globals = {
	"HUDFade",
	"HUDFadeDB",
	"HUDFade_OnCompartmentClick",
	"HUDFade_OnCompartmentEnter",
	"HUDFade_OnCompartmentLeave",
	"SLASH_HUDFADE1",
	"SLASH_HUDFADE2",
	"BINDING_HEADER_HUDFADE",
	"BINDING_NAME_HUDFADE_TOGGLE",
	"BINDING_NAME_HUDFADE_PEEK",
	"BINDING_NAME_HUDFADE_SCREENSHOT",
	"BINDING_NAME_HUDFADE_ENABLE",
	"BINDING_NAME_HUDFADE_PAN",
	"SlashCmdList",
}

-- WoW API and frames the addon reads
read_globals = {
	"AlertFrame",
	"BackdropTemplateMixin",
	"C_CVar",
	"C_GamePad",
	"C_NamePlate",
	"C_Timer",
	"ClearOverrideBindings",
	"CreateFrame",
	"EditModeManagerFrame",
	"EnumerateFrames",
	"GameTooltip",
	"GetBindingAction",
	"GetBindingKey",
	"GetBindingText",
	"GetBuildInfo",
	"GetCVar",
	"GetCurrentKeyBoardFocus",
	"GetCursorInfo",
	"GetCursorPosition",
	"GetMouseFoci",
	"GetMouseFocus",
	"GetPhysicalScreenSize",
	"GetTime",
	"hooksecurefunc",
	"InCombatLockdown",
	"InterfaceOptions_AddCategory",
	"InterfaceOptionsFrame_OpenToCategory",
	"IsKeyDown",
	"IsMouseButtonDown",
	"IsMouselooking",
	"issecretvalue",
	"IsShiftKeyDown",
	"LibStub",
	"Minimap",
	"MoveViewRightStart",
	"MoveViewRightStop",
	"PixelUtil",
	"Screenshot",
	"SetCVar",
	"SetOverrideBinding",
	"Settings",
	"UIPanelWindows",
	-- DynamicCam's fields on UIParent, which we share its UI fade through
	UIParent = { other_fields = true, fields = { ludius_intendedUIParentAlpha = { read_only = false },
		ludius_alphaBeforeFadeOut = { read_only = false } } },
	"UISpecialFrames",
	"UnitExists",
	"UnitInVehicle",
	"UnitIsDead",
	"wipe",
}

-- The test file builds a fake WoW API, so it sets the game's globals itself.
files["tests/mock.lua"] = {
	ignore = { "1" },
}
