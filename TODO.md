Reference: [Bonus-roll findings and assumptions](BONUS_ROLL_FINDINGS.md).

- Before considering re-enabling the retained tooltip reconciliation, establish
  a reliable personal remaining-loot source. Correct spec ownership and a
  stable, name-matching tooltip are insufficient: Heroic Ula'tek showed already
  obtained items, and other lists grew or disappeared between reads.
- On a future live world transition with an active offer, verify that tooltip
  reconciliation stays disabled after reissue.
  The tooltip owner must remain unknown; visibility and Roll/Pass protection
  must still work. Do not use zoning as a way to reconcile another spec.
- Live-verify that saved Obtained history remains unchanged by tooltip reads,
  spec changes, hide/show, and recovered offers with reconciliation disabled.
  Actual awarded items must still update the spec used for the roll. Correct
  Restoration reward tracking and the used-roll message without an unused-roll
  expiration message are recorded in the findings.
- Live-verify the current-season Mythic+ reward and knockout pool boundaries.
