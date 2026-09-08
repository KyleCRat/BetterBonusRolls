- Live-verify that a real item bonus roll prints the used source and actual loot specialization, marks the matching item Obtained, and never prints the unused-roll expiration message.
- Live-verify tooltip reconciliation against a source with previously obtained
  items, then switch loot spec on the same offer and check both spec histories.
  Confirm Blizzard refreshes the native remaining-items tooltip after the
  switch; its API does not return the specialization used to generate it.
- Dungeon eligibility findings: the tested Mythic 0 completion did not show a
  bonus-roll window. Treat Normal and Heroic as unsupported for now; these are
  working assumptions, not independently tested results. Ruby Life Pools +4
  was confirmed to offer a bonus roll.
- Follow-up: remove Normal, Heroic, and Mythic 0 from dungeon selectors, keeping
  the +2 through +10 options and +10 default. Continue using Mythic Journal
  item lookups and separate tracking for each selectable key level; preserve
  existing saved history.
- Live-verify the current-season Mythic+ reward and knockout pool boundaries;
  the +4 offer does not establish which key levels share obtained-item history.
- Before release, update the LibModernSettings submodule to version 1.6 and
  disable the developer preview flag.
