import AppKit
import ApplicationServices

let excelBundleID = "com.microsoft.Excel"
/// Marks key events we synthesize, so our own event tap lets them through.
let syntheticEventMarker: Int64 = 0x5845_4C48 // "XELH"

struct ActionError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func excelApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: excelBundleID).first
}

enum Runner {
    static func run(_ action: Action) throws {
        guard let excel = excelApp() else { throw ActionError("Excel is not running") }
        switch action {
        case .shortcut(let s): try postShortcut(s)
        case .menu(let path): try pressMenu(AXUIElementCreateApplication(excel.processIdentifier), path)
        case .applescript(let src): try runAppleScript(src)
        case let .ribbon(tab, control, item):
            try pressRibbon(AXUIElementCreateApplication(excel.processIdentifier), tab, control, item)
        }
    }

    // MARK: shortcut

    static func parseShortcut(_ spec: String) throws -> (CGKeyCode, CGEventFlags) {
        var flags: CGEventFlags = []
        var key: String?
        // Split on "+" but allow "+" itself as the final key ("cmd++").
        var parts = spec.lowercased().components(separatedBy: "+")
        if spec.hasSuffix("++") { parts.removeLast(2); parts.append("+") }
        for p in parts {
            switch p {
            case "cmd", "command": flags.insert(.maskCommand)
            case "ctrl", "control": flags.insert(.maskControl)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: key = p
            }
        }
        guard let k = key, let code = keyCodes[k] else { throw ActionError("unknown key in shortcut '\(spec)'") }
        return (code, flags)
    }

    static func shortcutIsValid(_ spec: String) -> Bool { (try? parseShortcut(spec)) != nil }

    static func postShortcut(_ spec: String) throws {
        let (code, flags) = try parseShortcut(spec)
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    /// US ANSI virtual key codes.
    static let keyCodes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
            "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "forwarddelete": 117,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        let fkeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80]
        for (i, c) in fkeys.enumerated() { m["f\(i + 1)"] = c }
        return m
    }()

    // MARK: menu

    /// The menu bar item at `path`, e.g. ["Format", "Row", "Auto-fit"].
    static func findMenuItem(_ app: AXUIElement, _ path: [String]) -> AXUIElement? {
        guard var el: AXUIElement = AX.attr(app, kAXMenuBarAttribute) else { return nil }
        for (i, title) in path.enumerated() {
            // Below the bar, an item's children are a single AXMenu holding the next level.
            let container = i == 0 ? el : (AX.children(el).first { AX.role($0) == kAXMenuRole } ?? el)
            // "A|B": either title (for items Excel renames, e.g. "Freeze Panes|Unfreeze Panes").
            let names = title.components(separatedBy: "|")
            guard let next = AX.children(container).first(where: { names.contains(AX.title($0) ?? "") }) else { return nil }
            el = next
        }
        return el
    }

    static func pressMenu(_ app: AXUIElement, _ path: [String]) throws {
        let name = path.joined(separator: " › ")
        guard let el = findMenuItem(app, path) else { throw ActionError("menu item not found: \(name)") }
        guard AX.isEnabled(el) else { throw ActionError("\(name) is greyed out right now") }
        try AX.press(el)
    }

    // MARK: AppleScript

    private static var compiled: [String: NSAppleScript] = [:]

    static func runAppleScript(_ src: String) throws {
        let script = compiled[src] ?? NSAppleScript(source: src)!
        compiled[src] = script
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err { throw ActionError("AppleScript: \(err[NSAppleScript.errorMessage] ?? err)") }
    }

    // MARK: ribbon

    /// Selects `tab` on the ribbon and returns the control titled `control` on it, plus the tab
    /// that was selected before if it was a different one.
    static func findRibbonControl(_ app: AXUIElement, _ tab: String, _ control: String) throws -> (AXUIElement, previousTab: AXUIElement?) {
        guard let win: AXUIElement = AX.attr(app, kAXFocusedWindowAttribute) else { throw ActionError("no Excel window") }
        let ribbon = { AX.find(win, maxDepth: 3, { AX.role($0) == kAXTabGroupRole }) }
        guard let r = ribbon() else { throw ActionError("ribbon not found") }
        guard let t = AX.children(r).first(where: { AX.title($0) == tab && AX.role($0) != kAXScrollAreaRole }) else {
            throw ActionError("ribbon tab not found: \(tab)")
        }
        var previous: AXUIElement?
        if (AX.attr(t, kAXValueAttribute) as Int?) != 1 {
            previous = AX.children(r).first { AX.role($0) != kAXScrollAreaRole && (AX.attr($0, kAXValueAttribute) as Int?) == 1 }
            try AX.press(t)
        }
        guard let ctl = AX.waitFor(timeout: 1, { () -> AXUIElement? in
            guard let area = ribbon().flatMap({ AX.children($0).first { AX.role($0) == kAXScrollAreaRole } }) else { return nil }
            return AX.find(area, maxDepth: 4, { AX.title($0) == control })
        }) else { throw ActionError("ribbon control not found: \(tab) › \(control)") }
        return (ctl, previous)
    }

    static func pressRibbon(_ app: AXUIElement, _ tab: String, _ control: String, _ item: String?) throws {
        let (ctl, previousTab) = try findRibbonControl(app, tab, control)
        // Go back to the tab the user was on, like Windows does after a key tip runs. Not while a
        // drop-down or box we opened is still waiting for input, since switching tabs would close it.
        var restoreTab = true
        defer { if restoreTab, let previousTab { try? AX.press(previousTab) } }
        guard AX.isEnabled(ctl) else { throw ActionError("\(control) is greyed out right now") }
        guard let item else {
            // Do what the Windows key tip does: open drop-downs, put the cursor in boxes, press buttons.
            // (Pressing a split button like Borders would re-apply its last choice instead.)
            switch AX.role(ctl) {
            case kAXComboBoxRole:
                restoreTab = false
                AXUIElementSetAttributeValue(ctl, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            case kAXMenuButtonRole:
                restoreTab = false
                showMenu(ctl)
            default: try AX.press(ctl)
            }
            return
        }
        // A drop-down's entries are an AXMenu under the button. Excel builds it the first time the
        // menu opens and keeps it, so it is often there already and the entry can be pressed directly.
        let entry = { AX.find(ctl, maxDepth: 4, { AX.role($0) == kAXMenuItemRole && AX.title($0) == item }) }
        if let mi = entry() { try AX.press(mi); return }
        showMenu(ctl)
        guard let mi = AX.waitFor(timeout: 1.5, entry) else {
            try? postShortcut("escape") // close the drop-down we opened
            throw ActionError("menu entry not found: \(control) › \(item)")
        }
        try AX.press(mi)
    }

    /// Opens a drop-down. AXShowMenu blocks until the menu closes, so don't wait for it.
    static func showMenu(_ el: AXUIElement) {
        AXUIElementSetMessagingTimeout(el, 0.1)
        AXUIElementPerformAction(el, kAXShowMenuAction as CFString)
        AXUIElementSetMessagingTimeout(el, 0)
    }
}

/// Thin helpers over the Accessibility C API.
enum AX {
    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] { attr(el, kAXChildrenAttribute) ?? [] }
    static func role(_ el: AXUIElement) -> String? { attr(el, kAXRoleAttribute) }

    /// The visible name: AXTitle, else AXDescription.
    static func title(_ el: AXUIElement) -> String? {
        if let t: String = attr(el, kAXTitleAttribute), !t.isEmpty { return t }
        if let d: String = attr(el, kAXDescriptionAttribute), !d.isEmpty { return d }
        return nil
    }

    static func isEnabled(_ el: AXUIElement) -> Bool { attr(el, kAXEnabledAttribute) ?? true }

    static func press(_ el: AXUIElement) throws {
        let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
        guard r == .success else { throw ActionError("press failed (AX error \(r.rawValue))") }
    }

    /// Breadth-first search, bounded so a huge tree can't stall the key path.
    static func find(_ root: AXUIElement, maxDepth: Int, nodeCap: Int = 1500,
                     _ match: (AXUIElement) -> Bool) -> AXUIElement? {
        var level = [root], seen = 0
        for _ in 0...maxDepth {
            var next: [AXUIElement] = []
            for el in level {
                if match(el) { return el }
                seen += 1
                if seen > nodeCap { return nil }
                next += children(el)
            }
            if next.isEmpty { return nil }
            level = next
        }
        return nil
    }

    /// Polls `get` while letting the run loop spin, so the target app can redraw.
    static func waitFor<T>(timeout: TimeInterval, _ get: () -> T?) -> T? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let v = get() { return v }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < end
        return nil
    }
}
