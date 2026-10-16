# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Capture screen: the mouse pointer is in interactive captures when "Capture the mouse pointer" is on, and M shows or
  hides it for one capture. An info panel (I: screen, selection, window, mouse), a preview of the selection (P: in a
  corner, at the zoomer, off) and window details (D). The panels move out of the way of the mouse and the selection,
  and the key, info, preview (including its place) and zoomer choices are remembered.
- Fixed-size capture (F) with the sizes from Settings › Capture and the last five region sizes: 1–9, PgUp/PgDn or
  [ ] pick a size, C moves the area to another corner or the middle, edges snap to windows and screens unless ⌥ is
  held.
- Text capture (T): recognises the text on the screen (Vision); click a line or drag over words to copy the text.
- QR codes on the capture screen get a frame; click one to copy what it says or open its link (Settings › Capture
  turns it off).
- Settings › Capture: what the full screen hotkey captures (the screen with the mouse, all screens, or one screen),
  the text recognition language, and which messages are shown.
- Editor: cut, copy, paste and duplicate elements (⌘X/⌘C/⌘V/⌘D); select several with Shift-click, a rubber band
  dragged over them with the Select tool, or Select All, and move, delete, arrange or restyle them together. ⌘C
  copies the image when no element is selected.
- Editor: image elements: paste an image or drop image files onto the canvas; Shift keeps the aspect ratio while
  resizing; optional shadow. Edit › Insert Window adds a capture of an open window the same way.
- Editor: Object menu with the drawing tools and their one-letter shortcuts, Select All, Delete, Arrange (Bring to
  Front ⇧⌘F, Bring Forward ⌥⇧⌘F, Send Backward ⌥⇧⌘B, Send to Back ⇧⌘B), Save Elements… and Load Elements…
  (`.greenshot-elements` files).
- Editor: cut mark element (K): a band across the image with straight, zig-zag, wavy or torn edges, a transparent or
  filled gap, a shadow and an optional line. A mark across the columns comes from cutting columns out, or from
  rotating the image.
- Editor: font family and horizontal/vertical alignment for text and speech bubbles; counter start value and outline
  width; shadow for freehand, highlight, obfuscate, counter, emoji and image elements; 2×/3×/4× for the magnifier.
- Editor: any emoji through the system Character Viewer (double-click an emoji, or More Emoji…); zoom presets
  25 %–600 % in the View menu; Close All (⌥⌘W).
- Editor: Drop Shadow and Torn Edges ask for their settings (thickness, offset, darkness; edges, tooth size and
  ranges, background colour, and the torn edges' own shadow with its thickness, offset and darkness) and remember
  them. Image menu shortcuts: ⌃⌘B border, ⌃⌘S drop shadow, ⌃⌘T torn edges, ⌃⌘G grayscale, ⌃⌘I invert.
- Editor: Resize (⌥⌘R, pixels or percent, aspect ratio kept), Rotate (⌥⌘→ / ⌥⌘←), Enlarge Canvas (⌥⌘=), Shrink
  Canvas (⌥⌘−), Clear Background (⌘⌫), Remove Transparency, Auto Crop (⌥⌘A), Adjust brightness/contrast/gamma.
  The elements move, scale and turn along.
- Editor: Cut Out the Selected Rows / Columns: the rows or columns of the crop selection are cut out and the two
  sides joined; elements inside the cut go, elements after it move along. The joint can be marked with a cut mark
  (None, Line, Zig-zag, Wave or Torn, chosen in the crop bar), whose gap keeps a few rows or columns of the strip.
- Editor: Obfuscate Text… finds text with text recognition and pixelates, blurs, highlights or magnifies every match,
  with the pixel size, blur radius, magnification or highlight colour set in the dialog.
- Print options before printing (colour, grayscale, black and white, inverted; a footer from a pattern; shrink,
  enlarge, rotate, center), and a Settings › Printer tab.
- New destinations: Email (⌘E), Share, Copy Text (OCR) (⌥⌘T), External commands (any program with the screenshot
  as `{0}`, a URL from its output or all of it to the clipboard), Save as PDF (⌥⌘P; page size, margins, shrink or
  fit), Open With (any app that opens images), QR code actions. All of them are in the destination menu, the
  editor's File menu and Settings › Destinations.
- Upload destinations, like Greenshot's Jira, Confluence, Box and Dropbox plugins: "Upload to Jira…" (issue key,
  recent issues or a JQL/text search, optional comment, a message that opens the issue), "Upload to Confluence…"
  (page search by title or CQL, wiki markup or image link to the clipboard, open the page), "Upload to Box" and
  "Upload to Dropbox" (your own app registration, OAuth 2 with PKCE in a sign-in sheet, folder, shared link to the
  clipboard). Atlassian API tokens, the Box client secret and the sign-ins are kept in the Keychain. All four are in
  the destination menu, the editor's File menu and Settings › Destinations (with Test Connection, Sign In and Sign
  Out).
- Output: no-overwrite naming ("name (2)"), an optional JPEG quality prompt, reducing PNG/GIF to N colours, the
  clipboard formats (PNG, TIFF, JPEG, HTML), and a message level.
- Menu bar: Open Recent Capture, Quick Settings (mouse pointer, destinations, print options, sound, notifications),
  and Open Image from Clipboard is disabled when there is nothing to open. Help: Greenshot Help and Report an Issue.
- Settings: new Destinations, Editor, Printer and Expert tabs (Expert resets the `${NUM}` counter). Checks GitHub
  for a new version every 14 days (adjustable, 0 = never), plus Check Now.

- A Dock icon (and a place in ⌘Tab) while an editor or Settings is open; it goes away with the last window, while
  the menu bar icon stays until Quit. On by default, Settings › General › "Show in Dock while a window is open".
  Clicking the Dock icon shows the open screenshots or Settings. The menu bar icon keeps the place it is ⌘-dragged to.
- Open at login, like Greenshot's "start with Windows": the welcome window offers it, ticked by default, and users
  who saw the welcome before are asked once. When macOS wants approval, its Login Items settings open, and
  Settings › General shows what is missing.
- A Quit button in Settings › General, for when macOS hides the menu bar icon (behind the notch, or in its menu bar
  settings). Opening the app again from Spotlight or Finder shows Settings.

- Speech bubble element (S), ported from Greenshot's `SpeechbubbleContainer`: a rounded text box with a tail whose
  tip is a handle; blue outline and bold text on white by default, text edited in place.
- Emoji element (M): placed with a click, resized at its corners, picked from a short list in the top bar or with a
  double-click; the last pick is remembered.
- Effects menu in the editor and an Image menu: torn edges, border, drop shadow, grayscale and invert with
  Greenshot's default settings, applied to the whole screenshot as one undo step.

### Changed

- The Reuse editor, Suppress save dialog at close and Match size to capture settings take effect; with Match size
  off the window keeps the last editor's frame.
- Printing follows the Printer settings: a wide screenshot prints on portrait paper, shrunk to fit, unless "Rotate"
  is on (before, it always printed landscape).
- The "After a capture" destination switches moved from Settings › Output to Settings › Destinations.
- The 28 pt font size is now 27 pt, the Mac size of the speech bubble's 20 pt on Windows.

### Fixed

- Settings › Output: the destinations can be turned on while "Ask every time" is on (turning one on turns the menu
  off). Before, they were greyed out and "Ask every time" couldn't be turned off, so captures couldn't go straight to
  the clipboard.
- Opening the app again (Spotlight, Finder) always shows Settings or the open screenshots on the Space you are on.
  Before, a Settings window left open on another Space meant nothing appeared. Settings, like the editors, now comes
  to your Space and hides when you click another app.
- Starting the app shows a short "is running" message (click it for Settings), since a menu bar app opens no window
  and macOS may hide its icon behind the notch.
- When screen recording isn't allowed, the app now tries a capture once, which is what makes recent macOS versions
  list it under Screen & System Audio Recording; the message also says to add it with + when it isn't listed.
- The screen recording message explains what to do when the switch is already on but belongs to an older build, and
  `scripts/build-app.sh` signs with a "Greenshot Dev" certificate when there is one, so the permission survives
  rebuilds (see the README).
- "Open in Image Editor" opens the editor right where you are, also over a full screen app, without jumping to the
  desktop; it hides when you click another app and comes back when you open Greenshot again (Spotlight, Finder, or
  "Show Open Screenshots" in the menu bar menu). Greenshot no longer turns into a Dock app while an editor is open.
- The editor no longer opens wider than the screen.
- The capture screen appears right away over the app in front, also a full screen one, instead of waiting on
  another Space until Greenshot was clicked in the Dock (it happened while an editor window was open).
- Retina screenshots keep their size when saved or copied: the files carry 144 dpi and the clipboard image its
  point size, so Preview, other apps and the editor (File › Open, drag onto the app) show them at their real size,
  and annotations added after reopening have the right line thickness and font size.

## [0.1.0] - 2026-10-16

### Added

- Menu bar app with global hotkeys (⌃⌥⌘4 region, ⌃⌥⌘5 window, ⌃⌥⌘3 full screen, ⌃⌥⌘6 last region).
- Capture screen ported from Greenshot: frozen screen, region and window modes, zoomer, size labels, keyboard
  selection, Shift to keep one direction, help panel.
- Captures: region, window (active, interactive or from a list), full screen (all displays or one), last region,
  image from the clipboard or a file.
- Destinations: destination picker, image editor, clipboard, save directly, save as, print.
- Image editor: rectangle, ellipse, line, arrow, freehand, text, counter, highlight (text marker, area, grayscale,
  magnify), obfuscate (pixelate, blur), crop, undo/redo, zoom, remembered styles per tool.
- Greenshot's filename patterns, including .NET date formats.
- Settings window: hotkeys, launch at login, capture options, destinations, output folder, pattern and format.
- `--snapshot <folder>` renders the UI to PNG files for development.
