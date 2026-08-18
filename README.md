# SimpleFrame

Minimal player and target unit frames for World of Warcraft retail.

Flat health and power bars, a cast bar, a target-of-target bar, and buff/debuff
icons on the target — with the option to hide Blizzard's frames entirely. No
libraries, no media files, no dependencies.

**Requires:** WoW retail 12.x (Midnight), Interface `120100`.

## Install

1. Download the repository as a ZIP, or clone it.
2. Put the `SimpleFrame` folder into
   `World of Warcraft/_retail_/Interface/AddOns/`.
3. Restart the game, or `/reload` if it is already running.

The folder must be named exactly `SimpleFrame`, matching `SimpleFrame.toc` — WoW
locates an addon by that pairing. If you used GitHub's *Download ZIP*, the
archive contains a `SimpleFrame-main` wrapper folder; move the inner folder out
and rename it, otherwise the addon will not appear in the addon list.

Your settings and frame positions are stored in
`WTF/Account/<ACCOUNT>/SavedVariables/SimpleFrame.lua`, outside the addon
folder, so updating is a straight overwrite.

## Features

- **Player frame** — health bar, power bar, name and level, health text, cast bar,
  and a 1px red outline around the frame while you are in combat.
- **Target frame** — the same, plus aura icons with cooldown swipe, stack counts
  and dispel-colored borders, and a classification line above the frame
  (`Rare Elite Beast`, `Boss Dragonkin`, `Night Elf Druid`).
- **Pet frame** — health and power bars at three-quarter size, independently
  movable, shown only while you have a pet.
- **Target of target** — a small health bar to the right of the target frame.
- **Flat bars** — solid single-color fills, no gradient, no border art.
- **Class-colored health** for players, reaction-colored for NPCs; grey when
  dead or disconnected.
- **Blizzard's frames are left alone** until you explicitly opt in to hiding them.

### Aura layout

The rows swap depending on who you are looking at, so the auras you care about
are always the ones on top:

| Target | Above the frame | Below the frame |
|---|---|---|
| Hostile | All buffs | Only the debuffs **you** applied |
| Friendly | All debuffs (what you would dispel) | All buffs |

## Usage

| Command | Effect |
|---|---|
| `/sf` | Open the settings panel (also under Options → AddOns → SimpleFrame) |
| `/sf unlock` | Show green drag boxes; drag to reposition |
| `/sf lock` | Save positions and hide the drag boxes |
| `/sf reset` | Restore the default positions |

Left-click a frame to target the unit, right-click for the unit menu.

While unlocked, dimmed placeholder icons show where the aura rows will sit, so
you can position against the full footprint even with nothing targeted. The drag
boxes swallow clicks, so targeting resumes once you `/sf lock`.

## Settings

Options → AddOns → SimpleFrame, or `/sf`.

| Group | Settings |
|---|---|
| Frames | Player frame, target frame, pet frame, target of target, player cast bar, target cast bar, target auras, target classification, combat indicator, class colored health |
| Size | Frame width, health bar height, power bar height, scale, health text (none / value / percent / both) |
| Auras | Aura icon size, auras per row |
| Target auras from Blizzard | Use Blizzard target auras, aura offset X, aura offset Y |
| Default Blizzard frames | Hide Blizzard player frame, hide Blizzard target frame |

Frame positions are set by dragging, not in the panel.

## Target auras in combat

On 12.x an addon is refused access to a unit's auras once they are secret —
`"Auras cannot be accessed when secret while tainted by ..."` — which in
practice is every target in combat. Blizzard's own code is not tainted, so its
aura display keeps working.

**Use Blizzard target auras** (Options → AddOns → SimpleFrame) works around
this: `TargetFrame` stays alive but is stripped down to its `Auras` container
alone — portrait, border art, name, level, health and mana bars all hidden — and
parked on the SimpleFrame target frame. Two offset sliders nudge the icons into
place, since Blizzard positions them relative to its own frame.

This overrides *Hide Blizzard target frame*, which would otherwise take the
aura display down with it. With it off, SimpleFrame draws its own aura icons,
which work out of combat only.

## Click-casting

All three frames register with the standard `ClickCastFrames` registry, so
**Clique** and any addon following the same convention can bind spells to them
with no extra setup — they show up alongside the Blizzard frames in Clique's
frame list.

Bindings take priority over the addon's own click behavior. A button Clique has
bound runs that binding; anything unbound still left-clicks to target and
right-clicks for the unit menu.

## Notes

- **Hiding the Blizzard frames is off by default.** Turning it back **off**
  requires a `/reload` — the frames are unregistered and reparented to a hidden
  holder, which cannot be cleanly undone at runtime.
- Anything touching secure frames is deferred while you are in combat and
  applied as soon as you leave it. `/sf unlock` refuses outright in combat.
- Target-of-target polls every 0.2s, because the `targettarget` unit token does
  not fire `UNIT_*` events.

### Midnight secret values

WoW 12.0 hides combat-relevant numbers behind *secret values*. Addon code may
hand them to a widget (`StatusBar:SetValue`, `FontString:SetFormattedText`,
`AbbreviateNumbers`) but any Lua comparison, arithmetic, `string.format`, or
table lookup keyed on one raises an error. `Secrets.lua` holds the guards. The
practical consequences:

- Health and power **bars** are always accurate — values go to the status bar
  untouched.
- Health **percentage** comes from `UnitHealthPercent`, which evaluates the
  ratio engine-side.
- Auras come from `C_UnitAuras.GetUnitAuras`. The older enumeration APIs
  (`GetAuraDataByIndex` and `GetAuraSlots`) both *raise* once a unit's auras are
  secret — `"Auras cannot be accessed when secret while tainted by ..."` — which
  in practice is every target in combat, so neither can be used. The slot walk
  remains only as a fallback for clients that predate `GetUnitAuras`.
- Compound filters like `HARMFUL|PLAYER` return nothing through that API, so
  "only my debuffs" is applied afterwards from each aura's
  `isFromPlayerOrPlayerPet`. That check fails open: an unreadable source shows
  the aura rather than hiding it.
- Cooldown swipes and stack counts are dropped for any aura whose timings come
  back secret; the icon still shows.

If you are extending this addon, read `Secrets.lua` first — it is the shortest
path to not reintroducing these errors.

## Layout

| File | Contents |
|---|---|
| `Secrets.lua` | Secret-value guards; loaded first |
| `Core.lua` | Saved variables, defaults, lifecycle events, drag mode, slash commands |
| `UnitFrame.lua` | Secure unit button factory: bars, texts, cast bar, layout |
| `Auras.lua` | Target buff/debuff icon grid and drag placeholders |
| `Blizzard.lua` | Hiding the default frames, and borrowing their aura display |
| `Options.lua` | Settings panel registration |
| `Icon.tga` | Addon list icon, referenced by `## IconTexture` |

## License

[MIT](LICENSE) — Copyright (c) 2026 Daniel Rabe.
