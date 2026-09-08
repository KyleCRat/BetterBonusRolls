# BetterBonusRolls

BetterBonusRolls only shows you bonus rolls for the content and loot specializations you care about. Configure each character separately; matching offers stay visible and everything else is hidden without being declined.

The addon is disabled by default.

## Getting Started

1. Open the settings with `/bbr`, the minimap button, or the AddOn Compartment.
2. Enable **BetterBonusRolls** for your character.
3. Open a content page and enable the bosses, dungeons, or outdoor content where you want to bonus roll.
4. Choose **Current Spec** or a specific loot specialization for each enabled rule.
5. Use the cog on a supported row to review its bonus-rollable items and manually mark anything you have already obtained.

Unchecked rows are treated as content you do not want to bonus roll and their offers are hidden while the addon is enabled.

## What Happens When a Roll Appears

- Clicking Blizzard's **Roll** button always opens a confirmation. The roll is not used until you accept it.
- If the configured loot specialization is not active, a **Change Loot Spec** button appears beside the roll. It changes only your loot specialization and never uses the roll.
- If you remain in the wrong loot specialization, the confirmation warns you before offering **Roll Anyway**.
- Clicking Blizzard's **No** button hides the offer without declining it. BetterBonusRolls prints a reminder that `/bbr show` can restore it while the offer remains active.
- When a bonus roll awards a tracked item, its matching entry is automatically marked **Obtained** for that source, difficulty, and loot specialization.
- Once the server offer expires, it can no longer be restored.

BetterBonusRolls never automatically spends or permanently declines a bonus roll.

## Supported Content

| Content | Available rules |
| --- | --- |
| Raids and Lairs | Choose each boss, difficulty, and loot specialization independently. |
| Current Season Dungeons | Choose each dungeon, its minimum Mythic+ key level from `+2` through `+10`, and loot specialization. New rules default to `+10`, which also includes higher keys. Normal, Heroic, and Mythic 0 are not selectable. |
| Bountiful Delves | Use one rule for all Bountiful Delves with a minimum Tier 1-11 and loot specialization. |
| Outdoor Content | Configure current-season World Bosses individually and Nightmare Prey separately. |

Bonus-rollable item lists are available for raids, Lairs, current-season dungeons, and individual World Bosses. These include equipment and specialization-specific tier tokens. Blizzard does not currently expose a complete equivalent loot pool for Bountiful Delves or Nightmare Prey.

## Commands

| Command | Aliases | Action |
| --- | --- | --- |
| `/bbr` or `/bbr settings` | `s`, `config`, `c` | Open settings. |
| `/bbr show` | `sh` | Restore a hidden offer while it is active. |
| `/bbr hide` | `h` | Hide the visible offer without declining it. |
| `/bbr enable` | `e` | Enable BetterBonusRolls for this character. |
| `/bbr disable` | `d` | Disable BetterBonusRolls and restore Blizzard's normal behavior. |
| `/bbr status` | `st` | Show addon and active-offer status. |
| `/bbr help` | `?` | Show command help. |

`/betterbonusrolls` can be used in place of `/bbr`.

## License

BetterBonusRolls is available under the [MIT License](LICENSE). Embedded libraries retain their own licenses.
