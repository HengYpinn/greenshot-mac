# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
