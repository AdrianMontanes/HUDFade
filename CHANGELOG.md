# HUD Fade

## 1.1.1

- Opening a window, like the map or your bags, now counts as activity. After you close it the HUD stays for your idle time instead of hiding right away. A popup that arrives while you are away still leaves it hidden.

## 1.1.0

- Nameplates, including EllesmereUI's names above characters, now fade out and back in with the HUD instead of vanishing all at once when the fade ends. Names the game draws itself still switch off at once: the game gives addons no way to fade them.
- Nameplates now stay hidden in combat while the HUD is hidden, for example after you hide it mid-fight or with Combat unticked. They used to come back as soon as a fight started.
- New **Damage numbers** option: the damage and healing numbers over your targets go with the HUD too. It is part of the Everything preset, and on unless you use the Blizzard preset.
- After you hide the HUD with your Hide UI key, a new target or a cast no longer brings it back. It stays hidden until you press the key again, apart from combat, windows, typing and dying (each if ticked). Hiding for being idle works as before: any input, a target included, brings it back.
- After a screenshot without the HUD, the chat says it was saved, and the first time each session also where.
- The "Target circle and glow" option is now called **Target circle**.

## 1.0.0

First release.

- One key fades the whole interface at once, Blizzard UI and EllesmereUI together, without touching any single frame. It takes over your Hide UI key (Alt+Z) and is safe in combat.
- Comes back when it matters: combat, a target, an open window, typing in chat or dying. Each one is optional.
- Hides when idle after 30 seconds (adjustable). Moving the mouse, clicking or pressing a key brings it back; camera movement and auto-run only count if you want them to. After 10 minutes away (adjustable) it hides even over an open window.
- Choose what goes with it: Everything (names, chat bubbles, nameplates and the target circle too) or Blizzard (like Alt+Z), or tick your own.
- A key for screenshots with no HUD and no names, and a key that shows the HUD while held.
- Optional pixel shift for OLED screens: the whole UI moves a pixel or two every few minutes, never in combat.
- Hidden opacity from 0% (true black) to 50%.
- Minimap button, an on/off switch with its own key, and `/hudfade why` and `/hudfade what` for troubleshooting.
- Works on WoW Forever and Retail (12.x).
