# HUD Fade

## 1.4.0

- New **Camera pan** (off by default, under Idle and on the Burn-in protection page): while the HUD is hidden for being idle or AFK (you choose which), the camera turns slowly around your character, so the game world doesn't sit still on your screen either. Any key, click, mouse or controller movement stops it at once, and it waits for the idle or AFK time again before turning.
- Pick its speed, from one turn every 10 minutes to one a minute.
- For a cinematic look, start it any time with a key (Key Bindings > AddOns > HUD Fade) or `/hudfade pan`. Started this way, it keeps turning while you move, fight or use the UI, until you press the key again.
- The automatic pan waits during combat. Both wait during cinematics and vehicles, and leave the camera to DynamicCam's rotation or ElvUI's AFK screen while they turn it.

## 1.3.0

- New **Elements** page in the settings (or `/hudfade elements`): choose, part by part, what happens to the HUD while it is hidden. Each part (action bars, menu and bags, XP bars, cooldown manager, cast bar, player, target, party and raid, boss frames, buffs, chat, minimap, quest tracker, damage meters, boss mod timers) has a State: **Hidden** with the rest, **Shown on mouseover**, or **Always visible**. It works with the game's own UI, EllesmereUI, ElvUI, Bartender4 and Dominos.
- **Shown on mouseover**: a hidden part fades in while your mouse is over its spot, even after you hide the HUD with your Hide UI key, and its tooltips show too. Action bars come back one at a time, only the bar under the mouse, or all together with One at a time unticked.
- **Notifications** that hide with the HUD can stay instead: zone names, raid warnings and boss emotes, errors and quest progress, toasts and banners, the breath bar, loss of control and talking heads.
- **In combat** column: untick a part and a fight that starts while the HUD is hidden brings back only the ticked parts, while the rest stays hidden. Nameplates have their own box.
- Names, nameplates, the target circle and damage numbers moved to the Elements page, under Game world. The main page keeps the preset menu and a button to the Elements page.
- The Minimap box under "also hide" is now the Minimap row on the Elements page. If you had it unticked, the minimap stays always visible as before.

## 1.2.1

- Immersion's quest and gossip window now counts as a window, so the HUD comes back and the dialogue stays on screen. It used to fade away with the HUD. With Immersion's own Hide interface option on, the UI stays hidden while you talk, as Immersion intends.
- The new friends list (the Social window) and any other game window HUD Fade didn't know by name now count as windows too.
- Pixel shift steps aside, and the HUD stays visible, while you move frames with ElvUI's movers or unlocked Bartender4 or Dominos bars, as it already did for Edit Mode and EllesmereUI.
- Controllers: running with the movement stick or pressing jump now counts as activity, so the HUD no longer hides while you play with a controller. The camera stick counts only with Camera movement ticked, like the mouse.
- DynamicCam: when one of its situations dims the UI (Fade Out UI), your Hide UI key and idle hiding still hide the HUD fully, and showing it comes back to DynamicCam's dim. When the situation ends, the UI goes to what HUD Fade wants instead of flashing back for a second. 3D portraits now dim along with the rest of the UI, and a tooltip DynamicCam keeps visible stays closed while the HUD is hidden. `/hudfade why` mentions the dim.
- 3D portraits whose addon resets their opacity while the HUD is hidden (ElvUI does) no longer blink back for a moment.

## 1.2.0

- New **welcome window** on your first login with HUD Fade (and once for everyone updating): choose how long before the HUD hides when idle and when you're AFK, what else to hide, HUD-free Print Screen and pixel shift, and see which keys do what (keys are set in the game's Key Bindings, under AddOns). Open it again any time with `/hudfade welcome`. It replaces the chat message on first login.
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
