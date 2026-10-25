# HighlightedTextEditor fork

Upstream: https://github.com/kyle-n/HighlightedTextEditor
Base revision: 759d7b4bd2c10d0bbe93bc62d68572a3702049e3
Fork: https://github.com/andylin2004/HighlightedTextEditor
Branch: feat/editor-improvements
License: MIT (see LICENSE).

## Rendering

The renderer combines font traits separately for every existing font run.
Attribute-only rules preserve font boundaries, including different sizes and
nested bold and italic styling.

`TextFormattingRule(fontTransform:)` transforms each existing font run. Callers
can adjust weight while retaining the run's size and other traits. Application
styling policies remain in the caller.

`highlightingRevision(_:)` opts into reusing the applied rendering on unchanged
updates. Change the revision whenever highlighting callbacks or captured values
change behavior. Exact UTF-16 text, text size category, and color scheme changes
invalidate rendering automatically, as do native edits and input composition.
Reused updates still refresh introspection and callbacks and preserve the live
selection. Without a revision, every update renders as before.

## Matching

`HighlightRule` supports an optional `matchFilter` receiving the complete source
and UTF-16 match range. Existing regex rules accept all matches by default.

The `ranges` initializer also accepts parser-provided UTF-16 ranges. Providers
receive the current source on every highlighting pass. Empty, out-of-bounds, and
invalid Unicode ranges are ignored. Existing regex initializers remain supported.

## Input composition

The UIKit update path defers document and selection replacement during active
marked-text composition. Committed selections use UTF-16 offsets and are clamped
before restoration. The coordinator refreshes its parent on each update so that
commits use the current bindings and callbacks.

## Verification

Package regressions live in `Tests/HighlightedTextEditorTests`, covering font-run
composition, transforms, regex callbacks and filters, parser ranges, and invalid
ranges. Consumer integration suites should additionally exercise actual input
composition, selection restoration, and binding refreshes in a hosted editor.

When updating from upstream, retain these behaviors and run the package tests
and the consuming application's integration suite.
