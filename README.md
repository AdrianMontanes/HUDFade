# OLED HUD

Fade or hide the whole World of Warcraft interface at once: Blizzard's UI and EllesmereUI together, with no setup per addon.

Made for OLED screens (no static HUD burning in while you're away) and for HUD-free HDR screenshots and recordings.

## Why another fade addon

Most fade addons change the opacity of each UI frame one by one. EllesmereUI does the same for its own mouseover and visibility rules, so the two keep overriding each other and you get flicker, bars that come back, or art showing through.

OLED HUD never touches a single frame. It fades the layer every UI frame sits on, so EllesmereUI (or any other UI addon) keeps doing its thing underneath and nothing fights. The few things that don't live on that layer are handled too: 3D portraits, the floating player and NPC names, and nameplates.

## Features

- **One key hides everything.** Uses your Hide UI key (Alt+Z by default), but fades smoothly and is safe in combat.
- **Comes back when it matters:** combat, a target, a window or popup, typing in chat, being dead. Each one can be switched off.
- **Hide when idle:** after 30 seconds with no input (adjustable) the HUD fades out, and comes back the moment you move the mouse or press a key. Looking around with the camera and auto-running don't count as input unless you want them to, so you can take in the view with no HUD.
- **Clean screenshots:** a key that takes a screenshot with no HUD and no names, then puts everything back.
- **Hold to peek:** a key that shows the HUD only while held.
- **Hide the mouse pointer** when it's still (optional, experimental).
- **One switch for everything:** turn OLED HUD off and on from its settings, a key, or `/ohud off` / `/ohud on`, with no reload.
- **Dim instead of hide:** set the hidden opacity anywhere from 0% (true black) to 50%.

Type `/ohud` to toggle, `/ohud options` for settings, `/ohud why` to see what is keeping the HUD up.

## Supported versions

WoW Forever and Retail (12.x). Classic flavors are planned.

## Recording in HDR

If you play in HDR and want to capture it, take a look at **REPLAYD**.

## License

MIT
