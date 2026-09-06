# SimpleFrame

Minimal player and target unit frames for World of Warcraft retail.

Flat health and power bars, a cast bar, a target-of-target bar, and Blizzard's
own buff/debuff icons borrowed onto the target frame. No libraries, no media
files, no dependencies.

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
- **Target frame** — health and power bars, name and level, health text, a
  classification line above the frame (`Rare Elite Beast`, `Boss Dragonkin`,
  `Night Elf Druid`), and a yellow `!` for enemies that count toward a quest.
- **Target auras** — Blizzard's own aura display, stripped off its frame and
  parked on this one, with sliders for scale and position. It works in combat,
  which no addon-drawn alternative can — see below.
- **Leader and assist markers** — Blizzard’s own leader and assistant icons,
  on the player and target frames.
- **Raid group number** in the middle of the player frame, while in a raid.
- **Talent loadout name** in the band above the player frame, falling back to
  the specialization when no named loadout is active — replaced by the
  **elapsed combat time** while fighting.
- **Pet frame** — health and power bars at three-quarter size, independently
  movable, shown only while you have a pet.
- **Target of target** — a health bar stacked against the target frame at the
  same width, at 70% height, on whichever side the buff row is not using.
- **Incoming heals and absorbs** overlaid on the health bars: the fill reads as
  current health, then incoming heals, then shield.
- **Top backdrop** — optional dark backing behind the band above the frame.
- **Flat bars** — solid single-color fills, no gradient, no border art.
- **Class-colored health** for players, reaction-colored for NPCs; grey when
  dead or disconnected.
- **Blizzard's player frame is left alone** until you opt in to hiding it. Its
  target frame is always borrowed, for the auras.

### Aura layout

Which side the buffs take is **Blizzard's Edit Mode setting**, not a SimpleFrame
one: Edit Mode → Target Frame → *Buffs on top*. SimpleFrame has no checkbox for
it, because an addon cannot write it — see below.

SimpleFrame reads it and puts the target-of-target bar on the other side, so the
two never compete for the same strip. With the bar above the frame it parks
beyond the classification line, leaving that line welded to the bars it
describes. Change it in Edit Mode and the bar moves as you leave.

## Usage

| Command | Effect |
|---|---|
| `/sf` | Open the settings panel (also under Options → AddOns → SimpleFrame) |
| `/sf unlock` | Show green drag boxes; drag to reposition |
| `/sf lock` | Save positions and hide the drag boxes |
| `/sf reset` | Restore the default positions |

Left-click a frame to target the unit, right-click for the unit menu.

The drag boxes swallow clicks, so targeting resumes once you `/sf lock`. The
aura icons are Blizzard's and are positioned by their own offset sliders, not by
dragging.

## Settings

Options → AddOns → SimpleFrame, or `/sf`.

| Group | Settings |
|---|---|
| Frames | Player frame, target frame, pet frame, target of target |
| Bars | Frame width, health bar height, power bar height, scale, health text (none / value / percent / both), class colored health, incoming heals and absorbs |
| Cast bars | Player cast bar, target cast bar |
| On the frame | Combat indicator, raid group number |
| Above the frame | Top backdrop, talent loadout, combat timer, target classification, quest indicator, leader and assist |
| Target auras | Aura scale, aura offset X, aura offset Y |
| Default Blizzard frames | Hide Blizzard player frame |

Sections are grouped by where a setting shows up on the frame.

Frame positions are set by dragging, not in the panel.

## Target auras

On 12.x an addon is refused access to a unit's auras once they are secret —
`"Auras cannot be accessed when secret while tainted by ..."` — which in
practice is every target in combat. Blizzard's own code is not tainted, so its
aura display keeps working.

So SimpleFrame does not draw aura icons. `TargetFrame` stays alive but is
stripped down to its `Auras` container alone — portrait, border art, name,
level, health and mana bars all hidden — and parked on the SimpleFrame target
frame. Scale and two offset sliders place the icons, since Blizzard positions
them relative to its own frame.

Earlier versions offered addon-drawn icons as an alternative. They only ever
worked out of combat, which is when target auras matter least, so they are gone
along with their settings. Anything left in your saved variables from them is
pruned on load.

Three consequences of borrowing the whole frame:

- **The target cast bar is Blizzard's.** It comes along with the frame, and
  animates its own alpha while fading, so it overwrites any attempt to hide it
  and reappears in combat. SimpleFrame draws no target cast bar of its own; the
  player cast bar is unaffected.
- **Blizzard's target frame cannot also be hidden**, since hiding it would take
  the aura display with it. Only the player frame has a hide toggle.
- **The buff side is set in Edit Mode**, not here. Writing `TargetFrame`'s
  `buffsOnTop` field, or mirroring its aura container directly, taints the
  container; Blizzard's next layout pass then compares `numVisibleAuraRows` — a
  secret — and raises inside its own dirty-flag processing, which can leave the
  aura display stuck until you reload. So SimpleFrame reads the setting and
  never writes it.

Turning the SimpleFrame target frame off leaves Blizzard's alone from then on,
but a frame already stripped stays stripped until a `/reload`.

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
- **Auras are not read, and the borrowed display is not reconfigured.** Every
  enumeration API — `GetAuraDataByIndex`, `GetAuraSlots`,
  `C_UnitAuras.GetUnitAuras` — is refused once a unit's auras are secret, so
  Blizzard's own display is borrowed instead. Its container is only ever moved
  and scaled from the outside; calling a layout setter *on* it taints it, and
  Blizzard's own code then raises on a secret row count.
- Incoming heals and absorbs come from `CreateUnitHealPredictionCalculator`,
  which does the arithmetic engine-side. **Addition on a secret raises just as
  comparison does** — a secret may only be passed to a widget setter, never
  operated on. So the overlays are anchored to the health bar's own fill texture,
  whose right edge already marks where the fill ends, and scaled against
  `GetMissingHealth()`. They are shown or hidden with `SetAlpha(amount)`, which
  resolves to 0 for a zero amount and clamps to 1 for any positive one — the only
  way to ask "is there any" without comparing.

If you are extending this addon, read `Secrets.lua` first — it is the shortest
path to not reintroducing these errors.

## Layout

| File | Contents |
|---|---|
| `Secrets.lua` | Secret-value guards; loaded first |
| `Core.lua` | Saved variables, defaults, lifecycle events, drag mode, slash commands |
| `UnitFrame.lua` | Secure unit button factory: bars, texts, cast bar, layout |
| `Blizzard.lua` | Hiding the default player frame, and borrowing the target's aura display |
| `Options.lua` | Settings panel registration |
| `Icon.tga` | Addon list icon, referenced by `## IconTexture` |

## License

[MIT](LICENSE) — Copyright (c) 2026 Daniel Rabe.
