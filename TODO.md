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
- Remove the duplicated `pack`/`safeCall` wrappers from `Catalog.lua` and
  `LootTracker.lua`. Call required Interface `120100` APIs directly, preserve
  multiple returns explicitly at their call sites, and use error-reporting
  `pcall` only around genuine optional or transactional failure boundaries so
  API errors cannot be silently mistaken for legitimate `nil` results.
