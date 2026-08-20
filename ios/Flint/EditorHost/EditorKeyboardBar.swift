// EditorKeyboardBar — the compact Markdown toolbar above the system keyboard.
//
// It is a horizontally scrolling pill: iPad shows the complete command set;
// iPhone keeps the same controls but lets the user swipe through the row. The
// native accessory only sends coarse commands to CodeMirror, never text per key.
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
    private let onAttach: () -> Void

    init(webView: WKWebView, onAttach: @escaping () -> Void) {
        self.webView = webView
        self.onAttach = onAttach
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 56))
        backgroundColor = .clear
        isOpaque = false
        autoresizingMask = .flexibleWidth

        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        // The toolbar floats above the keyboard like Obsidian's: the material
        // belongs to the compact control group, not to the whole accessory
        // width. The note/keyboard remains visible around it.
        pill.backgroundColor = UIColor(FlintColor.surface).withAlphaComponent(0.88)
        pill.layer.cornerRadius = FlintRadius.xl
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor(FlintColor.border).cgColor
        pill.clipsToBounds = true
        addSubview(pill)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        pill.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let commands: [(String, String, String)] = [
            ("arrow.uturn.backward", "undo", "Desfazer"),
            ("arrow.uturn.forward", "redo", "Refazer"),
            ("doc.badge.plus", "wikilink", "Inserir link de nota"),
            ("tag", "tag", "Inserir tag"),
            ("paperclip", "attach", "Anexar arquivo"),
            ("textformat.size", "heading", "Título"),
            ("bold", "bold", "Negrito"),
            ("italic", "italic", "Itálico"),
            ("strikethrough", "strike", "Riscado"),
            ("chevron.left.forwardslash.chevron.right", "code", "Código"),
            ("quote.opening", "quote", "Citação"),
            ("link", "link", "Link"),
            ("list.bullet", "list", "Lista"),
            ("list.number", "numberedList", "Lista numerada"),
            ("checklist", "checklist", "Checklist"),
            ("increase.indent", "indent", "Aumentar recuo"),
            ("decrease.indent", "outdent", "Diminuir recuo")
        ]
        for (symbol, command, label) in commands {
            stack.addArrangedSubview(Self.button(symbol, command: command, label: label, target: self))
        }

        let dismiss = Self.button(
            "keyboard.chevron.compact.down",
            command: "dismiss",
            label: "Fechar teclado",
            target: self
        )
        stack.addArrangedSubview(dismiss)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 1740),
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: pill.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // No intrinsic width, fixed bar height.
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 56) }

    private static func button(
        _ symbol: String,
        command: String,
        label: String,
        target: Any?
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = UIColor(FlintColor.textPrimary)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = command
        button.addTarget(target, action: #selector(commandTapped(_:)), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        return button
    }

    @objc private func commandTapped(_ sender: UIButton) {
        guard let command = sender.accessibilityIdentifier else { return }
        if command == "dismiss" {
            webView?.endEditing(true)
            return
        }
        if command == "attach" {
            onAttach()
            return
        }
        webView?.evaluateJavaScript("window.flintCommand && window.flintCommand('\(command)')")
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
