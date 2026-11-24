# Keymap format

ExcelHotkey reproduces Windows Excel's Alt key tips (e.g. `Alt, H, O, I`) on Mac Excel.
The user taps Option alone, then types the key-tip letters. Each sequence is looked up in a
keymap and the bound action runs in Mac Excel.

Keymap files are JSON, under `keymap/`. All files are merged at load time.

```json
{
  "groups": {
    "H":  "Home",
    "HO": "Format"
  },
  "bindings": [
    {
      "keys": "HOI",
      "label": "AutoFit Column Width",
      "action": { "menu": ["Format", "Column", "Auto-fit Selection"] }
    }
  ]
}
```

## `groups`
Maps every *proper prefix* of every binding's `keys` to a short label shown in the on-screen
guide (what the Windows key tip opens: a tab, a drop-down, a gallery). Every prefix must have
an entry (e.g. binding `HOI` needs `H` and `HO`).

## `bindings`
- `keys`: the Windows key-tip letters after Alt, uppercase A–Z and digits 0–9, no separators.
  Multi-letter key tips are just concatenated (`Alt, H, F, C` → `"HFC"`).
  A binding's `keys` must not be a prefix of another binding's `keys`.
- `label`: what Windows calls the command (short, user-facing).
- `action`: exactly ONE of the following keys.

### Action types (in order of preference — use the first that works)

1. `"shortcut": "cmd+shift+L"` — a native Mac Excel keyboard shortcut.
   Modifiers: `cmd`, `ctrl`, `opt`, `shift`. Key: a letter, digit, punctuation char
   (`- = [ ] ; ' , . / \` `), or one of `f1`…`f19`, `return`, `tab`, `space`, `delete`,
   `forwarddelete`, `escape`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`.
   Only use shortcuts you are confident exist in current Mac Excel (Microsoft 365).
2. `"menu": ["Format", "Row", "Auto-fit"]` — a Mac Excel menu bar path. Every title must match
   `reference/excel-menus.txt` exactly (character for character, including `...` and casing).
3. `"applescript": "tell application \"Microsoft Excel\" to autofit rows of selection"` —
   a complete AppleScript using Excel's dictionary
   (`/Applications/Microsoft Excel.app/Contents/Resources/Excel.sdef`). Use for commands with no
   menu item, e.g. a specific border style. Must compile with `osacompile`.
4. `"ribbon": {"tab": "Home", "control": "Borders", "item": "Thick Outside Borders"}` —
   press a ribbon control by its accessibility title (from `reference/excel-ribbon.txt`);
   `item` (optional) is the menu entry to choose in the drop-down it opens. Last resort.

Commands that open a dialog on Windows should open the equivalent dialog on Mac.
Skip commands that have no Mac Excel equivalent at all.
