# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Screen recording: Record Screen, Record Window… and Record Region… in the menu bar menu record to an MP4 (H.264 or
  HEVC) with what the Mac plays, the microphone, or both. A "Start or stop recording" hotkey; a countdown; a menu bar indicator
  with the recorded time (click to stop, ⌃-click to pause, resume or discard). A window recording follows the window,
  keeps its size or scales when the window is resized, and ends when the window closes. While recording the Mac stays
  awake, the recording pauses while the screen is locked, and the file is finished before the Mac sleeps or Greenshot
  quits. Settings › Video: quality presets or custom frame rate, bit rate and size, grayscale, the mouse pointer,
  sound, a length limit, the folder (~/Movies/Greenshot) and file name pattern, and what happens with a finished
  recording (show in Finder, open, open with, share, copy the path, or ask every time).
- Command line tool `greenshot-cli` in the app bundle (Contents/Helpers): open images, take screenshots, reload the
  settings, quit the app and run links, with exit codes; it starts the app when needed. Screenshots of the full
  screen, a window or the last region it asks for wait for you to allow them (Don't Allow is the default).
- `greenshotmac://` links open Settings (on a tab), About, Self-Service and the log viewer (filtered by a search text);
  capture and clipboard links work when allowed in Settings › Expert › Automation (off by default).
- Only one copy of the app runs: a second start passes its command to the running one, or says that it runs and where.
  `GreenshotMac --help` and `--background`.
- AppleScript (capture, open clipboard, show settings, show about, reload settings); Shortcuts, Siri and Spotlight
  actions (Take Screenshot, Capture Region, Window or Full Screen, Open Clipboard, Open Image); a Services menu entry
  "Open in Greenshot for Mac" for image files and images.
- Administrators can lock settings and set defaults with a configuration profile (managed preferences, like upstream's
  greenshot-fixed.ini and greenshot-defaults.ini): locked controls show a lock, "Set by your organisation", and
  Settings, Quick Settings, the Expert tab and single destinations can be turned off. A sample profile is in
  docs/admin.
- Recipes engine, without a user interface yet: recipe files load and validate as upstream's do and run as flows with
  branches, joins, conditions and error routes, with expressions such as `${now:yyyy-MM-dd}`. A recipe file runs only
  after you approve that exact content; approvals are signed, and a changed file is asked about again. A command, file,
  folder or destination the recipe decides only when it runs needs its permission too. Files over 1 MB or with more
  than 200 steps, and very long or deeply nested expressions, are refused. Image effects, OCR, QR/barcode scanning,
  text effects and annotations already work as steps.

- Notifications: after a capture, one macOS notification lists where it went, with a thumbnail. Click it within an
  hour to send the capture somewhere else (also after a restart); Edit, Show in Finder and Copy Link buttons; QR codes
  found in the capture are listed (look-alike web addresses show their real host). Settings › Capture › Notifications
  turns the thumbnail on or off and shows whether macOS allows the notifications. Without macOS notifications the
  message in the corner shows an icon per kind and wraps longer texts.
- Diagnostics: a log file in ~/Library/Logs/Greenshot for Mac (Community) and a log viewer (search, log level, live
  entries, load earlier). A Self-Service window (system, your setup with one-click fixes, files and log, clipboard,
  hotkeys and conflicts with the macOS screenshot shortcuts, code signature). A bug report with an issue identifier
  and GitHub links, after an error or, at the next start, after a crash.
- A welcome window with your hotkeys, setup checks and tips replaces the welcome message (existing users see it once);
  an About window with a Self-Service button; Help › Welcome Guide, Self-Service and Log Viewer.
- Editor: torn edges are an element (new random edges, settings, remove later; the canvas grows for their shadow);
  cut marks and torn edges can be drawn into the image with Apply to the Image; cut marks have Cut Edge Settings…;
  cropping with a "Cut edges" style tears the sides the crop cut off; cut marks and torn edges cast one shared shadow.
- Editor: SVG pictures stay sharp at any size as elements, and SVG files open. The mouse pointer of a capture is an
  element you can move, resize or delete.
- Editor: Edit › Insert QR / Barcode… in 15 formats (QR, Aztec, Data Matrix, PDF-417, Code 128/39/93, EAN-13/8,
  UPC-A/E, Codabar, ITF, MSI, Plessey), QR codes for WiFi, contacts, SEPA transfers, email, events, phone, SMS and
  places; colours, round dots and margin with a live preview; double-click to change a code later.
- .greenshot files: open those of Greenshot for Windows 1.2–1.4 with their elements (and .gst element files with
  Object › Load Elements); Save keeps a .greenshot editable; File › Save as Greenshot File… and the output format
  "Greenshot (editable)". Unsaved screenshots are kept when you log out, restart or shut down, or if the app quits
  unexpectedly, and reopen at the next start.
- Edit › Insert Window: shorter titles and a picture of the window while you point at it.
- Capture: window mode can select the areas inside a window (a sidebar, a toolbar, part of a web page; Settings ›
  Capture, needs the Accessibility permission), with PgUp/PgDn for a larger or smaller area. On HDR screens (macOS 15,
  Apple silicon) bright HDR content is tone mapped instead of cut off; screenshots without HDR content keep their
  exact colours. The mouse pointer is also captured on its own for the editor.
- Hotkeys can require the left or the right key of a modifier, e.g. only the right ⌘ (needs Accessibility, or Input
  Monitoring to only listen; otherwise either key works).
- Destinations: Microsoft Word, Excel, PowerPoint and Outlook, and Notes in OneNote's place (AppleScript): a new
  document, slide or mail, or one already open (listed in the destination menu); Settings › Destinations › Microsoft
  Office and Notes. Email with CC or BCC writes the mail in Mail.
- Jira and Confluence Server and Data Center: personal access token or user name and password (asked at upload and
  kept in the Keychain); the Confluence dialog can browse spaces and pages, pick pages open in Safari or Chrome, and
  include personal spaces. Settings › Destinations › Your own servers trusts a self-hosted server's certificate by
  host or fingerprint.


- Capture screen: width and height rulers around the selection with its size in the middle, a dotted crosshair with
  the mouse position, a larger zoomer (a fifth of the display) that shows the selection's edges and can be made
  see-through, and a selection that slides from window to window while panels slide and fade. Window mode also picks
  floating palettes, panels and open menus. A dragged region includes the pixel under the mouse.
- Hotkeys of several steps, like ⌃⌥⌘K then C; Settings › General explains why a key can't be used and warns when two
  hotkeys clash. A "Capture text" hotkey and menu item (the capture screen in text mode, the text to the clipboard).
- Settings › Capture: the sound played after a capture, the zoomer's opacity, and recognising text as soon as the
  capture screen opens.
- Menu bar icon: a click (and a double-click) can run an action you choose, such as capture region or open Settings;
  right-click always shows the menu. The icon can be hidden (open the app again to get to Settings). Capture Window
  from List shows a picture of the window and cuts long titles; Capture Full Screen names each display's position;
  Capture Last Region is greyed out until there is one; Help in the menu.
- Settings › General › Appearance (same as macOS, light or dark); Settings › Expert: beta updates, window thumbnails,
  window title length and an editable next file number. `--settings-dir <folder>` keeps the settings in a JSON file.
- Editor: a two-row toolbar with Delete, Cut, Copy, Paste, Settings, Help and a button per destination; a status bar
  with the last save or export (click it to copy the path or show it in Finder) and a zoom menu; File › New Image
  (size in Settings › Editor), Show in Finder and Copy Path. Editor windows open where the last one was closed, sized
  to the capture.
- Editor: ⌃0–9 sets the fill colour and ⌃⇧0–9 the line colour of the selection, ⌃+ / ⌃− the line width (⇧ by 5),
  ⌃/ the shadow. Shift keeps the aspect ratio of any element while resizing, Option draws or resizes from the centre,
  lines snap to 15°. Z opens Resize.
- Editor: crop modes (Crop, Crop Out Vertically, Crop Out Horizontally, Auto Crop; C cycles them) and handles on the
  crop area. The element context menu has Expand Capture and Move Outside, Stretch, Dock to Edge and Reset Size.
- Editor: paste text as a text element, paste image files copied in Finder and pictures from copied web content, drop
  pictures and web links; icons use their largest size. Number fields for line width, font size, pixel size, blur and
  the area highlight's brightness; cut-edge styles with previews; fonts shown in their own face; colours can be partly
  transparent.
- Image: save as WebP (lossless), ICO, TGA, PBM and PDF. "Reduce the number of colours" writes real 8-bit palette
  PNG, TIFF and GIF files, GIF is always reduced, and an option saves with 256 colours when an image has fewer. PNG,
  JPEG and TIFF files carry a Software tag.
- Image: Drop Shadow and Torn Edges apply their last settings (hold ⌥ to change them first); Remove Transparency asks
  for the background colour; the Effects button also offers Remove Transparency and Obfuscate Text, which now shows
  its matches live with a count.
- Destinations: the menu after a capture comes back when a save, upload or print was cancelled or failed; it is sorted
  like Greenshot's, with icons and keys, and only lists uploads that are set up. New sub-menus: add the capture to an
  open editor, print to a given printer, upload to a recent or on-screen Jira issue or a recent Confluence page.
  Uploads show a progress window with Cancel.
- Saving: the quality dialog (JPEG quality, reduce colours, "don't ask again"), Save As opens in the pattern's sub
  folder or the last folder used, the output folder can hold pattern variables, a failed save opens Save As, and the
  file path is copied after every save. New pattern variable `${windowtitle}`.
- Jira: favourite filters and sortable columns with issue-type icons; Confluence: search in one space; both can reduce
  colours. External commands: an image format per command, `${…}` variables, the saved file when there is one, icons,
  and a warning when the program is missing.


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

- New text is 11 pt and speech bubbles 20 pt by default, pasted text 12 pt: the same size as in Greenshot for Windows
  (it was a third bigger). Cut marks use Greenshot's shadow.
- The duplicate Messages section of Settings › Output is gone; the notification options are on the Capture tab, like
  upstream.
- The app is signed with the Apple Events entitlement, for the Office, Mail and Notes destinations.

- Pixelate can no longer be reversed: blocks vary in size and carry noise from a key that is never stored, like
  Greenshot 1.4. Shrink Canvas trims any border of one colour, not only a transparent one.
- Text elements get Greenshot's 2 pt frame in the text colour (set Width to 0 for none); Return finishes a text and
  Shift-Return adds a line. The area highlight uses Greenshot's brightness and blur radius. Undo is limited by the
  memory of earlier images (256 MB) instead of 100 steps, and arrow-key moves undo together.
- "Capture last region" with nothing stored beeps instead of opening the capture screen; ⌘↩ and similar keys are no
  longer accepted as hotkeys. New installs capture the screen with the mouse for the full screen hotkey.
- Zoom steps through Greenshot's zoom values, ⌘-scroll zooms, and zooming in goes to the selection.
- Reusing the editor picks one without unsaved changes first.

- The Reuse editor, Suppress save dialog at close and Match size to capture settings take effect; with Match size
  off the window keeps the last editor's frame.
- Printing follows the Printer settings: a wide screenshot prints on portrait paper, shrunk to fit, unless "Rotate"
  is on (before, it always printed landscape).
- The "After a capture" destination switches moved from Settings › Output to Settings › Destinations.
- The 28 pt font size is now 27 pt, the Mac size of the speech bubble's 20 pt on Windows.

### Fixed

- Text recognition (OCR) and QR code reading, in recipe steps, on the capture screen and in Edit › Redact Text, no
  longer freeze when several run at once or on Macs with few cores.
- Security: crafted Greenshot for Windows files can no longer crash the app or fill the memory; elements with
  impossible positions (from files or the clipboard) are left out; Jira icons get your credentials only from the
  site's own address; certificate exceptions apply only to your Jira and Confluence servers; tokens are only sent to
  the host they were saved for; only pages on the Confluence site are opened; bug reports no longer show free text
  from the settings; http:// Jira or Confluence URLs get a warning.

- Open Image from Clipboard after copying a file in Finder opened the file's icon instead of the image. Opened images
  are now turned upright by their EXIF orientation.
- After ⌘Tab or a notification took the keyboard, moving the mouse gives the keys back to the capture screen.

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
