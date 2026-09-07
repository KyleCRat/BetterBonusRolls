# Changelog

## Unreleased

### Changed

- Updated raid difficulty sections to use modern charcoal and silver
  expandable headers.

### Fixed

- Restored larger Blizzard difficulty icons beside raid section names and a
  brighter, optically centered borderless arrow that points down when
  collapsed and up when open.

## [12.1.0-1] - 2026-09-02

### Features

- Added opt-in, character-specific bonus-roll rules for raids, Lairs, current-season dungeons, Bountiful Delves, World Bosses, and Nightmare Prey.
- Added per-boss raid difficulty and loot-specialization choices, per-dungeon minimums from Normal through `+10`, and Bountiful Delve minimums from Tier 1 through Tier 11.
- Added current-season content discovery in Dungeon Journal order, with separate raid pages and collapsible difficulty groups.
- Added a wrong-loot-specialization sidecar that can change only the loot specialization before rolling.
- Added minimap and AddOn Compartment launchers plus `/bbr` command aliases.
- Added persisted Mythic+ run detection so the completed dungeon and key level survive a UI reload while its bonus-roll offer is active.

### Safety

- Added mandatory confirmation after every real click on Blizzard's Roll button, including an explicit warning when the active loot specialization does not match the configured rule.
- Changed Blizzard's No button to hide the offer without declining it while BetterBonusRolls is enabled; `/bbr show` restores an active hidden offer.
- Added one-shot offer validation, automatic disarming when offer state changes, and fail-closed handling when an offer cannot be safely identified.
- Added conflict detection for BonusRollConfirm and BonusRollGate plus automated critical-path safety checks.
