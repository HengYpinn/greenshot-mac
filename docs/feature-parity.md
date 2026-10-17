# Feature parity with Greenshot for Windows

This is the checklist for bringing everything Greenshot for Windows does to this Mac port. It compares upstream [greenshot/greenshot](https://github.com/greenshot/greenshot) at commit `0aedcf04` (2026-10-17) with this repository at `fddb81b`, and is updated as the work packages land (last: wave 4: recipes in the app, recipe editor and manager, MCP server for AI tools, browser extension). To update it against a newer upstream, start from `git log 0aedcf04..HEAD` upstream.

## How it was made

- Seven inventories, one per area (capture, editor, image operations and formats, destinations and plugins, app shell and settings, recipes, automation), each read the upstream code and docs and looked for the same thing in this port. A row is only ✅ when it names the Swift file and line that does it.
- Five completeness checks then walked every upstream UI string (873), every setting (206), every control in the settings window and the other 48 windows, every tray-menu item, every editor menu and toolbar item (176), both changelogs, the docs and all 381 commits since 2024, and tied each one to a row or to a reason (label, error text, dead code). Nothing is left unexplained.
- Two of the checks re-read 295 of the 298 ✅ rows in the Swift code: 15 were downgraded to 🟡, and 1 🟡 turned out to be done already.

## Summary

| Area | ✅ | 🟡 | ❌ | 🍎 | ➖ | ➕ | Rows |
|---|---|---|---|---|---|---|---|
| [Capture](parity/cap.md) | 114 | 1 | 0 | 2 | 10 | 0 | 127 |
| [Editor](parity/edt.md) | 141 | 2 | 0 | 13 | 10 | 0 | 168 |
| [Image operations and file formats](parity/img.md) | 67 | 0 | 0 | 6 | 6 | 0 | 80 |
| [Destinations and plugins](parity/dst.md) | 122 | 2 | 0 | 12 | 12 | 0 | 148 |
| [App shell, settings, notifications](parity/app.md) | 134 | 2 | 9 | 11 | 27 | 0 | 185 |
| [Automation (command line, URL scheme, MCP, browser extension)](parity/aut.md) | 68 | 0 | 0 | 0 | 6 | 0 | 74 |
| [Recipes](parity/rcp.md) | 192 | 4 | 0 | 0 | 7 | 0 | 203 |
| Found by the checks | 7 | 0 | 0 | 0 | 0 | 0 | 7 |
| **All** | **845** | **11** | **9** | **44** | **78** | **0** | **992** |

➕ marks Mac-only additions with no upstream counterpart (AppleScript, Shortcuts, the Services menu, extra `greenshotmac://` actions).

## Work packages

Every 🟡 and ❌ row, and the 🍎 and ➕ rows that still need Mac work, belong to one package. Estimates are rough person-days for the Mac work. In total: A about 23-29 days, B about 42-60, C about 66-100 (plus 25-40 for a drag-to-connect recipe graph), so all of it is roughly 130-190 person-days of work.

### A. Smaller gaps in what the port already has

| Package | Open | Rows | Estimate (days) |
|---|---|---|---|
| [A1. Capture screen and hotkeys polish](#a1) | ✅ | 29 | 4-5 |
| [A2. Editor canvas: elements, styles, selection, paste and drop](#a2) | 1 | 47 | 5-6 |
| [A3. Editor window: toolbar, status bar, zoom, colour dialog, add to editor](#a3) | ✅ | 16 | 3-4 |
| [A4. Image operations, file formats and output options](#a4) | ✅ | 36 | 4-5 |
| [A5. Destinations, picker, saving and upload polish](#a5) | 1 | 39 | 4-5 |
| [A6. Menu bar icon, app shell and settings polish](#a6) | 1 | 27 | 3-4 |

### B. Medium features with a clear Mac design

| Package | Open | Rows | Estimate (days) |
|---|---|---|---|
| [B1. Native notifications: thumbnail, buttons, one summary per capture](#b1) | ✅ | 14 | 4-5 |
| [B2. Diagnostics: logging, log viewer, Self-Service, bug report, setup checks](#b2) | ✅ | 18 | 5-6 |
| [B3. Welcome wizard, tips and About](#b3) | ✅ | 5 | 2 |
| [B4. Torn edges and cut marks as editable elements with Apply to image](#b4) | ✅ | 4 | 3-4 |
| [B5. .greenshot files: open upstream files, save editable documents](#b5) | ✅ | 4 | 5-8 |
| [B6. QR code and barcode generator (editable element)](#b6) | ✅ | 4 | 4-5 |
| [B7. Office and Mail via AppleScript (Word, Excel, PowerPoint, Outlook, Mail, Notes)](#b7) | 1 | 12 | 4-6 |
| [B8. Jira/Confluence Server and Data Center, TLS exceptions, Confluence browsing](#b8) | ✅ | 7 | 3 |
| [B9. Window mode: inner windows and areas via Accessibility](#b9) | ✅ | 3 | 3-5 |
| [B10. HDR / wide-colour capture](#b10) | ✅ | 1 | 1-2 |
| [B11. Mouse pointer and SVG as editable elements](#b11) | 1 | 4 | 2-3 |
| [B12. Admin policy via managed preferences (locked settings, hidden items)](#b12) | ✅ | 5 | 3-4 |
| [B13. Restore open editors after quit, log out or crash](#b13) | ✅ | 5 | 2-3 |

### C. Large subsystems

| Package | Open | Rows | Estimate (days) |
|---|---|---|---|
| [C1. Translations: localisation plumbing + upstream language packs](#c1) | 10 | 10 | 7-10 (+ review by native speakers) |
| [C2. Automation: greenshotmac:// actions, command line tool, AppleScript, Shortcuts, Services](#c2) | ✅ | 39 | 6-8 |
| [C3. MCP server for AI tools (capture, list windows, consent)](#c3) | ✅ | 18 | 4-6 |
| [C4. Browser extension (Chrome/Edge/Firefox, then Safari)](#c4) | ✅ | 9 | 4-6 |
| [C5. Video recording (screen, window, region to MP4)](#c5) | 1 | 22 | 5 reduced / 10 full |
| [C6. Recipes: engine, triggers, steps, approval (MVP)](#c6) | 4 | 156 | 15-20 |
| [C7. Recipes: editor, manager, options, extensions](#c7) | ✅ | 72 | 25-40 (list editor); node graph +25-40 |

### D. Optional

| Package | Open | Rows | Estimate (days) |
|---|---|---|---|
| [D1. Left/right ⌘⌥⌃⇧ in hotkeys (needs the Input Monitoring permission)](#d1) | ✅ | 1 | 3-4 |

## Package contents

<a id="a1"></a>
### A1. Capture screen and hotkeys polish

- `APP-076` ✅ Hotkeys that are key sequences (chords, e.g. "Ctrl+K then P") for recipes
- `APP-118` ✅ Custom camera sound file (`NotificationSound` = path of a .wav, default embedded camera sound)
- `CAP-005` ✅ Capture last region hotkey: same area again without the capture screen (default Shift+PrintScreen)
- `CAP-010` ✅ Capture a given file ("capture" from a file path: CaptureFile)
- `CAP-013` ✅ Built-in "OCR text to clipboard" recipe starts the capture screen in text mode and copies only the text (own hotkey/menu entry)
- `CAP-017` ✅ Camera sound after a capture; custom wav (NotificationSound)
- `CAP-032` ✅ Hotkey validation: a trigger key is required, Esc/Enter/Tab/CapsLock reserved, non-function keys need a modifier, Shift alone not allowed with letters/digits
- `CAP-033` ✅ Multi-chord hotkey sequences (e.g. "Ctrl+K, C"), 2.5 s chord timeout
- `CAP-035` ✅ Standalone keys as hotkeys (PrintScreen, ScrollLock, Pause, F1-F24 without modifier)
- `CAP-038` ➖ "Register Hotkeys" on/off setting ("registerhotkeys", tooltip: reserve Prnt/Ctrl+Print/Alt+Prnt at startup)
- `CAP-053` ✅ Selection frame with width/height rulers (width above, height left) and the size in the middle as large as fits
- `CAP-054` ✅ Crosshair: two dotted lines across the whole screen at the mouse with the position next to it, region and text modes, hidden while dragging
- `CAP-055` ✅ Region size is exactly the capture: the pixel under the mouse belongs to it (corner pixel inclusive)
- `CAP-063` ✅ Keys that work while another window has taken focus: moving the mouse restores key input
- `CAP-065` ✅ Selection animates (slides) from window to window; selection rectangle animation
- `CAP-066` ✅ Panels slide to their new corner (0.35 s) and fade in/out; panel only grows while shown
- `CAP-071` ✅ Window mode: selection follows the window under the mouse, click or Enter captures it; only the visible part (cut at screen edges)
- `CAP-076` ✅ Window capture contains only the window (not what covers it); minimised window restored first
- `CAP-085` ✅ Fixed size: snaps edges to the window under the mouse, the windows around it and the monitor (a few px); hold Alt places freely
- `CAP-091` 🍎 Text mode result as text to clipboard via Windows OCR destination; also copy only the text
- `CAP-093` ✅ "Text recognition: Always run OCR on every capture" (AlwaysRunOCROnCapture)
- `CAP-101` ✅ Zoomer shows the selection edges (so you see whether a pixel is in or out)
- `CAP-102` ✅ Zoomer size = one fifth of the smaller side of the monitor
- `CAP-103` ✅ ZoomerOpacity setting (0..1, ini only)
- `CAP-110` ✅ Panel placement: always in a corner of the monitor with the mouse, farthest free corner, moves only if mouse is close, overlaps another panel, or covers >25 % of the selection (selection counts after 0.3 s stable)
- `CAP-130` ✅ ScreenCaptureMode: Auto (monitor with mouse) / FullScreen / Fixed + ScreenToCapture
- `DST-065` ✅ Always run OCR on every capture so text lines show as hotspots in the capture window
- `R2-004` ✅ Hotkey editor dialog ("Configure Hotkey: <action>"): Ctrl/Alt/Shift/Win checkboxes, a capture field ("Click here to focus and press shortcut keys"), a live "Preview:", "+ Add Step" to build a key sequence (each step removable with an X), inline validation error, Clear / Reset (back to a single chord), Save / Apply, Cancel. The settings row shows a read-only hotkey chip with an "Edit" button (tooltip "Change Hotkey") that opens this dialog; admin-locked hotkeys are disabled
- `R3-003` ✅ Capture screen keeps working after another window took the keyboard focus (Alt+Tab, a message box of another program): the screen stays on top and the next mouse move gives the keys back

<a id="a2"></a>
### A2. Editor canvas: elements, styles, selection, paste and drop

47 rows; see the area files. By section: 1. Drawing element types (containers) (8); 2. Fields (14); 3. Adorners, selection, arrange, clipboard, drag/drop (15); 4. Undo (3); 7. Colour picker (1); 8. Keyboard shortcut groups (editor) (2); 9. Editor configuration properties (IEditorConfiguration.cs) (2); Crop and auto crop (1); New rows (1).

<a id="a3"></a>
### A3. Editor window: toolbar, status bar, zoom, colour dialog, add to editor

- `DST-011` ✅ After every export the editor status bar / notification says "Exported to: <target>" (or "Error while exporting to <target>: ...")
- `DST-014` ✅ Exported file / URL is remembered on the surface (`LastSaveFullPath`, `UploadUrl`), clears the "modified" flag after a save
- `DST-039` ✅ Editor "Copy path to clipboard" for the saved file
- `EDT-121` ✅ Window placement remembered (position/size/maximized) and reset if off-screen; MatchSizeToCapture
- `EDT-123` ✅ Default editor size when opened without capture (500x500)
- `EDT-132` ✅ Destination toolbar buttons (save, copy to clipboard, print + dynamic destination split buttons with drop-downs, icon-only)
- `EDT-141` ✅ Zoom drop-down button in status bar ("100%")
- `EDT-142` ✅ Ctrl+mouse wheel zooms (100 ms throttle); step through fixed zoom values
- `EDT-143` ✅ Zoom keeps selection/centre in view
- `EDT-145` ✅ Status bar message after save/export ("Image saved to {0}", time stamp, error in red with warning sign)
- `EDT-146` ✅ Status bar context menu after save: Copy path to clipboard, Open directory in Explorer
- `EDT-149` ✅ Toolbar: Print, Delete, Cut, Copy, Paste, Undo, Redo, Settings, Help buttons
- `EDT-183` ✅ HTML hex entry and R/G/B/Alpha numeric boxes, "Transparent" button, Apply/Cancel
- `EDT-203` ✅ Window placement (Flags, ShowCommand, Min/Max/Normal position)
- `EDT-208` ✅ DefaultEditorSize
- `IMG-071` ✅ Editor opens the capture / "Add capture to open editor" destination, reuse editor, match size

<a id="a4"></a>
### A4. Image operations, file formats and output options

- `APP-099` ✅ Expert: auto reduce colours when image has fewer than 256 colours
- `DST-034` ✅ Reduce colours to N (default 256) and auto-reduce when fewer than 256 colours are used
- `DST-048` ✅ Open image from clipboard: images in many formats, copied files (CF_HDROP), virtual files (Outlook attachments), HTML `<img>` URLs downloaded, Greenshot objects (drawables)
- `DST-087` ✅ Jira upload "Reduce colors" setting
- `DST-101` ✅ Confluence settings: URL, session timeout, upload format, JPEG quality, reduce colours
- `DST-110` ✅ Box/Dropbox/Confluence/Jira: upload format and JPEG quality; reduce colours (Confluence/Jira)
- `DST-115` ✅ PDF as a normal file format (primary output format, Save As filter)
- `EDT-160` ✅ Effects drop-down: Border, Drop shadow, Torn edge, Grayscale, Invert, Remove transparency (only when image has alpha), Redact text (beta)
- `EDT-161` ✅ Drop shadow: click applies stored settings, right-click opens settings dialog
- `EDT-162` ✅ Torn edges: click applies, right-click settings
- `EDT-163` ✅ Resize (Z key, toolbar): resize dialog
- `EDT-168` ✅ Remove transparency with colour dialog
- `EDT-184` ✅ Colour picker used by Remove-transparency and other colour needs
- `IMG-003` ✅ Drop shadow settings dialog: thickness 1-20 px, offset X and Y -20..20, darkness 1-40; OK/Cancel; right-click on the button opens it, left-click applies the stored settings
- `IMG-010` ✅ Monochrome effect (threshold 0-255)
- `IMG-011` ✅ Reduce colors effect (Wu quantizer, N colours)
- `IMG-014` ✅ Resize canvas effect (left/right/top/bottom + background colour; empty = default for format)
- `IMG-016` ✅ Shrink canvas (auto-crop of the border)
- `IMG-018` ✅ Remove transparency with a chosen colour (colour dialog, default white)
- `IMG-042` ✅ Search button, Auto Search (live), live match count "Matches found: N" and yellow preview boxes before applying
- `IMG-050` ✅ Pixelate that cannot be reversed: secret (AES-CBC) noise per block, stable for repaint/export (1aa2febb)
- `IMG-061` ✅ Open WebP, TGA, PBM
- `IMG-062` ✅ Open ICO (all sizes)
- `IMG-067` ✅ EXIF orientation applied when reading files/clipboard (`ProcessEXIFOrientation`, default true)
- `IMG-069` ✅ File type registration / "Open with Greenshot" for images, .greenshot association
- `IMG-070` ✅ Image from clipboard on open: formats PNG, DIBv5, JPEG, JFIF, TIFF, GIF, DIB, file drop, HTML with img (downloaded)
- `IMG-081` ✅ Save WebP (quality = JPEG quality), TGA, PBM
- `IMG-082` ✅ Save ICO (multi-size icon from image)
- `IMG-085` ✅ Saveable formats registry / unsupported-format failure surfaced to user (b73acc3f)
- `IMG-090` ✅ Reduce colours to 256 on save (`OutputFileReduceColors`), target count `OutputFileReduceColorsTo`
- `IMG-091` ✅ Force colour reduction for GIF (GIF always quantised)
- `IMG-092` ✅ Auto reduce colours (`OutputFileAutoReduceColors`: count colours, 8-bit if < 256)
- `IMG-096` ➖ Optimise PNG with an external command (`OptimizePNGCommand` + arguments {0}), also on upload
- `IMG-097` ✅ Greenshot "Software" tag in output (PNG tEXt Software, EXIF Software, JPEG tag)
- `IMG-102` ✅ Upload format + JPEG quality + reduce colours per upload plugin (Box, Dropbox, Jira, Confluence, ...)
- `IMG-103` ✅ Clipboard copy formats setting (PNG, HTML, HTMLDATAURL, DIB, BITMAP) and DIBv5 with alpha

<a id="a5"></a>
### A5. Destinations, picker, saving and upload polish

- `APP-212` ✅ Output tab: Copy file path to clipboard every time an image is saved
- `DST-004` ✅ Picker re-shows after the picked export failed or was cancelled, until one succeeds or the user closes it
- `DST-005` ✅ Picker lists only destinations that are available (Jira/Confluence only with a configured URL, Email only with a MAPI client, QR only when codes were found, excluded ones hidden)
- `DST-006` ✅ Picker items sorted by priority then name; each destination has an icon and a shortcut hint ("Ctrl+S", "Ctrl+Shift+C")
- `DST-007` ✅ Dynamic sub-destinations in the picker/File menu (printers, open Word documents, open editors, recent Jira issues, open Confluence pages, external commands) loaded in the background with a "..." placeholder
- `DST-012` ✅ Long uploads show a progress dialog with a Cancel button, only after 300 ms (no flicker for quick ones)
- `DST-016` ✅ "Add to editor - <title>" sub-destinations: place the capture as an image element in an already open editor
- `DST-019` ✅ Output folder setting with a folder browser; pattern variables also work in the folder (`FillVariables` on `OutputFilePath`)
- `DST-021` ✅ File name pattern setting with a help window listing every variable
- `DST-024` ✅ Pattern variables from capture metadata: `${windowtitle}`, `${url}`, `${browser}` (browser extension), `${source}`, capture method
- `DST-026` 🍎 Overwrite setting: when the generated file exists, upstream shows a Save-As dialog; allowed overwrite replaces it
- `DST-027` ✅ When saving fails (no write access, bad path) upstream tells the user and falls back to Save As
- `DST-028` 🍎 Invalid filename pattern: error text, opens Settings so the user can fix it, retries
- `DST-029` ✅ Save of an already saved capture / opened file overwrites that file in place (uses `captureDetails.Filename`)
- `DST-030` ✅ Copy file path to clipboard after saving (`OutputFileCopyPathToClipboard`)
- `DST-031` ✅ Save As dialog starts in the folder of the last Save As (`OutputFileAsFullpath`), else the output folder
- `DST-033` ✅ Quality dialog also has a "Reduce colors" checkbox that is saved with "Don't ask again"
- `DST-037` ✅ Temporary named files cleaned up (share files, Excel tmp)
- `DST-038` ✅ Open the folder of the last saved file in the file manager ("Open directory in Explorer", tray "Open last capture in explorer")
- `DST-057` ✅ Print footer with date/time and title, footer pattern, uses UI language for dates (#820)
- `DST-059` ✅ One print destination per installed printer (default printer first); prints straight to that printer without a dialog
- `DST-060` ✅ Notification after printing ("Print job was sent to '{0}'")
- `DST-066` ➖ Window-title fixes: regex per browser to strip " - Mozilla Firefox" / " - Google Chrome" from the title used in file names (`ActiveTitleFixes`, `TitleFixMatcher`, `TitleFixReplacer`; ini only)
- `DST-069` ✅ Duplicate command names rejected with a tooltip
- `DST-071` ✅ Per-command output image format (png, jpg, ... c3198f43)
- `DST-075` ✅ Environment/pattern variables in the command line and arguments (`${...}`, `%windir%`)
- `DST-076` ✅ Command works on the capture's saved file when it has one (`captureDetails.Filename`), else a temp file
- `DST-079` ✅ Built-in default commands: MS Paint, Paint.NET (not recreated once deleted: `DeletedBuildInCommands`)
- `DST-080` ✅ Invalid commands (program no longer exists) removed from the configuration at startup
- `DST-081` ✅ Icon of the command's program shown in menus (`IconCache`, also for UWP/Store apps via `WindowsAppHelper`)
- `DST-088` 🟡 Recent Jira issues offered as destinations: the app watches window titles for issue keys (`ABC-123`) and lists issues the user recently looked at
- `DST-089` ✅ Issue list from a Jira favourite filter (dropdown), sortable columns: type icon, key, created, assignee, reporter, summary
- `DST-090` ✅ Issue-type icons and the server favicon on Jira destinations
- `DST-095` ✅ Page chooser tab "Search pages" (title text, optional space)
- `DST-105` ✅ Dynamic "Upload to Confluence: <open page title>" entries in the picker
- `EDT-133` ✅ "Add to editor" dynamic destination: add this capture as image to another open editor; editor-with-title drop-down
- `IMG-089` ✅ Ask for quality before saving ("Show quality dialog every time"), with "Reduce colours" checkbox in the dialog and "Don't ask again"
- `IMG-094` ✅ Copy file path to clipboard after save (`OutputFileCopyPathToClipboard`)
- `R3-001` ✅ Save As with a filename pattern that expands to a sub-folder (e.g. `${YYYY}-${MM}-${DD}/${NUM} - ${title}`): the dialog opens inside that sub-folder, which is created on the fly and removed again when the dialog is cancelled and the folder is still empty

<a id="a6"></a>
### A6. Menu bar icon, app shell and settings polish

- `APP-002` ✅ Menu: Capture last region, hotkey shown, item greyed out while no region was captured yet
- `APP-004` ✅ Menu: Capture full screen; with several displays a submenu "all" + one entry per display, named with its position (top/bottom/left/right)
- `APP-006` ✅ Window list titles cut to `MaxMenuItemLength` (default 25) so the menu does not get too wide
- `APP-007` ✅ Hover over a window-list entry shows a live thumbnail of that window beside the menu (`ThumnailPreview`, default on)
- `APP-010` ✅ Menu: Open last capture location (opens the last saved file in the file manager; falls back to the output folder when the file is gone)
- `APP-019` 🟡 Menu: Help (opens the offline help file in the UI language)
- `APP-031` ✅ Left click on the tray icon runs `LeftClickAction` (default show menu); choices: open last in explorer, open last in editor, open settings, show menu, capture clipboard, open clipboard in editor, open file in editor, capture region, capture screen, capture window, open empty editor, do nothing
- `APP-032` ✅ Double click on the tray icon runs `DoubleClickAction` (default open last capture in explorer); the single click is then delayed by the system double-click time
- `APP-033` ✅ Click action: Open empty editor (a blank image to draw on)
- `APP-034` ✅ `HideTrayicon` (ini `DisableTrayicon`): run without a tray icon
- `APP-046` ✅ Update check at startup after 20 s and then every `UpdateCheckInterval` days while running (re-checked every 30 min when not due)
- `APP-062` ✅ Open Settings on a given tab or plugin (`SelectTab("general"/"capture"/.../"expert"/plugin name)`), from `greenshot://settings?tab=` and the "More..." quick-setting
- `APP-071` ✅ Theme drop-down: same as Windows / Light / Dark, applied immediately
- `APP-101` ✅ Expert: window thumbnails in context menu
- `APP-102` ✅ Expert: check for unstable updates
- `APP-105` ✅ Expert: `${NUM}` counter - editable number
- `APP-119` ✅ Notification when the OS has notifications off: nothing shown, no capture kept
- `APP-120` ✅ About window: product name + version + bitness, GPL text with link, hosted-by-GitHub, bug-report and donate links (carry `?version=`), Fugue icon credits, translation credits, PORTABLE/BETA badges, animated logo, Self-Service button, keys S/E/L/I/T
- `APP-152` ✅ Beta/unstable update notices (`CheckForUnstable`, `LatestBetaVersion`)
- `APP-186` ✅ `UpdateCheckInterval` `LastUpdateCheck` `CheckForUnstable`
- `APP-188` ✅ `ThumnailPreview`
- `APP-190` ✅ `LeftClickAction` `DoubleClickAction`
- `APP-192` ✅ `MaxMenuItemLength`
- `APP-194` ✅ `Theme`
- `AUT-002` ✅ `--ini-directory <dir>`: read/write greenshot.ini from another folder (portable/side-by-side config)
- `CAP-008` ✅ Tray "Capture full screen" submenu with all monitors or one monitor (upstream labels all/left/right/top/bottom by position)
- `CAP-041` ✅ Tray icon left-click / double-click action (LeftClickAction)

<a id="b1"></a>
### B1. Native notifications: thumbnail, buttons, one summary per capture

- `APP-035` ✅ Balloon notification API: title, text, level icon (info/warning/error), click and closed callbacks, hide
- `APP-084` ✅ "Show a thumbnail of the capture in the notification" (only offered where the service can show captures)
- `APP-110` ✅ Native OS notifications with fallback to a simple balloon (provider list by priority; toast registration with app id and icon; disabled-by-user/policy detection)
- `APP-111` ✅ Thumbnail (364x180) of the capture inside the notification, switchable with `ShowNotificationThumbnail`
- `APP-112` ✅ One notification per capture summarising every export ("Exported to: Clipboard"), title = captured window title, one row per destination with its icon, error/warning kind
- `APP-113` ✅ Notification buttons: Edit (open kept capture in editor), Show in folder (saved file), Copy link (upload link; drop-down to choose when several links)
- `APP-114` ✅ Click a notification to re-offer the capture (destination flyout), also after Greenshot was closed; capture kept as `.greenshot` + thumbnail and cleaned up after 1 h / on click / at startup
- `APP-115` ✅ A failed export names which destination failed and why; failed flow lists successes and the failure
- `APP-116` ✅ Error/warning icon on the notification (and per-destination icons)
- `APP-117` ✅ QR/barcode rows in the notification ("QR code: ..."), up to 3; http(s) links shown fully with IDN host as punycode and copyable, other text shortened and not a link
- `APP-184` ✅ `PlayCameraSound` `ShowTrayNotification` `NotificationLevel` `ShowNotificationThumbnail` `NotificationSound`
- `APP-200` ✅ "Better notifications" (#1516): one notification with preview and destinations, click to send elsewhere even after Greenshot closed, buttons Edit / folder / copy link, failed-export detail, QR codes, appears once in notification settings, level choice + preview choice
- `CAP-136` ✅ Notification after a capture (tray balloon/toast, thumbnail, click to send elsewhere, QR link copy)
- `DST-139` ✅ Notification thumbnail of the capture

<a id="b2"></a>
### B2. Diagnostics: logging, log viewer, Self-Service, bug report, setup checks

- `APP-052` ✅ Unhandled exception -> bug report window (see APP-126)
- `APP-126` ✅ Bug report window on an unhandled exception: type, message, expandable stack trace, hash `[XXXXXXXX]`, "Search GitHub for this error", "Report issue" with the hash, copy details/stack trace, outdated-version warning with upgrade button, Self-Service link; shown on a separate STA thread when the process is dying
- `APP-130` ✅ Setup checks with one-click fixes (version up to date; tray icon visible; Print key not taken by Snipping Tool / OneDrive); same lines in Welcome step 3 and Self-Service "Your setup"
- `APP-131` ✅ Self-Service window shell: sidebar of diagnostic categories (System, Setup, Files, Clipboard, Hotkeys, Integrity, Imgur when keys exist, DEBUG: Integration), keys 1-5/E/F/L/I/C/H/K/V/T/F5/Esc, theme toggle, minimize/maximize, opened from About, bug report, `greenshot://self-service?section=`
- `APP-132` ✅ Self-Service > System & Hardware: OS, display scaling, process/GC/physical memory, runtime, uptime, screens layout; "Copy System Info"
- `APP-133` ✅ Diagnostic report text (version+edition, OS, hardware, settings dump without secrets) used by Copy System Info and bug reports
- `APP-134` ✅ Self-Service > Files: config file path with exists/not-found, Copy Path, open; log file path; quick-glance + "Open Log Viewer"
- `APP-135` ✅ Self-Service > Clipboard diagnostics: live list of clipboard formats, which process locks/owns the clipboard, monitor loop (600 ms), test now
- `APP-136` ✅ Self-Service > Hotkeys & conflicts: status of each configured hotkey (registered / conflict / disabled), re-register, detect OneDrive, Windows 11 Snipping Tool, Dropbox, ShareX, Snagit, Lightshot, PicPick
- `APP-137` ✅ Self-Service > Installation integrity: verify files against `checksum.SHA256` (filters, search, copy report)
- `APP-140` ✅ Log file `greenshot.log` (rolls over at 1 MB) with an entry layout that indents continuation lines; log4net config variants (debug/release/portable/zip)
- `APP-141` ✅ Log sanitising: control and bidi/invisible characters escaped as `\uXXXX`, entries over 64 KB cut with a note
- `APP-142` ✅ Log viewer window: tail of the log (64 KB chunks), Load Earlier (+64 KB), Load Entire Log, Wrap text, Copy Log, Refresh (F5), live-appended new entries while open (250 ms), status/empty/error lines, keys Esc/F5/Ctrl+F/T
- `APP-143` ✅ Log search: shows only entries (not lines) containing the text, ignoring case, from the whole log; exception lines stay with their entry; "N of M log entries contain ..."; 300 ms debounce
- `APP-144` ✅ Log level drop-down (Error/Warn/Info/Debug) changes how much is written until restart; the change itself is logged first
- `APP-145` ✅ `greenshot://log?search=<text>` opens the log viewer filtered (max 200 chars, only filters, never changes level; link from web pages allowed, `greenshot://exit` refused)
- `APP-201` ✅ "Log viewer in Self-Service": read/copy the log, search, live entries, log level, `greenshot://log?search=`
- `CAP-040` ✅ Self-service "Hotkeys and conflicts" page: status per hotkey (registered/failed/disabled), re-register button, detect OneDrive / Windows Snipping Tool / Dropbox / ShareX / Snagit grabbing PrintScreen, one-click disable

<a id="b3"></a>
### B3. Welcome wizard, tips and About

- `APP-045` ✅ Start: welcome window when `WelcomeShown` is false (see APP-125)
- `APP-125` ✅ Welcome window wizard shown once: (1) welcome, (2) basics with the user's four hotkeys, (3) setup checks with fix buttons, (5) done + settings button + random tip with "Another tip"; Back/Next/"Let's go!", dots, Esc; re-open by pipe `FIRST_LAUNCH`
- `APP-127` ✅ Tips: 10 tips + one about notifications, random start, "Another tip"
- `APP-183` ✅ `WelcomeShown`
- `APP-208` ✅ Welcome window (9794710c), per-user autostart (a4996c33), theme following (878a3c2c), memory dial (377dcfa6), Greenshot Light (fac2f115), WPF tray menu (0a728ffa), OCR language setting (2869a69a) - landed after the changelog was last updated (2026-03-14), so they are not in it

<a id="b4"></a>
### B4. Torn edges and cut marks as editable elements with Apply to image

- `EDT-024` ✅ Cut mark: "Apply to the image" button and context item
- `EDT-025` ✅ Torn edge as an editable element (TornEdgeContainer), selectable, re-seed, settings, apply to image; commit 9f6726c0
- `IMG-006` ✅ Torn edges as an editable ELEMENT (TornEdgeContainer): added to the surface, can be moved/resized/changed later, "New random edge" (reseed), "Apply to the image" button, Ctrl+T shortcut
- `IMG-036` ✅ Cut edge settings dialog + "Apply to the image" (bake cut mark/torn edge into the pixels)

<a id="b5"></a>
### B5. .greenshot files: open upstream files, save editable documents

- `EDT-012` ✅ Step label start value (counter start) setting in toolbar; stored in .greenshot file; commit ca4af519 translation
- `EDT-034` ✅ Unknown/foreign containers on load: backwards-compatible deserialization of old .greenshot elements (BinaryFormatter)
- `IMG-068` ✅ Open a `.greenshot` file (PNG + serialized elements) as editable document
- `IMG-084` ✅ Save .greenshot (PNG + elements + footer) from editor/Save As/file destination (5172972a); "Save background only"

<a id="b6"></a>
### B6. QR code and barcode generator (editable element)

- `DST-133` ✅ Insert a generated QR code / barcode into the editor ("Insert QR / Barcode..."): QR, Aztec, DataMatrix, PDF417, Code128/39/93, EAN-8/13, UPC-A/E, Codabar, ITF, MSI, Plessey
- `DST-134` ✅ QR payload wizard: Text/URL, WiFi (SSID, password, encryption), vCard, EPC payment (IBAN/BIC/amount), e-mail, calendar event, phone, SMS, geo
- `DST-135` ✅ QR look: foreground/background colour, rounded dots, margin, live preview, Insert/Cancel
- `DST-136` ✅ Generated code stays editable as an element (`BarcodeContainer`, model in `Tag`; re-edit)

<a id="b7"></a>
### B7. Office and Mail via AppleScript (Word, Excel, PowerPoint, Outlook, Mail, Notes)

- `DST-050` ✅ E-Mail destination: new message with the screenshot attached, subject = capture title, To/CC/BCC from settings
- `DST-051` ✅ E-Mail settings: To, CC, BCC
- `DST-097` ✅ Page chooser tab "Open pages": pages currently open in a browser, found from window titles/URLs
- `DST-121` ✅ Word: insert into a new document, or into any open document (sub-destinations, picker asks new vs open when auto-exporting)
- `DST-122` ✅ Word: lock aspect ratio of the image
- `DST-123` ✅ Excel: insert into a new workbook or an open one
- `DST-124` ✅ PowerPoint: new presentation or open presentation, one slide per capture, picture centred, title as slide text
- `DST-125` ✅ PowerPoint settings: lock aspect ratio; slide layout (`PowerpointSlideLayout`, default picture with caption, falls back to blank)
- `DST-126` ✅ Outlook: new e-mail with the image inline (HTML) or attached (text), subject pattern, default To/CC/BCC
- `DST-127` 🟡 Outlook: insert into an open message/inspector window (and meeting items when allowed)
- `DST-128` ✅ OneNote: new page in the default notebook, or an existing page (dynamic list of notebooks/sections/pages)
- `DST-130` ✅ Office settings window (Outlook format, subject, To/CC/BCC, allow meetings, Word/PowerPoint options)

<a id="b8"></a>
### B8. Jira/Confluence Server and Data Center, TLS exceptions, Confluence browsing

- `APP-197` ✅ `AllowedUntrustedCertificateHosts` `AllowedCertificateThumbprints`
- `DST-091` ✅ Jira Server / Data Center support (default URL `https://jira`, user + password login dialog, `login_error`)
- `DST-096` ✅ Page chooser tab "Browse pages": tree of spaces and their pages
- `DST-098` ✅ Include personal spaces in search and browsing
- `DST-103` ✅ Confluence Server / Data Center and `/rest/api` v1 content calls
- `DST-142` ✅ TLS certificate validation re-enabled; per-host exceptions for self-signed servers (`AllowedUntrustedCertificateHosts`, wildcards such as `*.mycompany.local`)
- `DST-143` ✅ Trust specific certificates by thumbprint (`AllowedCertificateThumbprints`, SHA-1/SHA-256, colon/space tolerant)

<a id="b9"></a>
### B9. Window mode: inner windows and areas via Accessibility

- `CAP-072` ✅ Window mode selects the innermost window (child windows, e.g. a panel or toolbar inside a program); move to outer edge for the whole window
- `CAP-073` ✅ Window mode (beta): UI Automation "areas" inside windows (menu, sidebar, part of a web page), smallest area under the mouse, areas under 64 px skipped; PgUp/PgDn larger/smaller area; spinner while the areas are read (>200 ms)
- `CAP-106` ✅ Keys panel lists PgUp/PgDn area keys in window mode (beta)

<a id="b10"></a>
### B10. HDR / wide-colour capture

- `CAP-120` ✅ HDR screens: bright parts are tone mapped instead of cut off; SDR content keeps its exact colours on HDR screens

<a id="b11"></a>
### B11. Mouse pointer and SVG as editable elements

- `CAP-019` ✅ Mouse cursor is captured as its own object (icon, hotspot, position) and stays an editable/movable/removable element in the editor; CursorVisible flag
- `EDT-027` ✅ Mouse cursor as separate movable element from capture (CursorContainer)
- `EDT-030` 🟡 SVG vector element (drop/paste SVG stays scalable)
- `IMG-064` ✅ Open SVG (rasterised; as SvgContainer element when inserted)

<a id="b12"></a>
### B12. Admin policy via managed preferences (locked settings, hidden items)

- `APP-064` ✅ Controls locked by admin (`greenshot-fixed.ini`) are disabled (`FixedToEnabledConverter`)
- `APP-094` ✅ Admin policy: values locked by `greenshot-fixed.ini` (controls disabled, quick settings hidden), defaults by `greenshot-defaults.ini`; `DisableSettings`, `DisableQuickSettings`, `HideExpertSettings`, `HideTrayicon`
- `APP-187` ✅ `DisableSettings` `DisableQuickSettings` `HideTrayicon` `HideExpertSettings`
- `DST-009` ✅ Hide destinations by configuration (`ExcludeDestinations`) and plugins (`IncludePlugins` / `ExcludePlugins`); admin-only `.ini` values
- `DST-010` ✅ Lock destination settings via `greenshot-fixed.ini` (the Destinations tab checkboxes are disabled when fixed)

<a id="b13"></a>
### B13. Restore open editors after quit, log out or crash

- `APP-048` ✅ Restart Manager: when Windows Update/installer closes Greenshot, open editors are saved to temp `.greenshot` files and reopened after restart (`--restore`)
- `APP-205` ✅ Windows Restart Manager integration (`--restore`)
- `EDT-130` ✅ Save open editors to temp .greenshot files on OS shutdown/restart manager and reopen after restart
- `EDT-135` ✅ Edit > Insert window submenu (live list of windows with icons + thumbnail preview on hover) inserts a window capture as image element
- `IMG-107` ✅ Editor destination: save modified editors to temp `.greenshot` when Windows shuts down

<a id="c1"></a>
### C1. Translations: localisation plumbing + upstream language packs

- `APP-043` ❌ First run: language picker window when `Language` is empty
- `APP-070` ❌ Language drop-down (all installed language packs, "Description=" shown); change applies at once to all windows
- `APP-129` ❌ Language selection window (first start)
- `APP-170` ❌ Localisation infrastructure: UI strings from language files, English fallback per missing key, runtime language switch (live in all windows), language list with `Description=`, `--language` flag (AUT)
- `APP-171` ❌ 40 language packs: ar-SY, ca-CA, cs-CZ, da-DK, de-DE, de-x-franconia, el-GR, en-US (base), es-ES, et-EE, fa-IR, fi-FI, fr-FR, fr-QC, he-IL, hu-HU, id-ID, it-IT, ja-JP, kab-DZ, ko-KR, lt-LT, lv-LV, nl-NL, nn-NO, pl-PL, pt-BR, pt-PT, ro-RO, ru-RU, sk-SK, sl-SI, sr-RS, sv-SE, tr-TR, uk-UA, va-VA, vi-VN, zh-CN, zh-TW
- `APP-172` ❌ Right-to-left languages (ar-SY, fa-IR, he-IL) layout
- `APP-173` ❌ Plugin language files (jira, office, pdf, confluence, externalcommand, dropbox, box) translated per language
- `APP-176` 🟡 Offline help pages in 17 languages (de, en, es, fr, hu, it, ko, nl, nn, pl, pt-BR, pt-PT, ru, sv, tr, va, zh-CN), opened from Help menu by UI language
- `APP-180` ❌ `Language`
- `APP-207` ❌ Translation updates (Turkish, Swedish, Polish, Japanese, Persian) and the translation agent

<a id="c2"></a>
### C2. Automation: greenshotmac:// actions, command line tool, AppleScript, Shortcuts, Services

- `AUT-001` ➖ `--language <code>` startup option: set UI language and save config
- `AUT-003` ➖ `--no-run`: exit immediately without starting or showing Greenshot (used by installer/scripts)
- `AUT-004` ✅ `--restore` (hidden): started by Windows Restart Manager after update/reboot; ends silently if already running
- `AUT-005` ✅ `--autostart`: started at logon; ends silently if another instance runs
- `AUT-006` ➖ `-Embedding` (hidden): added by Windows COM when a toast click starts Greenshot; accepted and ignored
- `AUT-007` ✅ `--help` / `-h` / `-?` print usage and the command syntax (attaches or allocates a console)
- `AUT-008` ✅ Startup command after the options: `Greenshot.exe <file>`, `--file`, `--recipe`, `--reload`, `--exit` are forwarded to the running instance, or Greenshot starts and runs it itself; `--exit`/`--reload` do nothing if not running; invalid command prints an error on the caller's console
- `AUT-009` ✅ Single-instance guard: second start shows "Greenshot is already running" window (InstanceRunningWindow, owned by APP) and exits; arguments are forwarded first (AUT-008)
- `AUT-020` ✅ `greenshot-cli` terminal binary (console subsystem, prints output of the command, exit codes 0/1/2/3, starts Greenshot when not running, UTF-8 output, works with pipes/redirects)
- `AUT-021` ✅ `--help`/`-h` and `--version`/`-v` answered by the CLI itself, work without Greenshot running
- `AUT-028` ✅ `--file` / `-f <file...>` and positional file paths: open one or more files (OpenFile triggers / editor), relative paths resolved against the caller's cwd, extension whitelist, no ADS/control chars/bidi/device names, must exist
- `AUT-029` ✅ `--reload`: reload configuration in the running instance
- `AUT-030` ✅ `--exit`: quit the running instance
- `AUT-031` ✅ `--version` against the running Greenshot (VERSION IPC command returns the product version)
- `AUT-032` ✅ Exit codes of the CLI (0 ok, 1 failure, 2 invalid command line, 3 Greenshot not available, or the recipe's Stderr-step code) and stderr/stdout streaming frames (O/E/X)
- `AUT-033` ✅ `greenshot:` URL given as the only argument is executed like a URL-scheme link
- `AUT-040` ✅ Local IPC server in the running app: named pipe `Greenshot_IPC`, length-prefixed JSON frames, HELLO handshake with source/reply_format/client/version, replacing the old WM_COPYDATA (c602070c)
- `AUT-041` ✅ Per-source command whitelists: `cli` (everything), `url_scheme` (CLI, URL_SCHEME, RUN_RECIPE, SETTINGS, ABOUT, SELF_SERVICE, LOG_VIEWER, RECIPE_EDITOR, RECIPE_MANAGER), `open_with` (CLI, OPEN_FILE), `native_messaging` (HANDSHAKE, IMPORT_CAPTURE, TAB_CHANGED, VERSION, LIST/DESCRIBE/RUN_RECIPE), `mcp`; source bound by HELLO and overwritten on every envelope
- `AUT-042` ✅ Client verification: only Greenshot.exe, greenshot-cli, greenshot-proxy, greenshot-mcp from Greenshot's own directory may connect (process path of pipe client); pipe refuses network logons
- `AUT-043` ✅ Path hardening for IPC file arguments: control chars, null bytes, bidi override, alternate data streams, reserved device names, UNC, canonicalization, extension whitelist
- `AUT-044` ✅ Cold start: if Greenshot is not running the proxy/CLI starts it (global mutex against start storms, 10 s timeout, 250 ms pipe polling)
- `AUT-045` ✅ IPC notifications/events: server pushes events to watch connections (`{"event":"tools_changed"}`, `shutdown` with reason exit/update/session_end) without waiting for the client to read (out buffer, 2 min reply write timeout) (9bba94ef)
- `AUT-046` ✅ Reply protocol: JSON for json sources; text frames O/E/X for terminal; one final reply per request even on handler failure
- `AUT-047` ➖ Plugin seam `IIpcCommandExtension` / `GreenshotModule`: optional parts (browser extension, AI tools) add commands, source whitelists, access checks (also 6aa9af56 plugin seams for capture tools)
- `AUT-048` ✅ `greenshot-proxy` native bridge (GUI subsystem: no console flash) used as native-messaging host, URL protocol handler and Explorer "Open with" target
- `AUT-050` ✅ URL protocol registered (`greenshot:` and `greenshot://`), opaque and hierarchical forms both accepted; web pages can open it, so a whitelist applies
- `AUT-051` ✅ `greenshot://settings[?tab=general\|capture\|output\|destination\|editor\|printer\|plugins\|recipes\|expert][&plugin=<Name>]` opens Settings at a tab / plugin
- `AUT-052` ✅ `greenshot://about` opens About
- `AUT-053` ✅ `greenshot://self-service[?section=system\|setup\|files\|clipboard\|hotkeys\|checksum\|imgur\|debug_integration]` opens Diagnostics & Self-Service
- `AUT-054` ✅ `greenshot://log[?search=<text>]` opens log viewer filtered by search text (max 200 chars; never changes log level) - new in 0aedcf04
- `AUT-055` ✅ `greenshot://recipe-editor[?recipe=<id>]` and `greenshot://recipe-manager`
- `AUT-057` ✅ Mac-only URL actions worth adding (no upstream row): `greenshotmac://capture/region\|window\|fullscreen\|last`, `greenshotmac://open?file=` (must NOT be allowed from a URL, upstream forbids file opening from web pages), `greenshotmac://clipboard`
- `AUT-060` ✅ "Open with Greenshot" for images (ProgID Greenshot.Image for png/jpg/bmp/gif/tif/webp/ico/svg/jxr/emf/wmf/tga) and Greenshot as default app for `.greenshot`
- `AUT-088` ➖ Greenshot Light / edition gating of AI tools and extension (GreenshotModule)
- `AUT-090` ✅ Installer registers `greenshot:` URL protocol, native messaging host manifests (Chrome/Edge/Firefox), Open-with ProgIDs, RegisteredApplications (`includes\url-protocol.iss`, `browser-extension.iss`); self-service debug page registers for current user
- `AUT-091` ➖ Windows toast activation COM class (ToastActivator)
- `AUT-100` ✅ AppleScript dictionary (`.sdef`) so `tell application "GreenshotMac" to capture region` works, replacing COM/`greenshot-cli` scripting on Windows
- `AUT-101` ✅ Shortcuts / Siri / Spotlight actions via App Intents (capture region/window/full screen, open file)
- `AUT-102` ✅ NSServices (Services menu: "Open in Greenshot" for images/files)

<a id="c3"></a>
### C3. MCP server for AI tools (capture, list windows, consent)

- `APP-096` ✅ AI tools tab (beta testers): allow AI tools, allowed programs, denied list, recipe proposals, excluded apps, notify on capture, MCP download hint
- `AUT-070` ✅ `greenshot-mcp` stdio MCP server executable ("greenshot", Native AOT, starts Greenshot if needed, reconnects, watch connection) separate download next to Greenshot.exe
- `AUT-071` ✅ MCP tool `list_windows`: top-level windows in Z-order with id, title, process, class, bounds, minimized, active, plus displays; ids expire after 10 min and are per AI tool and MCP session
- `AUT-072` ✅ MCP tool `capture_window` (by id, exact content even when covered, without activating, `ocr=true`)
- `AUT-073` ✅ MCP tool `capture_region` (x,y,width,height screen coords, optional OCR)
- `AUT-074` ✅ MCP tool `capture_screen` (all displays, optional OCR)
- `AUT-075` ✅ Image result limits: scaled to 1568 px on the longest side (`MaxImageSize`, 0 = original); OCR returns text and position of each line
- `AUT-079` ✅ AI tools opt-in switch "Let AI tools use Greenshot" (`AiToolsEnabled`, default off; every request refused without asking while off; only version check answers; lockable in greenshot-fixed.ini)
- `AUT-080` ✅ `AiToolsAllowRecipeProposals` (default on) switch: "Let AI tools propose recipes"
- `AUT-081` ✅ Per-program consent: first request shows a question with program name, path and signer; stored in `AiToolsAllowedClients`; the dialog stays on top without keyboard focus, no default button, ignores Escape, buttons react after 1 s; "No" remembered until restart; helper programs shown under their app's name
- `AUT-082` ✅ mcp-server identity check: pipe client must be `greenshot-mcp.exe` in Greenshot's directory (`AiToolsMcpServerPaths` extra paths for Debug builds)
- `AUT-083` ✅ Excluded applications: `AiToolsExcludedProcesses` (default KeePass, KeePassXC, 1Password, Bitwarden, LastPass, Dashlane, Enpass, RoboForm, NordPass, ProtonPass) never listed/captured, blacked out in every capture taken by an AI recipe; editable list in settings with Add (Enter) and Remove
- `AUT-084` ✅ Notification on every AI capture (`AiToolsNotifyOnCapture`, default on)
- `AUT-085` ✅ Settings tab "AI tools" (shown when beta tester is ticked on Expert tab): Access group with greenshot-mcp present check (found/not found/wrong version, download link), Allowed programs list with remove, "Not allowed until restart" list with Allow / Ask Again, permissions (proposals, notify), excluded apps list, Approved recipes list with Details / Review / Revoke
- `AUT-086` ✅ Documented client connection recipes (Claude Code `claude mcp add`, Claude Desktop JSON, Antigravity, Gemini CLI, VS Code `servers`, Cursor, Windsurf, Codex)
- `AUT-087` ✅ Shutdown semantics for MCP: `exit` keeps greenshot-mcp alive and reconnects later; `update` makes it exit; `session_end`
- `CAP-014` ✅ AI tool captures (greenshot-mcp): AI capture window/region/screen recipes, excluded processes, notify on capture
- `CAP-123` ✅ Capture of protected/DRM windows and apps excluded for AI tools

<a id="c4"></a>
### C4. Browser extension (Chrome/Edge/Firefox, then Safari)

- `AUT-062` ✅ Extension package: MV3 manifest "Greenshot Companion" v1.0.0 (Chrome/Edge service worker + Firefox gecko id `greenshot@getgreenshot.org`, min 121), permissions activeTab/tabs/nativeMessaging/storage, host `<all_urls>`. Files (all, none are C#): manifest.json, background.js (298 lines), popup/popup.html, popup.js, popup.css, options/options.html, options.js, icons/icon-16/32/48/128.png, icons/g.svg
- `AUT-063` ✅ Native messaging connection to host, auto reconnect, HANDSHAKE (extension version) -> Greenshot replies `{status:ready, greenshot_running, greenshot_version, config{capture_format, track_tab_urls, full_page_delay_ms}}`; ON badge when connected
- `AUT-064` ✅ "Capture Visible Page" button: `captureVisibleTab` -> base64 PNG/JPEG + metadata (title, url, timestamp) sent as IMPORT_CAPTURE; Greenshot decodes and runs the built-in "Capture from browser extension" recipe (dynamic destination "Export Browser Capture")
- `AUT-065` ✅ IMPORT_CAPTURE safety limits: only PNG/JPEG by signature, max 32767 px per side and 100 MP checked from the header before decoding, ack `{status, reply_to, width, height}`
- `AUT-066` ✅ QA tab URL tracking: extension reports active tab url/title (TAB_CHANGED) when it changes, ignoring chrome://, edge://, about:, extension pages; Greenshot keeps BrowserContextTracker and exposes `${Browser.Url}`, `${Browser.Domain}`, `${Browser.Title}`, `${Browser.Ticket}` to recipes/filename patterns
- `AUT-067` ✅ Extension origin policy: only official extension IDs and `allowed_origins`/`allowed_extensions` of the host manifests may connect; dev IDs read on each connection
- `AUT-068` ✅ Extension popup UI: Greenshot logo, connection status indicator (Connecting/online/offline), Capture Visible Page button, feedback message, QA URL Tracking badge, Settings link
- `AUT-069` ✅ Extension options page: "QA Tab URL Tracking" switch, "Capture Format" PNG (lossless) / JPEG (compressed), saved indicator; stored in chrome.storage.local; UPDATE_CONFIG/RECONNECT/GET_STATUS runtime messages
- `CAP-011` ✅ Browser-extension capture import (ImportExtensionCapture, extension trigger recipe)

<a id="c5"></a>
### C5. Video recording (screen, window, region to MP4)

- `CAP-200` ✅ Record video via recipe step RecordVideo (experimental); output MP4 path put in the flow (VideoFilePath, VideoRecordingResult with path, duration, size, width, height, fps, format, hasAudio)
- `CAP-201` ✅ Record target: monitor (index), window (active window, by title, title regex, process name, case option, pre-supplied handle), or region (x,y,w,h or pre-supplied)
- `CAP-202` ✅ Delay before recording starts (DelayMs)
- `CAP-203` ✅ Stop conditions: DurationSeconds, record until the window closes (default for window targets without duration), cancel
- `CAP-204` ✅ Container/codec: MP4 with H.264 (AVC) + AAC, or MP4 with H.265 (HEVC) + AAC (VideoFormat Mp4_H264, Mp4_HEVC)
- `CAP-205` ✅ Quality presets: SmallSize (15 fps, 0.8 Mbps, 1280x720), Balanced (30 fps, 2.5 Mbps), HighQuality (60 fps, 8 Mbps), HighFrameRateGaming (144 fps, 25 Mbps), Custom
- `CAP-206` ✅ Frame rate (default 30, any e.g. 15/30/60/144) and bitrate (default auto: max(1.5 Mbps, w*h*fps/20))
- `CAP-207` ✅ Output size: TargetWidth/TargetHeight or ScaleFactor (0..2, e.g. 0.5/0.75), GPU scaling; even dimensions forced for H.264/HEVC
- `CAP-208` ✅ Colour mode FullColor or Grayscale
- `CAP-209` ✅ Record the mouse cursor (CaptureMouseCursor, default true)
- `CAP-210` ➖ Show OS capture border during recording (Windows 11 yellow border, default off)
- `CAP-211` ✅ What happens when the target window is resized: LetterboxFixedCanvas (default, keeps canvas size) or ScaleToFit
- `CAP-212` ✅ Audio: None / system audio (loopback) / microphone / both mixed, AAC 192 kbps, custom audio provider
- `CAP-213` ✅ Pause and resume the recording (API; used for auto-pause)
- `CAP-214` ✅ Prevent system sleep during recording (default on)
- `CAP-215` ✅ Auto-pause when the workstation is locked (default on), resume on unlock; auto-finalise the file before system suspend
- `CAP-216` ✅ Output file: OutputFilePath, OutputDirectory, FilenamePattern (supports %VAR% and {yyyyMMdd_HHmmss}); default Videos\Greenshot\Greenshot_Recording_<timestamp>.mp4; file system access gated by recipe authorisation
- `CAP-217` ✅ Recording events: state changes (Unstarted, Recording, Paused, Finalizing, Stopped, Cancelled, Failed), duration ticks, errors
- `CAP-218` ✅ Hardware-accelerated pipeline: D3D11 staging ring buffer, GPU crop for region/window, Media Foundation transcoder; first-frame wait of 2 s
- `CAP-219` ➖ HDR in video
- `CAP-220` 🟡 Recorded video flows into destinations (Save/Share/Upload)
- `CAP-221` ✅ Permissions needed: Screen Recording (shared), Microphone (only for mic audio)

<a id="c6"></a>
### C6. Recipes: engine, triggers, steps, approval (MVP)

156 rows; see the area files. By section: 1. Tray icon menu (TrayMenu.cs) -> status item menu (2); 4. Settings window - shell (1); 7. Settings window - other tabs (1); greenshot-cli command line (CliCommandParser.cs, main_cli.c) (6); greenshot: URL scheme (1); File association (1); MCP server and AI tools (greenshot-mcp, Greenshot/Ai) (3); Starting a capture (entry points, tray menu, hotkeys) (2); External command plugin (1); QR code (1); Effects (whole-image operations) (2); Text redaction (Obfuscate text, OCR based) (1); A. Core model: recipe file, flow, graph engine (25); B. Expressions, variables, configuration precedence (14); C. Triggers (16); D. Steps (each step type and its options) (58); F. Approval, trust and consent (17); J. Interaction with other slices (4).

<a id="c7"></a>
### C7. Recipes: editor, manager, options, extensions

72 rows; see the area files. By section: E. Recipe options (settings a recipe offers) (8); G. Extensions (automatic steps): slots, composer, built-ins (14); H. Recipe manager (tray menu and window) (16); I. Recipe editor (Recipe Editor plugin, node graph) (31); New rows (3).

<a id="d1"></a>
### D1. Left/right ⌘⌥⌃⇧ in hotkeys (needs the Input Monitoring permission)

- `CAP-034` ✅ Left/right modifier distinction in hotkeys (ModifierLocation Any/Left/Right)

## Not applicable on a Mac

78 rows are Windows-only with no Mac meaning (installer, registry, Active Setup, Restart Manager, DPI manifests, DIB clipboard formats, Windows OCR engine choice, …); each says why in its area file. Upstream also removed some features, which are not to be ported: the Imgur upload plugin (#1529; the Self-Service page that deletes old Imgur uploads is not needed here either), the Flickr, Google Photos/Picasa and Photobucket plugins (#928), Office before 2013 (#1485), Internet Explorer capture, the WM_COPYDATA messages (replaced by named pipes) and the XML language files.

