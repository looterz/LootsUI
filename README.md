# Loot's UI

Hide and show interface frames with macro conditionals, on every flavor of World of Warcraft.

Give a frame a rule like `[mod:ctrl][combat] show; hide` and Loot's UI keeps it out of the way
until you want it. Action bars, unit frames, the minimap, bags, the objective tracker and more,
each with its own rule. On top of the game's own conditionals, LootsUI adds a few of its own,
so a rule can react to things the macro system has no idea about.

LootsUI was heavily inspired by [DinksUI](https://github.com/Duenke/DinksUI/tree/main), which
showed how well macro conditionals work for driving what your interface shows. It was built to
take that idea further, with a set of custom conditions of its own and support for every flavor
of the game.

## Getting started

1. Type `/loots` to open the options.
2. Pick a preset from the Presets tab to see it working, or go straight to a tab and write your
   own rules.
3. Frames with an empty box are left alone.

Presets overwrite the rules in the current profile, so make a profile first if you want to keep
what you have. Profiles live in the Profiles tab and can differ per character.

## Commands

| Command | Result |
| --- | --- |
| `/loots` | Opens the options |
| `/loots show` | Reveals everything without losing your rules |
| `/loots hide` | Puts your rules back in charge |
| `/loots toggle` | Flips between the two, handy in a macro |
| `/loots status` | Prints the rule in effect for each frame |
| `/loots debug` | Prints what LootsUI thinks is true right now |

`/lootsui` works the same as `/loots`.

## Writing rules

A rule is a list of conditions and what to do when they match.

```
[condition] show; hide
[condition] hide; show
```

Several bracket groups in a row mean **or**, so `[mod:ctrl][combat] show; hide` matches if
either is true. Commas inside one group mean **and**, so `[combat,damaged]` needs both. The
last part of a rule with no brackets is the fallback, which is why `show; hide` reads as "show
when something above matched, otherwise hide".

Your rule is handed to the game's own macro parser, so **anything valid in a macro is valid
here**, including `[mod:alt]`, `[flying]`, `[group:raid]`, `[form:1]` and `[@target,exists]`.
The full reference is the [macro conditionals
documentation](https://warcraft.wiki.gg/wiki/Macro_conditionals), with more background in the
[macro documentation](https://warcraft.wiki.gg/wiki/Macro).

## LootsUI conditions

These are added by LootsUI. Mix them with the game's own conditionals freely, use them inside
the same brackets, and put `no` in front of any of them to invert it.

### Health

| Condition | True when |
| --- | --- |
| `[damaged]` | Your health is below maximum |
| `[damaged:70]` | Your health is below 70 percent |

### Resources

| Condition | True when |
| --- | --- |
| `[resource]` | Your resource is below maximum |
| `[resource:90]` | Your resource is below the percent you give |
| `[noresource]` | Your resource is completely empty |
| `[fullresource]` | Your resource is full |

Resource means whatever your character is running on at that moment, mana, rage, energy, focus
or runic power, so one rule covers every class. It follows a druid through its forms, reading
energy in cat and mana in caster.

### Target

| Condition | True when |
| --- | --- |
| `[hastarget]` | You have something targeted |
| `[notarget]` | You have nothing targeted |

### Location

| Condition | True when |
| --- | --- |
| `[instance]` | You are in an instance |
| `[instance:raid]` | You are in an instance of that type, such as party, raid, pvp or arena |

Some things you might expect here are already in the game and need nothing from LootsUI:
`[stealth]`, `[resting]`, `[mounted]`, `[flying]`, `[indoors]`, `[group:raid]` and `[form:1]` all
work as written. For death, `[dead]` reads your target, so use `[@player,dead]` for yourself and
`[@player,nodead]` for alive. Prefer these where they exist, since the game evaluates them
itself and can hide frames outright.

The Help tab in game lists the same set, generated from what is actually installed, so it is
never out of date.

## Examples

| Rule | Effect |
| --- | --- |
| `[combat][mod:alt] show; hide` | Action bars during a fight, or whenever you hold alt |
| `[mod:ctrl][combat][damaged] show; hide` | Player frame when it matters, gone when it does not |
| `[hastarget] show; hide` | Target frame only when you actually have a target |
| `[combat][resource:35] show; hide` | Resource bar in combat or when you are running dry |
| `[stealth,nocombat] hide; show` | A clean screen while you are sneaking around |
| `[resting,nomod] hide; show` | Quiet interface in town, back with a modifier |
| `[instance:raid] show; hide` | Raid frames only inside raids |

## Fading

Frames can snap or fade. Fading is the default, a tenth of a second each way. The Fading tab
changes that and the timings, and any frame can be set to its own Instant or Fade regardless of
the default.

One thing to know: a frame hidden by a fade, or by any rule using a LootsUI condition, goes
transparent rather than fully hidden, so it can still catch a mouse click in the space it
occupied. Rules built only from the game's own conditionals hide frames outright.

That split is not a preference, it is what the game allows. Only the transparent route can
react during a fight, because addons are not permitted to re-register a visibility rule once
combat has started.

Fades interrupt cleanly, so a frame caught half way through fading out reverses from where it
is rather than starting over.

## Keybinding

Binding a key means hovering the button you want to bind, which is impossible if the bar is
hidden. So while the game's Quick Keybind Mode is open, LootsUI reveals everything, and hands
control back to your rules the moment you leave it. Nothing to turn on.

This follows the mode itself rather than any particular addon, so it works whether you got there
from the Key Bindings panel or with
[QuickKeybindMode](https://github.com/looterz/QuickKeybindMode)'s `/kb`.

## Supported clients

| Client | TOC | Interface |
| --- | --- | --- |
| Retail | `LootsUI.toc` | 120007 |
| Classic Era, Season of Discovery, Hardcore | `LootsUI_Vanilla.toc` | 11509 |
| Anniversary (Burning Crusade) | `LootsUI_TBC.toc` | 20506 |
| Wrath Titan Reforged | `LootsUI_Wrath.toc` | 38001 |
| Classic (Mists of Pandaria) | `LootsUI_Mists.toc` | 50504 |

A frame that does not exist in the client you are playing is greyed out in the options rather
than causing errors.

If Questie is installed, its tracker is covered by the Objective Tracker rule alongside the
game's own, so one rule handles both.

## Credits

Heavily inspired by [DinksUI](https://github.com/Duenke/DinksUI/tree/main) by Duenke, which is
where the idea of driving frame visibility with macro conditionals comes from. LootsUI exists to
carry that further: custom conditions such as `[damaged]`, `[resource:90]`, `[hastarget]` and
`[instance]` that the macro system has no equivalent for, and one addon that runs on Classic Era,
Anniversary, Wrath Titan Reforged, Mists Classic and retail alike.
