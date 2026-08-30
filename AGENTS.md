# BetterBonusRolls development guidance

- Target only Mainline WoW Interface `120100` and Lua 5.1.
- Verify uncertain APIs against the local BlizzardInterfaceCode export for build `12.1.0.69497`.
- Keep all persisted settings character-specific in `BetterBonusRollsDB` through LibSimpleDB.
- Keep LibModernSettings and LibSimpleDB pinned git submodules; embed LibStub locally.
- Preserve Dungeon Journal and current-season ordering instead of sorting labels alphabetically.
- Treat secret values as opaque. Test them with `issecretvalue` before comparison, formatting, indexing, arithmetic, or branching.

## Non-negotiable bonus-roll safety invariants

- Never call the spell-confirmation accept or decline APIs directly from addon code.
- Never programmatically click Blizzard's Roll or Pass buttons.
- Never expose a slash command or test control that spends or declines a roll.
- While enabled, Blizzard's Pass button only hides the frame; it never invokes its captured native callback.
- The captured native Roll callback remains a local upvalue and is reachable only after a real Blizzard Roll-button click followed by acceptance of the addon's confirmation for an unchanged offer snapshot.
- Consume the one-shot authorization before invoking the captured native Roll callback.
- Disarm on cancel, Escape, timeout, frame hide, new offer, loot-spec change, rule change, disable, or any snapshot mismatch.
- A mismatch never auto-reopens confirmation; require another Blizzard Roll-button click.

## Verification

- Run Lua syntax checks when `luac` is available.
- Run `lua tests/run.lua` when a Lua 5.1-compatible interpreter is available.
- Run the static safety scan in `tests/static-safety.ps1`.
- Review all shipped Lua for the safety invariants before release.
