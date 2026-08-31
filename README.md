# BetterBonusRolls

BetterBonusRolls is a safety-focused World of Warcraft addon for Mainline `12.1.0` (`120100`). It filters bonus-roll offers by encounter, difficulty, dungeon, key level, Delve tier, content type, and character-specific loot specialization.

The addon is disabled by default. Enable it per character in **Options > AddOns > BetterBonusRolls** or with `/bbr enable`.

## Features

- Every click on Blizzard's Roll button opens a second confirmation, even when the configured loot specialization is already active.
- A configured offer in the wrong loot specialization remains visible and gains a compact **Loot Spec** sidecar showing the configured specialization icon. The sidecar disappears when the correct specialization is active; clicking its icon changes loot specialization only and never spends a roll.
- Clicking Blizzard's No button hides the offer without declining it. `/bbr show` restores it while the server offer remains active.
- Unconfigured offers are hidden by default while the addon is enabled.
- Every raid, Lair, dungeon, and outdoor-content rule has its own enable checkbox. Enabling a row selects `Current Spec (<name>)`; the dropdown then offers that dynamic choice followed by every direct class specialization. Disabling the row greys it and shows `Bonus roll disabled` in the locked dropdown.
- Raid and Lair rules are configured per boss, difficulty, and loot specialization. Flexible Mythic uses the Mythic rule; World remains distinct from Raid Finder.
- Current-season dungeon rules are configured per challenge map. Each has an inclusive minimum of Normal, Heroic, Mythic (M0), or `+2` through `+10`; new rules default to `+10`, and keys above `+10` use that same cap.
- Bountiful Delves use one character-wide rule, an inclusive Tier 1-11 minimum, and one loot specialization. New Delve rules default to Tier 1.
- Current-season World Bosses are configured individually by encounter. Nightmare Prey has its own fallback rule even though Blizzard reports both through the World Boss bonus-roll difficulty bucket.
- Raid, Lair, World Boss, encounter, difficulty, and dungeon lists are discovered from the current client instead of hard-coding a season. This includes raid-like Lair instances such as Tidebound Grotto when the Encounter Journal exposes their World/Normal/Heroic/Mythic variants.
- Settings are stored per character through LibSimpleDB.
- A draggable minimap button and the native AddOn Compartment entry use the addon icon and open settings only. Minimap visibility and position are stored per character, and `/bbr` remains available if the button is hidden.

## Safety contract

BetterBonusRolls never spends or permanently declines a bonus roll automatically.

A roll can reach Blizzard's native Roll handler only after both of these direct user actions:

1. Click Blizzard's Roll button on the active offer.
2. Accept BetterBonusRolls' confirmation for that exact, unchanged offer state.

The one-shot authorization is discarded if the popup is canceled, escaped, hidden, or times out; if a new offer appears; if loot specialization or a rule changes; if the frame closes; if the addon is disabled; or if any captured state no longer matches. A changed state requires a fresh click on Blizzard's Roll button. The Roll button is disabled while confirmation is pending, and authorization is consumed before Blizzard's native handler is invoked.

While enabled, Blizzard's No button only removes the frame from the group-loot container. It does not invoke Blizzard's native decline handler. A server timeout simply expires the offer and prints that it can no longer be restored.

BetterBonusRolls intentionally has no roll command, decline command, test-spend control, automatic retry, or queued roll action.

## Configuration

The main settings page contains the character-specific master switch, minimap-button visibility, and safety summary. Subcategories include:

- **Current Season Dungeons** - enable, minimum difficulty, and desired loot specialization per challenge map.
- **Outdoor Content** - one global Bountiful Delves row, one row per current-season World Boss, and a separate Nightmare Prey row.
- **One page per current-season raid or Lair** - enable and desired loot specialization per boss and supported difficulty.

Use the checkbox at the left of a row to enable or disable it. Missing rules deny automatic display while the addon is enabled. Existing schema-1 dungeon rules are migrated to the former global Mythic+ minimum, capped at `+10`. Stale SavedVariables do not apply unless their IDs occur in the current client catalog.

## Commands

- `/bbr` or `/bbr config` - open settings.
- `/bbr show` - restore a hidden active offer.
- `/bbr hide` - hide the visible offer without declining it.
- `/bbr enable` - enable the addon for this character.
- `/bbr disable` - disable the addon and restore native Blizzard button scripts.
- `/bbr status` - report addon and active-offer status.
- `/bbr help` - show command help.

## Scope and compatibility

Version 1 configures current-season raids, raid-like Lairs, current-season dungeons, Bountiful Delves, individual current-season World Bosses, and Nightmare Prey. An unverified Delve tier, an ambiguous standard-dungeon instance shared by differently configured challenge-map rows, an unknown or inconsistent World Boss encounter, or an unknown future difficulty fails closed and can still be restored manually with `/bbr show` while active.

BonusRollConfirm and BonusRollGate modify the same Blizzard controls. If either is loaded, BetterBonusRolls refuses to enable until the conflicting addon is disabled and the UI is reloaded.

## Development

LibModernSettings `1.5.0` and LibSimpleDB `2.0.0` are pinned git submodules. LibDBIcon `12.0.3`, LibDataBroker, and CallbackHandler are vendored for the minimap launcher. Clone with submodules initialized, or run:

```text
git submodule update --init --recursive
```

The release packager uses `.pkgmeta` externals and omits development tests. See [AGENTS.md](AGENTS.md) for invariants and validation commands.

## License

BetterBonusRolls is available under the [MIT License](LICENSE). Embedded libraries retain their own licenses.
