# Local HighlightedTextEditor fork

Upstream: https://github.com/kyle-n/HighlightedTextEditor
Base revision: 759d7b4bd2c10d0bbe93bc62d68572a3702049e3
License: MIT (see LICENSE).

Fork: https://github.com/andylin2004/HighlightedTextEditor
Branch: codex/consumer-editor-fixes

consumer currently uses a vendored copy through a relative Xcode package reference.
Existing API calls remain source-compatible. The highlighting engine
combines font traits for each existing font run instead of copying the final
run's font over the entire match. Attribute-only rules leave fonts untouched.
This preserves overlapping bold and italic styles when quote, underline,
strikethrough, color, or other attribute rules cover a larger range.

The UIKit update path also defers document and selection replacement during
marked-text composition. Committed selections are stored as UTF-16 ranges and
clamped before restoration, rather than retaining stale UITextRange objects.
The coordinator refreshes its parent each update so commits use current bindings
and callbacks. consumer's integration tests cover real marked text through SwiftUI
refreshes, composition commit, Unicode input, and shorter external replacements.

HighlightRule also accepts an optional matchFilter callback. It receives the full
document and UTF-16 match range, allowing consumer to share contextual Markdown
validation between controls and highlighting without putting Discord syntax
into the package. Existing rules accept every regex match by default.

HighlightRule also accepts parser-provided UTF-16 ranges through its ranges
initializer, ignoring invalid ranges before applying formatting.

Regression tests live in Tests/HighlightedTextEditorTests. consumer's editor tests
also exercise the actual SwiftUI editor with this package.

These changes are published in the fork linked above.
When updating from upstream, retain the font-run fix and run both test suites.
