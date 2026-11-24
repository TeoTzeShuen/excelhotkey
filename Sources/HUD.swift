import AppKit

/// A floating guide that never takes focus: shows the typed key tips and the keys available next.
final class HUD {
    private let panel: NSPanel
    private let label = NSTextField(labelWithAttributedString: NSAttributedString())
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        label.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: bg.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),
        ])
        panel.contentView = bg
    }

    /// Shows what can follow `typed` in `keymap`.
    func show(typed: String, keymap: Keymap) {
        let text = NSMutableAttributedString()
        let crumbs = (0..<typed.count).map { i -> String in
            let p = String(typed.prefix(i + 1))
            return "\(p.last!) \(keymap.groups[p] ?? "")"
        }
        text.append(line(crumbs.isEmpty ? "⌥ Key Tips" : "⌥ " + crumbs.joined(separator: "  ›  "), bold: true))

        let opts = keymap.options(after: typed)
        // Up to 12 per column, at most 3 columns (then columns grow taller).
        let rows = max(1, min(opts.count, 12), Int((Double(opts.count) / 3).rounded(.up)))
        let cols = Int((Double(opts.count) / Double(rows)).rounded(.up))
        let para = NSMutableParagraphStyle()
        para.tabStops = (1..<max(cols, 1)).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * 250) }
        for r in 0..<rows {
            let rowText = NSMutableAttributedString(string: "\n")
            for c in 0..<cols {
                let i = c * rows + r
                guard i < opts.count else { break }
                let o = opts[i]
                if c > 0 { rowText.append(NSAttributedString(string: "\t")) }
                rowText.append(NSAttributedString(string: " \(o.key) ", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                    .backgroundColor: NSColor.quaternaryLabelColor,
                ]))
                let name = o.label.count > 30 ? String(o.label.prefix(29)) + "…" : o.label
                rowText.append(NSAttributedString(string: "  " + name + (o.isGroup ? " ›" : ""), attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: o.isGroup ? NSColor.secondaryLabelColor : NSColor.labelColor,
                ]))
            }
            rowText.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: rowText.length))
            text.append(rowText)
        }
        present(text, autoHide: nil)
    }

    func flash(_ message: String) {
        present(line("⌥ " + message, bold: false), autoHide: 3)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private func line(_ s: String, bold: Bool) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private func present(_ text: NSAttributedString, autoHide: TimeInterval?) {
        hideWork?.cancel()
        label.attributedStringValue = text
        let size = label.fittingSize
        let frame = NSRect(x: 0, y: 0, width: size.width + 28, height: size.height + 20)
        let anchor = excelWindowFrame() ?? NSScreen.main?.visibleFrame ?? frame
        // Top-centre of the Excel window, just below the ribbon.
        panel.setFrame(NSRect(x: anchor.midX - frame.width / 2, y: anchor.maxY - 165 - frame.height,
                              width: frame.width, height: frame.height), display: true)
        panel.orderFrontRegardless()
        if let autoHide {
            let w = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: w)
        }
    }

    /// Excel's focused window in Cocoa screen coordinates.
    private func excelWindowFrame() -> NSRect? {
        guard let excel = excelApp(),
              let win: AXUIElement = AX.attr(AXUIElementCreateApplication(excel.processIdentifier), kAXFocusedWindowAttribute),
              let posV: AXValue = AX.attr(win, kAXPositionAttribute),
              let sizeV: AXValue = AX.attr(win, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posV, .cgPoint, &pos)
        AXValueGetValue(sizeV, .cgSize, &size)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }
}
