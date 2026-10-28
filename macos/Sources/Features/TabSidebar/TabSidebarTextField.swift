import AppKit
import SwiftUI

/// A single-line text field backed by NSTextField, so the sidebar controls exactly how Esc,
/// Return, arrow keys, selection and focus behave (SwiftUI's TextField does not expose them).
struct TabSidebarTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont
    var textColor: NSColor
    var placeholderColor: NSColor
    /// Caret color, and (at 30 %) the selection color.
    var accentColor: NSColor?
    /// Select all text when the field gets focus (rename).
    var selectAllOnFocus = false
    /// Become first responder as soon as the field appears (rename).
    var focusOnAppear = false
    /// Increment to request focus again (search).
    var focusTick = 0

    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onMoveDown: (() -> Void)?
    var onBlurCommit = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusAwareTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.accentColor = accentColor
        field.onFocusChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.focusChanged(focused)
        }
        context.coordinator.lastTick = focusTick
        if focusOnAppear {
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.font = font
        (field as? FocusAwareTextField)?.accentColor = accentColor
        field.textColor = textColor
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font])

        if context.coordinator.lastTick != focusTick {
            context.coordinator.lastTick = focusTick
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TabSidebarTextField
        var lastTick = 0
        private var didCommit = false

        init(_ parent: TabSidebarTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func focusChanged(_ focused: Bool) {
            parent.onFocusChange(focused)
            if focused, parent.selectAllOnFocus {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = NSApp.keyWindow else { return }
                    (window.firstResponder as? NSText)?.selectAll(nil)
                }
            }
            if !focused, parent.onBlurCommit, !didCommit {
                parent.onSubmit()
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                didCommit = true
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                didCommit = true
                parent.onCancel()
                return true
            case #selector(NSResponder.moveDown(_:)):
                if let move = parent.onMoveDown {
                    move()
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}

/// An NSTextField that reports when it gains or loses first responder status.
final class FocusAwareTextField: NSTextField {
    var onFocusChange: ((Bool) -> Void)?
    var accentColor: NSColor?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // The shared field editor is created on focus; the selection must never be the system blue.
            if let editor = currentEditor() as? NSTextView, let accent = accentColor {
                editor.insertionPointColor = accent
                editor.selectedTextAttributes = [.backgroundColor: accent.withAlphaComponent(0.3)]
                editor.drawsBackground = false
            }
            onFocusChange?(true)
        }
        return result
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusChange?(false)
    }
}
