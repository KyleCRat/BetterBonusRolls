Reference: [Bonus-roll findings and assumptions](BONUS_ROLL_FINDINGS.md).

- Harden tooltip reconciliation against partial lists that grow or disappear
  between reads. A nonempty, name-matching subset does not prove completeness.
- On a future live world transition with an active offer, verify that tooltip
  reconciliation is cancelled and stays disabled for that offer after reissue.
  The tooltip owner must remain unknown; visibility and Roll/Pass protection
  must still work. Do not use zoning as a way to reconcile another spec.
- Live-verify that a real item bonus roll prints the used source and actual loot
  specialization and never prints the unused-roll expiration message. Correct
  Restoration item tracking after a spec switch is recorded in the findings.
- Live-verify tooltip reconciliation with previously obtained items while the
  intended loot spec is selected before the offer appears. Then switch specs:
  the tooltip must update only the original spec's history, while an awarded
  item updates the spec used for the roll. Check switching back, delayed item
  loading, hide/show, and a new offer with a different initial spec. A recovered
  offer after reload or zoning must skip tooltip reconciliation.
- Live-verify the current-season Mythic+ reward and knockout pool boundaries.
