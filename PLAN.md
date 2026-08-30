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
