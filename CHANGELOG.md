# Changelog

All notable changes to tmux-scrollable are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-10-03

### Changed

- `Alt+r` now steps up through the presets and back down (33 → 50 → 66 → 100 → 66 → 50 …)
  instead of looping back to the smallest. The direction is remembered per column; a column
  at a width matching no preset first steps up to the next larger one.
- Default presets are `33.33 50 66.66 100` (were `30 50 90`); `@scrollable-presets` accepts
  decimals.

### Documented

- Pane numbers (`prefix q`) follow creation order, so a column inserted mid-strip gets the
  highest number rather than the one matching its position.

## [0.1.0] - 2026-10-03

First release.

### Added

- Scrollable tiling for tmux panes, like niri and PaperWM: columns live on a horizontal
  strip wider than the terminal and the view scrolls instead of squeezing panes.
- `Alt+n` opens a new column right of the current one and scrolls to it
  (`@scrollable-split-key`, `@scrollable-width`).
- `Alt+r` cycles the current column through 30% / 50% / 90% of the terminal, like niri's
  `Mod+R` (`@scrollable-preset-key`, `@scrollable-presets`).
- Explicit panning on every focus change so the whole active column is visible with the
  least movement (niri's `center-focused-column "never"`). Works with `select-pane`, the
  mouse and vim-tmux-navigator.
- Column widths are fixed cell counts: chosen relative to the terminal when set, then
  kept when the terminal is resized. Space after the last column stays empty; a single
  column always fills the terminal.
- Columns are read from tmux's own layout tree, so vertical splits and stock horizontal
  splits inside a column are left alone; widths are applied with one `select-layout`.
- Hooks are registered under the array key `[tmux-scrollable]` and never clobber user
  hooks. Runs are serialised with `flock` when available.
- Refuses to load on tmux older than 3.8, which renders panned windows incorrectly and can
  spin the server at 100% CPU (tmux issue 5664).
- `cursor-offset.patch`: one-line fix for tmux hiding the cursor while the view is
  scrolled, needed until it is upstream.
- `@scrollable-log` debug log of every layout change.
- End-to-end test suite (`test/e2e.sh`) on a throwaway tmux server, run in CI against
  tmux 3.8-rc3 with the patch applied.
- Demo recording script (`demo/record.sh`) producing `demo.gif` with asciinema and agg.

### Known limits

- Column widths come from the client that triggered the change; other clients of a
  different size attached to the same session get a scaled view.
- Columns resized by hand snap back to their stored width on the next split, close or
  `Alt+r`.
- tmux-resurrect restores a scrolled window squeezed into the terminal.

[Unreleased]: https://github.com/yanglited/tmux-scrollable/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/yanglited/tmux-scrollable/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yanglited/tmux-scrollable/releases/tag/v0.1.0
