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
| Command line tool, links, AppleScript, Shortcuts, Services menu, one running copy | ✅ (greenshot-cli, `greenshot:` links) | ✅ ([below](#command-line-and-automation)) |
| Admin policy: locked settings, defaults, hidden Settings and destinations | ✅ (greenshot-fixed.ini) | ✅ by managed preferences ([below](#managed-settings-administrators)) |
| Screen recording to MP4 (screen, window, region; sound and microphone; pause; countdown) | only in recipes | ✅ |
| Recipes: built-in and your own, editor (steps list and flow diagram), manager, automatic steps, approval of every file | ✅ | ✅ ([below](#recipes)) |
| MCP server for AI tools: list windows, screenshots with OCR, run and propose recipes, consent per program | ✅ | ✅ ([below](#ai-tools-mcp)) |
| Browser extension: capture the visible page with its address | ✅ (Chrome, Firefox) | ✅ Chrome, Edge, Firefox ([below](#browser-extension)); Safari not yet |
| Translations: 40 language packs, right-to-left, language setting, help in your language | ✅ | ✅ Greenshot's translations for the texts the Mac shares with Greenshot for Windows; the rest machine translations ([below](#translations)) |

The row-by-row comparison with Greenshot for Windows (992 features: each one done, or not applicable on a Mac with the
reason) is in [docs/feature-parity.md](docs/feature-parity.md). Some parts can only be checked on a real Mac with
accounts and permissions this project's automated checks don't have; reports and contributions are welcome, see
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
menu bar (the app icon's viewfinder in one colour); while an editor or Settings is open it also shows in the Dock and in ⌘Tab (Settings › General ›
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
still asks, remove the app from the list with −, then reopen it and allow it again. The Keychain doesn't go by the
certificate: after each rebuild of a self-signed or ad hoc app, macOS asks once for each item Greenshot stored there;
enter your login password and choose Always Allow (Allow alone asks again the next time).

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
secret, the sign-ins) live in your Keychain, never in the settings. While the Keychain is locked, or its password
prompt was cancelled or denied, they are kept: an upload says so instead of asking you to sign in again, and
Settings › Destinations shows Retry. Try again and unlock the Keychain or allow Greenshot when macOS asks; if macOS
doesn't ask, lock and unlock the login keychain in Keychain Access (find it with Spotlight), or restart Greenshot.

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

## Recipes

Recipes run a capture as a series of steps, started by a hotkey, an entry in the menu bar's Recipes submenu or the
editor's Recipes menu, a copied image, Open With, the command line or an AI tool. Greenshot for Mac comes with the 13
built-in recipes of Greenshot for Windows; a hotkey or menu capture captures exactly as before until a recipe file
replaces its built-in recipe or an automatic step applies to it.

- **Your own recipes:** import a `.gsrecipe.json` file with Recipes › Import Recipe… or in Settings › Recipes.
  Greenshot shows in plain words what the file does and asks before using it, and again whenever the file changes;
  programs, uploads and file access each need their own switch. Settings › Recipes switches recipes off and lists your
  recipes with their approvals. The approvals are signed with a key in your Keychain. If the Keychain is locked when
  Greenshot starts (or its password prompt was cancelled or denied), the approvals are kept but don't count yet:
  recipe files ask again, and an approval is saved if the Keychain can be used by then (unlock it or allow Greenshot
  when macOS asks). The earlier approvals count again at the next Reload Recipes, approval or start that can read the
  Keychain; unlocking it alone doesn't bring them back.
- **Recipe editor** (menu bar › Recipe Editor…): recipes are edited as a list of steps; branches and parallel lanes are
  indented. Each step's settings are a form made from its contract. The Flow tab draws the flow and copies it as Mermaid
  text. Saving renews the recipe's approval and asks only when a change adds a trigger that starts on its own, a new
  permission, or replaces a built-in recipe. Shortcuts: ⌘N new, ⌘O open, ⌘S save, ⇧⌘S save as, ⌘R test run, ⇧⌘M recipe
  manager.
- **Recipe Manager:** search and filter recipes and automatic steps; Edit, Test Run, Details, Permissions, Unload or
  Reset Default.
- **Automatic steps:** small steps Greenshot adds to your captures, like a caption with the date, a border or a drop
  shadow. Switch them on in Settings › Recipes or Quick Settings › Automatic steps, and choose which captures and
  destinations they're for. Automatic step files (`.gsrecipe.json` with `"kind": "extension"`) are approved like recipe
  files before they're used.

The file format is upstream's: see `Resources/recipe.schema.json` and upstream's recipe documentation. Recipe hotkey
letters name US key positions on the Mac; Settings and the menus show the key of your keyboard layout. An Annotation
step's Line and Arrow take a Mac-only `StartCorner` (`TopLeft`, `TopRight`, `BottomLeft`, `BottomRight`): the corner
of the box where the line starts (Greenshot for Windows ignores it and starts at the top left).

## AI tools (MCP)

Greenshot for Mac comes with greenshot-mcp, an MCP server for AI tools (Claude Code, Claude Desktop, VS Code, Cursor,
…). They can list your windows, take screenshots (with OCR) and run or propose recipes, after you switch on Settings ›
AI Tools and allow each program the first time. A program that runs in a runtime (node, Python, …) is allowed together
with its script; a signed program with its Team ID. Password managers are never shared, every AI screenshot shows a
notification, and a recipe an AI tool proposes starts switched off. Settings › AI Tools has copyable setup for each AI
tool; see [docs/mcp/README.md](docs/mcp/README.md).

## Browser extension

The Companion extension for Chrome, Edge and Firefox 126 or later (in `Extensions/Browser`) sends the visible page,
with its address, to Greenshot. Install the connection in Settings › Expert › Browser extension, then load the extension
folder with Load unpacked (Chrome, Edge) or Load Temporary Add-on (Firefox). See
[docs/browser/README.md](docs/browser/README.md). File names can use `${url}`, `${browser}` and the active tab's
`${Browser.Url}`, `${Browser.Domain}`, `${Browser.Title}` and `${Browser.Ticket}`.

## Translations

Greenshot for Mac uses the translations of Greenshot's 40 language packs, by Greenshot's translators, for every text the
Mac shares with Greenshot for Windows. The other texts (the Mac's own, and those a pack doesn't translate yet) are
machine translations, made by an AI model and checked by a script for placeholders and wording, not by native speakers:
about 4 in 5 texts in German and up to 9 in 10 in other languages, so 95–98 % of the texts show in your language (names,
formats and codes stay as they are). About says so in each language that has them. Kabyle and Franconian are the least
reliable. Corrections are welcome: [docs/translations.md](docs/translations.md) lists the coverage per language and says
how to correct a machine translation (one line in `scripts/l10n/machine/<language>.tsv`). Choose the language in
Settings › General (or on the welcome window's first page, or with `--language de-DE`); it shows after a relaunch.
macOS's own per-app language (System Settings › General › Language & Region) works too. Arabic, Persian and Hebrew are
laid out right to left. Help › Greenshot Help opens Greenshot's help in your language, offline when needed.

## Command line and automation

`greenshot-cli` is in the app bundle (Contents/Helpers). It sends its arguments to the running app, starting the app
when it isn't running, and prints the reply:

    greenshot-cli <file...>                Open image files in the editor (also --file, -f)
    greenshot-cli --capture <mode>         Take a screenshot: region, window, fullscreen, last or text (-c)
    greenshot-cli --reload                 Reload the settings
    greenshot-cli --exit                   Quit the app
    greenshot-cli greenshotmac://<link>    Run a link
    greenshot-cli --recipe <cmd> [k=v…]    Run a recipe with a Commandline trigger (-r; --json, --query, --async)
    greenshot-cli --list-recipes / --info  The recipes you can run (-l), one recipe's arguments (-i)
    greenshot-cli --version / --help

Any program on your Mac can run greenshot-cli, so a screenshot of the full screen, a window or the last region asks
you first: "<program> asks Greenshot for Mac to take a screenshot of …" with Allow and Don't Allow (Don't Allow is
the default; without an answer nothing is captured). Region and text captures don't ask, as you select the area; their
capture screen waits for a click (a second after it shows) before keys work, so what you type into another app at
that moment can't finish it. Escape cancels at once. greenshot-cli shows control characters in what it prints (a QR
code's text, OCR) as `\xNN` on a terminal.

Exit codes: 0 success, 1 failure (also a screenshot you didn't allow), 2 invalid command line, 3 the app isn't
available. To put it on your PATH, use Settings › Expert › Automation › Copy Install Command, or:

    sudo ln -sf "/Applications/Greenshot for Mac (Community).app/Contents/Helpers/greenshot-cli" /usr/local/bin/greenshot-cli

(no sudo needed for ~/.local/bin or /opt/homebrew/bin).

Links (from a browser, Alfred, Raycast, `open`):
- `greenshotmac://settings?tab=general|capture|output|destinations|editor|printer|expert|video|recipes|aitools` (`plugin=<name>` opens Destinations)
- `greenshotmac://about`, `greenshotmac://self-service?section=system|setup|files|clipboard|hotkeys|integrity`
- `greenshotmac://log?search=<text>`
- `greenshotmac://recipe/<id>?key=value` runs a recipe whose Commandline trigger allows browsers (a link can't give it
  file or folder paths);
  `greenshotmac://recipe-editor` and `greenshotmac://recipe-manager` open those windows
- `greenshotmac://capture/region|window|fullscreen|last|text` and `greenshotmac://clipboard`, only when
  "Allow links to take screenshots" is on in Settings › Expert › Automation (any web page can open a link)

AppleScript: `tell application "Greenshot for Mac (Community)" to capture full screen` (also capture region, window,
last region, text; open clipboard; show settings pane "editor"; show about; reload settings).
Shortcuts: Take Screenshot, Capture Region, Capture Window, Capture Full Screen, Open Clipboard in Greenshot, Open Image
in Greenshot. Services menu: "Open in Greenshot for Mac" for image files and selected images.

## Managed settings (administrators)

Greenshot for Mac reads managed preferences: the Mac's counterpart of Greenshot's `greenshot-fixed.ini` and
`greenshot-defaults.ini`. Install a configuration profile for the app's bundle identifier,
`io.github.greenshot-mac.GreenshotMac` (or the `BUNDLE_ID` your build of `scripts/build-app.sh` uses), through your MDM
or by hand. A sample with comments is in [docs/admin/GreenshotMac.mobileconfig](docs/admin/GreenshotMac.mobileconfig).
It uses Apple's `com.apple.ManagedClient.preferences` payload with `Forced`; a payload with the bundle identifier as its
`PayloadType` and the keys directly in it works the same.

- **Keys.** Every setting is `Greenshot.` + its name in the settings file. To see the names, start the app once with
  `--settings-dir <folder>` and read `settings.json`. Examples: `Greenshot.outputFormat` = `jpg`, `Greenshot.jira.url`. A
  member of a group uses a dot (`Greenshot.printing.footer`), or a dictionary for the group (`Greenshot.printing` =
  {footer = true}) sets only the members in it.
- **Locked.** Keys the profile forces are locked. Settings shows the control disabled with a lock, "Set by your
  organisation". The value wins at every start and every change and is never saved, so the user's own values come back
  when the profile is removed. Locked quick settings are left out of the menu bar menu.
- **Defaults.** `Greenshot.defaults` (a dictionary of settings by name) and keys that are not forced (for example
  `sudo defaults write /Library/Preferences/io.github.greenshot-mac.GreenshotMac Greenshot.outputFormat jpg`) fill in
  settings a user doesn't have yet: at the first start, or a setting added by an update. Users can change them.
- **Values.** Switches as `<true/>` / `<false/>`; numbers; texts (a text is also read as a number, a switch or a
  comma-separated list); lists; dictionaries. An empty text clears a hotkey. A hotkey is `{keyCode, modifiers}` with the
  Carbon key code and modifier flags (control 4096, option 2048, shift 512, command 256); ⌃⌥⌘4 is
  `{keyCode = 21, modifiers = 6400}`. A value of the wrong type or an unknown key is ignored and logged (Log Viewer,
  category Managed).

| Upstream (greenshot.ini) | Mac key | Effect |
|---|---|---|
| `DisableSettings` | `Greenshot.disableSettings` | Settings… is left out of the menus; any other way to Settings says it is turned off |
| `DisableQuickSettings` | `Greenshot.disableQuickSettings` | no Quick Settings in the menu bar menu |
| `HideExpertSettings` | `Greenshot.hideExpertSettings` | no Expert tab |
| `HideTrayicon` | `Greenshot.hideMenuBarIcon` | no menu bar icon (opening the app again shows Settings) |
| `ExcludeDestinations`, `ExcludePlugins` | `Greenshot.excludeDestinations` | these destinations are left out of every list and menu and refused; Mac names (`clipboard`, `file`, `fileAs`, `jira`, …), upstream's (`FileNoDialog`, `EMail`, `Windows10Share`, …) and plugin names (`Office Plugin`, `Jira Plugin`, …) |
| `WelcomeShown` | `Greenshot.welcomeShown` | true: no welcome window |
| `IncludePlugins` | — | not ported: list what to exclude instead |

The profile is read at the start, and again when Settings or the menu bar menu opens. Destination buttons in an editor's
toolbar are set when the editor opens; an excluded destination is refused either way. Settings changed outside the
Settings window (editor dialogs, keys on the capture screen) show no lock but keep the locked value. Launch at login and
the Keychain sign-ins can't be locked here. Don't force `welcomeShown` to false (the welcome window would show at every
start) or `incrementingNumber` (`${NUM}` would stop counting).

## Contributing

The project is a Swift package with five targets:

- `Sources/GreenshotCore`: everything without windows — filename patterns, settings, the annotation model,
  the renderer, joining displays, the automation protocol and the recipe engine (`Recipes`). Covered by tests in
  `Tests/GreenshotCoreTests`.
- `Sources/GreenshotMac`: the app — hotkeys (`App`), the capture screen and screen recording (`Capture`),
  destinations (`Output`), the editor (`Editor`) and the settings window (`Settings`).
- `Sources/greenshot-cli`, `Sources/greenshot-mcp` and `Sources/greenshot-native-host`: the command line tool, the MCP
  server for AI tools and the browser extension's native messaging host, which `scripts/build-app.sh` puts in
  `Contents/Helpers`. The browser extension itself is in `Extensions/Browser`.

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
