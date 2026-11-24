import Foundation

/// One way of running a command in Mac Excel. See docs/keymap-format.md.
enum Action {
    case shortcut(String)
    case menu([String])
    case applescript(String)
    case ribbon(tab: String, control: String, item: String?)
}

struct Binding {
    let keys: String
    let label: String
    let action: Action
}

enum KeymapError: Error, CustomStringConvertible {
    case bad(String, String)
    var description: String {
        switch self { case let .bad(file, msg): return "\(file): \(msg)" }
    }
}

/// All bindings plus the labels for intermediate prefixes, merged from every keymap file.
struct Keymap {
    var bindings: [String: Binding] = [:]
    var groups: [String: String] = [:]

    enum Lookup { case binding(Binding), prefix, none }

    func lookup(_ keys: String) -> Lookup {
        if let b = bindings[keys] { return .binding(b) }
        if bindings.keys.contains(where: { $0.hasPrefix(keys) }) { return .prefix }
        return .none
    }

    /// The next keys valid after `prefix`, each with its label (binding label or group label).
    func options(after prefix: String) -> [(key: String, label: String, isGroup: Bool)] {
        var seen: [String: (String, Bool)] = [:]
        for k in bindings.keys where k.hasPrefix(prefix) && k.count > prefix.count {
            let next = String(k.dropFirst(prefix.count).prefix(1))
            let full = prefix + next
            if let b = bindings[full] {
                seen[next] = (b.label, false)
            } else if seen[next] == nil {
                seen[next] = (groups[full] ?? "…", true)
            }
        }
        return seen.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.key < $1.key }
    }

    /// Loads every *.json in `dirs`, in order; later files override earlier ones by `keys`.
    static func load(from dirs: [URL]) throws -> Keymap {
        var map = Keymap()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try map.merge(file: url)
            }
        }
        return map
    }

    private mutating func merge(file url: URL) throws {
        let name = url.lastPathComponent
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw KeymapError.bad(name, "top level is not an object")
        }
        for (k, v) in root["groups"] as? [String: String] ?? [:] { groups[k.uppercased()] = v }
        for (i, raw) in (root["bindings"] as? [[String: Any]] ?? []).enumerated() {
            guard let keys = (raw["keys"] as? String)?.uppercased(), !keys.isEmpty,
                  let label = raw["label"] as? String,
                  let a = raw["action"] as? [String: Any] else {
                throw KeymapError.bad(name, "binding #\(i) needs keys, label and action")
            }
            bindings[keys] = Binding(keys: keys, label: label, action: try parseAction(a, name, keys))
        }
    }

    private func parseAction(_ a: [String: Any], _ file: String, _ keys: String) throws -> Action {
        guard a.count == 1 else { throw KeymapError.bad(file, "\(keys): action must have exactly one key") }
        if let s = a["shortcut"] as? String { return .shortcut(s) }
        if let m = a["menu"] as? [String], !m.isEmpty { return .menu(m) }
        if let s = a["applescript"] as? String { return .applescript(s) }
        if let r = a["ribbon"] as? [String: String], let tab = r["tab"], let control = r["control"] {
            return .ribbon(tab: tab, control: control, item: r["item"])
        }
        throw KeymapError.bad(file, "\(keys): unknown action \(a.keys.joined())")
    }

    /// Structural problems: bindings that shadow longer ones, missing group labels.
    func problems() -> [String] {
        var out: [String] = []
        for k in bindings.keys.sorted() {
            if bindings.keys.contains(where: { $0 != k && $0.hasPrefix(k) }) {
                out.append("\(k) is a prefix of another binding, so the longer one can never run")
            }
            for i in 1..<max(1, k.count) where groups[String(k.prefix(i))] == nil {
                out.append("\(k): no group label for \(k.prefix(i))")
            }
        }
        return Array(Set(out)).sorted()
    }
}
