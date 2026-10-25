#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import HighlightedTextEditor

final class RenderReuseTests: XCTestCase {
    @MainActor
    func testReturnFromHeadingResetsTypingFont() throws {
        _ = NSApplication.shared
        var source = "# Heading"
        var nativeView: NSTextView?
        let binding = Binding(get: { source }, set: { source = $0 })
        let rule = HighlightRule(pattern: try NSRegularExpression(pattern: "^#[^\\n]*"),
                                 formattingRule: TextFormattingRule(key: .font, value: NSFont.boldSystemFont(ofSize: 28)))
        func editor() -> some View {
            HighlightedTextEditor(text: binding, highlightRules: [rule])
                .onSelectionChange { (_: NSRange) in }
                .introspect { nativeView = $0.textView }
                .frame(width: 400, height: 120)
        }
        let host = NSHostingView(rootView: editor())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func flush() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        flush()
        let view = try XCTUnwrap(nativeView)
        view.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        view.typingAttributes = [.font: NSFont.boldSystemFont(ofSize: 28)]
        view.insertNewline(nil)
        host.rootView = editor()
        flush()
        XCTAssertEqual(source, "# Heading\n")
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, defaultEditorFont.pointSize)
        view.insertText("body", replacementRange: view.selectedRange())
        XCTAssertEqual((view.textStorage?.attribute(.font, at: view.string.utf16.count - 1, effectiveRange: nil) as? NSFont)?.pointSize,
                       defaultEditorFont.pointSize)
        view.setSelectedRange(NSRange(location: 4, length: 0))
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 28)
        view.setSelectedRange(NSRange(location: 10, length: 0))
        XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, defaultEditorFont.pointSize)
    }

    @MainActor
    func testHostedEditorSkipsOnlyUnchangedOptedInRendering() throws {
        _ = NSApplication.shared
        var passes = 0
        var introspections = 0
        var nativeView: NSTextView?
        var text = "hello"
        let binding = Binding(get: { text }, set: { text = $0 })
        func editor(revision: Int?, size: ContentSizeCategory = .large,
                    scheme: ColorScheme = .light) -> AnyView {
            let rule = HighlightRule(ranges: { source in
                passes += 1
                return [NSRange(location: 0, length: source.utf16.count)]
            }, formattingRules: [TextFormattingRule(key: .underlineStyle, value: 1)])
            var editor = HighlightedTextEditor(text: binding, highlightRules: [rule])
                .introspect { internals in
                    nativeView = internals.textView
                    introspections += 1
                }
            if let revision = revision { editor = editor.highlightingRevision(revision) }
            return AnyView(editor.environment(\.sizeCategory, size)
                .environment(\.colorScheme, scheme).frame(width: 400, height: 120))
        }
        let host = NSHostingView(rootView: editor(revision: 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func flush() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        func refresh(_ root: AnyView) { host.rootView = root; flush() }
        flush()
        let view = try XCTUnwrap(nativeView)
        XCTAssertGreaterThan(passes, 0)
        var previous = passes
        let previousIntrospections = introspections
        view.setSelectedRange(NSRange(location: 2, length: 1))
        refresh(editor(revision: 1))
        XCTAssertEqual(passes, previous)
        XCTAssertGreaterThan(introspections, previousIntrospections)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 1))

        refresh(editor(revision: 2))
        XCTAssertGreaterThan(passes, previous)
        previous = passes
        refresh(editor(revision: 2, size: .accessibilityLarge))
        XCTAssertGreaterThan(passes, previous)
        previous = passes
        refresh(editor(revision: 2, size: .accessibilityLarge, scheme: .dark))
        XCTAssertGreaterThan(passes, previous)

        previous = passes
        text = "changed"
        refresh(editor(revision: 2, size: .accessibilityLarge, scheme: .dark))
        XCTAssertGreaterThan(passes, previous)
        XCTAssertEqual(view.string, text)

        // A native edit can return to the same source while losing attributes.
        previous = passes
        view.string = "changed"
        view.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: view))
        refresh(editor(revision: 2, size: .accessibilityLarge, scheme: .dark))
        XCTAssertGreaterThan(passes, previous)
        XCTAssertEqual(view.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int, 1)

        refresh(editor(revision: nil))
        previous = passes
        refresh(editor(revision: nil))
        XCTAssertGreaterThan(passes, previous)
    }
}
#endif
