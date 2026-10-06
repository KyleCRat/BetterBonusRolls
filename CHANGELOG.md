# Changelog

## [12.1.5-5] - 2026-10-06

- Updated for WoW 12.1.5.

## [12.1.0-4] - 2026-09-16

### Added

- Added opt-in, character-specific development mode with chat diagnostics for
  bonus-roll tooltips, loot-specialization changes, and obtained-item tracking.
  Diagnostics also capture Prey quest context, pending offers, and offers
  reappearing after zone transitions.
  Developer previews can now be enabled without editing addon files or reloading.

### Changed

- Updated LibModernSettings to 1.7.0 for improved settings layout, dropdown
  refresh behavior, and compatibility between embedded library copies.

### Fixed

- Prey offers now use the Prey rule instead of being mistaken for Normal raid
  encounters. Detection uses the active Prey quest and an outdoor offer with
  no Journal source, without depending on reward-cache names or item IDs.
  The source remains attached to the offer after its quest leaves the log.
- Disabled tooltip-based checklist reconciliation because cache tooltips can
  include already-obtained items or incomplete lists. They no longer overwrite
  manual or confirmed Obtained history. Actual bonus-roll rewards still update
  the checklist, and manual tracking remains available.
  The retained reconciliation code also protects already-confirmed items from
  tooltip-driven unchecks if it is re-enabled in the future.
- Loading-screen zone changes invalidate the active offer's tooltip owner;
  reissued prompts cannot restore it. Source rules and loot-spec controls remain available.
  Zone transitions and changed offer snapshots still cancel pending Roll
  confirmations and require another Blizzard Roll-button click.
