# Greenshot for Mac (Community)

A free, open source screenshot tool for macOS, ported from [Greenshot](https://github.com/greenshot/greenshot) for Windows:
capture a region, a window or the whole screen with a hotkey, mark it up in the editor, and save, copy or print it.

> [!IMPORTANT]
> **This is an unofficial, community-made port.** It is not made, endorsed or supported by the Greenshot team.
> The Greenshot team publishes its own, separate "Greenshot" app in the Mac App Store; this project is unrelated
> to it. Please report problems with this port here, not to the Greenshot project.

## Features

| | Greenshot for Windows | This port |
|---|---|---|
| Capture region, with zoomer, size labels and keyboard selection | ✅ | ✅ |
| Capture window (active window, or pick it on the capture screen) | ✅ | ✅ |
| Capture full screen (all displays or one) | ✅ | ✅ |
| Capture last region | ✅ | ✅ |
| Capture window from a list | ✅ | ✅ |
| Open an image from the clipboard or a file | ✅ | ✅ |
| Destination picker after a capture | ✅ | ✅ |
| Save directly with a filename pattern, Save as, Copy, Print | ✅ | ✅ |
| Editor: rectangle, ellipse, line, arrow, freehand, text, counter | ✅ | ✅ |
| Editor: speech bubble, emoji | ✅ | ✅ (any emoji through the macOS Character Viewer) |
| Editor: highlight (text marker, area, grayscale, magnify) | ✅ | ✅ |
| Editor: obfuscate (pixelate, blur), obfuscate text found by OCR | ✅ | ✅ |
| Editor: image element (paste, drop, insert window), cut marks | ✅ | ✅ (cut marks horizontal only) |
| Editor: cut/copy/paste/duplicate, multi-select, arrange, save/load elements | ✅ | ✅ (element files are not compatible with Windows) |
| Editor: font family, text alignment, counter start, crop, undo/redo, remembered styles | ✅ | ✅ |
| Effects: torn edges, border, drop shadow, grayscale, invert, with settings dialogs | ✅ | ✅ (the torn edges' own shadow uses the default settings) |
| Image: resize, rotate, enlarge/shrink canvas, clear background, remove transparency, auto crop, adjust | ✅ | ✅ (vertical/horizontal cut-out not yet) |
| Capture screen: info panel, selection preview, window details, mouse pointer | ✅ | ✅ |
| Fixed-size and text (OCR) capture modes, QR codes on the capture screen | ✅ | ✅ (Vision instead of Windows OCR / Zxing) |
| Print options (colours, footer, shrink/enlarge/rotate/center) | ✅ | ✅ |
| Destinations: email, share, OCR to clipboard, external command, PDF, QR code actions | ✅ | ✅ |
| Office destinations (Word, Excel, PowerPoint, Outlook, OneNote) | ✅ | "Open with…" any app instead |
| Output options: no overwrite, JPEG quality prompt, reduce colours, clipboard formats | ✅ | ✅ |
| Quick settings in the menu, open recent capture, update check | ✅ | ✅ |
| Upload plugins (Jira, Confluence, Box, Dropbox) | ✅ | not yet |
| Recipes, MCP server, browser extension, video recording, translations | ✅ | not yet |

Contributions for the missing parts are welcome; see [Contributing](#contributing).

## Install

Requirements: macOS 14 (Sonoma) or later, and the Swift 6 toolchain. The free Xcode Command Line Tools are enough
(`xcode-select --install`); the full Xcode is not needed.

```bash
git clone <this repository> greenshot-mac
cd greenshot-mac
scripts/build-app.sh
```

This builds `build/Greenshot for Mac (Community).app`. Drag it to your Applications folder and open it. It lives in the
menu bar (camera icon); while an editor or Settings is open it also shows in the Dock and in ⌘Tab (Settings › General ›
"Show in Dock while a window is open"). On a MacBook with a notch, macOS hides menu bar icons that don't fit; opening
the app again from Spotlight brings up Settings, which has a Quit button.

Like Greenshot on Windows, it can open when you log in, so the hotkeys work right after a restart: the welcome window
offers it (ticked by default), and Settings › General › Launch at login turns it on or off. If macOS asks you to approve
it, turn the app on in System Settings › General › Login Items & Extensions.

The first time you take a screenshot, macOS asks you to allow **screen recording**: turn on the app in
System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen it.

macOS remembers the screen recording permission per signature. A plain build is signed ad hoc, which changes with
every build, so you would have to allow screen recording again after each rebuild. To keep it, create a signing
certificate once: in Keychain Access choose Keychain Access › Certificate Assistant › Create a Certificate…, name it
`Greenshot Dev`, Identity Type "Self Signed Root", Certificate Type "Code Signing". `scripts/build-app.sh` uses it
automatically (another one with `SIGN_IDENTITY="Name" scripts/build-app.sh`). If the permission switch is on but the app
still asks, remove the app from the list with −, then reopen it and allow it again.

## Using it

### Hotkeys

Macs have no Print Screen key and ⇧⌘3/4/5 belong to macOS, so the defaults use ⌃⌥⌘ with the same digits.
All of them can be changed in Settings › General (an F13 key works like Print Screen).

| Capture | Greenshot (Windows) | Default here |
|---|---|---|
| Region | Print Screen | ⌃⌥⌘4 |
| Window | Alt + Print Screen | ⌃⌥⌘5 |
| Full screen | Ctrl + Print Screen | ⌃⌥⌘3 |
| Last region | Shift + Print Screen | ⌃⌥⌘6 |
| Open image from clipboard | none | none |

### The capture screen

Like Greenshot, the app freezes the screen first, so menus and tooltips stay where they were while you select.

| Key | Does |
|---|---|
| Drag | select a region |
| Space | switch between region and window mode (from fixed size or text, back to region) |
| Enter | start and finish a selection with the keyboard |
| Arrow keys | move the mouse one pixel (with ⌃ or ⌘: ten) |
| Shift (while dragging) | keep the selection to one direction |
| M | show or hide the mouse pointer in this capture |
| Z | zoomer on or off |
| H or F1 | help on or off |
| I | info panel (screen, selection, window, mouse) on or off |
| P | preview of the selection: in a corner, at the zoomer, off |
| D | window mode: the window's details on or off |
| F | fixed-size mode: an area of a chosen size follows the mouse |
| 1–9, PgUp/PgDn, [ ] | fixed size: pick, previous or next size |
| C | fixed size: hold the area at another corner or the middle |
| hold ⌥ | fixed size: place the area without snapping to windows and screens |
| T | text mode: click a line or drag over words to copy the text |
| click a QR code frame | copy what it says or open its link |
| Esc or right click | cancel |

### The editor

| Tool | Key | | Tool | Key |
|---|---|---|---|---|
| Select | V | | Speech bubble | S |
| Rectangle | R | | Highlight | H |
| Ellipse | E | | Obfuscate | O |
| Line | L | | Counter | I |
| Arrow | A | | Emoji | M |
| Freehand | F | | Crop | C |
| Text | T | | Cut mark | K |

Shift draws squares, circles and lines at 45°. Delete removes the selected element, the arrow keys move it
(Shift: ten points), Esc deselects. Double-click a text to edit it. Right-click an element to bring it to the front or
send it to the back. ⌘S saves, ⇧⌘S saves as, ⇧⌘C copies the image, ⌘P prints, ⌘Z / ⇧⌘Z undo and redo.

A speech bubble is a text box with a tail: drag the handle at the tip of the tail to point it somewhere, double-click
the bubble to edit its text. An emoji is placed with a click; pick another one in the bar at the top or by
double-clicking it, and resize it at its corners.

Shift-click selects several elements; ⌘X/⌘C/⌘V/⌘D cut, copy, paste and duplicate them (⌘C copies the image when
nothing is selected), ⌘A selects all. Paste an image, drop image files on the canvas or use Edit › Insert Window to
add pictures as elements. The Object menu lists the tools, Arrange moves elements up and down, and Save Elements… /
Load Elements… keep the elements in a `.greenshot-elements` file. A cut mark (K) is a band across the picture with
torn, wavy, zig-zag or straight edges.

The Image menu (and the top bar) changes the whole screenshot: Effects (torn edges, border, drop shadow, grayscale,
invert; Drop Shadow and Torn Edges ask for their settings), Adjust…, Resize… (⌥⌘R), Rotate (⌥⌘→ / ⌥⌘←), Enlarge
and Shrink Canvas (⌥⌘= / ⌥⌘−), Clear Background (⌘⌫), Remove Transparency, Obfuscate Text… (finds text with
text recognition and covers every match), Auto Crop (⌥⌘A) and crop to the selected rows or columns. Each is one
undo step; the elements stay editable and move along.

### Destinations

After a capture (or from the editor's File menu) a screenshot can go to: the image editor, Save Directly, Save As…,
Save as PDF… (⌥⌘P), Copy to Clipboard, Copy Text (OCR) (⌥⌘T), Print… (with print options), Email… (⌘E),
Share… (AirDrop, Messages, Notes, …), Open With (any app that opens images), an external command (Settings ›
Destinations: any program gets the screenshot as `{0}`, and a URL from its output can go to the clipboard), and QR
Code (copy or open what a code in the screenshot says). Settings › Destinations chooses which of them run without
asking.

### File names

"Save directly" writes to the output folder (default: Desktop) with a filename pattern, the same patterns as Greenshot:
the default `${capturetime:d"yyyy-MM-dd HH_mm_ss"}-${title}` gives `2026-10-16 14_05_09-Safari.png`.

| Variable | Value |
|---|---|
| `${capturetime:d"<format>"}` | the capture time in a .NET date format, e.g. `d"yyyy-MM-dd"` or `d"D"` |
| `${title}` | the window title |
| `${YYYY}` `${MM}` `${DD}` `${hh}` `${mm}` `${ss}` | parts of the capture time |
| `${NUM}` | a counter, `000001` |
| `${user}` `${hostname}` | user and computer name |
| `${Desktop}` `${MyPictures}` `${MyDocuments}` | folders |
| `${RRRR}` | random characters, as many as R's |
| `${HOME}` and any environment variable | its value |

Options follow a colon, separated by `;`: `p<width>[,<char>]` pads, `s<start>[,<length>]` takes a substring,
`r<old>,<new>` replaces. A `/` in the pattern makes sub folders, e.g. `${YYYY}/${MM}/${title}`.

## Contributing

The project is a Swift package with two targets:

- `Sources/GreenshotCore`: everything without windows — filename patterns, settings, the annotation model,
  the renderer, joining displays. Covered by tests in `Tests/GreenshotCoreTests`.
- `Sources/GreenshotMac`: the app — hotkeys (`App`), the capture screen (`Capture`), destinations (`Output`),
  the editor (`Editor`) and the settings window (`Settings`).

```bash
swift test                     # the core tests
swift build                    # the app, for development
scripts/build-app.sh           # the .app bundle
```

To look at UI changes without granting screen recording, render the editor, capture screen and settings to PNG files:

```bash
swift build && "$(swift build --show-bin-path)/GreenshotMac" --snapshot /tmp/greenshot-snapshots
```

When porting a feature, read how upstream does it in [greenshot/greenshot](https://github.com/greenshot/greenshot)
(for example `src/Greenshot.Editor/Drawing` for the editor elements and `docs/capture-user-guide.md` for the capture
screen) and mention the upstream file in a comment, like the existing code does.

## License and credits

Greenshot for Mac (Community) is free software, licensed under the
[GNU General Public License version 3 or later](LICENSE).

It is a derivative work of **Greenshot**, Copyright © 2007-2026 Thomas Braun, Jens Klingen, Robin Krom,
licensed under the GNU GPL version 1 or later — <https://getgreenshot.org/>, <https://github.com/greenshot/greenshot>.
See [NOTICE.md](NOTICE.md). "Greenshot" refers to the original project; the app icon is this project's own drawing.
