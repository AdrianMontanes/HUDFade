<img src=".github/icon.png" alt="" width="96" align="right">

# HUD Fade

Fade or hide the whole World of Warcraft interface at once: Blizzard's UI and EllesmereUI together, with no setup per addon.

Made for OLED screens (no static HUD burning in while you're away) and for HUD-free HDR screenshots and recordings.

## Why another fade addon

Most fade addons change the opacity of each UI frame one by one. EllesmereUI does the same for its own mouseover and visibility rules, so the two keep overriding each other and you get flicker, bars that come back, or art showing through.

HUD Fade never touches a single frame. It fades the layer every UI frame sits on, so EllesmereUI (or any other UI addon) keeps doing its thing underneath and nothing fights. The few things that don't live on that layer are handled too: 3D portraits, the floating player and NPC names, chat bubbles, and nameplates.

## Features

- **One key hides everything.** Uses your Hide UI key (Alt+Z by default), but fades smoothly and is safe in combat.
- **Comes back when it matters:** combat, a target, a window or popup, typing in chat, dying. Each one can be switched off.
- **Hide when idle:** after 30 seconds with no input (adjustable) the HUD fades out, and comes back the moment you move the mouse or press a key. Looking around with the camera and auto-running don't count as input unless you want them to, so you can take in the view with no HUD. A window or chat box left open keeps the HUD only until you have been away for 10 minutes (adjustable).
- **Clean screenshots:** a key that takes a screenshot with no HUD, names or chat bubbles, then puts everything back.
- **Hold to peek:** a key that shows the HUD only while held.
- **Hide the mouse pointer** when it's still (optional, experimental).
- **Pixel shift (burn-in protection):** every few minutes the whole interface moves a pixel or two, Blizzard UI and EllesmereUI together, so nothing sits on the same pixels for hours. Never during combat, and your layout is never changed. Optional.
- **One switch for everything:** turn HUD Fade off and on from its settings, a key, or `/hudfade off` / `/hudfade on`, with no reload.
- **Dim instead of hide:** set the hidden opacity anywhere from 0% (true black) to 50%.

Type `/hudfade` for settings, `/hudfade toggle` to hide or show the HUD, `/hudfade why` to see what is keeping it visible, `/hudfade shift now` to try pixel shift, `/hudfade what` to name a UI element under the mouse, and `/hudfade log` to see what the HUD and the pointer did lately.

## Install

- **CurseForge or Wago app:** search for HUD Fade.
- **By hand:** download the zip from [Releases](https://github.com/AdrianMontanes/HUDFade/releases) and unzip it into your AddOns folder, for example `World of Warcraft\_forever_\Interface\AddOns` for WoW Forever or `World of Warcraft\_retail_\Interface\AddOns` for Retail. You should end up with an `AddOns\HUDFade` folder.

## Supported versions

WoW Forever and Retail (12.x). Classic flavors are planned.

## Something stays visible?

Hover it and type `/hudfade what`, then [open an issue](https://github.com/AdrianMontanes/HUDFade/issues) with what it printed and which UI addons you use.

## Recording in HDR

If you capture your HDR gameplay, try [REPLAYD](https://replayd.download/with/hudfade), a game recorder for Windows.

## License

MIT
