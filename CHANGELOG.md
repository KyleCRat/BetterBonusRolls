# Changelog

## [Unreleased]

### Fixed

- Remaining-item tooltips now update only the loot specialization active when
  the bonus-roll offer first appeared. Changing loot spec no longer risks
  applying an unchanged tooltip to the new spec's checklist. Awarded items
  still update the specialization used for the roll.
- Tooltip reconciliation is skipped for recovered offers whose original loot
  specialization is unknown, including after a UI reload.

## [12.1.0-2] - 2026-09-08

### Added

- Added bonus-roll item checklists for raids, Lairs, current-season dungeons,
  and World Bosses, including specialization-specific tier tokens and item
  tooltips. Open a row's Items cog to review its loot.
- Added an item checklist beside active bonus-roll offers, with the source,
  difficulty, loot specialization, and remaining-item count.
- Added the Enabled Bonus Roll Loot Tracker settings page to manage items
  from all enabled rules in one place.
- Bonus-roll rewards and matching Blizzard remaining-item tooltips now update
  Obtained checkmarks for the relevant source, difficulty, and actual loot
  specialization, including after a loot-spec change.
- Confirmed items now explain their status in checkbox tooltips and ask before
  being manually unchecked. Later confirmed data takes precedence over manual
  changes; existing checkmarks are preserved as unconfirmed.

### Changed

- Dungeon minimums now offer Mythic+ `+2` through `+10`, defaulting to `+10`
  and including higher keys. Older Normal, Heroic, and Mythic 0 minimums move
  to `+2` without moving their saved item history.
- Dungeon Obtained progress is tracked separately for each selectable key
  level and loot specialization.
- Refreshed raid difficulty headers with modern styling, larger difficulty
  icons, and clearer expand/collapse arrows.
- Improved item-list spacing, column widths, checkbox placement, and crisp
  borders. The main settings page now links directly to every subpage.
- Updated the embedded LibModernSettings dependency to 1.6.0 and disabled the
  developer preview command.

### Fixed

- Improved cold-start catalog and loot loading, including legacy dungeons and
  Lair World and Mythic difficulties. Incomplete data is retried, with a Retry
  button when loading cannot finish.
- Prevented overlapping loot requests from showing another source's items.
  Delayed item data can now finish loading without a settings redraw.
- Warm loot lists load immediately, and expanded panels retain their height
  while refreshing to avoid Loading flicker and layout jumps.
- Obtained tooltips refresh immediately after a checkbox changes, and
  uncached bonus-roll rewards wait for item data before being recorded.
- Successful and failed rolls no longer print an unused-roll expiration
  message.
- Improved Mythic+ detection across reloads and temporary zone changes while
  rejecting stale run data. Eligible offers hidden only while key data loads
  can reappear automatically without overriding a manual hide or reopening
  roll confirmation.

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
