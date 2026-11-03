# Changelog

## [Unreleased]

### Added

- In-game update highlights and full notes through the Changelog settings page
  and shared `/changelog` window. New-release notices can be disabled.
  Notification preferences and read status are shared across your account,
  so each release only needs to be acknowledged once across your characters.

### Changed

- Hidden bonus-roll reminders now appear immediately and repeat after 5 and
  10 seconds while the offer remains active and hidden, with `/bbr show`
  highlighted in yellow to stand out after loot-message spam.
- Raid and Lair settings pages now open every difficulty with an enabled boss.
  If none are enabled, only the top difficulty opens. Manual expansion and
  collapse remain available while viewing the page.

## [12.1.5-6] - 2026-10-18

### Fixed

- Bonus-roll offers hidden by Pass, `/bbr hide`, or filtering now stay hidden
  through Blizzard's periodic refresh and same-offer zone redisplays. Use
  `/bbr show` to restore a hidden offer while it is still active.
- Delve minimum-tier rules now recognize the tier shown in the active Delve
  when Blizzard's tier API returns zero, retaining it through completion.

## [12.1.5-5] - 2026-10-06

- Updated for WoW 12.1.5.
