# PureFade

**PureFade** is a lightweight, zero-dependency UI fading addon for **World of Warcraft Forever (`Interface: 16001`)**. It smoothly fades away unused UI elements while you explore the world and brings them back only when you need them — on hover, combat, targeting, vital changes, location context, or temporary peeks.

## Highlights

- **Zero Dependencies & Combat-Safe:** Uses pure `SetAlpha` fading with zero Ace3/LibStub bloat and full protection against WoW Forever secret values.
- **Granular UI Control:** Fade Action Bars, Unit Frames, Personal Resource Display, Buffs, Debuffs, Minimap (including smooth player-arrow scaling and individual minimap parts), Quest Tracker, Chat, Cooldown Manager, Damage Meter, and more.
- **Smart Triggers:**
  - **Core:** In Combat (with configurable Combat Fade-Out Delay), Enemy Targeted (living targets only — looting corpses won't pull up your UI), Friendly Targeted.
  - **Vitals:** Health Not Full, Power Not Full (including Rage/Runic Power draining), Pet Health Not Full, Pet Not Happy (Hunter), Has Any Debuff, Short / Expiring Buffs.
  - **Context & Minimap:** Group/Raid, Instance, City/Resting, Open World, Casting, Mounted, Flight Path, In Vehicle, Tracking Active, Unread Mail, Indoors, Minimap Ping.
  - **Smart Peeks:** In-place **Single-Buff Peek** (only newly gained/refreshed or expiring buffs appear in place), **New Chat Message Peek** (clean active-tab overlay without background box), and **Quest Progress / Change Peek**.
- **QoL Auto-Reveals & Immersion Polish:** Automatically pauses in Blizzard Edit Mode, respects cutscenes/`Alt+Z`, ignores hover while rotating the camera, suppresses tooltips on hidden frames, reveals relevant frames for Spellbook/Dragging/Bags/Chat Typing, suppresses triggers while Dead / Ghost, and includes a native **Hold to Peek All UI** keybinding.
- **Groups, Per-Element Opacity & Hover Buffer:** Link elements into groups (e.g. Action Bars, Unit Frames, Minimap) with adjustable Mouseover Buffer reach, optional Hover Reveal Delay, per-element Faded Opacity overrides, and a 1-click **UI Layout** preset (**Blizzard Default UI** vs. **Separated Menu & Bags**).
- **3rd-Party Addon Support + Visual Frame Picker:** Built-in support for **Bartender4** (per-bar), **Dominos** (per-bar), **Questie**, **Details!**, **Recount**, **Skada**, **RXPGuides**, **TomTom** (independent Crazy Arrow & Coordinates), **MinimapButtonButton**, **Titan Panel**, **RareScanner**, **HealBot**, **BigWigs**, and **DBM** — plus a 1-click **Pick Frame on Screen** button on both Elements and Addons pages.
- **Profiles & Sharing:** Per-character profiles, a pristine **Default** profile (editing automatically saves to **Custom**), and popup **Export / Import (`PF1:...`)** strings to share setups.

## Slash Commands

- `/purefade` — Open PureFade settings (`Options → AddOns → PureFade`)
- `/purefade toggle` — Temporarily reveal all faded UI at 100% (or resume fading)
- `/purefade why [filter]` — Diagnostic printout showing why matching elements are currently visible or faded

## License

Released under the [MIT License](LICENSE).
