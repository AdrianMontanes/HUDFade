<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/icon-dark.png">
  <img src=".github/icon-light.png" alt="HUD Fade logo" height="96">
</picture>

# HUD Fade

Fade your whole World of Warcraft UI at once, Blizzard's and EllesmereUI's together.<br>
Made for OLED burn-in care and HUD-free screenshots.

[![CurseForge](https://img.shields.io/badge/CurseForge-HUD%20Fade-F16436?logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/hud-fade)
[![Latest release](https://img.shields.io/github/v/release/AdrianMontanes/HUDFade?label=release&color=F7752A)](https://github.com/AdrianMontanes/HUDFade/releases/latest)
[![WoW Forever and Retail](https://img.shields.io/badge/WoW-Forever%20%7C%20Retail-148EFF)](#install)
[![MIT license](https://img.shields.io/github/license/AdrianMontanes/HUDFade?color=blue)](LICENSE)

</div>

## Why HUD Fade

Most fade addons set each frame's opacity one by one, and UI addons like EllesmereUI do the same for their own mouseover rules, so the two fight: flicker, bars popping back, art showing through. HUD Fade fades the one layer every frame sits on instead, so your UI addons keep working underneath. It also handles what lives outside that layer: 3D portraits, names, chat bubbles, nameplates and the target circle.

## Features

- **One key hides everything.** Your Hide UI key (Alt+Z) now fades smoothly and is safe in combat.
- **Comes back when it matters:** combat, a target, a window, typing in chat, dying. Each can be switched off.
- **Hides when idle** after 30 seconds (adjustable). Turning the camera doesn't wake it, so you can take in the view.
- **Clean screenshots:** a key that takes one with no HUD, names or chat bubbles, then puts everything back.
- **Hold to peek** at the HUD while it's hidden.
- **Pixel shift:** moves the whole UI a pixel or two every few minutes to spread OLED wear. Optional, never in combat.
- **Dim instead of hide:** hidden opacity from 0% (true black) up to 50%.
- **Your call on the world:** hide names and nameplates too, or leave them like the game's own Hide UI does.

No setup per addon and no reload. Keys for hide/show, peek, screenshot and on/off are in the game's Key Bindings, under AddOns.

## Commands

| Command | What it does |
| :--- | :--- |
| `/hudfade` | Open the settings |
| `/hudfade toggle` | Hide or show the HUD (also `show` and `hide`) |
| `/hudfade on` / `off` | Turn HUD Fade on or off |
| `/hudfade shot` | Take a screenshot without the HUD |
| `/hudfade shift` | Pixel shift status (also `on`, `off`, and `now` to see a move) |
| `/hudfade why` | Say what is keeping the HUD visible |
| `/hudfade what` | Name the UI element under the mouse |
| `/hudfade reset` | Go back to the default settings |

`/hfade` works too, as a shorter `/hudfade`.

## Install

- **CurseForge app:** search for HUD Fade.
- **By hand:** download the zip from [Releases](https://github.com/AdrianMontanes/HUDFade/releases/latest) and unzip it into `World of Warcraft\_forever_\Interface\AddOns` (or `_retail_` for Retail), so you end up with an `AddOns\HUDFade` folder.

Works on WoW Forever and Retail (12.x). Classic versions are planned.

## Something stays visible?

Hover it, type `/hudfade what`, and [open an issue](https://github.com/AdrianMontanes/HUDFade/issues/new/choose) with what it printed and which UI addons you use.

## Recording in HDR?

Try [REPLAYD](https://replayd.download/with/hudfade), my native game recorder for Windows, built from scratch with HDR and OLED monitors in mind.
