# Bonus-roll Findings

Reference notes from user-reported in-game testing for Midnight Season 2
(Interface 120100). Observed results and working assumptions are kept separate.
Outstanding verification tasks belong in [TODO.md](TODO.md).

Tooltip-based checklist reconciliation is currently disabled. Its implementation
is retained for investigation; only actual bonus-roll rewards and manual edits
update Obtained history. Earlier tooltip ownership safeguards below remain in
place but do not establish that the tooltip represents personal remaining loot.

## Eligibility and rewards

| Content | Finding | Evidence status |
| --- | --- | --- |
| Normal dungeons | Treated as unsupported for now; not independently tested. | Working assumption |
| Heroic dungeons | Treated as unsupported for now; not independently tested. | Working assumption |
| Mythic 0 | No bonus-roll window appeared after the tested dungeon was cleared. | Observed in the reported test |
| Voidscar Arena +2 | Offered a bonus roll. The reward tooltip showed Hero 1/6, item level 305. | Confirmed offer and tooltip |
| Ruby Life Pools +4 | Offered a bonus roll. The reward tooltip showed Hero 2/6, item level 308. | Confirmed offer and tooltip |
| Tier 1 Bountiful Delve | Offered a bonus roll. BBR hid it because the Delves rule was disabled. | Confirmed offer |
| Tier 11 Bountiful Delve | Parhelion Plaza offered cache 279284, difficulty 208, item context 108, treasure context level 11. Tooltip showed Hero 1/6, item level 305. | Confirmed offer and diagnostic capture, 2026-09-15 |
| Nightmare Prey | Kursak the Coiled offered cache 280131, difficulty 14, item context 55, treasure context level 0, Journal instance 0 and no encounter ID. Tooltip showed Hero 1/6, item level 305. | Confirmed offer and diagnostic capture, 2026-09-15 |
| Nightmare Prey, second boss | Batani the Scaled used the same prompt fields. Active Prey quest 95023 was available at the initial prompt, with `IsComplete` false and no quest tag. It left the quest log about one second later. | Confirmed diagnostic capture, 2026-09-15, build 69814 |
| Nightmare Prey, classification fix | Ranger Swiftglade (quest 91235) was correctly shown as Nightmare Prey before automatic quest turn-in and remained classified after a spec switch and portal. The initial outdoor instance was Voidstorm, type `none`, game map 2771. | Confirmed diagnostic capture, 2026-09-15, build 69814 |

## Prey detection

The previous routing treated difficulty 14 as a raid and only considered Prey
for difficulty 172 without a known encounter. The first two tested Nightmare Prey
offers were therefore misclassified before the player took a portal.

The revised detection captures `C_QuestLog.GetActivePreyQuest()` when an outdoor
bonus-roll offer first opens without a Journal instance or encounter. Dungeon
and Delve difficulties are excluded. The captured quest ID belongs to that
offer and is retained after the quest leaves the log and for recognized
redisplays. An active quest cannot override an identified boss offer. Missing
quest or location data does not establish a Prey source; the diagnostic
module's recent quest ID is not used as a fallback.

This is an inference from the initial offer and active-quest context, not a
Blizzard-provided Prey identifier on the prompt. The Ranger Swiftglade test
verified the revised classification before the portal: `kind=prey`,
`allowed=true`, and the configured Restoration rule were recorded immediately.
The automatic turn-in removed the quest about one second later without losing
the source. This validates that observed event order, not every possible race.
There is no reward-cache name, cache-ID list, or quest-ID list in detection,
so replacing the cache in a new tier does not require a classifier update.
Generic cache equality is still used to identify a redisplay of the same
offer, not to decide whether a newly opened offer is Prey.

API lookup used the local 12.1.0.69497 export and the 12.1.0.69587 runtime
index; the live diagnostics above came from build 69814. The active-quest API
is present in both references and was observed working in the live logs.

## Live tooltip and zone-transition observations (2026-09-15)

- Delve API tooltip entries grew from none to 3 to 32. The final list included
  the name Galerider's Chausses twice. It remained unchanged after Elemental
  was switched to Enhancement and then Restoration.
- Prey API tooltip entries changed from none to 5 to 26 and then disappeared.
  The 26 entries returned after zoning. The API and native hovered tooltip
  both remained unchanged after Restoration was switched to Elemental.
- These are observations of tooltip contents, not proof of completeness or
  which specialization's knockout history the contents represent. A valid
  nonempty list can still be partial; an empty list is not proof of completion.
- The player confirmed taking a portal from Zul'Aman to Silvermoon while the
  same Prey offer remained available. A second SPELL_CONFIRMATION_PROMPT
  arrived with a shorter duration. The calculated expiration changed from
  1789488860 to 1789488859; BBR assigned a new generation and recaptured the
  tooltip owner. Restoration remained selected during this transition.
- A prompt event alone therefore does not prove a brand-new offer. The later
  spec-switch/portal test below also showed that keeping the same offer does
  not guarantee that its tooltip retains the same specialization.
- The Prey tooltip says its reward list is shared with Preyhunter's Hero
  Chest. This does not by itself establish shared obtained-item history.

### Spec switch followed by a portal: Ranger Swiftglade

- At 13:27:00, the offer opened with Elemental selected and captured owner 262.
  It remained generation 1 throughout the test. The initial tooltip grew from
  no items to 2 to 26 items (34 total lines).
- At 13:27:16, the sidecar switched loot spec to Restoration (264). API reads
  and native hovers still showed the initial Elemental list before the portal.
- The player left the world at 13:27:41 and received the repeated prompt at
  13:27:52. Its calculated deadline was one second later than BBR's stored
  deadline. The old implementation kept owner 262 and did not attach 264.
- After the portal, the tooltip grew from no items to 23 to 26 items. Three
  trinkets changed: Void-Reaper's Libram, Spirit-Rending Poison, and Ophidian
  Bone Whistle were replaced by Cosmic Bell, Pulse Seeker's Oculus, and Chiral
  Marrowgrafter. This matched the earlier Restoration-start Prey list. Both
  the API and native hover at 13:28:02 showed the changed list, even though
  both settled lists had the same 34-line count.
- Prey classification and visibility passed, including automatic quest
  turn-in and the portal. No roll was used, and no Obtained history changed:
  Prey has no trackable Journal pool, so reconciliation was skipped.

The tooltip can therefore regenerate across a world transition without a new
offer or reward-cache identity. Retaining the initial owner after zoning is
unsafe for tracked content. BBR deliberately skips tooltip reconciliation for
the rest of that offer instead of trying to identify the refreshed list's spec.
Zoning is not a supported way to reconcile another specialization.

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
selected when the offer first appears, even if the player later switches,
until a world transition. This is based on reported tests, not a guaranteed
Blizzard API contract.
`C_TooltipInfo.GetItemByID` accepts no specialization argument and does not
identify which specialization generated the list. BBR therefore captures the
initial spec for a new offer and never relabels its tooltip after a spec change.
On `PLAYER_LEAVING_WORLD`, BBR cancels pending tooltip reads and Journal-pool
reconciliation and locks the current offer's tooltip owner to unknown. Queued
or repeated prompts cannot reattach an owner for that offer. This does not
undo Obtained history already reconciled before the transition.

Recognized reissues preserve the source when spell/source and reward-cache
context match and the deadline remains within one second of the original.
Only reissues without a world transition may retain a known tooltip owner.
That tolerance never preserves Roll authorization. An uncertain redisplay or
a recovered offer without original context also skips tooltip reconciliation.
Actual awarded-item tracking remains independent and uses the roll's result
spec; a distinct new offer can capture its own initial tooltip owner normally.

### Heroic Ula'tek with Restoration selected before the offer

- The player had already bonus-rolled Aqirbane Reliquary (268265) and Awoken
  Dreadfang Cuirass (271876); Jan'thrazet, the Soul Fang (271092) was missing.
  For the test, the dagger was manually checked and the Reliquary unchecked.
  The Cuirass remained checked and confirmed.
- At 21:30:02, the offer correctly identified Heroic Ula'tek, difficulty 15,
  Journal instance 1320, encounter 2895. Both the selected loot spec and the
  captured tooltip owner were Restoration (264). The tracking key was
  `raid:1320:2895:15:264`.
- Cache 278284, item context 5, treasure context level 4 listed all three
  items. API queries and native hovers agreed, with the full list still shown
  at 21:31:27, about 85 seconds after the prompt. There was no spec switch or
  world transition to explain the mismatch.
- Reconciliation treated those entries as three remaining items. It cleared
  the deliberately checked dagger and also incorrectly cleared the Cuirass's
  real Obtained and Confirmed Obtained flags. The Reliquary stayed unchecked.
  A parsed `remainingItems` count is BBR's interpretation, not a Blizzard
  guarantee that the list excludes previously obtained rewards.
- At 21:31:29, the actual roll awarded the dagger with reported spec 264.
  BBR correctly recorded it as Obtained and Confirmed Obtained for Heroic
  Ula'tek / Restoration and printed the used-roll message. No unused-roll
  expiration message appeared, despite `SPELL_CONFIRMATION_TIMEOUT` firing.

This contradicts the assumption that a correctly owned, settled cache tooltip
is authoritative personal knockout history. The dagger award is consistent
with separate server-side knockout tracking, but one award does not prove the
server's selection algorithm. More retry time would not fix the observed
stable full-pool list; ignoring only confirmed-item clears would still allow
partial lists to create false obtained flags.

All tooltip-based history writes are therefore disabled, including in
development mode. The reconciliation code and independent diagnostic API/native
hover captures are retained. Disabling it preserves existing saved records; it
does not automatically reconstruct records overwritten by earlier tooltips.

The retained reconciliation write path now refuses to uncheck an item or clear
its confirmation when `confirmedObtained` is already true. Existing saves do
not distinguish observed-roll confirmations from older tooltip inferences, so
this conservatively protects all confirmed records. Explicit manual unchecking
still works and retains the confirmation evidence. This safeguard does not
make tooltip reconciliation reliable or re-enable it.

## Current design decisions

- Dungeon minimum selectors offer +2 through +10, with +10 as the default.
  The +10 selection also covers higher keys. Normal, Heroic, and Mythic 0 are
  not selectable.
- Bountiful Delves retain their existing Tier 1-11 minimum choices. The Tier 1
  test confirms that the lowest selectable tier can offer a bonus roll.
- Dungeon obtained-item history remains separate for each selectable key level.
  These offers and reward tooltips do not establish whether different key
  levels share Blizzard's obtained-item history.
- Obtained history is updated only by actual bonus-roll rewards and manual
  edits. Tooltip reconciliation remains dormant until reliable personal
  remaining-loot semantics can be demonstrated and re-enabling is approved.
