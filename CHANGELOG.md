# Changelog

## v1.0.0
- Initial public release of **PureFade** for World of Warcraft Forever (`16001`).
- Zero-dependency, combat-safe UI fading engine with smooth fade-in, separate Combat Fade-In Duration, fade-out, hover hold, and configurable Mouseover Buffer reach.
- Comprehensive built-in Blizzard UI coverage: Action Bars, Unit Frames (including Personal Resource Display), Group & PvP, Minimap (with smooth 3D arrow/dot scaling and indoor redraw fix), Buffs & Debuffs (independent elements with in-place single-buff peek), Cast Bar, Quest Tracker, Cooldown Manager, Damage Meter, Chat (with zero-dip active-tab message peek), and Gamepad frames.
- Smart Triggers across **Core** (In Combat + Fade-Out Delay, Living Enemy Targeted, Friendly Targeted), **Vitals** (Health/Power/Pet Health thresholds, Hunter Pet Happiness, Debuff active, Short/Expiring Buffs), **Context** (Group, Instance, City/Resting, Open World, Casting, Mounted, Flight Path), **Minimap** (Tracking Active, Unread Mail, Indoors, Minimap Ping), and **Peek** (New Chat Message, Buff Changed, Quest Progress/Change).
- Automatic QoL reveals for Spellbook, Cursor Dragging, Bags Open, and Chat Typing.
- Element **Groups** with Hover-Only or Full Trigger Sync.
- Built-in 3rd-party addon support (**Bartender4** granular per-bar control, **Questie**, **Details!**, **RXPGuides**, **TomTom**, **MinimapButtonButton**, **Titan Panel**, **RareScanner**, **HealBot**, **BigWigs**, **DBM**) plus a 1-click **Visual Frame Picker** for any custom frame.
- Native `Options → AddOns → PureFade` UI with universal Search, read-only immutable **Default** profile, and **Profile Export / Import (`PF1:...`)**.
