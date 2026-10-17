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
| Editor: image element (paste, drop, insert window), cut marks | ✅ | ✅ |
| Editor: cut/copy/paste/duplicate, multi-select, arrange, save/load elements | ✅ | ✅ (element files are not compatible with Windows) |
| Editor: font family, text alignment, counter start, crop, undo/redo, remembered styles | ✅ | ✅ |
| Effects: torn edges, border, drop shadow, grayscale, invert, with settings dialogs | ✅ | ✅ |
| Image: resize, rotate, enlarge/shrink canvas, clear background, remove transparency, auto crop, cut-out, adjust | ✅ | ✅ |
| Capture screen: info panel, selection preview, window details, mouse pointer | ✅ | ✅ |
| Fixed-size and text (OCR) capture modes, QR codes on the capture screen | ✅ | ✅ (Vision instead of Windows OCR / Zxing) |
| Print options (colours, footer, shrink/enlarge/rotate/center) | ✅ | ✅ |
| Destinations: email, share, OCR to clipboard, external command, PDF, QR code actions | ✅ | ✅ |
| Office destinations (Word, Excel, PowerPoint, Outlook, OneNote) | ✅ | ✅ by AppleScript (Notes instead of OneNote) |
| Output options: no overwrite, quality dialog, reduce colours (8-bit palette files), clipboard formats | ✅ | ✅ |
| File formats: PNG, JPEG, GIF, TIFF, BMP, WebP, ICO, TGA, PBM, PDF | ✅ | ✅ (WebP is saved lossless) |
| Hotkeys of several steps, menu bar icon click actions, light/dark appearance | ✅ | ✅ |
| Quick settings in the menu, open recent capture, update check | ✅ | ✅ |
| Upload plugins (Jira, Confluence, Box, Dropbox) | ✅ | ✅ (Cloud and Server/Data Center; Box and Dropbox need your own app registration) |
| Notifications with thumbnail and buttons, log viewer, Self-Service, bug report, welcome window | ✅ | ✅ |
| QR / barcode generator, editable torn edges, SVG and mouse pointer elements | ✅ | ✅ |
| .greenshot files (also from Windows), unsaved screenshots kept across restarts | ✅ | ✅ (Mac files open in Windows as the image only) |
| Areas inside windows, HDR capture, left/right modifier hotkeys | ✅ | ✅ (Accessibility / Input Monitoring permissions) |
| Recipes, MCP server, browser extension, video recording, translations | ✅ | not yet |

The row-by-row comparison with Greenshot for Windows (992 features, what is done and what is planned) is in
[docs/feature-parity.md](docs/feature-parity.md). Contributions for the missing parts are welcome; see
[Contributing](#contributing).

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

Some features ask macOS for more permissions, only when you use them: **Notifications** (the message after a capture),
**Accessibility** (areas inside windows, hotkeys that need the left or right key of a modifier; Input Monitoring is
enough for the hotkeys to only listen) and **Automation** (the Office, Mail and Notes destinations, Confluence pages
open in a browser). Keep one copy of the app: two copies with the same identifier (e.g. one in build/ and one in
Applications) can make a click on a notification open the other one.

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

Shift draws squares, circles and lines at 15° steps, and keeps the aspect ratio while resizing; Option draws and
resizes from the centre. With elements selected, ⌃0–9 sets the fill colour, ⌃⇧0–9 the line colour, ⌃+ / ⌃− the line
width and ⌃/ the shadow. Delete removes the selected element, the arrow keys move it
(Shift: ten points), Esc deselects. Double-click a text to edit it. Right-click an element to bring it to the front or
send it to the back. ⌘S saves, ⇧⌘S saves as, ⇧⌘C copies the image, ⌘P prints, ⌘Z / ⇧⌘Z undo and redo.

A speech bubble is a text box with a tail: drag the handle at the tip of the tail to point it somewhere, double-click
the bubble to edit its text. An emoji is placed with a click; pick another one in the bar at the top or by
double-clicking it, and resize it at its corners.

Shift-click selects several elements, or drag a rubber band over them with the Select tool; ⌘X/⌘C/⌘V/⌘D cut,
copy, paste and duplicate them (⌘C copies the image when nothing is selected), ⌘A selects all. Paste an image, drop image files on the canvas or use Edit › Insert Window to
add pictures as elements. The Object menu lists the tools, Arrange moves elements up and down, and Save Elements… /
Load Elements… keep the elements in a `.greenshot-elements` file. A cut mark (K) is a band across the picture with
torn, wavy, zig-zag or straight edges; cutting columns out makes one down the picture.

The Image menu (and the top bar) changes the whole screenshot: Effects (torn edges, border, drop shadow, grayscale,
invert; Drop Shadow and Torn Edges ask for their settings), Adjust…, Resize… (⌥⌘R), Rotate (⌥⌘→ / ⌥⌘←), Enlarge
and Shrink Canvas (⌥⌘= / ⌥⌘−), Clear Background (⌘⌫), Remove Transparency, Obfuscate Text… (finds text with
text recognition and covers every match; pixel size, blur radius, magnification and highlight colour are in the
dialog), Auto Crop (⌥⌘A) and Cut Out the Selected Rows or Columns (the rows or columns of the crop selection are cut
out and the sides joined, with an optional cut mark over the joint chosen in the crop bar). Each is one undo step;
the elements stay editable and move along.

### Destinations

After a capture (or from the editor's File menu) a screenshot can go to: the image editor, Save Directly, Save As…,
Save as PDF… (⌥⌘P), Copy to Clipboard, Copy Text (OCR) (⌥⌘T), Print… (with print options), Email… (⌘E),
Share… (AirDrop, Messages, Notes, …), Open With (any app that opens images), an external command (Settings ›
Destinations: any program gets the screenshot as `{0}`, and a URL from its output can go to the clipboard), and QR
Code (copy or open what a code in the screenshot says), and the uploads: Jira, Confluence, Box and Dropbox. Settings
› Destinations chooses which of them run without asking.

### Uploads

Greenshot's upload plugins are built in, set up under Settings › Destinations. Secrets (API tokens, the Box client
secret, the sign-ins) live in your Keychain, never in the settings.

- **Jira** and **Confluence** (Atlassian Cloud): the site URL (Confluence sites end in `/wiki`), your email and an
  [API token](https://id.atlassian.com/manage-profile/security/api-tokens). "Upload to Jira…" asks for the issue (a
  key, one of the last ten, or a search by words or JQL), attaches the image and can add a comment; the message
  afterwards opens the issue. "Upload to Confluence…" asks for the page (the last ten, or a search by title or CQL),
  attaches the image, copies the wiki markup `!name!` or the image's link to the clipboard and opens the page.
- **Box** and **Dropbox**: Greenshot for Windows ships its own app keys, which this port can't reuse, so you register
  an app of your own once (the Settings footers say where and with which redirect URI: `http://127.0.0.1:52398/box`
  and `greenshotmac://oauth/dropbox`) and paste its client ID (Box: and secret) or app key. The first upload signs you
  in through the browser (OAuth 2 with PKCE); the refresh token stays in the Keychain. The image goes to the Box folder
  ID or the Dropbox folder you set, and a link (shared when asked for) goes to the clipboard.

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
