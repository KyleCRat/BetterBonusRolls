# Bonus-roll Findings

Reference notes from user-reported in-game testing for Midnight Season 2
(Interface 120100). Observed results and working assumptions are kept separate.
Outstanding verification tasks belong in [TODO.md](TODO.md).

## Eligibility and rewards

| Content | Finding | Evidence status |
| --- | --- | --- |
| Normal dungeons | Treated as unsupported for now; not independently tested. | Working assumption |
| Heroic dungeons | Treated as unsupported for now; not independently tested. | Working assumption |
| Mythic 0 | No bonus-roll window appeared after the tested dungeon was cleared. | Observed in the reported test |
| Voidscar Arena +2 | Offered a bonus roll. The reward tooltip showed Hero 1/6, item level 305. | Confirmed offer and tooltip |
| Ruby Life Pools +4 | Offered a bonus roll. The reward tooltip showed Hero 2/6, item level 308. | Confirmed offer and tooltip |
| Tier 1 Bountiful Delve | Offered a bonus roll. BBR hid it because the Delves rule was disabled. | Confirmed offer |

## Tooltip specialization and awarded items

During the reported Heroic Ula'tek test in The Venomous Abyss:

- The offer appeared with Elemental loot specialization selected. Its
  remaining-item tooltip included Font of Venomous Rage and the Elemental list.
- Switching loot specializations twice and re-hovering did not change that
  tooltip to Restoration's loot list.
- Rolling with Restoration selected awarded Awoken Dreadfang Cuirass. BBR
  correctly marked it Confirmed Obtained for Heroic Ula'tek / Restoration.
- The tooltip did not confirm Aqirbane Reliquary, previously obtained for
  Restoration. This test does not establish that tooltip reconciliation works
  when the offer initially appears with the intended specialization selected.

Working assumption: the remaining-item tooltip belongs to the specialization
selected when the offer first appears, even if the player later switches. This
is based on the reported test, not a guaranteed Blizzard API contract.
`C_TooltipInfo.GetItemByID` accepts no specialization argument and does not
identify which specialization generated the list. BBR therefore captures the
initial spec from a fresh prompt event and never relabels its tooltip after a
spec change. Recovered offers without that original context skip tooltip
reconciliation; actual awarded-item tracking remains independent and uses the
roll's result specialization.

## Current design decisions

- Dungeon minimum selectors offer +2 through +10, with +10 as the default.
  The +10 selection also covers higher keys. Normal, Heroic, and Mythic 0 are
  not selectable.
- Bountiful Delves retain their existing Tier 1-11 minimum choices. The Tier 1
  test confirms that the lowest selectable tier can offer a bonus roll.
- Dungeon obtained-item history remains separate for each selectable key level.
  These offers and reward tooltips do not establish whether different key
  levels share Blizzard's obtained-item history.
