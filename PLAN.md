# BetterBonusRolls implementation plan

Status: implemented for WoW `12.1.0` / Interface `120100`.

## Goal

Improve bonus-roll filtering and loot-specialization awareness without creating any path that can spend or permanently decline a roll without direct user input.

## Implemented behavior

1. The addon is disabled by default and uses character-specific LibSimpleDB storage.
2. While enabled, an absent rule denies automatic display.
3. Raid and Lair rules are keyed by current-season Journal instance, encounter, canonical difficulty, and desired current-class loot specialization.
4. Every rule has an explicit enable checkbox. Enabling defaults to Blizzard's dynamic `Current Spec (<name>)` loot setting (`0`), followed by every direct class specialization in the dropdown. Disabling greys and locks the dependent fields.
5. Current-season dungeon rules are keyed by challenge map, desired loot specialization, and a per-dungeon inclusive threshold. Normal, Heroic, and Mythic appear only when that dungeon exposes the difficulty in the current Adventure Guide; Timewalking is ignored. Every current-season dungeon also offers `+2` through `+10`, new rules default to `+10`, and higher keys canonicalize to that cap.
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

## Next milestone: Per-rule loot lists and obtained tracking

Status: implemented; the live Journal matrix and a real bonus-roll result still require in-game verification.

### First-version scope and decisions

1. Cover every current-season source with a reliable Encounter Journal pool: raid and Lair encounters, dungeons, and individual World Bosses. Bountiful Delves and Nightmare Prey remain unchanged in this milestone because the client does not expose a complete Journal pool for them.
2. Treat every classified bonus-rollable entry as an item to acquire. This version does not add a separate Wanted selector; each entry is either remaining or Obtained.
3. Store Obtained state per character and preserve it when a rule is disabled or its selected specialization changes.
4. Resolve `Current Spec` to the player's concrete active specialization before querying or storing item state. Changing active specialization refreshes an open `Current Spec` item list.
5. Keep the same base item independent between concrete specialization combinations and between raid difficulties. A dungeon's minimum threshold selects its base Normal, Heroic, or Mythic Journal pool; every Mythic+ threshold uses the Mythic pool. The threshold is not part of the dungeon/spec ownership key.
6. Mark items obtained only through a manual checkbox or an observed `BONUS_ROLL_RESULT` in this milestone. Automatic bag, bank, account-bank, or equipment ownership scans are deferred.
7. Do not add attempt history, currency counts, estimated rolls remaining, or lockout summaries yet. The first checkpoint is a trustworthy item pool and Obtained state.

### Row and expansion UI

1. Add an **Items** action column immediately after **Enable** and before the dungeon, boss, or outdoor-content name. Keep a consistent 8px visual gap between the Enable checkbox, Items cog, and source name. This keeps the two row actions together at the left edge while leaving minimum and loot-specialization choices together on the right.
2. Use a 34px LibModernSettings square tertiary button with a 24px Blizzard settings-cog icon. The cog begins disabled with the rest of the row and uses the existing `Enable this bonus-roll rule first` tooltip. Enabling a valid rule enables the cog; disabling the rule collapses any open item section.
3. Clicking the cog toggles an inline details section directly beneath that source row. Expansion is transient page state and is not stored in SavedVariables. Multiple source sections may remain open.
4. Keep the primary source row at its current height. Inset the bordered detail region 8px from the parent row's left and right edges, retain 8px of internal padding below its last item, and leave another 8px of parent-row margin below the border. Alternate the item-row backgrounds. The detail region expands the owning table row below the primary cells and causes subsequent rows, difficulty groups, the table, and the Settings canvas scroll extent to reflow.
5. Add the minimum reusable LibModernSettings table support needed for a row to change height and notify its owner that table height changed. Loot rendering and SavedVariables remain addon-owned.
6. The detail section identifies the concrete loot specialization and shows `N remaining / N total`. While Journal or item data is pending, show a neutral loading row; show a clear empty or unavailable message instead of an empty box.
7. Preserve Encounter Journal loot order. Each loot row contains an **Obtained** checkbox followed by the item icon and a colored item link using the same font size as boss names, with consistent 8px gaps between all three elements. Hovering either the icon or link opens the tooltip for the exact Journal link returned for that source, difficulty, specialization, and selected dungeon threshold. Tooltip state is cleared when a row is hidden or reused.
8. Manual checkbox changes update only loot-tracking state and the open item summary. They must not call `NotifyConfigurationChanged`, disarm a bonus-roll confirmation, or rebuild unrelated settings controls.
9. Raid and Lair item sections use the row's exact Journal difficulty, including the Journal's flexible-Mythic ID behind the canonical Mythic rule. Dungeon selectors are built from the base difficulties each selected Journal instance actually exposes, omit Timewalking, and carry their Journal difficulty with the displayed choice. Normal and Heroic query their own pools; Mythic and every `+2` through `+10` choice query the base Mythic pool. World Bosses use their cataloged Journal instance, encounter, and valid Journal difficulty rather than the runtime bonus-roll difficulty `172`.

### Loot-pool query and cache

1. Add an addon-owned loot-tracking module loaded after `Catalog.lua` and before `RollController.lua` and `Settings.lua`. It owns Journal queries, session loot-pool caches, stable tracking keys, Obtained persistence, and sanitized result recording. It never receives or stores Blizzard Roll or Pass callbacks.
2. Build a query key from source identity, Journal difficulty, class, and concrete specialization. Cache the generated pool only for the current session; do not persist names, icons, item links, or the derived pool because Journal data and item variants can change with client builds and seasons.
3. Query the Journal lazily on first cog expansion and invalidate the affected cache when its specialization, dungeon threshold, or relevant catalog identity changes.
4. Serialize all Journal selection through one FIFO owner because the Encounter Journal has one shared mutable instance/difficulty/filter context. For the MVP, drive Blizzard's visible navigation path directly: select the appropriate Raid or Dungeon tab, display the requested instance so `EncounterJournal.instanceID` and the backend agree, set difficulty, select the encounter when applicable, clear the slot filter, and apply the class/spec loot filter. `EJ_SetDifficulty` synchronously refreshes the instance stored on `EncounterJournal`; setting that field through `EncounterJournal_DisplayInstance` first prevents the previously viewed page from replacing the request. Do not hide the Guide, wait for it to close, or restore its prior page. If it is open, the user may see it navigate and it remains on the queried page. Apply this navigation once per request, then use bounded exponential polling without restarting cold Journal data.
5. Before caching a result, verify the exact `EncounterJournal.instanceID` and encounter context, the Journal difficulty through `C_EncounterJournal.GetBaseDifficultyID`, class/spec filter, and every public returned encounter ID against the active queue owner. Base-difficulty comparison is required because Lair flexible Mythic behaves as primary Mythic and Lair World behaves as Raid Finder even though each retains its distinct rule identity and display label. Discover dungeon encounters from the already selected instance using the same single-index `EJ_GetEncounterInfoByIndex` call used by Blizzard. `EncounterJournalItemInfo.encounterID` is documented as optional, so a nil encounter is valid once the instance context matches; a present encounter must belong to the requested source. Do not gate enumeration on `EJ_IsLootListOutOfDate()`; Blizzard uses that flag to choose how its visible loot page refreshes, and a cold but loadable list may still be marked out of date. A mismatched or incomplete context remains Loading until the bounded timeout and can never complete or populate another row's cache. Only after the active owner finishes may the next request select Journal state.
6. Enumerate `C_EncounterJournal.GetLootInfoByIndex` entries and retain the exact returned link. Deduplicate only identical base item IDs within one combination while preserving the first Journal position.
7. Classify an entry as a current bonus-roll candidate when it is either equippable or its explicit `C_Item.GetItemSpecInfo(itemID)` table contains the selected concrete specialization. Always exclude items identified as cosmetic, decor, or Delve companion Curios. `C_Item.DoesItemContainSpec` is not a discriminator because it also returns true for unrestricted rewards. A cache miss or indeterminate classification is Loading, not Excluded; deduplicate asynchronous item-data requests and refresh only waiting open sections.
8. Treat secret or invalid identifiers as opaque and fail closed. Never compare, format, persist, or use a secret value as a table key.
9. Listen to `ITEM_DATA_LOAD_RESULT` as the primary completion event for
   `C_Item.RequestLoadItemDataByID`, with `GET_ITEM_INFO_RECEIVED` retained as
   a compatibility signal. Defer completion refreshes to the next frame so a
   synchronous event cannot be overwritten by the original Loading result.
10. Read a Journal pool immediately after its one navigation pass. Treat
    zero-count, zero-candidate, missing-row, and missing-link results as
    transient, then retry Journal and item requests through shared schedulers
    after 0.25, 0.5, 1, and 2 seconds. Perform a final item-cache
    reconciliation, then show a manual Retry action instead of leaving a
    permanent Loading or trusting a transient empty result. While refreshing
    an expanded settings row, preserve its last rendered item-row height so a
    temporary Loading message does not collapse the surrounding table. Keep
    the panel visually unchanged during the one-tick pending state and show
    Loading only when the immediate read confirms that data is incomplete.

### Character-specific persistence

Add a normalized schema-owned table separate from the roll rules. Its logical shape is:

```text
obtainedItems.raid[instanceID][encounterID][difficultyID][specID][itemID] = true
obtainedItems.dungeon[challengeMapID][specID][itemID] = true
obtainedItems.worldBoss[encounterID][specID][itemID] = true
```

Only concrete specialization IDs are valid in this table; `0` is a dynamic UI selection and is never a persistence key. Unchecking an item removes its boolean state. Disabling or deleting a rule does not erase its obtained items, so changing away from and later returning to a combination restores progress. Orphaned entries from a later season are harmless and remain hidden unless that exact catalog identity returns.

### Roll-result lifecycle and the false-expiration TODO

The current handler receives `BONUS_ROLL_STARTED`, clears challenge state, and disarms the confirmation, but it does not mark the offer as used. The later `SPELL_CONFIRMATION_TIMEOUT` therefore follows the ordinary expiration path and prints the incorrect `expired without being used` message. The item tracker and this bug require the same explicit observational lifecycle:

1. After confirmation revalidates the immutable offer snapshot, consume the one-shot authorization exactly as today. Copy the already-validated snapshot into a separate observational result candidate before invoking the captured native Roll callback. This candidate cannot authorize or repeat an action.
2. `BONUS_ROLL_STARTED` has no payload. Associate it only with that candidate, transition the offer to Used/Rolling, retain its source and concrete loot-specialization context, and prevent any later confirmation timeout for that offer from being reported as expiration.
3. Register `BONUS_ROLL_FAILED` and `BONUS_ROLL_RESULT`. Failure clears the candidate without marking an item. A result is accepted only for the current started candidate.
4. `BONUS_ROLL_RESULT` supplies `typeIdentifier`, exact `itemLink`, quantity, actual `specID`, optional `currencyID`, and `isSecondaryResult`, but no encounter or difficulty. Combine its public fields with the retained source snapshot. Use the result's concrete `specID`, not the configured desired spec, so a confirmed wrong-spec roll is recorded under the specialization that actually produced the reward.
5. For an item result, derive a public base item ID from the exact result link and mark that source/difficulty/spec/item combination Obtained. Save the state even if its item section is not currently open; refresh an open matching checkbox and summary in place.
6. Report one player-facing success message for the primary result, for example `Bonus roll used on Heroic Ula'tek with Restoration loot specialization: [Item].` Secondary result events may update matching data but must not produce duplicate completion messages.
7. A confirmation timeout before `BONUS_ROLL_STARTED` remains a genuine expiration. A timeout after Started, Result, or Failed is cleanup only and must not print the expiration warning.
8. Clear stale observational candidates on a new offer, addon disable, explicit failure, completed result, or invalid/secret result state. Do not let observational cleanup alter the existing authorization rules.

The implementation is complete. The TODO remains open only until this lifecycle
is verified with a live roll.

### Confirmed API surface

- The Encounter Journal can enumerate the displayed loot pool for a selected instance, encounter, difficulty, class, and specialization. The relevant APIs are `EJ_SelectInstance`, `EJ_SelectEncounter`, `EJ_SetDifficulty`, `EJ_SetLootFilter`, `EJ_GetNumLoot`, and `C_EncounterJournal.GetLootInfoByIndex`.
- `EncounterJournalItemInfo` supplies the base item ID, encounter ID, name, icon, slot, armor type, link, seasonal display ID, and per-player or rarity display flags. It does not identify whether an entry is specifically eligible for a bonus roll.
- `displayAsPerPlayerLoot` cannot identify bonus-rollable items because Blizzard also sets it on non-equipment rewards such as decor.
- `C_Item.IsCurioItem` identifies Delve companion curios, not raid rewards whose names contain "Curio". Raid Curios are excluded by being non-equippable.
- `BONUS_ROLL_STARTED` confirms that a roll began but has no payload. `BONUS_ROLL_FAILED` also has no payload.
- `BONUS_ROLL_RESULT` supplies the reward type, exact item link, quantity, actual loot specialization ID, currency ID, and secondary-result state. It does not repeat the source encounter or difficulty.
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

The initial equipment rule selected exactly the three equipment entries and rejected the Curio and decor.

A second live classification test used Mythic The Lost Explorers with Enhancement Shaman loot. Venomcast Remnant (`270924`) is a bonus-rollable tier token reported as non-equippable Miscellaneous/Junk with no cosmetic, decor, Curio, or consumable flag. Its explicit specialization table contains Elemental (`262`), Enhancement (`263`), and Restoration (`264`). By comparison, Slumbering Coil Curio (`270909`) has no `GetItemSpecInfo` result even though `DoesItemContainSpec(270909, 7, 263)` returns true. The implementation therefore uses explicit specialization-table membership rather than `DoesItemContainSpec`, item class, Journal `Other` filter type, item name, or conversion spell ID.

Additional validation must include encounters containing mounts, pets, cosmetic armor, more tier tokens, World Boss loot, and dungeon loot at every base difficulty the current Journal exposes. Verify that Timewalking is absent, Mythic and all Mythic+ thresholds return the Mythic pool, and simultaneous expansions or Retry actions cannot exchange results between sources.
