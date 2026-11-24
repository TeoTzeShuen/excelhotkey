# ExcelHotkey

Windows-style Alt key tips for Excel on the Mac.

On Windows you press `Alt, H, O, I` to autofit a column. Mac Excel's Option-key tips stop
halfway: `Option, H, O` opens the Format menu, and from there you need the trackpad.
ExcelHotkey is a small menu bar app that fills the gap. While Excel is frontmost, tap Option
on its own, then type the Windows key-tip letters.

- A panel near the top of the Excel window shows what you've typed and the keys you can press next.
- `Esc` or `Delete` goes back one level. Tapping Option again cancels.
- Option held together with another key works as usual (`⌥G` still types ©).
- Excel's built-in Option key tips are turned off while the app runs, so the two don't clash.

About 290 sequences are mapped across Home, Insert, Page Layout, Formulas, Data, Review,
View and File. Some examples:

| Keys | Command |
|---|---|
| `H O I` / `H O A` | AutoFit column width / row height |
| `H I R` / `H D C` | Insert rows / delete columns |
| `H B A` / `H B N` | All borders / no border |
| `H A C` / `H W` | Centre / wrap text |
| `H H` / `H F C` | Fill colour / font colour palettes |
| `H V V` | Paste values |
| `H U S` | AutoSum (press Return to confirm, as on Windows) |
| `A S A` / `A T` | Sort A to Z / filter |
| `W F F` | Freeze / unfreeze panes |

Run `ExcelHotkey --list` to see every sequence.

## Install

Requires macOS 13 or later, Microsoft Excel (Microsoft 365, English UI) and the Xcode
command line tools (`xcode-select --install`).

```sh
./scripts/make-cert.sh   # once per Mac: a local code-signing identity
./scripts/install.sh     # build, copy to ~/Applications, start at login
```

Then grant the permissions macOS asks for:

- **Accessibility** (System Settings › Privacy & Security › Accessibility): turn on
  ExcelHotkey. It's needed to read the keyboard and press Excel's menus and ribbon.
- **Automation**: the first command that uses AppleScript asks to control Excel. Allow it.

The signing identity from `make-cert.sh` keeps the app's signature the same across rebuilds,
so macOS doesn't ask for Accessibility again each time you reinstall.

The menu bar icon (⌥) has **Enabled**, **Reload Keymap**, **Open Keymap Folder** and **Quit**.

To uninstall:

```sh
launchctl bootout gui/$(id -u)/local.excelhotkey
rm -rf ~/Applications/ExcelHotkey.app ~/Library/LaunchAgents/local.excelhotkey.plist
```

## Changing the key tips

Sequences live in JSON files. The built-in ones are in `keymap/`. Put your own files in
`~/Library/Application Support/ExcelHotkey/keymap/`; a binding there overrides a built-in one
with the same keys. Changes load automatically the next time you tap Option.

```json
{
  "groups": { "H": "Home", "HO": "Format" },
  "bindings": [
    { "keys": "HOI", "label": "AutoFit Column Width",
      "action": { "menu": ["Format", "Column", "Auto-fit Selection"] } }
  ]
}
```

An action is a native shortcut, a menu bar path, an AppleScript or a ribbon control. The full
format is in [docs/keymap-format.md](docs/keymap-format.md). `reference/` has dumps of Excel's
menu bar and ribbon to copy exact titles from.

## Development

```sh
./scripts/build.sh                                        # builds build/ExcelHotkey.app
B=build/ExcelHotkey.app/Contents/MacOS/ExcelHotkey
$B --validate      # check every binding against the running Excel
$B --check-ribbon  # find every ribbon control (switches tabs, returns to Home)
$B --run HOI       # run one binding now
```

`--validate` checks that menu paths exist, AppleScripts compile and shortcuts parse.
Set `EXCELHOTKEY_KEYMAP_DIR` to load an extra keymap folder while testing.

| File | What it does |
|---|---|
| `Sources/KeyTips.swift` | Event tap and the key-tip state machine |
| `Sources/Keymap.swift` | Loads and merges the JSON keymaps |
| `Sources/Actions.swift` | Runs shortcuts, menu items, AppleScript and ribbon controls |
| `Sources/HUD.swift` | The floating guide panel |
| `Sources/main.swift` | Menu bar app and the command-line test modes |

## Limitations

- Menu and ribbon titles are matched in English, so other Excel languages need their own keymap.
- Dialogs that a command opens (Format Cells, for example) are ordinary Mac dialogs without key tips.
- Some ribbon commands briefly switch the ribbon tab to reach a control, then switch back.
