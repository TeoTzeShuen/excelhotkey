import AppKit

let userKeymapDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ExcelHotkey/keymap")

/// Bundled keymap first, then the user's folder (its bindings override bundled ones).
func keymapDirs() -> [URL] {
    var dirs: [URL] = []
    if let res = Bundle.main.resourceURL?.appendingPathComponent("keymap") { dirs.append(res) }
    if let dev = ProcessInfo.processInfo.environment["EXCELHOTKEY_KEYMAP_DIR"] { dirs.append(URL(fileURLWithPath: dev)) }
    dirs.append(userKeymapDir)
    return dirs
}

func newestModification(_ dirs: [URL]) -> Date {
    dirs.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] }
        .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        .max() ?? .distantPast
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyTips: KeyTips!
    private let hud = HUD()
    private var statusItem: NSStatusItem!
    private var keymapStamp = Date.distantPast
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: userKeymapDir, withIntermediateDirectories: true)
        keyTips = KeyTips(keymap: Keymap())
        reloadKeymap(announce: false)
        keyTips.willStart = { [weak self] in
            guard let self else { return }
            if newestModification(keymapDirs()) > self.keymapStamp { self.reloadKeymap(announce: false) }
        }
        keyTips.onChange = { [weak self] typed in
            guard let self else { return }
            if let typed { self.hud.show(typed: typed, keymap: self.keyTips.keymap) } else { self.hud.hide() }
        }
        keyTips.onRun = { [weak self] b in
            do { try Runner.run(b.action) } catch { self?.hud.flash("\(b.label): \(error)") }
        }
        buildMenu()
        startWhenTrusted()
    }

    private func startWhenTrusted() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), keyTips.start() {
            statusItem.button?.toolTip = "ExcelHotkey: tap Option in Excel"
            return
        }
        statusItem.button?.toolTip = "ExcelHotkey needs Accessibility permission"
        // Poll without prompting again until the user grants it in System Settings.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted(), self.keyTips.start() else { return }
            t.invalidate()
            self.statusItem.button?.toolTip = "ExcelHotkey: tap Option in Excel"
        }
    }

    private func reloadKeymap(announce: Bool) {
        let dirs = keymapDirs()
        keymapStamp = newestModification(dirs)
        do {
            keyTips.keymap = try Keymap.load(from: dirs)
            let problems = keyTips.keymap.problems()
            problems.forEach { NSLog("ExcelHotkey keymap: %@", $0) }
            if announce {
                hud.flash("Loaded \(keyTips.keymap.bindings.count) key tips" + (problems.isEmpty ? "" : ", \(problems.count) problems (see Console)"))
            }
        } catch {
            hud.flash("Keymap error: \(error)")
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "option", accessibilityDescription: "ExcelHotkey")
        let menu = NSMenu()
        enabledItem = menu.addItem(withTitle: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = .on
        menu.addItem(withTitle: "Reload Keymap", action: #selector(reload), keyEquivalent: "")
        menu.addItem(withTitle: "Open Keymap Folder", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ExcelHotkey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        keyTips.enabled.toggle()
        enabledItem.state = keyTips.enabled ? .on : .off
        statusItem.button?.appearsDisabled = !keyTips.enabled
    }
    @objc private func reload() { reloadKeymap(announce: true) }
    @objc private func openFolder() { NSWorkspace.shared.open(userKeymapDir) }
}

// MARK: command line (testing)

/// `--validate`: check the keymap against the running Excel.
/// `--run KEYS`: run one binding now. `--list`: print all bindings.
func commandLine(_ args: [String]) -> Int32? {
    guard let cmd = args.first else { return nil }
    let map: Keymap
    do { map = try Keymap.load(from: keymapDirs()) } catch { print("keymap error: \(error)"); return 1 }
    switch cmd {
    case "--list":
        for b in map.bindings.values.sorted(by: { $0.keys < $1.keys }) { print("\(b.keys)\t\(b.label)\t\(b.action)") }
        return 0
    case "--run":
        guard args.count == 2, case .binding(let b) = map.lookup(args[1].uppercased()) else {
            print("no binding for \(args.dropFirst().joined())"); return 1
        }
        if case .shortcut = b.action { // synthetic keys go to the frontmost app
            excelApp()?.activate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        do { try Runner.run(b.action); print("ok: \(b.keys) \(b.label)"); return 0 } catch { print("FAIL: \(b.keys) \(b.label): \(error)"); return 1 }
    case "--validate":
        var bad = map.problems()
        let app = excelApp().map { AXUIElementCreateApplication($0.processIdentifier) }
        for b in map.bindings.values.sorted(by: { $0.keys < $1.keys }) {
            switch b.action {
            case .menu(let path):
                if let app, Runner.findMenuItem(app, path) == nil { bad.append("\(b.keys): menu not found \(path.joined(separator: " › "))") }
            case .applescript(let src):
                var err: NSDictionary?
                if !(NSAppleScript(source: src)?.compileAndReturnError(&err) ?? false) {
                    bad.append("\(b.keys): AppleScript does not compile: \(err?[NSAppleScript.errorMessage] ?? "?")")
                }
            case .shortcut(let s):
                if !Runner.shortcutIsValid(s) { bad.append("\(b.keys): bad shortcut \(s)") }
            case .ribbon: break // only checkable by pressing it
            }
        }
        bad.forEach { print($0) }
        print("\(map.bindings.count) bindings, \(bad.count) problems")
        return bad.isEmpty ? 0 : 1
    case "--check-ribbon": // switches ribbon tabs to find each control, then returns to Home
        guard let excel = excelApp() else { print("Excel is not running"); return 1 }
        let app = AXUIElementCreateApplication(excel.processIdentifier)
        var bad: [String] = []
        for b in map.bindings.values.sorted(by: { $0.keys < $1.keys }) {
            guard case let .ribbon(tab, control, _) = b.action else { continue }
            do { _ = try Runner.findRibbonControl(app, tab, control) } catch { bad.append("\(b.keys): \(error)") }
        }
        _ = try? Runner.findRibbonControl(app, "Home", "Paste") // leave the ribbon on Home
        bad.forEach { print($0) }
        print("\(bad.count) ribbon problems")
        return bad.isEmpty ? 0 : 1
    default:
        print("usage: ExcelHotkey [--list | --validate | --check-ribbon | --run KEYS]")
        return 2
    }
}

if let code = commandLine(Array(CommandLine.arguments.dropFirst())) { exit(code) }
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
