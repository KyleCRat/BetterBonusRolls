# BetterBonusRolls development guidance

- Target only Mainline WoW Interface `120105` and Lua 5.1.
- Verify uncertain APIs against the local BlizzardInterfaceCode export matching the target client build.
- Keep all persisted settings character-specific in `BetterBonusRollsDB` through LibSimpleDB.
- Keep LibModernSettings, LibSimpleDB, and LibChangelog pinned git submodules;
  embed LibStub locally. Align submodule commits with released `.pkgmeta` tags.
- LibChangelog 1.0.1 requires LibModernSettings 1.10.0 or newer. Keep LMS at
  `Libs/LibModernSettings-1.0`, including its Media directory, so its embedded
  texture paths resolve without another addon providing the library.
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

## In-game changelog

- `Changelog/Changelog.lua` registers after database initialization, independently
  of bonus-roll filtering. Store `autoShow` and `acknowledgedVersion` through
  `NS.DB` under `changelog`; BBR intentionally uses character-specific storage
  rather than the library's suggested account-wide namespace.
- LibChangelog owns the shared `/changelog` command, notification timing and
  acknowledgement. Do not add another popup queue or copy its UI. Highlight
  actions may navigate to existing settings; they must not roll or decline.
- Keep `CHANGELOG.md`'s Unreleased section current during development.
  `Changelog/ReleaseNotes.lua` is a generated release snapshot. After its initial
  integration preview, leave it unchanged until explicit release preparation.
  Do not hand-edit it or run its generator/check on every development change.
- During release preparation, finalize the changelog and corresponding
  `Changelog/Highlights.lua` entry under the same version as the TOC, then run:

  ```powershell
  lua Libs/LibChangelog-1.0/tools/generate.lua CHANGELOG.md Changelog/ReleaseNotes.lua VERSION
  lua Libs/LibChangelog-1.0/tools/generate.lua CHANGELOG.md Changelog/ReleaseNotes.lua VERSION --check
  ```

  Replace `VERSION` with the finalized release version. Unreleased snapshots
  are manual-preview only; do not relabel one as a released version at runtime.

## Verification

### Development diagnostics

- Hidden commands: `/bbr dev` toggles development mode; `/bbr dev on` and
  `/bbr dev off` set it explicitly. It defaults off and persists per character.
- Development mode enables `/bbr preview` (`/bbr p`) without reloading. Turning
  it off closes the preview and stops diagnostic captures. It does not enable
  bonus-roll filtering or authorize any roll.
- Diagnostics print only to local chat; use the existing chat-copy interface.
  No log buffer or saved log is retained. Keep command usage out of the README
  and ordinary help/settings.
- Tooltip reconciliation is disabled in `LootReconciliation.lua`; retain its
  implementation for investigation, but do not re-enable it without explicit
  approval and evidence of reliable personal remaining-loot semantics.
  Development mode must not enable tooltip-based history writes. Actual
  bonus-roll rewards and manual checklist changes remain independent.
- The retained reconciliation write path must not uncheck an already-confirmed
  item or clear its confirmation based on tooltip contents. Existing saves do
  not distinguish confirmation sources; protect all confirmed records.
  Explicit manual unchecking remains available and retains that evidence.
- Compare `diagnostic API` and `native hover` tooltip lines. The retained
  reconciliation path does not read or apply tooltips while disabled.
  Hover the reward icon before/after changing specs to capture Blizzard's shown
  tooltip alongside the separate API queries. Repeated text reports unchanged.
- Diagnostic reads must never be passed to reconciliation or change its owner.
  Secret values print as markers, never through a recursive table dump.
- A world transition invalidates the active offer's tooltip owner and cancels
  tooltip reconciliation for the rest of that offer. Reissued prompts must not
  restore it; diagnostic reads and actual bonus-roll reward tracking remain separate.
- Prey diagnostics include active quest changes, quest turn-in/removal,
  pending confirmation records, UI map IDs, and world transitions. A recent
  Prey quest ID is transient diagnostic context, not an offer-classification
  signal. `offer identity replaced` logs the previous owner and deadline.

### Checks

- Style baseline: StyLua 2.5.2 and Selene 0.31.0. Configuration is prepared,
  but the initial formatting/lint migration has not been run because neither
  executable was available during setup. Do not report style compliance until
  the checks pass; do not install tooling without explicit permission.
- Use Lua 5.1, UTF-8/LF, four spaces, and the formatter's 80-column guide.
  Keep nonempty functions/callbacks and loops multiline. Only simple
  single-branch conditionals may collapse. Review naming and logical spacing
  even when formatting and lint checks pass.
- Run `stylua --check .` and `selene .` with zero findings. Apply formatting
  with `stylua --verify .` when completing the initial migration. Owned addon
  Lua and existing tests are included; LibStub and LibDBIcon remain upstream
  vendors. Development-only configuration is excluded from release packages.
- LibModernSettings and LibSimpleDB are pinned maintained-library submodules.
  They still need standalone style configuration/migration in their own
  repositories; do not rewrite or advance their pins as an addon-only cleanup.
  After those repositories adopt the baseline, run both checks from each
  library root as well. Parent Selene excludes them for separate checking;
  parent StyLua does not silently exclude them. Until then, migration remains
  incomplete and checks must not be described as an all-library style pass.
- LibChangelog carries its own style configuration. Run its style checks from
  `Libs/LibChangelog-1.0` separately, plus
  `lua tests/run.lua ../LibStub/LibStub.lua`. The generated release snapshot is
  excluded from addon style checks, not from Lua syntax and load-order checks.
- Run Lua syntax checks when `luac` is available.
- Run `lua tests/run.lua` when a Lua 5.1-compatible interpreter is available.
- Run the static safety scan in `tests/static-safety.ps1`.
- Review all shipped Lua for the safety invariants before release.
