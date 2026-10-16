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
| Editor: speech bubble, emoji | ✅ | ✅ (a short emoji list instead of the full picker) |
| Editor: highlight (text marker, area, grayscale, magnify) | ✅ | ✅ |
| Editor: obfuscate (pixelate, blur) | ✅ | ✅ |
| Editor: crop, undo/redo, remembered styles per tool | ✅ | ✅ |
| Effects: torn edges, border, drop shadow, grayscale, invert | ✅ | ✅ (upstream's default settings) |
| Effects: settings dialogs, rotate, resize, canvas size, remove transparency | ✅ | not yet |
| Text (OCR) and fixed size capture modes | ✅ | not yet |
| Upload plugins (Imgur, Jira, Confluence, Box, Dropbox), Office export | ✅ | not yet |
| Recipes, MCP server, browser extension, translations | ✅ | not yet |

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
menu bar (camera icon), not in the Dock.

The first time you take a screenshot, macOS asks you to allow **screen recording**: turn on the app in
System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen it.

The build is signed ad hoc. macOS remembers the screen recording permission per signature, so after a rebuild you
may have to allow it again; building with a stable identity avoids that: `SIGN_IDENTITY="My Certificate" scripts/build-app.sh`.

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
| Space | switch between region and window mode |
| Enter | start and finish a selection with the keyboard |
| Arrow keys | move the mouse one pixel (with ⌃ or ⌘: ten) |
| Shift (while dragging) | keep the selection to one direction |
| Z | zoomer on or off |
| H or F1 | help on or off |
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
| Text | T | | | |

Shift draws squares, circles and lines at 45°. Delete removes the selected element, the arrow keys move it
(Shift: ten points), Esc deselects. Double-click a text to edit it. Right-click an element to bring it to the front or
send it to the back. ⌘S saves, ⇧⌘S saves as, ⇧⌘C copies the image, ⌘P prints, ⌘Z / ⇧⌘Z undo and redo.

A speech bubble is a text box with a tail: drag the handle at the tip of the tail to point it somewhere, double-click
the bubble to edit its text. An emoji is placed with a click; pick another one in the bar at the top or by
double-clicking it, and resize it at its corners.

The Effects menu (in the editor's top bar and the Image menu) changes the whole screenshot: torn edges, border,
drop shadow, grayscale or invert. Each is one undo step; the elements stay editable and move along when the
picture grows.

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
