# HUD Fade

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
