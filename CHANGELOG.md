# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Translations: menus, the editor, Settings and dialogs show Greenshot's translations in 39 languages from Greenshot's
  language packs, and machine translations (by an AI model, not reviewed by native speakers) for the texts the packs
  don't have, so 95–98 % of the texts are translated in every language (coverage per language and how to correct a
  machine translation in docs/translations.md). About says when a language has machine translations. Choose the language in Settings › General or on the welcome window's first page (it
  shows after a relaunch), or start with `--language <code>`. Arabic, Persian and Hebrew windows are laid out right to
  left, with numbers and hotkeys kept in order. Help opens Greenshot's help in your language, offline too.
- Editor: SVG pictures, pictures, emoji and QR codes / barcodes turn with Rotate instead of being squeezed, and turned
  SVG and emoji elements from Greenshot for Windows files keep their turn. Several area highlights no longer darken each
  other's areas. The colour panel lists the 12 colours you used last as the "Greenshot Recent" palette.
- Destinations: Jira issues you looked at in any window are offered in the destination menu and the upload window (only
  keys of your Jira's own projects; needs Screen Recording; pauses while the Mac sleeps or is locked). Outlook can attach
  screenshots to open meetings you organise (legacy Outlook; Settings › Destinations › "Outlook: allow export in meeting
  items"). External commands can write their output to the log ("Write the output to the log"); their errors are logged
  when the command fails, at most 600 characters, with passwords and tokens replaced.
- Recipes: the InteractiveSelection step's SelectionTool accepts Region, Window and Text; the RecordVideo step's
  ShowCaptureBorder draws a yellow frame around what is recorded that is not in the video; a recipe's print options
  apply only to its own print, and options locked by your organisation win and show greyed out with a lock.

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
- Recipes: a capture can run as a recipe, a series of steps started by a hotkey, the menu bar's Recipes submenu, the
  editor's Recipes menu, a copied image, Open With, the command line or an AI tool. 13 built-in recipes as in Greenshot
  for Windows (region, window, active window, full screen, last region, clipboard, open file, OCR text, a notification's
  capture, browser extension captures and three AI tool captures); a hotkey or menu capture captures exactly as before
  until a recipe file replaces its built-in, an automatic step changes it, or you switch it off. Steps capture, select,
  play the camera sound, export to every destination (with file, editor and printer options per step), notify once per
  flow, copy image or text, record video, run external commands, upload to Jira, Confluence, Box and Dropbox, and show a
  decision prompt or a destination flyout. Recipe files load and validate as upstream's do, with expressions such as
  `${now:yyyy-MM-dd}`.
- Recipe approval: a recipe file runs only after you approve that exact content. The approval window says in plain
  words what it does, with a switch per trigger and per permission, and what changed in a changed file; approvals are
  signed, a changed file is asked about again, and a command, file, folder or upload target a recipe decides only when
  it runs needs its permission too. Approve is never the Return button and waits a moment when the window opened on its
  own. Files over 1 MB or with more than 200 steps, and very long or deeply nested expressions, are refused.
- Recipe editor (menu bar › Recipe Editor…): recipes as a list of steps with branches and parallel lanes, forms made from
  each step's contract (colour, file, sound, table, destination and hotkey editors), Triggers, Options, Error Routes,
  Recipe and JSON tabs, a Flow tab that draws the flow and copies it as Mermaid text, annotations imported from open
  editors or .greenshot files, undo and redo, Test Run, and saving that renews the approval and asks before replacing a
  file that holds other recipes.
- Recipe Manager: search and filters over recipes and automatic steps, with Edit, Test Run, Details, Permissions, Unload
  or Reset Default, Load Recipe…, New Recipe, Reload All and Reset All. Settings › Recipes switches recipes on or off,
  lists your recipes with their approvals and files, shows the options of recipes and automatic steps, and asks before
  Unload and Reset Default.
- Automatic steps: Caption, Border and Drop shadow for every capture, switched on in Settings › Recipes or Quick Settings
  › Automatic steps and limited to some recipes and destinations; automatic step files are approved like recipe files.
- Recipe hotkeys work next to Greenshot's own (a clashing one is left out and listed in Settings › Recipes); Clipboard
  and Open With triggers run recipes when another app copies an image or a file is opened with Greenshot; a failed
  recipe says so in a notification. Quitting while recipes run or with unsaved recipe edits asks first.
- AI tools: greenshot-mcp, an MCP server in the app bundle, lets Claude Code, Claude Desktop, VS Code, Cursor and other
  AI tools list your windows, take screenshots with optional text recognition, and run or propose recipes. It is off
  until you switch it on in Settings › AI Tools, and each program is asked about once; a program running in a runtime
  (node, Python, …) is allowed together with its script, and a signed one with its Team ID. The question counts Allow
  only when nothing covers it. Password managers are never shared (their windows are blacked out), every AI screenshot
  shows a notification, and a recipe or automatic step an AI tool proposes starts switched off after you approve it.
- greenshot-cli runs recipes (`--recipe`/`-r` with arguments, `--list-recipes`/`-l`, `--info`/`-i`, `--json`, `--query`,
  `--async`) and asks before a recipe takes a screenshot you don't select; `greenshotmac://recipe/<id>` runs recipes that
  allow it, `greenshotmac://recipe-editor` and `greenshotmac://recipe-manager` open those windows.
- Browser extension "Greenshot for Mac (Community) Companion" for Chrome, Edge and Firefox (126 or later): Capture
  Visible Page sends the page to Greenshot, which asks where it goes, or a recipe with a browser extension trigger takes
  it. File names can use `${url}`, `${browser}` and the active tab's `${Browser.Url}`, `${Browser.Domain}`,
  `${Browser.Title}` and `${Browser.Ticket}` (cleaned, so they can't leave the output folder). Settings › Expert ›
  Browser extension installs the browsers' connection; administrators can switch the extension off.
- A recipe's RecordVideo step without DurationSeconds or UntilWindowCloses records until you stop it from the menu bar
  (Greenshot for Windows stops it at once).

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

- The menu bar icon is the app icon's viewfinder corners and selection in one colour instead of a camera, so it matches
  the Dock icon.
- The grayscale highlight now greys everything outside its area and keeps the area in colour, like Greenshot for
  Windows. Existing images with a grayscale highlight look different.
- The clipboard hotkey is called "Open image from clipboard" everywhere. File names use Latin digits in every language
  and region.
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

- Crashes: Greenshot no longer quits on extreme values. A recipe file with a number like 9223372036854775807 stopped
  it at load (and so at every launch); so did a recipe value that is infinite or not a number in a greenshot-cli, AI
  tool or browser reply, a configuration profile value of nan or infinity, two recipe steps with the same id in the
  recipe editor's Flow tab, huge or "nan" sizes in recipe effects (Resize, Resize canvas, Border, Drop shadow, Torn
  edges, Adjust, Text effect padding; they now report that they could not be applied), a recipe speech bubble far
  outside the capture, extreme pad or substring numbers in a file name pattern (`${title:p…}`, `${title:s…}`; padding
  is limited to 1024 characters) and a `${NUM}` counter at its largest value (it starts again at 0).
- Screen Recording: without the permission, the first capture shows a short message that opens the setting instead
  of doing nothing (in the app when Greenshot's notifications are off, without asking for them); a permission turned on while Greenshot runs is used as soon as macOS allows captures, without the
  "quit and reopen" message on every press, and Settings and Self-Service then say it is allowed.
- Editor: changes made while an upload or print was still running are no longer marked as saved when it finishes, so
  closing the window still asks and the autosave keeps them.
- Editor: counters keep their numbers when elements are brought to the front or sent to the back. They are numbered
  in the order they were added, as in Greenshot for Windows, also in saved .greenshot files and when they are
  imported into a recipe's Annotation step.
- Editor: Crop, Auto Crop and Shrink Canvas remove the elements that lie completely outside the new image, as in
  Greenshot for Windows, so the remaining counters renumber and no hidden elements are saved or come back when the
  canvas is enlarged. Undo brings them back.
- Editor: consecutive colour changes to the selected elements in the Line or Fill colour well are one undo step, as
  in Greenshot for Windows, however long the mouse moves in the colour panel.
- Screen recording: a recording whose file can't be written any more (the disk is full, the drive was removed) stops
  at once and keeps what was recorded until then; before, it went on and then deleted the whole file at Stop.
- Screen recording: a recipe's Record Video step can record again to the same file name; the new recording replaces
  the old file once it has its first frame, as in Greenshot for Windows (it failed with "Cannot Save"), and a
  recording that doesn't start keeps the old file (also with a very long file name). A recipe that records a display without a monitor number records
  the main display (the one with the menu bar); monitor numbers count displays in the same order as the AI tools'
  window list.
- Screen recording: a recording with sound no longer loses the first moment of sound or the sound just after a pause,
  and cancelling the countdown just as it reaches zero no longer starts the recording.
- Capture: "Capture active window" no longer captures another app's window when the active app has no window on the
  screen (after a click on the desktop, or with an app that only has a menu bar item); like Greenshot for Windows it
  captures the whole screen then, from the hotkey, the menu and recipes you start; started by greenshot-cli, a link,
  an AI tool or another program it reports that the window isn't there instead of taking more than was asked.
- Capture screen: the letter keys (Z, M, F, T, H, I, P, D, C, [ and ]) also work with Russian, Greek, Hebrew or Arabic
  keyboard layouts; Enter twice at the same spot no longer captures a single pixel on a non-Retina display; a
  selection across a Retina and a non-Retina display shows the size the capture will have.
- Hotkeys: shown with the keys of your keyboard layout in Settings, menus and messages (Z instead of Y on a German
  keyboard, A instead of Q on a French one), right after a layout switch. When macOS refuses some hotkeys, a
  notification that opens Self-Service › Hotkeys (shown in the app when Greenshot's notifications are off) replaces
  the alert that held up the start of the app (and a capture
  started at launch) and came back each time Settings closed. Clicking from one shortcut recorder straight to another
  no longer turns the hotkeys back on while the new shortcut is typed. Without the Accessibility or Input Monitoring
  permission, Settings warns when a hotkey or a recipe hotkey differs from another only by its left or right key,
  because only one of them can work then.
- Quick Settings › Show Notifications turns notifications back on after Settings was set to None, and its checkmark
  shows whether notifications are on.
- Settings › Destinations: a Microsoft Office destination whose app is no longer installed stays listed while it is
  turned on, so it can be turned off.
- Settings: a settings file with a missing or unknown print, email, drop shadow, PDF, Box or Dropbox option (for
  example from a newer version) keeps the other options of that group instead of resetting all of them.
- Quality dialog: no JPEG quality for WebP (it is saved lossless); "Reduce colours" is offered for every format it
  changes.
- An empty print footer, mail subject or external command argument stays empty instead of becoming "greenshot <date
  time>"; only an empty file name pattern still falls back to that name.
- Jira and Confluence: the search fields take JQL and CQL, including custom fields, functions such as openSprints(),
  and WAS or CHANGED; text that only looks like a query, or plain words ("project kickoff", "login (beta)"), is
  searched as words instead of failing with "Error in the JQL Query", and a "+" ("C++", "Q3+Q4 plan") is no longer
  read as a space (also in a Dropbox file name). A Jira upload whose comment could not be added counts as done and says the comment is missing,
  so a retry doesn't attach the file twice. After a Server/Data Center password changes, the next upload (also from a
  recipe) asks for it again instead of failing with HTTP 401 for the rest of the session.
- The QR Code destination no longer reports "Exported to: QR Code" when the screenshot has no QR code.
- Check Now says "No release has been published yet." when GitHub has no release, instead of "up to date".
- Recipes: a recipe whose error handler names a step that doesn't exist is reported when it is loaded, and if such a
  step fails the recipe fails instead of ending as a success; a recipe is no longer refused as a loop because of an
  error handler it never uses (for example when a step hands its errors to another recipe). A step that fails next to an error handler, and the saves
  and uploads of a recipe a failure is handed to, count in the recipe's result and failure message; parts of a recipe
  that run side by side no longer list an export again that a notification already showed.
- Recipes: a recipe runs after you approve its changed file again, even when another recipe in the same file can't be
  loaded; the second and later recipes of a new file are no longer shown as "changed outside Greenshot".
- Recipes: if the Keychain is locked or can't be read when Greenshot starts, approving a recipe no longer erases your
  approvals of other recipe files, and Revoke says when it couldn't revoke an approval instead of seeming to work.
- Recipes: "Reset to defaults" no longer also resets a recipe whose id starts with the same name, and drops a value
  that was typed but not yet applied; an automatic step limited to some destinations also runs for an external
  command with a comma or semicolon in its name; changing where an automatic step is used keeps the exclusion of a
  recipe that wasn't listed at that moment. Recipe elements far outside the capture no longer vanish from a saved
  .greenshot file: a Text effect element stays in range, an annotation that far away is skipped with a warning.
- Recipe editor: lines and arrows imported from the image editor keep their direction (a new `StartCorner` annotation
  setting); a TextEffect pattern written as text is shown as one pattern; clearing a list field removes it; Insert
  Step After on a Conditional or user prompt puts the step into its first branch; Delete after Undo removes the
  selected connection; a recipe with one step and no start step shows that step as its start everywhere.
- Recipes: a recipe file that lists thousands of next steps for one step no longer makes Greenshot or the recipe
  editor hang for minutes while it reads, shows or edits the file.
- Links and AI tools: `greenshotmac://recipe/…` with a recipe name that has spaces (`Save%20to%20Desktop`) runs that
  recipe; AI tools can give a capture region with decimal numbers.
- Browser extension: the popup says "Sent to Greenshot!" only when Greenshot took the screenshot, otherwise why not;
  it connects again by itself after Greenshot refused it and shows Greenshot's reason instead of just "Offline", no
  longer shows "Offline" right after Greenshot started, and no longer starts Greenshot's connection helper on every
  tab change while Greenshot isn't running or refuses it. `${Browser.*}` in file names is filled again at once after
  Greenshot restarts or the extension is switched back on, and is forgotten when the browser closes its connection,
  the extension is switched off in Settings or tab tracking is turned off.
- Logs and bug reports: deleting Greenshot.log while the app runs no longer loses the entries that follow; the log
  viewer's "Load Earlier" no longer gets stuck on an entry longer than 64 KB or leaves out a line; bug reports no
  longer contain the paths of your recipe files or the ids of your custom recipes, and only your own home folder is
  shortened to "~".
- PowerPoint: sending a screenshot works with PowerPoint 16 (it refused the new slide and the picture as the scripts made them, and has no slide height in its page setup).
- Office destinations: when macOS blocks Greenshot from Office's shared folder (macOS 15 and later), Greenshot says what to allow in Files & Folders and opens the setting, instead of "The screenshot could not be written".
- Editor: the green window button goes full screen like in other Mac apps (⌥-click fills the screen); the editor still opens over another app's full screen Space.
- Editor: the "Do you want to save the screenshot?" question at quit (and before a new capture replaces a changed one) shows on the Space you're on; it could open out of sight on another Space and leave every Greenshot window unclickable.
- Editor: a full screen editor stays full screen when an effect (Border, Drop Shadow, Torn Edge…), a crop or a resize changes the picture's size, instead of shrinking to a small window on a black screen; with "match size to capture" it fits the picture when it leaves full screen.
- Notes: a screenshot sent to Notes shows once; on macOS 26 and later it appeared twice.
- Translations: texts no longer cut off in longer languages. The Settings window grows to show all ten tab names; the
  log viewer's buttons, the recipe manager's status badges and search field, the Export Capture tiles, the recipe
  editor's toolbar (symbols only when the titles don't fit), pickers, prompt choices and arguments, the welcome window
  and the Self-Service sidebar make room for them; English looks as before. The recipe badges BUILT-IN, REPLACES
  BUILT-IN and AI, the recipe editor's approval notes, the barcode errors, the hotkey clash note, "Untitled" and the
  recipe outline's In/Out are translated now, and badges stay in capitals.
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

### Security

From a security review of the whole app (October 2026). Most of these stop another program on your Mac from using
Greenshot's screen recording permission behind your back.

- AI tools: the allowed AI tools, the excluded apps and the capture notification are sealed with a key in your
  Keychain. When another program edits them in the preferences, Greenshot resets them and asks again. After this
  update, AI tools you allowed before are asked about once more.
- AI tools: a runtime (Node.js, Bun, Deno, Python, Ruby, Perl, PHP) is allowed with every option before its script and
  with the variables that load code (`NODE_OPTIONS`, `PYTHONPATH`, `RUBYOPT`, `PERL5OPT`, `PHPRC`, …), so a tool
  started with options such as `node --no-warnings` is asked about once more. A shell between the AI tool and
  greenshot-mcp is skipped only when it is a system shell that starts greenshot-mcp directly: a shell script an AI
  tool runs no longer gets the AI tool's consent, and a tool started through Homebrew's bash or zsh or fish must start
  greenshot-mcp itself. A program that starts greenshot-mcp and then turns itself into an allowed program is refused.
- A capture screen that greenshot-cli, a link, AppleScript, Shortcuts or such a recipe opened waits for a click (a
  second after it shows) before keys work, so what you type into another app can't finish the capture. Escape cancels
  at once. The wait before a capture is at most 10 seconds, also when the preferences say more.
- greenshot-cli and the browser extension's helper send nothing to a program listening on Greenshot's socket that
  isn't Greenshot (greenshot-mcp already checked this); the extension then hears that the app is offline.
- greenshot-cli shows control characters from a QR code, OCR or a window title as `\xNN` on a terminal, so a QR code
  can't send escape sequences to it. Pipes, files and `--json` get the exact text.
- Links can no longer give a recipe file or folder paths; the command line still can.
- A web page can no longer end a Box sign-in or put its own text into the sign-in error.
- A window or page title can no longer choose the folder a screenshot or recording is saved in: in a folder pattern a
  title's "/", ".." and "~" are made harmless (`~/Shots/${title}` with the title "a/b" now makes one folder `a_b`), and
  a recording folder stays inside its fixed start. File names are cleaned per Unicode character, so a combining or
  invisible character can no longer hide a "/".
- A recipe's file name that comes from a value (a QR code's text, a variable) stays in the output folder; only a
  pattern that itself starts with "/" or "~" names another folder. A pattern that starts with a folder variable such
  as `${MyPictures}` now stays in the output folder too (set the step's folder instead), and a value in a pattern or
  video path that does start with "/" can't climb out of the folder it names. A recipe's recording stays in its
  output directory.
- Links in an external command's output open only when they are http or https. Box and Dropbox links open only on
  box.com and dropbox.com, and the update check opens only this project's GitHub releases page.
- Recipes: saving in the editor after the file was changed outside Greenshot asks about every new command, upload
  target or folder, not only new kinds of permission. The editor opens recipe files with the same 1 MB limit as
  loading them. A recipe whose error handling leads back to itself is refused, and a run stops after 16 error
  handlers or 8 forwards. The approval window says "When anything is copied to the clipboard" for a Clipboard trigger
  that isn't limited to images.
- Greenshot for Windows files (.greenshot, .gst) that reuse one element's data thousands of times can no longer use up
  the memory. Pasted or copied HTML with a huge number of `<img` tags no longer freezes the app. Pictures that claim
  more than 200 megapixels or 32767 pixels a side are refused before they are decoded (opened, pasted, dropped and
  downloaded pictures and the pictures in elements).
- The build's GitHub token can only read the repository.

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
