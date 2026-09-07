# BetterBonusRolls implementation plan

Status: implemented for WoW `12.1.0` / Interface `120100`.

## Goal

Improve bonus-roll filtering and loot-specialization awareness without creating any path that can spend or permanently decline a roll without direct user input.

## Implemented behavior

1. The addon is disabled by default and uses character-specific LibSimpleDB storage.
2. While enabled, an absent rule denies automatic display.
3. Raid and Lair rules are keyed by current-season Journal instance, encounter, canonical difficulty, and desired current-class loot specialization.
4. Every rule has an explicit enable checkbox. Enabling defaults to Blizzard's dynamic `Current Spec (<name>)` loot setting (`0`), followed by every direct class specialization in the dropdown. Disabling greys and locks the dependent fields.
5. Current-season dungeon rules are keyed by challenge map, desired loot specialization, and a per-dungeon inclusive threshold from Normal through `+10`. New rules default to `+10`; higher keys canonicalize to that cap.
6. Bountiful Delves use one global rule with a Tier 1-11 minimum. Current-season World Bosses use individual encounter rules, while Nightmare Prey uses a separate fallback rule within their shared difficulty bucket.
7. Raid-like Lairs are discovered from both Encounter Journal lists and expose the raid-style difficulties the current client reports. World remains distinct; flexible Mythic uses the Mythic rule.
8. A configured wrong-spec offer is shown with a **Switch to <Spec>** button. The button only calls the loot-specialization setter and cannot roll.
9. Blizzard's No button hides the frame without invoking its native decline script. The addon prints `/bbr show` recovery guidance.
10. Server timeout expires the offer without declining it and explicitly reports that it can no longer be restored.
11. Blizzard's Roll button always opens a custom confirmation. Correct-spec offers use **Use Bonus Roll**; wrong-spec or manually restored rule violations use **Roll Anyway**.
12. BonusRollConfirm and BonusRollGate are treated as conflicts; BetterBonusRolls refuses to enable alongside either one.

## Encounter detection decision

There is no pre-combat raid NPC, target, room, or map-area matching. Blizzard supplies `instanceID`, `encounterID`, and `difficultyID` on the post-defeat BonusRollFrame, which identifies the exact raid/Lair or current-season World Boss rule when action is needed. Dungeon offers combine that difficulty with the current-season Challenge Mode catalog and active/completed key data. Delves use difficulty 208 plus a public active-tier snapshot captured once for the offer. World Bosses and Nightmare Prey share difficulty 172: a known Journal encounter uses its individual World Boss rule, a positive unknown encounter fails closed, and an offer without a Journal encounter uses the Nightmare Prey fallback. Because loot specialization can be changed before rolling, the addon warns and offers the switch button on the live bonus-roll frame.

## Safety state machine

`Idle → direct Blizzard Roll-button click → one-shot token for exact state → custom confirmation accept → captured native Roll callback once`

The one-shot token includes offer generation, spell, expiry, instance, encounter, canonical difficulty, dungeon map/rank/threshold, challenge map/level, Delve tier/threshold, rule result, desired loot specialization, and current loot specialization. Cancel, Escape, timeout, frame hide, new offer, loot-spec change, rule change, addon disable, button interference, or snapshot mismatch disarms it. A mismatch requires another direct Blizzard Roll-button click and never reopens confirmation automatically.

The token is consumed before the captured native callback is invoked. The Roll button remains disabled while confirmation is pending. The native Roll callback is a local upvalue; the native Pass callback is retained only so disabling the addon can restore untouched Blizzard behavior.

The addon contains no direct spell-confirmation accept/decline calls, programmatic Roll/Pass clicks, roll/decline slash commands, test-spend control, retry, queue, or automatic action.

## Verification

- Lua 5.1 syntax validation for all addon-owned Lua.
- Focused mocked controller tests for the critical bonus-roll path: two-step authorization, one-shot consumption, state invalidation, hide versus pass, timeout/disable behavior, direct and `Current Spec` switching, and unconfigured-offer restoration.
- Static scan rejects direct confirmation APIs, programmatic Roll/Pass clicks, roll/decline commands, native Pass invocation, multiple native Roll invocation sites, or failure to consume authorization first.
- In-game smoke testing remains required for Blizzard frame geometry, Settings layout, live Journal data, real challenge completion payloads, and secure/secret-value behavior.

## Deferred feature: Loot goals and bonus-roll history

Status: research complete; implementation is deferred until the next set of smaller fixes and changes is finished.

### Confirmed API surface

- The Encounter Journal can enumerate the displayed loot pool for a selected instance, encounter, difficulty, class, and specialization. The relevant APIs are `EJ_SelectInstance`, `EJ_SelectEncounter`, `EJ_SetDifficulty`, `EJ_SetLootFilter`, `EJ_GetNumLoot`, and `C_EncounterJournal.GetLootInfoByIndex`.
- `EncounterJournalItemInfo` supplies the base item ID, encounter ID, name, icon, slot, armor type, link, seasonal display ID, and per-player or rarity display flags. It does not identify whether an entry is specifically eligible for a bonus roll.
- `C_Item.IsEquippableItem(itemID) == true` and `C_Item.IsCosmeticItem(itemID) ~= true` is the current candidate rule for identifying bonus-rollable equipment. This must be checked against additional raids, Lairs, World Bosses, and dungeons before becoming a production rule.
- `displayAsPerPlayerLoot` cannot identify bonus-rollable items because Blizzard also sets it on non-equipment rewards such as decor.
- `C_Item.IsCurioItem` identifies Delve companion curios, not raid rewards whose names contain "Curio". Raid Curios are excluded by being non-equippable.
- `BONUS_ROLL_STARTED` confirms that a roll began but has no payload. The addon must retain the already-resolved offer snapshot before this event.
- `BONUS_ROLL_RESULT` supplies the reward type, exact item link, quantity, actual loot specialization ID, currency ID, and secondary-result state. It does not repeat the source encounter or difficulty, so results must be associated with the retained offer snapshot.
- The bonus-roll prompt supplies the active `currencyID` and `currencyCost`. Once observed, `C_CurrencyInfo.GetCurrencyInfo(currencyID)` can report the character's current shared roll currency; no universal current-season currency ID should be hardcoded.
- `C_RaidLocks.IsEncounterComplete` reports whether a raid encounter is complete for a difficulty, not whether the character has already used a bonus roll there.
- `C_Item.GetItemCount` and inventory scanning can report currently owned copies, but base item IDs do not distinguish every difficulty or upgrade-track variant. Persisted history is required after an item is sold, deleted, or disenchanted.
- Blizzard exposes no historical bonus-roll log, drop probabilities, duplicate-protection state, or authoritative per-boss remaining-roll count. History can begin only when this feature is installed and active; it cannot be backfilled.

### Validated Ula'tek sample

The first live classification test used The Venomous Abyss instance `1320`, Ula'tek encounter `2895`, Heroic difficulty `15`, Shaman class `7`, and Restoration specialization `264`. Blizzard returned the instance from the raid list and exposed seven Journal entries.

| Item ID | Item | Classification | Candidate result |
| --- | --- | --- | --- |
| `279500` | "Rage of the Shackled" Mural | Housing decor; non-equippable | Excluded |
| `270909` | Slumbering Coil Curio | Reagent-class raid Curio; non-equippable | Excluded |
| `279125` | The Venomous Abyss Aureate Trophy | Housing decor; non-equippable | Excluded |
| `279129` | The Venomous Abyss Gleaming Trophy | Housing decor; non-equippable | Excluded |
| `271092` | Jan'thrazet, the Soul Fang | Equippable weapon | Included |
| `268265` | Aqirbane Reliquary | Equippable neck | Included |
| `271876` | Awoken Dreadfang Cuirass | Equippable mail chest | Included |

The candidate rule selected exactly the three equipment entries and rejected the Curio and decor. Additional validation must include encounters containing mounts, pets, cosmetic armor, tokens, and dungeon loot.

### Intended behavior

- Each configured Journal-backed source, difficulty, and concrete loot specialization can expose its filtered equipment pool and let the player select individual item goals.
- On `BONUS_ROLL_STARTED`, create an attempt tied to the existing immutable offer snapshot. Attach each `BONUS_ROLL_RESULT` to that attempt with its source, difficulty or key level, actual loot specialization, item ID and link, quantity, timestamp, and secondary-result state.
- Store goal selection and observed history in the existing character-specific database. Keep general acquisition and acquisition specifically through a bonus roll as separate facts.
- Report `N items remaining` and, when useful, `At least N item rewards needed`. Never describe that lower bound as an exact number of bonus rolls because unwanted results and duplicates can increase it.
- Show observed attempts, available shared currency, and raid lockout state where each is available. Do not claim an authoritative per-boss remaining-roll count that Blizzard does not expose.
- Keep the tracker observational. It must not call confirmation accept or decline APIs, invoke native Roll or Pass callbacks, click Blizzard buttons, or otherwise change the existing bonus-roll safety state machine.

### Open decisions before implementation

1. Decide whether acquiring a goal item through any source completes it or only an item observed through `BONUS_ROLL_RESULT`. The current recommendation is that either source completes the goal while bonus-roll provenance remains visible separately.
2. Decide whether a lower-difficulty or lower-upgrade-track version completes a goal selected for a higher difficulty.
3. Decide which ownership locations count: equipped gear, bags, character bank, reagent bank, and account bank.
4. Decide whether the first version covers only Journal-backed raids, Lairs, dungeons, and World Bosses or also attempts support for Bountiful Delves and Nightmare Prey without a complete Journal pool.
5. Decide how long detailed attempt history is retained and whether weekly summaries are preserved after reset.
