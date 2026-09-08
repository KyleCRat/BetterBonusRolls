- Live-verify that a real item bonus roll prints the used source and actual loot specialization, marks the matching item Obtained, and never prints the unused-roll expiration message.
- Live-verify that Mythic The Lost Explorers includes Venomcast Remnant for Enhancement while Slumbering Coil Curio remains excluded from Ula'tek's loot list.
- Live-verify that Nymrissa Wavecaller loads both Tidebound Grotto World and
  flexible-Mythic loot through their base Journal difficulties.
- Live-verify that Altar of Fangs dungeon loot and current-season World Boss
  loot recover through the bounded retry path without getting stuck on
  Loading or briefly caching a false empty list.
- With the Adventure Guide open on Heroic The Venomous Abyss, load Normal
  Altar of Fangs and verify the Guide visibly navigates to the Dungeon tab and
  requested instance/difficulty while the settings row receives the correct
  loot. Repeat between two dungeons and once with the Guide initially closed.
- Open or Retry Kings' Rest and Voidscar Arena together and verify their
  serialized Journal requests never display each other's loot.
- Compare one dungeon at Normal, Heroic, Mythic, and a Mythic+ threshold;
  verify each base selection uses its matching pool and Mythic+ uses Mythic.
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
