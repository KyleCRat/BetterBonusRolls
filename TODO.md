- Live-verify that a real item bonus roll prints the used source and actual loot specialization, marks the matching item Obtained, and never prints the unused-roll expiration message.
- Confirm the current-season Mythic+ bonus-roll reward-track breakpoints, then
  store Obtained progress separately for every selectable dungeon threshold
  even when multiple thresholds query the same base Mythic Journal item IDs.
- Harden the existing single persisted Mythic+ run: retry incomplete
  `CHALLENGE_MODE_START` data, retain it across temporary zone changes,
  overwrite it only for a verified new run, and add provenance and freshness
  rules so old completion data cannot impersonate it.
- Add a public LibModernSettings tooltip-refresh method for version 1.6 and
  replace BetterBonusRolls calls to the private `_ShowTooltip` helper.
- Before release, update the LibModernSettings submodule to version 1.6 and
  disable the developer preview flag.
