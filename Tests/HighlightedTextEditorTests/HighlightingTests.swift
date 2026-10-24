import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif
@testable import HighlightedTextEditor

final class HighlightingTests: XCTestCase {
    private struct Renderer: HighlightingTextEditor {
        var text: String
        let highlightRules: [HighlightRule]
    }

    #if os(macOS)
    private let bold: SymbolicTraits = .bold
    private let italic: SymbolicTraits = .italic
    #else
    private let bold: SymbolicTraits = .traitBold
    private let italic: SymbolicTraits = .traitItalic
    #endif

    private func rule(_ pattern: String, _ formatting: TextFormattingRule) throws -> HighlightRule {
        HighlightRule(pattern: try NSRegularExpression(pattern: pattern), formattingRule: formatting)
    }

    private func traits(_ text: NSAttributedString, at offset: Int) throws -> SymbolicTraits {
        let font = try XCTUnwrap(text.attribute(.font, at: offset, effectiveRange: nil) as? SystemFontAlias)
        return font.fontDescriptor.symbolicTraits
    }

    func testAttributeOnlyRulesPreserveMixedFonts() throws {
        let text = "> ***bruh* moment**"
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 12
        let result = Renderer.getHighlightedText(text: text, highlightRules: [
            try rule(#"\*\*.*\*\*"#, TextFormattingRule(fontTraits: bold)),
            try rule("bruh", TextFormattingRule(fontTraits: italic)),
            try rule(".*", TextFormattingRule(key: .paragraphStyle, value: paragraph)),
            try rule(".*", TextFormattingRule(key: .underlineStyle, value: 1)),
            try rule(".*", TextFormattingRule(key: .strikethroughStyle, value: 1)),
            try rule(".*", TextFormattingRule(key: .foregroundColor, value: SystemColorAlias.red))
        ])
        let bruh = (text as NSString).range(of: "bruh").location
        let moment = (text as NSString).range(of: "moment").location
        XCTAssertTrue(try traits(result, at: bruh).contains(bold.union(italic)))
        XCTAssertTrue(try traits(result, at: moment).contains(bold))
        XCTAssertFalse(try traits(result, at: moment).contains(italic))
        XCTAssertEqual(result.attribute(.underlineStyle, at: bruh, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(result.string, text)
    }

    func testBroaderTraitRuleCombinesEachExistingRun() throws {
        let result = Renderer.getHighlightedText(text: "one two three", highlightRules: [
            try rule("two", TextFormattingRule(fontTraits: italic)),
            try rule(".*", TextFormattingRule(fontTraits: bold))
        ])
        XCTAssertTrue(try traits(result, at: 4).contains(bold.union(italic)))
        for offset in [0, 8] {
            XCTAssertTrue(try traits(result, at: offset).contains(bold))
            XCTAssertFalse(try traits(result, at: offset).contains(italic))
        }
    }

    func testExplicitFontStillOverridesTraitsForCode() throws {
        let mono = SystemFontAlias.monospacedSystemFont(ofSize: 15, weight: .regular)
        let result = Renderer.getHighlightedText(text: "word code", highlightRules: [
            try rule(".*", TextFormattingRule(fontTraits: bold.union(italic))),
            try rule("code", TextFormattingRule(key: .font, value: mono))
        ])
        XCTAssertTrue(try traits(result, at: 0).contains(bold.union(italic)))
        XCTAssertEqual(result.attribute(.font, at: 5, effectiveRange: nil) as? SystemFontAlias, mono)
    }

    func testCallbackStillReceivesUnicodeMatchAndRange() throws {
        let text = "😀 café"
        var contents: [String] = []
        let result = Renderer.getHighlightedText(text: text, highlightRules: [
            try rule("café", TextFormattingRule(key: .underlineStyle, calculateValue: { content, range in
                contents.append(content)
                XCTAssertEqual(String(text[range]), "café")
                return 1
            }))
        ])
        XCTAssertEqual(contents, ["café"])
        XCTAssertEqual(result.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(result.string, text)
    }

    func testMatchFilterValidatesAgainstFullDocument() throws {
        let text = "😀 __literal__ __valid__"
        var candidates: [String] = []
        let highlight = HighlightRule(
            pattern: try NSRegularExpression(pattern: "__.*?__"),
            formattingRule: TextFormattingRule(key: .underlineStyle, value: 1),
            matchFilter: { source, range in
                XCTAssertEqual(source, text)
                let content = (source as NSString).substring(with: range)
                candidates.append(content)
                return content == "__valid__"
            }
        )
        let result = Renderer.getHighlightedText(text: text, highlightRules: [highlight])
        XCTAssertEqual(candidates, ["__literal__", "__valid__"])
        XCTAssertNil(result.attribute(.underlineStyle, at: (text as NSString).range(of: "literal").location, effectiveRange: nil))
        XCTAssertEqual(result.attribute(.underlineStyle, at: (text as NSString).range(of: "valid").location, effectiveRange: nil) as? Int, 1)
    }

    func testParserRangesPreserveTraitsAndUseCurrentSource() throws {
        var inputs: [String] = []
        let parsed = HighlightRule(ranges: { text in
            inputs.append(text)
            return [(text as NSString).range(of: "café")]
        }, formattingRules: [TextFormattingRule(fontTraits: italic)])
        for text in ["😀 café", "new café text"] {
            let result = Renderer.getHighlightedText(text: text, highlightRules: [
                parsed,
                try rule(".*", TextFormattingRule(fontTraits: bold))
            ])
            let location = (text as NSString).range(of: "café").location
            XCTAssertTrue(try traits(result, at: location).contains(bold.union(italic)))
            XCTAssertFalse(try traits(result, at: 0).contains(italic))
            XCTAssertEqual(result.string, text)
        }
        XCTAssertEqual(inputs, ["😀 café", "new café text"])
    }

    func testInvalidParserRangesAreIgnored() {
        let text = "😀 café"
        let parsed = HighlightRule(ranges: { _ in [
            NSRange(location: NSNotFound, length: 1),
            NSRange(location: -1, length: 2),
            NSRange(location: 0, length: -1),
            NSRange(location: 1, length: 1), // Inside an emoji's surrogate pair.
            NSRange(location: 0, length: Int.max),
            NSRange(location: 0, length: 0),
            NSRange(location: 3, length: 4)
        ] }, formattingRules: [TextFormattingRule(key: .underlineStyle, value: 1)])
        let result = Renderer.getHighlightedText(text: text, highlightRules: [parsed])
        XCTAssertNil(result.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(result.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(result.string, text)
    }

    func testFontTransformReceivesEachExistingRun() throws {
        let large = SystemFontAlias.systemFont(ofSize: 24)
        let transformed = TextFormattingRule(fontTransform: { font in
            #if os(macOS)
            return NSFont(descriptor: font.fontDescriptor, size: font.pointSize + 1) ?? font
            #else
            return UIFont(descriptor: font.fontDescriptor, size: font.pointSize + 1)
            #endif
        })
        let result = Renderer.getHighlightedText(text: "one two", highlightRules: [
            try rule("one", TextFormattingRule(key: .font, value: large)),
            try rule("two", TextFormattingRule(fontTraits: italic)),
            try rule(".*", transformed)
        ])
        let one = try XCTUnwrap(result.attribute(.font, at: 0, effectiveRange: nil) as? SystemFontAlias)
        let two = try XCTUnwrap(result.attribute(.font, at: 4, effectiveRange: nil) as? SystemFontAlias)
        XCTAssertEqual(one.pointSize, 25)
        XCTAssertEqual(two.pointSize, defaultEditorFont.pointSize + 1)
        XCTAssertFalse(one.fontDescriptor.symbolicTraits.contains(italic))
        XCTAssertTrue(two.fontDescriptor.symbolicTraits.contains(italic))
    }

    func testEmptyTextAndNoRulesRemainSupported() {
        XCTAssertEqual(Renderer.getHighlightedText(text: "", highlightRules: []).string, "")
        XCTAssertEqual(Renderer.getHighlightedText(text: "😀 plain", highlightRules: []).string, "😀 plain")
    }
}
