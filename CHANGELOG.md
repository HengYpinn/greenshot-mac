# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Speech bubble element (S), ported from Greenshot's `SpeechbubbleContainer`: a rounded text box with a tail whose
  tip is a handle; blue outline and bold text on white by default, text edited in place.
- Emoji element (M): placed with a click, resized at its corners, picked from a short list in the top bar or with a
  double-click; the last pick is remembered.
- Effects menu in the editor and an Image menu: torn edges, border, drop shadow, grayscale and invert with
  Greenshot's default settings, applied to the whole screenshot as one undo step.

### Changed

- The 28 pt font size is now 27 pt, the Mac size of the speech bubble's 20 pt on Windows.

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
