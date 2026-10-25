#if os(iOS)
//
//  HighlightedTextEditor.UIKit.swift
//
//
//  Created by Kyle Nazario on 5/26/21.
//

import SwiftUI
import UIKit

public struct HighlightedTextEditor: UIViewRepresentable, HighlightingTextEditor {
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }

    @Binding var text: String {
        didSet {
            onTextChange?(text)
        }
    }

    let highlightRules: [HighlightRule]
    var highlightingRevision: AnyHashable?
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.colorScheme) private var colorScheme

    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var onTextChange: OnTextChangeCallback?
    private(set) var onSelectionChange: OnSelectionChangeCallback?
    private(set) var introspect: IntrospectCallback?

    public init(
        text: Binding<String>,
        highlightRules: [HighlightRule]
    ) {
        _text = text
        self.highlightRules = highlightRules
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        updateTextViewModifiers(textView)
        runIntrospect(textView)

        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        // The input method owns marked text and its selection until commit.
        // Replacing it with the whole highlighted document duplicates content
        // and invalidates TextKit positions used by the keyboard.
        guard uiView.markedTextRange == nil else {
            context.coordinator.renderedSnapshot = nil
            return
        }
        let snapshot = HighlightingRenderSnapshot(text: text, revision: highlightingRevision,
                                                 sizeCategory: sizeCategory, colorScheme: colorScheme)
        if snapshot.canReuse(context.coordinator.renderedSnapshot, nativeText: uiView.text ?? "") {
            updateTextViewModifiers(uiView)
            runIntrospect(uiView)
            return
        }

        let wasScrollEnabled = uiView.isScrollEnabled
        let selection = context.coordinator.selectedRange ?? uiView.selectedRange
        uiView.isScrollEnabled = false
        context.coordinator.updatingUIView = true
        defer {
            uiView.isScrollEnabled = wasScrollEnabled
            context.coordinator.updatingUIView = false
        }

        let highlightedText = HighlightedTextEditor.getHighlightedText(
            text: text,
            highlightRules: highlightRules
        )

        uiView.attributedText = highlightedText
        context.coordinator.renderedSnapshot = snapshot
        updateTextViewModifiers(uiView)
        runIntrospect(uiView)
        // Save offsets, not UITextRange objects tied to the previous document.
        // External replacements can shorten the text while a selection exists.
        let start = min(max(selection.location, 0), highlightedText.length)
        let restored = NSRange(location: start, length: min(max(selection.length, 0), highlightedText.length - start))
        if uiView.selectedRange != restored { uiView.selectedRange = restored }
        context.coordinator.selectedRange = restored
        uiView.typingAttributes = Self.typingAttributes(in: highlightedText, at: restored.location)
    }

    private func runIntrospect(_ textView: UITextView) {
        guard let introspect = introspect else { return }
        let internals = Internals(textView: textView, scrollView: nil)
        introspect(internals)
    }

    private func updateTextViewModifiers(_ textView: UITextView) {
        // BUGFIX #19: https://stackoverflow.com/questions/60537039/change-prompt-color-for-uitextfield-on-mac-catalyst
        let textInputTraits = textView.value(forKey: "textInputTraits") as? NSObject
        textInputTraits?.setValue(textView.tintColor, forKey: "insertionPointColor")
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightedTextEditor
        var renderedSnapshot: HighlightingRenderSnapshot?
        var selectedRange: NSRange?
        var updatingUIView = false

        init(_ markdownEditorView: HighlightedTextEditor) {
            self.parent = markdownEditorView
        }

        public func textViewDidChange(_ textView: UITextView) {
            // For Multistage Text Input
            guard !updatingUIView else { return }
            renderedSnapshot = nil
            guard textView.markedTextRange == nil else { return }

            selectedRange = textView.selectedRange
            parent.text = textView.text
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !updatingUIView, textView.markedTextRange == nil else { return }
            selectedRange = textView.selectedRange
            textView.typingAttributes = HighlightedTextEditor.typingAttributes(
                in: textView.attributedText, at: textView.selectedRange.location
            )
            parent.onSelectionChange?([textView.selectedRange])
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onEditingChanged?()
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            parent.onCommit?()
        }
    }
}

public extension HighlightedTextEditor {
    func introspect(callback: @escaping IntrospectCallback) -> Self {
        var new = self
        new.introspect = callback
        return new
    }

    func onSelectionChange(_ callback: @escaping (_ selectedRange: NSRange) -> Void) -> Self {
        var new = self
        new.onSelectionChange = { ranges in
            guard let range = ranges.first else { return }
            callback(range)
        }
        return new
    }

    func onCommit(_ callback: @escaping OnCommitCallback) -> Self {
        var new = self
        new.onCommit = callback
        return new
    }

    func onEditingChanged(_ callback: @escaping OnEditingChangedCallback) -> Self {
        var new = self
        new.onEditingChanged = callback
        return new
    }

    func onTextChange(_ callback: @escaping OnTextChangeCallback) -> Self {
        var new = self
        new.onTextChange = callback
        return new
    }
}
#endif
