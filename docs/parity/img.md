# Parity: Image operations and file formats

Upstream Greenshot `0aedcf04` (2026-10-17) compared with greenshot-mac `fddb81b`. Back to the [overview](../feature-parity.md).

Status: ✅ done, 🟡 partial, ❌ missing, 🍎 a Mac equivalent is the way to do it, ➖ not applicable on a Mac, ⚙️ internal. Size of the remaining work: S < 2 h, M ≤ 1 day, L several days, XL a subsystem. The package column says which work package takes the row.


## Effects (whole-image operations)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-001 | Border effect (default 2 px, black; the canvas grows by the width) | 🟡 partial | S | C6 | Greenshot.Base/Effects/BorderEffect.cs:47 Width=2, Color=Black; ImageHelper.cs:840 | GreenshotCore/ImageEffects.swift:74 `border` (fixed 2 pt black, scale-aware). Missing: width and colour are fixed (no way to change them, same as upstream's editor button, but upstream's recipe step has Width/Color). | CoreGraphics context |
| IMG-002 | Drop shadow effect (darkness 0.6, size 7, offset -1,-1) | ✅ done | - |  | Effects/DropShadowEffect.cs:55; ImageHelper.cs:641; EditorConfiguration DropShadowEffectSettings | GreenshotCore/ImageEffects.swift:92 `dropShadow`; settings GreenshotCore/SettingsTypes.swift:96 | CGContext shadow; grows the canvas so a large offset does not clip (deliberate difference) |
| IMG-003 | Drop shadow settings dialog: thickness 1-20 px, offset X and Y -20..20, darkness 1-40; OK/Cancel; right-click on the button opens it, left-click applies the stored settings | ✅ done | - | A4 | Greenshot.Editor/Views/DropShadowSettingsWindow.xaml:156,172,180,194; ImageEditorForm.cs:2322 | wave 1: done | Mac always shows the dialog (no "apply last settings without dialog" path) |
| IMG-004 | Torn edge effect on the pixels: tooth height, horizontal/vertical tooth range, 4 edges, shadow, background colour, seed | ✅ done | - |  | Effects/TornEdgeEffect.cs:82; ImageHelper.cs:338 | GreenshotCore/ImageEffects.swift:118,144 `tornEdge`; SettingsTypes.swift:114 | Seeded RNG (SplitMix64) |
| IMG-005 | Torn edge settings dialog: Top/Left/Right/Bottom + "All" checkbox, tooth size 0-40, horizontal/vertical range 0-40, background colour button, "Generate shadow" with its own thickness/offset/darkness sliders (enabled only when checked) | ✅ done | - |  | Views/TornEdgeSettingsWindow.xaml:190-340 | GreenshotMac/Editor/EffectSettingsWindow.swift:137-258 (all controls, plus a "Transparent" reset button) |  |
| IMG-006 | Torn edges as an editable ELEMENT (TornEdgeContainer): added to the surface, can be moved/resized/changed later, "New random edge" (reseed), "Apply to the image" button, Ctrl+T shortcut | ❌ missing | L | B4 | Greenshot.Editor/Drawing/TornEdgeContainer.cs (518 lines); Surface.AddTornEdges (Surface.cs); ImageEditorForm.cs:2384,2125 BtnApplyToImageClick; commit 9f6726c0; lang `apply_to_image`, `cut_mark_reseed` | Mac applies torn edges destructively to the base image (EditorWindowController+Image.swift:53,`applyWithSettings`); AnnotationKind has no tornEdge (GreenshotCore/Annotation.swift:12-17). Only cut marks are elements. No "apply to image" for cut marks either (grep: none). | New AnnotationKind `.tornEdge` rendering with the existing tornEdgeImage + shadow, plus the cut-mark apply-to-image path (ImageOperations.cutOut already bakes cuts) |
| IMG-007 | Grayscale | ✅ done | - |  | Effects/GrayscaleEffect.cs:33; ImageHelper.cs:949 | GreenshotCore/ImageEffects.swift:54 |  |
| IMG-008 | Invert (negative; alpha kept) | ✅ done | - |  | Effects/InvertEffect.cs:33; ImageHelper.cs:711 | GreenshotCore/ImageEffects.swift:61 |  |
| IMG-009 | Adjust effect: brightness, contrast, gamma | ✅ done | - |  | Effects/AdjustEffect.cs:49; ImageHelper.cs:885,930; (no editor menu item upstream, only Brightness filter + recipe step) | GreenshotCore/ImageEffects.swift:214; dialog EffectSettingsWindow.swift:260-280; menu MainMenu+Image.swift:21 | Mac exceeds upstream (upstream exposes it only in recipes) |
| IMG-010 | Monochrome effect (threshold 0-255) | ✅ done | S | A4 | Effects/MonochromeEffect.cs:46; ImageHelper.cs:809; used by print and recipes | wave 1: done | Wire into recipe/print if those exist |
| IMG-011 | Reduce colors effect (Wu quantizer, N colours) | ✅ done | - | A4 | Effects/ReduceColorsEffect.cs:49; QuantizerHelper.cs | wave 1: done |  |
| IMG-012 | Resize effect | ✅ done | - |  | Effects/ResizeEffect.cs:49; ImageHelper.cs:1242,1258 | GreenshotCore/ImageOperations.swift:14,175 (elements keep position/scale) |  |
| IMG-013 | Resize dialog: width/height text boxes with unit combo (Pixels / Percent), "Maintain aspect ratio" | ✅ done | - |  | Views/ResizeSettingsWindow.xaml:284-300; .xaml.cs:39-70; keys resize_* | GreenshotMac/Editor/ResizeWindow.swift:9-113 |  |
| IMG-014 | Resize canvas effect (left/right/top/bottom + background colour; empty = default for format) | ✅ done | - | A4 | Effects/ResizeCanvasEffect.cs:53; ImageHelper.cs:1220 | wave 1: done |  |
| IMG-015 | Enlarge canvas by 25 px (FEATURE-919) | ✅ done | - |  | ImageEditorForm.cs:2290 | ImageOperations.swift:210; MainMenu+Image.swift:36 |  |
| IMG-016 | Shrink canvas (auto-crop of the border) | ✅ done | - | A4 | ImageEditorForm.cs:2300 | wave 1: done |  |
| IMG-017 | Rotate 90 clockwise / counter-clockwise (elements rotate along) | ✅ done | - |  | Effects/RotateEffect.cs:46 (only 90 / -90 / 270) | ImageOperations.swift:24,189 |  |
| IMG-018 | Remove transparency with a chosen colour (colour dialog, default white) | ✅ done | S | A4 | Effects/RemoveTransparencyEffect.cs:45; ImageEditorForm.cs:2415 | wave 1: done | Add NSColorPanel/colour well sheet |
| IMG-019 | Clear image (make transparent, Ctrl+Delete) | ✅ done | - |  | ImageEditorForm.cs:2395 | ImageOperations.swift:54,225; EditorWindowController+Image.swift:125 |  |
| IMG-020 | Effects pipeline for output (effects list applied when exporting, SurfaceOutputSettings.Effects), recipe "Image Effect" step: Border, DropShadow, TornEdge, Invert, Grayscale, Monochrome, Adjust, Rotate, Resize (px or percent), ResizeCanvas (margin or l/r/t/b), ReduceColors, RemoveTransparency with their parameters | ❌ missing | XL (recipes) | C6 | Greenshot.Base/Core/ImageIO.cs:187-210; Greenshot/Recipes/Steps/EffectCaptureStep.cs:42-71 | Mac has no recipe/output-effects pipeline (no Effect list in ImageExporter.swift). Recipes are probably another slice (REC); here only the effect primitives exist (see IMG-001..018). | Needs a recipe engine first |
| IMG-021 | Effects menu keyboard shortcuts (Ctrl+B border, "/" shadow, Ctrl+T torn, Ctrl+G grayscale, Ctrl+I invert) | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:1385 etc. | Mac remaps to Ctrl+Cmd+B/S/T/G/I (EditorWindowController+Image.swift:272 keyEquivalent) | deliberate |

## Crop and auto crop

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-030 | Crop tool (C) | ✅ done | - |  | ImageEditorForm.cs:1048; CropContainer.cs | GreenshotMac/Editor/CanvasView.swift (`tool == .crop`, `cropRect`) |  |
| IMG-031 | Crop mode "Auto crop" (also in crop-mode buttons; C again cycles Default, Vertical, Horizontal, Auto) with area limited to a crop selection; status text "Auto crop not possible" and fallback to default mode | ✅ done | S | A2 | ImageEditorForm.cs:2007-2105; Surface.cs:1195 AutoCrop; lang `autocrop`, `autocrop_not_possible`, `cropmode_auto` | wave 1: done | Crop modes are menu items, not mode buttons in the crop bar |
| IMG-032 | AutoCropDifference setting (0-255, default 10) | ✅ done | - |  | ICoreConfiguration.cs:222 | AutoCrop.swift:13; settings.value.autoCropDifference (EditorWindowController+Image.swift:229). Check there is a UI field in Settings (not verified here). |  |
| IMG-033 | Crop mode "Crop out horizontally" (cut rows, join parts) | ✅ done | - |  | CropContainer.CropModes.Horizontal; CutOutHelper.cs; SurfaceCutOutMemento.cs; commit 9f6726c0 | ImageOperations.swift:93,255 `cutOut`; EditorWindowController+Image.swift:241 | Elements survive the cut (placement before/inside/after/across, ImageOperations.swift:126-150) |
| IMG-034 | Crop mode "Crop out vertically" | ✅ done | - |  | same | EditorWindowController+Image.swift:247 |  |
| IMG-035 | Cut edges (CutMark element): styles None (seamless), Straight, Wavy, Zig-zag, Torn; tooth height and tooth range, shadow, fill colour, line colour; "New random edge" | ✅ done | - |  | CutMarkContainer.cs; CutMarkStyle.cs; CutShadow.cs; lang `cut_mark_*` | GreenshotCore/Annotation.swift:43 CutMarkStyle; CanvasView.swift:493 New Random Edges; Annotation.swift:206 |  |
| IMG-036 | Cut edge settings dialog + "Apply to the image" (bake cut mark/torn edge into the pixels) | ❌ missing | M | B4 | ImageEditorForm.cs:2125; lang `cut_mark_settings`, `apply_to_image` | No "apply to image" action found in GreenshotMac (grep "applyToImage"/"Apply to the image": none). Cut edge style/teeth edited in the property bar only. | Render element into base image |
| IMG-037 | Crop window size follows DPI ("DPI window size") | ➖ not applicable | - |  | commit 9f6726c0 | Windows DPI handling |  |

## Text redaction (Obfuscate text, OCR based)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-040 | Edit > Obfuscate/Redact Text... opens the dialog; OCR runs first with a wait cursor; messages "no capture", "OCR provider not available", "OCR failed: ...", "no text found" | ✅ done | - |  | ImageEditorForm.cs:2148-2220; TEXT_OBFUSCATION_FEATURE.md; keys `obfuscate_text_*` | EditorWindowController+Image.swift:158 (Vision OCR, TextRecognition.swift); TextObfuscationWindow.swift:244-265 | Windows OCR -> Vision, present |
| IMG-041 | Search field, Regex checkbox, Case sensitive checkbox, search scope Words/Lines | ✅ done | - |  | TextObfuscationWindow.xaml:325-342 | TextObfuscationWindow.swift:26-27,50,140-142 (empty search means all text, extra) |  |
| IMG-042 | Search button, Auto Search (live), live match count "Matches found: N" and yellow preview boxes before applying | ✅ done | M | A4 | TextObfuscationWindow.xaml:326,346; .xaml.cs:85,239-252 UpdatePreview; TEXT_OBFUSCATION_FEATURE.md "Preview" | wave 1: done | Run OCR when the sheet opens, draw boxes on the canvas |
| IMG-043 | Effect choice: Pixelate, Blur, Highlight (colour picker), Magnify; remembers TextObfuscationEffect | ✅ done | - |  | .xaml:361-423; .xaml.cs:107-154; config `TextObfuscationEffect` | TextObfuscationWindow.swift:52,60,79,118; SettingsTypes.swift:186-202 |  |
| IMG-044 | Pixel size 1-50, blur radius 1-30, magnification 1-10 | ✅ done | - |  | .xaml:374,390,422 | TextObfuscationWindow.swift:60 and SliderField rows 144-147 |  |
| IMG-045 | Advanced: horizontal/vertical padding -50..100 %, horizontal/vertical offset -100..100 px | ✅ done | - |  | .xaml:451-480 | TextObfuscationWindow.swift:61-64,160-163 |  |
| IMG-046 | Result: element per match (obfuscate container) so it stays editable | ✅ done | - |  | TextObfuscationWindow.xaml.cs:424 | EditorWindowController+Image.swift:167 `TextObfuscation.annotations` |  |
| IMG-047 | Recipe "Text Effect" step: OCR + patterns + Pixelize/Blur/Highlight/Redact/Magnify | ❌ missing | L | C6 | Greenshot/Recipes/Steps/TextEffectStep.cs:48 | No recipe engine on Mac | (REC slice) |

## Filters used by obfuscate/highlight (behaviour)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-050 | Pixelate that cannot be reversed: secret (AES-CBC) noise per block, stable for repaint/export (1aa2febb) | ✅ done | M | A4 | Drawing/Filters/PixelizationFilter.cs | wave 1: done | Custom block average with per-block random noise seeded once per element |
| IMG-051 | Faster box blur (f2e2a885) | ➖ not applicable | - |  | ImageHelper.cs:459 ApplyBoxBlur | Mac uses `CIGaussianBlur` (AnnotationRenderer.swift:481); performance only |  |
| IMG-052 | Inverted filters (obfuscate/highlight "invert" of selection) drawn once for multiple areas (4b3d9dee) | 🍎 Mac equivalent | - |  | DrawableContainerList.cs; AbstractFilter.cs | EDT slice; behaviour/perf. Check "Shift-area invert"-style option in EDT. |  |

## Opening files / reading formats

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-060 | Open PNG, JPG/JPEG, BMP, GIF, TIFF (.tif/.tiff) | ✅ done | - |  | Editor/FileFormatHandlers/DefaultFileFormatHandler.cs:41; ImageSharpFileFormatHandler.cs:50-52; commit 1079f7ad (TIFF via WIC) | GreenshotMac/Output/Clipboard.swift:51 ImageLoader.load via ImageIO; open panel `.image` EditorManager.swift:74; drops AppDelegate.swift:71 | ImageIO handles all |
| IMG-061 | Open WebP, TGA, PBM | ✅ done | S | A4 | ImageSharpFileFormatHandler.cs:52,64-66 | wave 1: done |  |
| IMG-062 | Open ICO (all sizes) | ✅ done | - | A4 | IconFileFormatHandler.cs:41,142 | wave 1: done |  |
| IMG-063 | Open WMF/EMF metafiles (vector, scalable as element) | ➖ not applicable | - |  | MetaFileFormatHandler.cs:39; Drawing/MetafileContainer.cs | Windows-only formats; no macOS decoder. Skip (or convert externally). |  |
| IMG-064 | Open SVG (rasterised; as SvgContainer element when inserted) | ❌ missing | M | B11 | SvgFileFormatHandler.cs:42,65; Drawing/SvgContainer.cs | `CGImageSource` cannot decode SVG; EditorManager open panel allows public.image (SVG conforms) but load fails. | NSImage(contentsOf:) with an SVG rep (macOS 14+) rasterised at a chosen scale; vector element optional |
| IMG-065 | Open DIB/Format17 (clipboard DIB, .dib file) | 🍎 Mac equivalent | - |  | DibFileFormatHandler.cs:47 | No DIB on macOS clipboard; PNG/TIFF paste covered by Clipboard.image (Clipboard.swift:48) |  |
| IMG-066 | Open JXR/HDP/WDP/WMP/DDS (WPF decoders) and any WIC codec | 🍎 Mac equivalent | - |  | WpfFileFormatHandler.cs:45 | ImageIO covers HEIC/JPEG-XL/AVIF/RAW natively on macOS (bonus), not JXR |  |
| IMG-067 | EXIF orientation applied when reading files/clipboard (`ProcessEXIFOrientation`, default true) | ✅ done | S | A4 | ICoreConfiguration.cs:388; ImageHelper.cs:63 Orientate | wave 1: done | Use kCGImageSourceCreateThumbnailWithTransform or read kCGImagePropertyOrientation |
| IMG-068 | Open a `.greenshot` file (PNG + serialized elements) as editable document | ❌ missing | L | B5 | GreenshotFileFormatHandler.cs:77,86-125; ImageIO.cs:281,610 | Not registered (Info.plist has only public.image, Resources/Info.plist:46-60). A `.greenshot` file is a valid PNG prefix, so the BACKGROUND IMAGE could be opened as a plain PNG (S) if the extension is whitelisted; elements are not loaded. | See Big subsystems |
| IMG-069 | File type registration / "Open with Greenshot" for images, .greenshot association | ✅ done | S | A4 | installer (NA); Info.plist | wave 1: done | add exported UTI `io.github.greenshot.greenshot` if .greenshot support is built |
| IMG-070 | Image from clipboard on open: formats PNG, DIBv5, JPEG, JFIF, TIFF, GIF, DIB, file drop, HTML with img (downloaded) | ✅ done | S | A4 | Core/ClipboardHelper.cs:56-104,809 | wave 1: done |  |
| IMG-071 | Editor opens the capture / "Add capture to open editor" destination, reuse editor, match size | ✅ done | S | A3 | Editor/Destinations/EditorDestination.cs:62-150; config ReuseEditor | wave 1: done |  |

## Saving / export formats and options

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| IMG-080 | Save PNG, JPG, BMP, GIF, TIFF | ✅ done | - |  | CoreFileFormats.cs:36-43; DefaultFileFormatHandler.cs:52 | GreenshotCore/ImageExporter.swift:10-50,64 |  |
| IMG-081 | Save WebP (quality = JPEG quality), TGA, PBM | ✅ done | M | A4 | ImageSharpFileFormatHandler.cs:64-66,101-110 | wave 1: done | WebP needs libwebp (SPM dependency) or skip; TGA trivial uncompressed writer |
| IMG-082 | Save ICO (multi-size icon from image) | ✅ done | M | A4 | IconFileFormatHandler.cs:52-140 | wave 1: done | Write ICO container with PNG entries (S-M) |
| IMG-083 | Save JXR | ➖ not applicable | - |  | WpfFileFormatHandler.cs:46 | Windows-only (WIC JPEG XR encoder) |  |
| IMG-084 | Save .greenshot (PNG + elements + footer) from editor/Save As/file destination (5172972a); "Save background only" | ❌ missing | L | B5 | GreenshotFileFormatHandler.cs:49-75; ImageIO.cs:159-170,307; commit 5172972a | Mac Save and Save As always flatten (EditorWindowController.swift:664,679) into ImageFormat; elements can only be saved to a separate JSON `.greenshot-elements` file (EditorWindowController.swift:706; ElementTransfer.swift:12) | See Big subsystems |
| IMG-085 | Saveable formats registry / unsupported-format failure surfaced to user (b73acc3f) | ✅ done | S | A4 | Core/FileFormat/FileFormatRegistry.cs; ImageIO.cs:128-135; ImageIOSaveToStreamTests | wave 1: done | Check ext vs. popup; warn |
| IMG-086 | Save As dialog format filter list built from the registry; preselect default format | ✅ done | - |  | Core/FileFormat; Controls/SaveImageFileDialog.cs:83-120 | ImageSaver.swift:55-82 FormatAccessory popup + allowedContentTypes |  |
| IMG-087 | Output file format setting (default PNG) | ✅ done | - |  | ICoreConfiguration.cs:132 OutputFileFormat | OutputTab.swift:50-54 Picker |  |
| IMG-088 | JPEG quality (default 80) | ✅ done | - |  | ICoreConfiguration.cs:156 OutputFileJpegQuality | OutputTab.swift:55-59 (slider 10-100; upstream 0-100) |  |
| IMG-089 | Ask for quality before saving ("Show quality dialog every time"), with "Reduce colours" checkbox in the dialog and "Don't ask again" | ✅ done | S | A5 | ICoreConfiguration.cs:160; Greenshot.Base/Wpf/Views/QualityWindow.cs:35-114; lang qualitydialog_* | wave 1: done |  |
| IMG-090 | Reduce colours to 256 on save (`OutputFileReduceColors`), target count `OutputFileReduceColorsTo` | ✅ done | M | A4 | ICoreConfiguration.cs:136,144; ImageIO.cs:213-250 | wave 1: done | Write palette PNG via ImageIO indexed CGImage |
| IMG-091 | Force colour reduction for GIF (GIF always quantised) | ✅ done | - | A4 | SurfaceOutputSettings.cs:84-92 | wave 1: done |  |
| IMG-092 | Auto reduce colours (`OutputFileAutoReduceColors`: count colours, 8-bit if < 256) | ✅ done | S | A4 | ICoreConfiguration.cs:140; ImageIO.cs:213-233; lang expert_autoreducecolors | wave 1: done |  |
| IMG-093 | Overwrite behaviour: `OutputFileAllowOverwrite` true = overwrite, false = show Save-As | ✅ done | - |  | ICoreConfiguration.cs:124 | OutputTab.swift:37; ImageSaver.swift:35 (Mac adds " (2)" suffix instead of a Save-As dialog) | Documented deviation |
| IMG-094 | Copy file path to clipboard after save (`OutputFileCopyPathToClipboard`) | ✅ done | - | A5 | ICoreConfiguration.cs:148 | wave 1: done |  |
| IMG-095 | Output file path, filename pattern, `OutputFileIncrementingNumber` | ✅ done | - |  | ICoreConfiguration.cs:120,128,164 | OutputTab.swift:20-34; Settings.swift:123 | (DST owns) |
| IMG-096 | Optimise PNG with an external command (`OptimizePNGCommand` + arguments {0}), also on upload | ➖ not applicable | M | A4 | ICoreConfiguration.cs:369,373 | upstream removed the code that ran OptimizePNGCommand (60956771) | Run configured command on temp file; fits ExternalCommandRunner.swift |
| IMG-097 | Greenshot "Software" tag in output (PNG tEXt Software, EXIF Software, JPEG tag) | ✅ done | S | A4 | ImageSharpFileFormatHandler.cs:84-95; ImageIO.cs:260 AddTag | wave 1: done | Add kCGImagePropertyPNGSoftware / TIFF Software dict |
| IMG-098 | Resolution written (DPI) | ✅ done | - |  | ImageIO/ImageHelper | ImageExporter.swift:77 (72 x scale) |  |
| IMG-099 | Images with alpha saved as JPEG/BMP get a flat background (JPEG: 24bpp) | ✅ done | - |  | DefaultFileFormatHandler.cs:86 | ImageExporter.swift:63 white background for non-alpha formats | Upstream's BMP keeps 32-bit alpha |
| IMG-100 | Saving file: creates directories, safe filename, refuses overwrite if disabled | ✅ done | - |  | ImageIO.cs:307-345 | ImageExporter.swift:94 createDirectory |  |
| IMG-101 | Non-seekable stream save | ➖ not applicable | - |  | ImageIO.cs:112 | .NET stream detail |  |
| IMG-102 | Upload format + JPEG quality + reduce colours per upload plugin (Box, Dropbox, Jira, Confluence, ...) | ✅ done | S | A4 | Plugin*/I*Configuration.cs `UploadFormat`, `UploadJpegQuality`, `UploadReduceColors`; commit 41642b95 | wave 1: done |  |
| IMG-103 | Clipboard copy formats setting (PNG, HTML, HTMLDATAURL, DIB, BITMAP) and DIBv5 with alpha | ✅ done | S | A4 | ICoreConfiguration.cs:76; ClipboardHelper.cs:420-470 | wave 1: done |  |
| IMG-104 | Save as PDF | 🍎 Mac equivalent | - |  | Plugin / destination | Mac has PdfDestination.swift (DST) |  |
| IMG-105 | EncodingCache for repeated exports (SurfaceExportSource) | ⚙️ internal | - |  | Core/Export/SurfaceExportSource.cs:226 | perf only |  |
| IMG-106 | Pipeline to export: DestinationExporter / ExportFiles / ExportResultHandler (clears modified flag, keeps capture) | 🍎 Mac equivalent | - |  | Core/Export/*.cs | Mac OutputManager.swift (DST) |  |
| IMG-107 | Editor destination: save modified editors to temp `.greenshot` when Windows shuts down | 🍎 Mac equivalent | M | B13 | docs/changelogs/CHANGELOG-1.4.md:62 | macOS app termination: no session-restore of unsaved editors found (grep "NSSupportsSuddenTermination"/restoration none). Could use NSDocument-like autosave of .greenshot. | Depends on IMG-084 |
