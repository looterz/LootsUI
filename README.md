# Loot's UI

Hide and show interface frames with macro conditionals, on every flavor of World of Warcraft.

Give a frame a rule like `[mod:ctrl][combat] show; hide` and Loot's UI keeps it out of the way
until you want it. Action bars, unit frames, the minimap, bags, the objective tracker, the
cooldown manager, the damage meter and more, each with its own rule. On top of the game's own conditionals, LootsUI adds a few of its own,
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

Presets overwrite the rules in the active profile, and ask before doing it. See the Profiles
section below for keeping settings per character and backing them up.

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

### Combat

| Condition | True when |
| --- | --- |
| `[lastcombat]` | You are in combat, or left it fewer than eight seconds ago |
| `[lastcombat:15]` | You are in combat, or left it fewer than the given seconds ago |
| `[recentcombat]` | The same as `[lastcombat:8]`, for rules that read better without a number |

The game's own `[combat]` cuts off the instant a fight ends. These keep a frame around for a
moment afterwards, so the cast bar, cooldowns or a damage meter do not vanish while you are
still looking at them. Use `[nolastcombat:30]` to mean "well out of combat".

### Health

| Condition | True when |
| --- | --- |
| `[damaged]` | Your health is below maximum |
| `[damaged:70]` | Your health is below 70 percent |

Retail and World of Warcraft: Forever sometimes keep health and resource numbers back from
addons, in PvP matches for instance. While they do, `[damaged]` and the resource conditions read
as false rather than guessing, and `/loots debug` says the value is hidden by the game. On
Forever the numbers are hidden most of the time, so build rules there on `[recentcombat]` and
the game's own conditionals instead.

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
| `[recentcombat][mod:alt] show; hide` | The same, but they linger eight seconds after the fight |
| `[lastcombat:20] show; hide` | Damage meter during a fight and for twenty seconds after |
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

One thing to know: most frames go transparent rather than fully hidden, so they can still catch
a mouse click in the space they occupied. Only protected frames, the action bars and unit frames
the game guards during combat, are hidden outright, and only when their rule is built from the
game's own conditionals with fading off.

That split is not a preference, it is what the game allows. A protected frame can only be hidden
in combat by the game itself, which is why those go through a rule the game evaluates. Every
other frame is left exactly where the game put it and faded, because moving it under an addon
frame taints the game's own code on modern clients and breaks things like the damage meter.

Fades interrupt cleanly, so a frame caught half way through fading out reverses from where it
is rather than starting over.

## Profiles

Every character starts on the shared Default profile, so a change made there follows all of
them. To give one character its own settings, open the Profiles tab and branch: the new profile
starts as a copy of what you have and only shows up for that character, so the rest stay on
Default.

The same tab has the rest of the toolbox: create a profile with a name of your own, duplicate
the active one, rename it, reset it, or delete one you no longer want. Copy settings from
pulls another profile's setup into the active one, including another character's, handy when
two characters share similar UI needs. Exports turn the active profile into plain text you can
save anywhere or send to a friend, and imports load one back in. Anything destructive asks
first: importing, copying over, resetting, renaming, deleting and applying a preset all
confirm before touching your rules.

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
| Retail | `LootsUI.toc` | 120100 |
| World of Warcraft: Forever | `LootsUI_Camelot.toc` | 16001 |
| Classic Era, Season of Discovery, Hardcore | `LootsUI_Vanilla.toc` | 11509 |
| Anniversary (Burning Crusade) | `LootsUI_TBC.toc` | 20506 |
| Wrath Titan Reforged | `LootsUI_Wrath.toc` | 38001 |
| Classic (Mists of Pandaria) | `LootsUI_Mists.toc` | 50504 |

A frame that does not exist in the client you are playing is greyed out in the options rather
than causing errors.

World of Warcraft: Forever runs the modern interface, so everything Retail has is there to
hide, including the Cooldown Manager and the Damage Meter. While it is in beta the game also
loads Blizzard's Issue Reporter, a report button parked on screen with no option to move or
hide it. It has a rule of its own under Interface, so `hide` alone puts it away and
`[mod:ctrl] show; hide` brings it back when you actually want to file something.

If Questie is installed, its tracker is covered by the Objective Tracker rule alongside the
game's own, so one rule handles both.

## Credits

Heavily inspired by [DinksUI](https://github.com/Duenke/DinksUI/tree/main) by Duenke, which is
where the idea of driving frame visibility with macro conditionals comes from. LootsUI exists to
carry that further: custom conditions such as `[recentcombat]`, `[damaged]`, `[resource:90]`, `[hastarget]` and
`[instance]` that the macro system has no equivalent for, and one addon that runs on Classic Era,
Anniversary, Wrath Titan Reforged, Mists Classic, World of Warcraft: Forever and retail alike.
