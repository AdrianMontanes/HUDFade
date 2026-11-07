# HUD Fade

## 0.2.15

- 3D portraits that an addon creates on first use (EllesmereUI's target portrait) now fade the moment they get a unit to show. Before, they could stay solid until the background check had walked every frame in the game, which can take half a minute or more with many addons installed.

## 0.2.14

- Hidden pointer on flight paths: moving the mouse no longer turns the camera. Mouse look speed goes down to almost nothing while the pointer is hidden there, so the camera only moves when you click and drag, at your normal speed. A click or any key brings the pointer back, and moving the mouse does too where the game reports mouse movement.

## 0.2.13

- Edit Mode and EllesmereUI's unlock mode count as an open window: the HUD stays visible while you arrange your frames, and only "Hide anyway when away" hides it.

## 0.2.12

- Pixel shift: EllesmereUI elements anchored to another one (like the cast bar under the player frame) no longer appear offset when they show up while the interface is shifted. EllesmereUI places them counting from the screen corner, so HUD Fade now takes its own move back out of those placements.
- Pixel shift now steps aside the moment EllesmereUI's unlock mode opens, instead of up to a second later.
- New setting "Hide anyway when away" (2 minutes to 1 hour, 10 minutes by default): after that long with no input, the HUD hides even over an open window or chat box, and even with Hide when idle set to Never. Combat still brings it back.
- A chat box left open no longer counts as typing. Only actually typing counts as activity.

## 0.2.11

- Shorter, clearer settings: "While HUD is hidden, also hide" (names and chat bubbles, nameplates, minimap, mouse pointer), "While HUD is hidden, bring it back on" (mouse moving, combat, target, casting, death, windows) and "Keep HUD visible during" (camera turning, auto-run or follow).
- Hidden pointer: the left-click guard while auto-running now switches on before the pointer hides, so a left click or drag really keeps you running. /hudfade why shows when it is on.

## 0.2.10

- Typing in chat counts as activity: after you send, the HUD stays for your idle time instead of hiding at once.
- Chat bubbles are hidden along with names while the HUD is hidden (the option is now "Hide names and chat bubbles while hidden").

## 0.2.9

- Hidden pointer: moving the mouse to bring the pointer back no longer turns the camera noticeably. While the pointer is hidden, mouse look speed is turned down to a tenth, and your own setting comes back with the pointer (also after a crash, at the next login). Flight paths and steering while flying keep the normal speed.

## 0.2.8

- New option "You move the mouse" (on by default) under "While hidden, bring the HUD back when". Off: once the HUD has hidden for being idle, only keys bring it back, so a bumped mouse or coming back from alt-tab leaves it hidden. While the HUD is visible, using the mouse always keeps it visible.
- "Hide when idle also waits while" is now "Keep the HUD visible while", with clearer tips.

## 0.2.7

- Pixel shift keeps the interface its shift distance in from the screen edges, so a frame you placed against an edge never goes past it. At most it comes back to exactly where you put it.
- Pixel shift steps aside while EllesmereUI's unlock mode is open (as it already did for Edit Mode), and puts the interface back in place before logout or reload, so no addon can save a shifted position.

## 0.2.6

- Hidden pointer: a left click while auto-running no longer stops your character. The first click only brings the pointer back, and you keep running.

## 0.2.5

- Hidden pointer: letting go of a right-drag no longer flashes the pointer back for a moment.
- After a left-drag the pointer no longer stays on screen until you move: once the mouse has been still for your idle time it hides again (turning your character to where the camera points, as a right-click would).
- Where the game puts the pointer back after a drag no longer counts as moving the mouse.

## 0.2.4

- The settings page scrolls when the settings window is too short for it, instead of the last options spilling over the window's border.

## 0.2.3

- "You are dead" is now "You die": the HUD comes back the moment you die, then hides again after your idle time even if you stay dead, so lying dead while away no longer keeps the HUD on screen. The Release Spirit popup no longer counts as an open window. As a ghost everything works as usual.

## 0.2.2

- New option under pointer hiding: Even when flying or swimming (off by default). The pointer also hides while flying, swimming or in a vehicle. Moving the mouse then steers you, as with the right button held, and a click or any key brings the pointer back.

## 0.2.1

- Pointer hiding now also works on flight paths. Moving the mouse turns the camera as usual, and a click or any key brings the pointer back. After landing it stays visible until the camera lines up with your character again.

## 0.2.0

First public release.

- One key fades the whole interface at once, Blizzard UI and EllesmereUI together, without touching any single frame.
- Comes back on combat, a target, an open window, typing in chat or being dead (each optional).
- Hides by itself after 30 seconds with no input (adjustable). Looking around with the camera doesn't count as input.
- Screenshot key with no HUD and no names, and a hold-to-peek key.
- Optional pixel shift for OLED burn-in protection, and optional pointer hiding.
- Works on WoW Forever and Retail.
