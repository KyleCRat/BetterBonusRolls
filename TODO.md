Reference: [Bonus-roll findings and assumptions](BONUS_ROLL_FINDINGS.md).

- Live-verify that a real item bonus roll prints the used source and actual loot
  specialization, marks the matching item Obtained, and never prints the 
  unused-roll expiration message.
- Live-verify tooltip reconciliation against a source with previously obtained
  items, then switch loot spec on the same offer and check both spec histories.
  Confirm Blizzard refreshes the native remaining-items tooltip after the
  switch; its API does not return the specialization used to generate it.
- Live-verify the current-season Mythic+ reward and knockout pool boundaries.
