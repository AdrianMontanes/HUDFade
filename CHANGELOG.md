# HUD Fade

## 0.3.7

- New **Mouse clicks** option under Idle, "Also counts as input" (on by default): a click brings the HUD back after idle hiding, even without moving the mouse. Holding a button to move the camera doesn't count as a click.
- "Camera turning" is now called **Camera movement**.

## 0.3.6

- The Hide UI and screenshot tooltips now mention the NVIDIA overlay, which also uses Alt+Z, and that other apps' screenshots (like NVIDIA's Alt+F1) need the HUD hidden first.

## 0.3.5

- Help and feedback is back to showing both addresses to copy, without the buttons.

## 0.3.4

- Help and feedback now has two buttons, **Addon page** and **Report a problem**, instead of raw addresses. Click one and its address appears, selected and ready to copy with Ctrl+C (addons can't open your browser).

## 0.3.3

- The second preset is now called **Blizzard** (it was "Like the game's Hide UI").

## 0.3.2

- New "Help and feedback" section at the bottom of the settings: the addon page and the place to report a problem, ready to copy.

## 0.3.1

- Settings page tidied into General, While HUD is hidden also hide, Idle, While HUD is hidden bring it back on, and Fade.
- Idle now holds everything about idle hiding: both timers plus what also counts as input (Mouse moving, Camera turning, Auto-run or follow). Mouse moving moved here from "bring it back on", and the old "Keep HUD visible during" section is gone.
- The screenshot option shows your own screenshot key, like the Hide UI one.
- Tooltips for Combat, Target, Casting, both idle timers and Hidden opacity. The note under the timers moved into the away timer's tooltip.

## 0.3.0

- New preset menu above "While HUD is hidden, also hide": **Everything** (the default: names, nameplates, the target circle and glow go with the HUD) or **Like the game's Hide UI** (names, chat bubbles, the target circle and glow stay, as with Alt+Z; nameplates go). Change a box yourself and it shows as Custom.
- Removed the "Mouse pointer when still" option and everything it needed (mouselook, slowed look speed, the left-button workarounds, `/hudfade log`). The game gives addons no reliable way to hide the pointer, the workarounds kept causing camera trouble, and screenshots never include the pointer anyway. If it was on, your mouse look speed is put back at login.

## 0.2.20

- Hidden pointer: fixed the camera getting stuck tilting only up and down, with the pointer not coming back until a click or key (seen after alt-tab and while sitting). 0.2.17 slowed sideways looking to almost nothing once the game seemed to report mouse moves, but that report is unreliable while the pointer is hidden, so the sideways move that brings the pointer back no longer registered. Sideways speed now stays at a tenth everywhere except flight paths.

## 0.2.19

- Hidden pointer: moving the mouse up or down tilted the camera without bringing the pointer back (a tilt turns nothing HUD Fade can notice). While the pointer is hidden, the up-and-down look speed now drops to almost nothing, so the camera stays level, and the next sideways move brings the pointer back as before.

## 0.2.18

- New "Target circle and glow" option under "While HUD is hidden, also hide", on by default: the circle under your target, the glow around it and around whatever is under the mouse (the game's Outline Mode), and your own character's highlight if you use one, are switched off while the HUD is hidden. The target circle moved here from "Names and chat bubbles".

## 0.2.17

- Hidden pointer: after you stopped moving with the pointer hidden, the next left-drag only brought the pointer back instead of turning the camera. Fixed: the game now picks up the change to the left button as you stop.
- Hidden pointer: moving the mouse while sitting down turned the camera slowly and left the pointer hidden (your character doesn't turn while sitting, which is how a move was noticed). Where the game reports the mouse's own movement, that now brings the pointer back too, and once that has been seen to work the camera stays still while the pointer is hidden.
- New `/hudfade log`: the last things the HUD and the pointer did, also kept in the saved variables, for reporting bugs that are hard to catch.

## 0.2.16

- "Names and chat bubbles" also switches off the circle under your target while the HUD is hidden, where the game still has that setting. Your target's own name always shows: the game has no setting for it.

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
