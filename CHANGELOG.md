# Changelog

## Unreleased

### Added

- Added expandable bonus-rollable item lists for enabled raid, Lair, dungeon,
  and World Boss rules, including specialization-specific tier tokens, exact
  item tooltips, and character-specific Obtained checkboxes.
- Bonus-roll item rewards now mark their matching source, difficulty, and
  actual loot-specialization entry as Obtained automatically.

### Changed

- Updated raid difficulty sections to use modern charcoal and silver
  expandable headers.
- Loot lists now retry transient Encounter Journal and item-data misses with
  bounded exponential backoff, then offer a manual Retry action if Blizzard's
  data still does not finish loading.
- Dungeon minimum menus now include only the standard base difficulties each
  dungeon exposes in the current Adventure Guide, omit Timewalking, and use
  the Mythic Journal pool for Mythic and every `+2` through `+10` threshold.
- Moved item-list cogs beside each rule's Enable checkbox, centered their
  headings, and applied consistent 8px spacing. Enlarged the cog art and item
  links, and placed Obtained checkboxes before item icons with matching gaps.
- Fully bordered expanded item lists, restored visible alternating item rows,
  and added 8px of parent-row containment below their existing bottom padding.

### Fixed

- Corrected loot-list item requests to listen for Blizzard's
  `ITEM_DATA_LOAD_RESULT` event and defer cache refreshes safely when that
  event fires synchronously, preventing rows from remaining stuck on Loading.
- Transient zero-count, zero-candidate, missing-row, and missing-link Journal
  results are no longer cached as valid empty loot lists.
- Encounter Journal loot queries are now serialized, and each result must be
  structurally matched to its owning instance, difficulty, specialization
  filter, and encounters, so overlapping expansions or Retry actions cannot
  exchange loot pools.
- Loot discovery now follows Blizzard's visible Adventure Guide navigation
  order: select the Raid or Dungeon tab, display the requested instance, apply
  its difficulty, then select an encounter and loot filter. This prevents an
  open Journal's difficulty refresh from restoring its previously viewed page.
- Lair World and flexible-Mythic loot queries now validate through Blizzard's
  base-difficulty mapping, allowing those pools to finish loading while their
  BetterBonusRolls rules remain distinct.
- Journal navigation now runs once per request while bounded backoff only
  checks for completed data, so cold loot data is no longer restarted on every
  retry. The Guide is intentionally left on the queried page for this MVP.
- Warm Journal pools are now read immediately after navigation; the 0.25, 0.5,
  1, and 2 second schedule is used only for cold-data retries.
  Expanded item panels retain their previous row height while refreshing so
  settings changes no longer collapse them to a single Loading row.
- The Loading message is deferred until the first immediate Journal read finds
  incomplete data, eliminating the one-tick flicker for warm loot pools.
- Expanded item panels, the bonus-roll preview, and the wrong-loot-specialization
  sidecar now share a crisp one-physical-pixel border across UI-scale and
  display-size changes instead of using pixelated tooltip chrome.
- Accepted Blizzard's documented encounter-less loot rows and now refresh
  dungeon encounter indexes within each serialized query attempt, so a cold
  legacy-dungeon catalog cannot make a valid combination immediately
  unavailable.
- Restored larger Blizzard difficulty icons beside raid section names and a
  brighter, optically centered borderless arrow that points down when
  collapsed and up when open.
- Successful and failed bonus-roll attempts no longer fall through to the
  misleading unused-roll expiration message.

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
