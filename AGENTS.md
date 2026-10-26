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

- Style baseline: StyLua 2.5.2 and Selene 0.31.0. Use the existing executables
  (by full path if absent from the session's PATH); do not install tooling,
  change global PATH, or add custom style checkers without explicit permission.
- Use Lua 5.1, UTF-8/LF, four spaces, and the formatter's 80-column guide.
  Keep nonempty functions/callbacks and loops multiline. Only simple
  single-branch conditionals may collapse. Review naming and logical spacing
  even when formatting and lint checks pass.
- Run `stylua --check .` and `selene .` with zero findings, including warnings.
  Apply formatting with `stylua --verify .`; add `--respect-ignores` when passing
  individual files. These checks cover all owned addon Lua and existing tests.
  Development-only configuration is excluded from release packages.
- Library lint migrations are being completed elsewhere to avoid repeating
  the work. Verification is temporarily deferred for the current pins:
  LibModernSettings 1.10.0, LibSimpleDB 2.0.0, and LibChangelog 1.0.1.
  Leave their code and pins untouched during this addon-only migration.
  These are per-library deferrals, not permanent lint exemptions.
- When adopting a linted release of each maintained library, remove its
  `.styluaignore` entry in the same update. Do not restore a blanket `Libs/**`
  exclusion: StyLua reads ancestor ignores even when run inside a submodule.
  Root formatting checks must then visit that library using its own config.
  LibStub and LibDBIcon remain upstream/vendor exclusions.
- From that update onward, require `stylua --check .` and `selene .` from the
  updated library's root with zero findings, plus its Lua 5.1 syntax checks,
  existing tests, and compatibility checks. Keep parent Selene exclusions only
  to separate library globals from the addon's environment; they must be paired
  with those separate library checks, not treated as verification exemptions.
  Check each later library update under the same rules and keep `.pkgmeta`
  tags aligned with gitlinks. Resolve migration work in the owning repository
  rather than repeating it in each consumer. Report any remaining deferrals;
  an addon-only pass must not be presented as an all-library pass.
- The generated `Changelog/ReleaseNotes.lua` snapshot is excluded from style
  checks, not from Lua syntax and load-order checks. Leave it unchanged during
  ordinary development and style work; follow the release procedure above.
- Keep `wow.yml` limited to reviewed globals used by this addon and its existing
  tests. Verify additions against the local Blizzard export or an explicit
  external contract. Keep default lint checks enabled; prefix intentionally
  unused bindings with `_` and document narrow exceptions beside the code.
- Run Lua syntax checks when `luac` is available.
- Run `lua tests/run.lua` when a Lua 5.1-compatible interpreter is available.
- Run the static safety scan in `tests/static-safety.ps1`.
- Review all shipped Lua for the safety invariants before release.
