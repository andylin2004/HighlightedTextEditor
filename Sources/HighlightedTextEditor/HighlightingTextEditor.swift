//
//  HighlightingTextEditor.swift
//
//
//  Created by Kyle Nazario on 8/31/20.
//

import SwiftUI

#if os(macOS)
import AppKit

public typealias SystemFontAlias = NSFont
public typealias SystemColorAlias = NSColor
public typealias SymbolicTraits = NSFontDescriptor.SymbolicTraits
public typealias SystemTextView = NSTextView
public typealias SystemScrollView = NSScrollView

let defaultEditorFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
let defaultEditorTextColor = NSColor.labelColor

#else
import UIKit

public typealias SystemFontAlias = UIFont
public typealias SystemColorAlias = UIColor
public typealias SymbolicTraits = UIFontDescriptor.SymbolicTraits
public typealias SystemTextView = UITextView
public typealias SystemScrollView = UIScrollView

let defaultEditorFont = UIFont.preferredFont(forTextStyle: .body)
let defaultEditorTextColor = UIColor.label

#endif

public struct TextFormattingRule {
    public typealias AttributedKeyCallback = (String, Range<String.Index>) -> Any

    let key: NSAttributedString.Key?
    let calculateValue: AttributedKeyCallback?
    let fontTraits: SymbolicTraits
    let transformFont: ((SystemFontAlias) -> SystemFontAlias)?

    // ------------------- convenience ------------------------

    public init(key: NSAttributedString.Key, value: Any) {
        self.init(key: key, calculateValue: { _, _ in value }, fontTraits: [])
    }

    public init(key: NSAttributedString.Key, calculateValue: @escaping AttributedKeyCallback) {
        self.init(key: key, calculateValue: calculateValue, fontTraits: [])
    }

    public init(fontTraits: SymbolicTraits) {
        self.init(key: nil, fontTraits: fontTraits)
    }

    /// Transform each existing font run without flattening its size or traits.
    public init(fontTransform: @escaping (SystemFontAlias) -> SystemFontAlias) {
        self.init(key: nil, transformFont: fontTransform)
    }

    // ------------------ most powerful initializer ------------------

    init(
        key: NSAttributedString.Key? = nil,
        calculateValue: AttributedKeyCallback? = nil,
        fontTraits: SymbolicTraits = [],
        transformFont: ((SystemFontAlias) -> SystemFontAlias)? = nil
    ) {
        self.key = key
        self.calculateValue = calculateValue
        self.fontTraits = fontTraits
        self.transformFont = transformFont
    }
}

public struct HighlightRule {
    /// Validate a regex match against its surrounding document before styling.
    public typealias MatchFilter = (String, NSRange) -> Bool
    let pattern: NSRegularExpression?
    let ranges: ((String) -> [NSRange])?

    let formattingRules: [TextFormattingRule]
    let matchFilter: MatchFilter?

    // ------------------- convenience ------------------------

    public init(pattern: NSRegularExpression, formattingRule: TextFormattingRule, matchFilter: MatchFilter? = nil) {
        self.init(pattern: pattern, formattingRules: [formattingRule], matchFilter: matchFilter)
    }

    // ------------------ most powerful initializer ------------------

    public init(pattern: NSRegularExpression, formattingRules: [TextFormattingRule], matchFilter: MatchFilter? = nil) {
        self.pattern = pattern
        self.ranges = nil
        self.formattingRules = formattingRules
        self.matchFilter = matchFilter
    }

    /// Supply ranges from a parser or other document model. Called with the
    /// current source on every highlight pass; invalid UTF-16 ranges are ignored.
    public init(ranges: @escaping (String) -> [NSRange], formattingRules: [TextFormattingRule]) {
        self.pattern = nil
        self.ranges = ranges
        self.formattingRules = formattingRules
        self.matchFilter = nil
    }

}

internal protocol HighlightingTextEditor {
    var text: String { get set }
    var highlightRules: [HighlightRule] { get }
}

public typealias OnSelectionChangeCallback = ([NSRange]) -> Void
public typealias IntrospectCallback = (_ editor: HighlightedTextEditor.Internals) -> Void
public typealias EmptyCallback = () -> Void
public typealias OnCommitCallback = EmptyCallback
public typealias OnEditingChangedCallback = EmptyCallback
public typealias OnTextChangeCallback = (_ editorContent: String) -> Void

extension HighlightingTextEditor {
    var placeholderFont: SystemColorAlias { SystemColorAlias() }

    static func getHighlightedText(text: String, highlightRules: [HighlightRule]) -> NSMutableAttributedString {
        let highlightedString = NSMutableAttributedString(string: text)
        let all = NSRange(location: 0, length: text.utf16.count)

        let editorFont = defaultEditorFont
        let editorTextColor = defaultEditorTextColor

        highlightedString.addAttribute(.font, value: editorFont, range: all)
        highlightedString.addAttribute(.foregroundColor, value: editorTextColor, range: all)

        highlightRules.forEach { rule in
            let ranges = rule.ranges?(text) ?? rule.pattern?.matches(in: text, options: [], range: all).map(\.range) ?? []
            ranges.forEach { range in
                guard range.location != NSNotFound, range.location >= 0, range.length > 0,
                      range.location <= all.length, range.length <= all.length - range.location,
                      let matchRange = Range(range, in: text),
                      rule.matchFilter?(text, range) ?? true else { return }
                rule.formattingRules.forEach { formattingRule in

                    // Preserve font boundaries within a match. Attribute-only
                    // rules must not replace fonts elsewhere in that range.
                    if !formattingRule.fontTraits.isEmpty || formattingRule.transformFont != nil {
                        var fonts: [(NSRange, SystemFontAlias)] = []
                        highlightedString.enumerateAttribute(.font, in: range, options: []) { value, range, _ in
                            let previousFont = value as? SystemFontAlias ?? editorFont
                            let font = formattingRule.transformFont?(previousFont) ?? previousFont.with(formattingRule.fontTraits)
                            fonts.append((range, font))
                        }
                        for (range, font) in fonts {
                            highlightedString.addAttribute(.font, value: font, range: range)
                        }
                    }

                    let matchContent = String(text[matchRange])
                    guard let key = formattingRule.key,
                          let calculateValue = formattingRule.calculateValue else { return }
                    highlightedString.addAttribute(
                        key,
                        value: calculateValue(matchContent, matchRange),
                        range: range
                    )
                }
            }
        }

        return highlightedString
    }
}
