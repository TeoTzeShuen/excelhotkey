import AppKit

/// Watches the keyboard while Excel is frontmost. A lone tap of either Option key starts
/// key-tip mode; the letters typed next are matched against the keymap.
final class KeyTips {
    var keymap: Keymap
    var enabled = true { didSet { if !enabled { cancel() } } }
    /// Called with the typed prefix while in key-tip mode, nil when it ends.
    var onChange: (String?) -> Void = { _ in }
    var onRun: (Binding) -> Void = { _ in }
    /// Called just before key-tip mode starts (used to hot-reload the keymap).
    var willStart: () -> Void = {}

    private var tap: CFMachPort?
    private var excelFrontmost = false
    private var optionTapPending = false
    private var typed: String? // nil = not in key-tip mode
    private var swallowedKeyUps = Set<Int64>()

    private static let optionKeyCodes: Set<Int64> = [58, 61] // left, right
    private static let escape: Int64 = 53, delete: Int64 = 51

    init(keymap: Keymap) {
        self.keymap = keymap
        let ws = NSWorkspace.shared
        excelFrontmost = ws.frontmostApplication?.bundleIdentifier == excelBundleID
        ws.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                          object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.excelFrontmost = app?.bundleIdentifier == excelBundleID
            if self?.excelFrontmost == false { self?.cancel() }
        }
    }

    /// Installs the event tap. Fails until the app has Accessibility permission.
    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<KeyTips>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func cancel() {
        optionTapPending = false
        if typed != nil { typed = nil; onChange(nil) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeyUps.remove(code) != nil { return nil }
        guard enabled, excelFrontmost else { return pass }

        switch type {
        case .flagsChanged:
            guard Self.optionKeyCodes.contains(code) else { optionTapPending = false; return pass }
            let others: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
            if event.flags.contains(.maskAlternate) {
                optionTapPending = event.flags.intersection(others).isEmpty
            } else if optionTapPending {
                optionTapPending = false
                toggle()
            }
            // Swallow Option's own press/release so Excel's built-in key tips stay out of the way.
            // Option+key chords still work: the key event itself carries the Option flag.
            return nil
        case .keyDown:
            optionTapPending = false
            guard typed != nil else { return pass }
            return keyDown(code, event) ? nil : pass
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            cancel()
            return pass
        default:
            return pass
        }
    }

    private func toggle() {
        if typed != nil { cancel(); return }
        willStart()
        typed = ""
        onChange("")
    }

    /// Handles a key while in key-tip mode. Returns true if the key was consumed.
    private func keyDown(_ code: Int64, _ event: CGEvent) -> Bool {
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            cancel(); return false
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
        swallowedKeyUps.insert(code)

        if code == Self.escape || code == Self.delete {
            if let t = typed, !t.isEmpty { typed = String(t.dropLast()); onChange(typed) } else { cancel() }
            return true
        }
        guard let ch = character(event), var t = typed else {
            // Arrows, Return, etc.: leave key-tip mode and let Excel have the key.
            swallowedKeyUps.remove(code)
            cancel()
            return false
        }
        t.append(ch)
        switch keymap.lookup(t) {
        case .binding(let b):
            typed = nil
            onChange(nil)
            DispatchQueue.main.async { self.onRun(b) }
        case .prefix:
            typed = t
            onChange(t)
        case .none:
            NSSound.beep() // like Windows: an unknown key tip is ignored
        }
        return true
    }

    /// The uppercase letter or digit the key produces, using the current keyboard layout.
    private func character(_ event: CGEvent) -> Character? {
        var len = 0
        var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        guard len == 1, let s = String(utf16CodeUnits: buf, count: 1).uppercased().first,
              s.isASCII, s.isLetter || s.isNumber else { return nil }
        return s
    }
}
