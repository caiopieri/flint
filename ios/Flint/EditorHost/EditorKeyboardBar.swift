// EditorKeyboardBar — a transparent keyboard accessory for the editor.
//
// The default WebKit form accessory (◁ ▷ Done) is drawn by iOS with its own
// opaque background. We replace it with a custom bar that has NO background, so
// it floats over the editor text: line up/down on the left, a "done" check on
// the right. The arrows move the CodeMirror cursor by line via a tiny JS hook
// (`window.flintMoveCursor`); the check dismisses the keyboard.
//
// WebKit owns the accessory on its inner content view (not the WKWebView), so we
// give just that content-view instance a dynamic subclass whose
// `inputAccessoryView` returns our bar — the established way to override it.
import ObjectiveC
import SwiftUI
import UIKit
import WebKit

final class FlintKeyboardAccessory: UIView {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        // The system resizes the accessory to the keyboard width; this is a
        // placeholder until then (flexibleWidth below stretches it).
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = .flexibleWidth

        let up = Self.button("chevron.up", action: #selector(lineUp), tint: UIColor(FlintColor.textSecondary))
        let down = Self.button("chevron.down", action: #selector(lineDown), tint: UIColor(FlintColor.textSecondary))
        let done = Self.button("checkmark", action: #selector(dismissKeyboard), tint: UIColor(FlintColor.accent))

        let leading = UIStackView(arrangedSubviews: [up, down])
        leading.spacing = 4
        leading.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leading)
        done.translatesAutoresizingMaskIntoConstraints = false
        addSubview(done)

        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            done.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // No intrinsic width, fixed bar height.
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

    private static func button(_ symbol: String, action: Selector, tint: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = tint
        button.addTarget(nil, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        return button
    }

    @objc private func lineUp() { move("up") }
    @objc private func lineDown() { move("down") }
    @objc private func dismissKeyboard() { webView?.endEditing(true) }

    private func move(_ dir: String) {
        webView?.evaluateJavaScript("window.flintMoveCursor && window.flintMoveCursor('\(dir)')")
    }
}

// Only its address is used (as a unique associated-object key); the value is
// never read or mutated, so `nonisolated(unsafe)` is the right escape hatch.
private nonisolated(unsafe) var flintAccessoryKey: UInt8 = 0

extension WKWebView {
    /// WebKit's text-editing first responder (a private `WKContentView`).
    fileprivate var flintContentView: UIView? {
        scrollView.subviews.first { String(describing: type(of: $0)).hasPrefix("WKContent") }
    }

    /// Install a custom transparent input accessory, replacing WebKit's default.
    /// Idempotent: re-installing only refreshes the associated bar. Safe to call
    /// once the page has loaded (the content view exists by then).
    func installFlintKeyboardAccessory(_ accessory: UIView) {
        guard let content = flintContentView else { return }
        objc_setAssociatedObject(content, &flintAccessoryKey, accessory, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let baseClass: AnyClass = object_getClass(content)!
        let subclassName = "Flint_" + NSStringFromClass(baseClass)
        if let existing = NSClassFromString(subclassName) {
            object_setClass(content, existing)
            return
        }
        guard let subclass = objc_allocateClassPair(baseClass, subclassName, 0) else { return }
        let selector = #selector(getter: UIResponder.inputAccessoryView)
        let block: @convention(block) (NSObject) -> UIView? = { object in
            objc_getAssociatedObject(object, &flintAccessoryKey) as? UIView
        }
        class_addMethod(subclass, selector, imp_implementationWithBlock(block), "@@:")
        objc_registerClassPair(subclass)
        object_setClass(content, subclass)
    }
}
