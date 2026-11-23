# Changelog

## v1.0.3
- **UI Layout Preset (Groups Page):** Added a 1-click **UI Layout** selector (**Blizzard Default UI** vs. **Separated Menu & Bags (Custom UI)**) to switch Micro Menu & Bags Bar between the unified Blizzard bottom bar and a dedicated Hover-Only corner group (works automatically with Edit Mode and Bartender4).
- **Action Bars Group Sync:** Switched the **Action Bars** default group to **Sync: Hover + Triggers** and cleared standalone Combat/Target triggers from **Micro Menu** and **Bags Bar** so they reveal cleanly with the Blizzard bottom bar and become hover-only as soon as unlinked.
- **Default Profile Polish:**
  - Set **Power Not Full** threshold to `< 90%` by default so casting a buff or two won't reveal the Player Frame.
  - Set **Focus Frame** and **Focus Target** to **Always** by default (matching Target Frame).
  - Widened the group sync button on the **Groups** page so `Sync: Hover + Triggers` displays without truncation.

## v1.0.2
- Enabled **In Combat** and **Enemy Targeted** triggers by default for **Micro Menu** and **Bags Bar** on the Default profile.

## v1.0.1
- **Copy-on-Write Profiles:** Edit any setting immediately while on **Default** — your first change automatically forks into **Custom** while keeping **Default** pristine. Switching back to **Default** and editing starts fresh from **Default**.
- **Redesigned Profiles & Groups Pages:** Switched to clean native WoW dropdowns (`Active Profile`, `Login Behavior`) and popup dialogs for Create, Rename, Delete, Export, and Import — removing always-visible text boxes. Renamed group "Members" to **Elements**, added group **Rename**, and improved card spacing.
- **Dead / Ghost Fade & Ghost Debuff Filter:** Added **Suppress automatic triggers while Dead / Ghost** (enabled by default) and filtered out the **Ghost** debuff (`spellId 8326`) from *Has Any Debuff*, keeping corpse runs clean and hover-only while preserving chat peeks and Always Show elements.
- **TomTom Split:** Split TomTom into independent **TomTom Crazy Arrow** (Always Show by default) and **TomTom Coordinates** (Follow: Minimap).
- **Elements Visual Frame Picker:** Replaced the manual `/fstack` text box on the **Elements** page with the 1-click **Pick Frame on Screen** button plus an optional **Add by Name** popup.
- **UI & Quality-of-Life Polish:**
  - Swapped Addon Compartment clicks: **Left-Click** to Pause/Resume, **Right-Click** to Open Settings.
  - Disabled the **Show When (Triggers)** button whenever **Always** is checked (saved triggers are preserved if unchecked).
  - Tuned Default profile defaults: **Quest Peek** `6s`, **Minimap Ping Peek** `5s`, and **Reveal Bags Bar when Bags are open** off by default.

## v1.0.0
- Initial public release of **PureFade** for World of Warcraft Forever (`16001`).
- Zero-dependency, combat-safe UI fading engine with smooth fade-in, separate Combat Fade-In Duration, fade-out, hover hold, and configurable Mouseover Buffer reach.
- Comprehensive built-in Blizzard UI coverage: Action Bars, Unit Frames (including Personal Resource Display), Group & PvP, Minimap (with smooth 3D arrow/dot scaling and indoor redraw fix), Buffs & Debuffs (independent elements with in-place single-buff peek), Cast Bar, Quest Tracker, Cooldown Manager, Damage Meter, Chat (with zero-dip active-tab message peek), and Gamepad frames.
- Smart Triggers across **Core** (In Combat + Fade-Out Delay, Living Enemy Targeted, Friendly Targeted), **Vitals** (Health/Power/Pet Health thresholds, Hunter Pet Happiness, Debuff active, Short/Expiring Buffs), **Context** (Group, Instance, City/Resting, Open World, Casting, Mounted, Flight Path), **Minimap** (Tracking Active, Unread Mail, Indoors, Minimap Ping), and **Peek** (New Chat Message, Buff Changed, Quest Progress/Change).
- Automatic QoL reveals for Spellbook, Cursor Dragging, Bags Open, and Chat Typing.
- Element **Groups** with Hover-Only or Full Trigger Sync.
- Built-in 3rd-party addon support (**Bartender4** granular per-bar control, **Questie**, **Details!**, **RXPGuides**, **TomTom**, **MinimapButtonButton**, **Titan Panel**, **RareScanner**, **HealBot**, **BigWigs**, **DBM**) plus a 1-click **Visual Frame Picker** for any custom frame.
- Native `Options → AddOns → PureFade` UI with universal Search, read-only immutable **Default** profile, and **Profile Export / Import (`PF1:...`)**.
