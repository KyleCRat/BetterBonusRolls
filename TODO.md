Reference: [Bonus-roll findings and assumptions](BONUS_ROLL_FINDINGS.md).

- Live-verify that a real item bonus roll prints the used source and actual loot
  specialization and never prints the unused-roll expiration message. Correct
  Restoration item tracking after a spec switch is recorded in the findings.
- Live-verify tooltip reconciliation with previously obtained items while the
  intended loot spec is selected before the offer appears. Then switch specs:
  the tooltip must update only the original spec's history, while an awarded
  item updates the spec used for the roll. Check switching back, delayed item
  loading, hide/show, and a new offer with a different initial spec. A recovered
  offer after reload must skip tooltip reconciliation. Next live test: Sunday,
  when another bonus-roll item is available.
- Live-verify the current-season Mythic+ reward and knockout pool boundaries.
