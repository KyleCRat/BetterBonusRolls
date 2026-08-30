# Changelog

## 12.1.0-1

- Initial BetterBonusRolls implementation for WoW `12.1.0` / Interface `120100`.
- Added an opt-in, character-specific rules database using LibSimpleDB `2.0.0`.
- Added LibModernSettings `1.5.0` pages for current-season dungeons, outdoor content, and per-instance raid/Lair encounter difficulties.
- Added current-client Encounter Journal and Challenge Mode catalog discovery with Dungeon Journal ordering.
- Added explicit enable checkboxes and Blizzard-style loot-specialization dropdowns with `Current Spec (<name>)` followed by every direct class specialization.
- Added per-dungeon Normal-through-`+10` minimums, defaulting to `+10` with higher keys capped to the same reward tier.
- Added one Bountiful Delves rule with a Tier 1-11 minimum, individual current-season World Boss rules, and a separate Nightmare Prey rule.
- Added collapsible raid difficulty groups with Blizzard difficulty icons and a desaturated storyline icon for Story difficulty.
- Added schema-2 migration from the former global Mythic+ minimum to per-dungeon thresholds.
- Added the loot-specialization switch button to active configured offers.
- Added mandatory correct-spec and wrong-spec roll confirmations guarded by an exact one-shot offer snapshot.
- Changed Blizzard's No action to recoverable hiding while enabled, with `/bbr show` restoration and explicit timeout reporting.
- Added conflict detection for BonusRollConfirm and BonusRollGate.
- Added static and mocked safety verification.
