# SimpleFrame

Minimal player and target unit frames for World of Warcraft retail (Interface 120100).
Plain health and power bars, a cast bar, a target-of-target bar, and buff/debuff
icons on the target. No libraries, no media files.

## Features

- **Player frame** — health bar, power bar, name/level, health text, cast bar.
- **Target frame** — same, plus aura icons: all buffs above the frame, your own
  debuffs below it, with cooldown swipe, stack counts, and dispel-type borders.
- **Target of target** — small health bar to the right of the target frame.
- Health bars are class-colored for players and reaction-colored for NPCs.
- The default Blizzard frames are left alone until you opt in to hiding them.

## Usage

| Command | Effect |
|---|---|
| `/sf` | Open the settings panel (also under Options → AddOns → SimpleFrame) |
| `/sf unlock` | Show green drag boxes; drag to reposition |
| `/sf lock` | Save positions and hide the drag boxes |
| `/sf reset` | Restore the default positions |

Left-click a frame to target the unit, right-click for the unit menu.

## Notes

- **Hiding the Blizzard frames is off by default.** Enable it under
  *Default Blizzard frames* in the settings panel. Turning it back **off**
  requires a `/reload` — the frames are unregistered and reparented, which
  cannot be cleanly undone at runtime.
- Layout changes that touch secure frames are deferred while you are in combat
  and applied as soon as you leave it. The same applies to `/sf unlock`.
- Target-of-target polls every 0.2s, because the `targettarget` unit token does
  not fire `UNIT_*` events.

### Midnight secret values

WoW 12.0 hides combat-relevant numbers behind *secret values*. Addon code may
hand them to a widget (`StatusBar:SetValue`, `FontString:SetFormattedText`,
`AbbreviateNumbers`) but any Lua comparison, arithmetic, `string.format`, or
table lookup keyed on one raises an error. `Secrets.lua` holds the guards; the
practical consequences are:

- Health and power **bars** are always accurate — the values go straight to the
  status bar untouched.
- Health **percentage** comes from `UnitHealthPercent`, which evaluates the
  ratio engine-side.
- Aura enumeration is *refused* in restricted contexts (in combat, and in
  Mythic+ even out of combat). When that happens the target aura icons simply
  disappear until the restriction lifts — this is a client limitation, not a
  bug in the addon.
- Cooldown swipes and stack counts are dropped for any aura whose timings come
  back secret; the icon still shows.

## Files

| File | Contents |
|---|---|
| `Core.lua` | Saved variables, defaults, lifecycle events, slash commands |
| `UnitFrame.lua` | Secure unit button factory: bars, texts, cast bar, layout |
| `Auras.lua` | Target buff/debuff icon grid |
| `Blizzard.lua` | Opt-in hiding of the default frames |
| `Options.lua` | Settings panel registration |
