# Parity: Editor

Upstream Greenshot `0aedcf04` (2026-10-17) compared with greenshot-mac `fddb81b`. Back to the [overview](../feature-parity.md).

Status: ✅ done, 🟡 partial, ❌ missing, 🍎 a Mac equivalent is the way to do it, ➖ not applicable on a Mac, ⚙️ internal. Size of the remaining work: S < 2 h, M ≤ 1 day, L several days, XL a subsystem. The package column says which work package takes the row.


## 1. Drawing element types (containers)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-001 | Rectangle element (R) with line colour, fill, thickness, shadow | ✅ done | - |  | Drawing/RectangleContainer.cs:63-66; editor_drawrectangle | GreenshotCore/Annotation.swift:11,181; AnnotationRenderer.swift:82 | CGContext drawing |
| EDT-002 | Ellipse element (E) | ✅ done | - |  | Drawing/EllipseContainer.cs:59-62; editor_drawellipse | Annotation.swift:11; AnnotationRenderer.swift:84 |  |
| EDT-003 | Line element (L), 2 move-handles at ends | ✅ done | - |  | Drawing/LineContainer.cs:47-49,59-60 | Annotation.swift:366-368 (start/end handles); AnnotationRenderer.swift:86 |  |
| EDT-004 | Arrow element (A) with arrow heads (none/start/end/both) | ✅ done | - |  | Drawing/ArrowContainer.cs:58-63; commit 3fec76cc | Annotation.swift:58 ArrowHeads; AnnotationRenderer.swift:243 drawArrow |  |
| EDT-005 | Freehand element (F) | ✅ done | - |  | Drawing/FreehandContainer.cs:67-68 | AnnotationRenderer.swift:298 freehandPath; CanvasView.swift:372 | Smoothing distance is hard-coded (see EDT-064) |
| EDT-006 | Text box element (T): in-place edit, border (line thickness), fill, shadow, font family/size/bold/italic, H and V alignment | 🟡 partial | S | A2 | Drawing/TextContainer.cs:100-109 | Annotation.swift:179-190; CanvasView.swift:859 beginEditing; AnnotationRenderer.swift:314. Missing: line thickness (border) not offered for text (EditorWindowController.swift:~175 "Width" group excludes .text); Enter-commits/Shift+Enter newline not handled (CanvasView.swift:922 only Esc) | NSTextView overlay |
| EDT-007 | Text editing keys: Enter commits, Shift+Enter new line, Esc commits, Ctrl+A select all, Ctrl+Backspace delete word | 🟡 partial | S | A2 | Drawing/TextContainer.cs:602-630; FEATURE-1064 | CanvasView.swift:922 handles only Esc (cancelOperation commits). Enter inserts a newline. Ctrl+A and Option+Backspace come from NSTextView natively | Add Return handler in textView(_:doCommandBy:) |
| EDT-008 | Text box auto-grows/FitToText while typing, double-click edits | ✅ done | - |  | Drawing/TextContainer.cs (FitToText, OnDoubleClick) | CanvasView.swift:931 textDidChange grows; :315,:348 double-click/click begins editing |  |
| EDT-009 | Speech bubble element (S) with draggable tail (target adorner), text, fill, line, shadow | ✅ done | - |  | Drawing/SpeechbubbleContainer.cs:79-88; Adorners/TargetAdorner.cs; editor_speechbubble | Annotation.swift:293 speechBubbleTail, :361 Handle.tail; AnnotationRenderer.swift:369; CanvasView.swift:258 drawnTail |  |
| EDT-010 | Step label / counter element (I): numbered circle, auto numbering, white-on-dark-red default | ✅ done | - |  | Drawing/StepLabelContainer.cs:100-107; editor_counter | Annotation.swift:193; AnnotationRenderer.swift:417 drawCounter; EditorDocument.swift:256 counterNumber |  |
| EDT-011 | Step label numbers renumber when labels are deleted/undone; label count shown in toolbar icon (btnStepLabel00..20+) | 🟡 partial | S | A2 | ImageEditorForm.cs:1749-1761; Surface.cs:260 AddStepLabel | Numbering is dynamic (EditorDocument.swift:256). Toolbar icon does not show the count (EditorTool.swift:49 static "1.circle") | cosmetic |
| EDT-012 | Step label start value (counter start) setting in toolbar; stored in .greenshot file; commit ca4af519 translation | ✅ done | - | B5 | ImageEditorForm.Designer.cs:1180-1185 counterUpDown 0..100; Surface.CounterStart; editor_counter_startvalue | EditorWindowController.swift:208-230 counterStartField+stepper (0..9999); EditorDocument.swift:29 counterStart |  |
| EDT-013 | Highlight element (H) with 4 modes: text marker, area, grayscale, magnify | ✅ done | - |  | Drawing/HighlightContainer.cs:48,83-120; Filters/HighlightFilter/BrightnessFilter/BlurFilter/GrayscaleFilter/MagnifierFilter | Annotation.swift:33 HighlightMode; AnnotationRenderer.swift:514-560 | Area dims to 0.7 brightness fixed (see EDT-056) |
| EDT-014 | Obfuscate element (O): pixelate / blur | ✅ done | - |  | Drawing/ObfuscateContainer.cs:45; Filters/PixelizationFilter.cs, BlurFilter.cs | Annotation.swift:38; AnnotationRenderer.swift:502-512 | Core Image pixelate/blur; upstream's "stable pixelation" (60af9a27) not needed |
| EDT-015 | Filter settings (mode) of highlight/obfuscate kept when loading saved elements (commit 6b1ba7c4) | ✅ done | - |  | Drawing/HighlightContainer.cs, ObfuscateContainer.cs | Annotation.swift:94-118 style stored in Codable element; ElementTransfer.swift | Mode is part of the element style, no rebuild step |
| EDT-016 | Crop container (C): drag area, adorners on edges, Confirm/Cancel, Enter/Esc | 🟡 partial | - | A2 | Drawing/CropContainer.cs:121-136 | CanvasView.swift:220 drawCrop, :593 applyCrop, :535 Enter; EditorWindowController.swift:247-252 Crop/Cancel buttons |  |
| EDT-017 | Crop mode: Default crop | ✅ done | - |  | Drawing/CropContainer.cs:76,176; editor_cropmode_default; ImageEditorForm.Designer.cs:1055 | EditorWindowController.swift:247 "Crop" button; EditorDocument.swift:267 crop |  |
| EDT-018 | Crop mode: crop out vertically (cut columns out, join sides) with cut-mark joint; commit 9f6726c0 | ✅ done | - |  | Drawing/CropContainer.cs; Surface.cs:1719 ApplyCutOut; Helpers/CutOutHelper.cs; editor_cropmode_vertical | EditorWindowController+Image.swift:141-145,163-190 cutOutSelectedColumns; Settings.swift:164 cutOutMarkStyle | Offered as Image-menu / pull-down items, not as radio buttons in the crop bar |
| EDT-019 | Crop mode: crop out horizontally (cut rows out) | ✅ done | - |  | same; editor_cropmode_horizontal | EditorWindowController+Image.swift:143,168 cutOutSelectedRows |  |
| EDT-020 | Crop mode: auto crop (button in crop bar + Image) with "Auto crop not possible" message | ✅ done | S |  | Forms/ImageEditorForm.cs:2084-2105 InitCropMode; editor_autocrop, editor_autocrop_not_possible | EditorWindowController+Image.swift:149 autoCrop, ⌥⌘A (MainMenu+Image.swift). Missing: no message when not possible (check :149-160); not a crop-bar button |  |
| EDT-021 | Crop mode toolbar: four mode buttons (default/vertical/horizontal/auto) appear while cropping, active one checked | 🟡 partial | M | A2 | ImageEditorForm.Designer.cs:1050-1085; ImageEditorForm.cs:1700-1710 | Mac crop bar has Crop/Cancel + joint popup only (EditorWindowController.swift:247-256); modes reachable from pull-down/Image menu | Switching mode while a crop area is drawn is not supported |
| EDT-022 | Pressing C while cropping cycles crop modes | ❌ missing | S | A2 | ImageEditorForm.cs:1351-1360, 2015-2031 CycleCropMode | CanvasView.swift:~560 C just selects the tool again |  |
| EDT-023 | Cut-mark element ("Cut edges"): band across the image with None/Line/ZigZag/Wave/Torn edges, tooth height/range, fill, shadow, new random edge, settings, apply to image; commit 9f6726c0 | 🟡 partial | M | A2 | Drawing/CutMarkContainer.cs:105-111,462-502; CutMarkStyle.cs; CutShadow.cs; editor_cut_mark* | GreenshotCore/CutMark.swift; Annotation.swift:43,203; AnnotationRenderer.swift:117; CanvasView.swift:494 "New Random Edges"; EditorWindowController.swift:199-201. Missing: "Cut edge settings…" context item; "Apply to the image" (flatten the element into the bitmap); cut mark is a dedicated tool (K) rather than a by-product of crop-out | upstream has no tool key for it |
| EDT-024 | Cut mark: "Apply to the image" button and context item | ❌ missing | M | B4 | ImageEditorForm.cs:2123-2133 BtnApplyToImageClick; CutMarkContainer.cs:497; editor_apply_to_image; Surface.cs:1851 ApplyElementToImage | no equivalent | bake element into base bitmap with undo |
| EDT-025 | Torn edge as an editable element (TornEdgeContainer), selectable, re-seed, settings, apply to image; commit 9f6726c0 | 🟡 partial | L | B4 | Drawing/TornEdgeContainer.cs:106-112,480-516; ImageEditorForm.cs:2364-2388 AddTornEdges | Mac torn edge is an immediate image effect (EditorWindowController+Image.swift:67 showTornEdgeSettings, ImageEffects.swift). Not an element, cannot be changed or removed later except by undo. Torn style exists on cut marks |  |
| EDT-026 | Image element (pasted/dropped/inserted picture) with shadow option, default-size reset, Shift keeps aspect | ✅ done | - |  | Drawing/ImageContainer.cs:78,200-281; commit a2efe6d9 | Annotation.swift:13,471 picture(); AnnotationRenderer.swift:163 drawPicture; Annotation.swift:399 keepAspect; EditorWindowController.swift:~187 shadow group includes .image | Shadow redefinition (a2efe6d9) not compared pixel-wise |
| EDT-027 | Mouse cursor as separate movable element from capture (CursorContainer) | ❌ missing | M | B11 | Drawing/CursorContainer.cs; Surface.cs:963 AddCursorContainer | Capture can include the pointer baked into the pixels (CaptureCoordinator.swift:59 showsCursor); no element | Would need capture to return cursor image + hotspot; element kind `cursor` |
| EDT-028 | Icon element (.ico dropped/pasted, IconContainer) | 🟡 partial | S | A2 | Drawing/IconContainer.cs; Surface.cs:947 AddIconContainer | Dropped image files become image elements (CanvasView.swift:754 performDragOperation). Multi-resolution icon selection not modelled | NSImage/ImageIO decodes .ico; treat as image |
| EDT-029 | Metafile (WMF/EMF) vector container | ➖ not applicable | - |  | Drawing/MetafileContainer.cs; FileFormatHandlers/MetaFileFormatHandler.cs | Windows GDI metafile; no Mac use |  |
| EDT-030 | SVG vector element (drop/paste SVG stays scalable) | ❌ missing | M | B11 | Drawing/SvgContainer.cs; VectorGraphicsContainer.cs; FileFormatHandlers/SvgFileFormatHandler.cs | Dropped SVG would only be rasterised by ImageLoader (CanvasView.swift:741) if at all | NSImage can render SVG on macOS 13+; keep `Data` and re-rasterise on resize |
| EDT-031 | Emoji element (M): placed by click, size 64, picker on double-click, remembers recent emoji | ✅ done | - |  | Drawing/Emoji/EmojiContainer.cs:46-110; Emoji/EmojiRenderer.cs; commits 10aac930, #358 | Annotation.swift:11; AnnotationRenderer.swift:379 drawEmoji; Settings.swift:129 recentEmoji; EditorWindowController.swift:612-636 pickEmoji; CanvasView.swift:628 showEmojiPalette | Uses system Character Viewer + short list instead of Twemoji picker |
| EDT-032 | Emoji picker: grouped tabs, skin-tone variations popup, centred on element, Esc closes (EmojiPicker.xaml) | 🍎 Mac equivalent | - |  | Controls/Emoji/EmojiPicker.xaml:15-136, EmojiPicker.xaml.cs, EmojiData.cs, Emojis.cs | Character Viewer: CanvasView.swift:628; short list EditorTool.swift:112 | System emoji picker has groups, search, skin tones natively |
| EDT-033 | Emoji font bundled (Twemoji) rendered with ImageSharp; toolbar emoji icon rendered async | ➖ not applicable | - |  | Drawing/Emoji/EmojiRenderer.cs; ImageEditorForm.cs:408 AssignEmojiButtonImageAsync | Apple Color Emoji via AppKit |  |
| EDT-034 | Unknown/foreign containers on load: backwards-compatible deserialization of old .greenshot elements (BinaryFormatter) | 🍎 Mac equivalent | - | B5 | Helpers/BinaryFormatterHelper.cs; FileFormatHandlers/GreenshotFileFormatHandler.cs | Mac uses own JSON `.greenshot-elements` (ElementTransfer.swift:16). Reading Windows `.greenshot`/`.gst` files is not possible | Cross-platform file reading belongs to IMG slice |

## 2. Fields / style options (toolbar properties)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-040 | Line colour (button; NumPad0-9 / Shift+0-9 shortcuts) | 🟡 partial | S | A2 | Fields/FieldType.cs LINE_COLOR; Designer btnLineColor; editor_forecolor | EditorWindowController.swift:528 lineColorWell (system NSColorWell). Colour shortcuts missing (EDT-094). NSColorPanel alpha not enabled (no `showsAlpha`, grep empty) so transparency cannot be picked | Set `NSColorPanel.shared.showsAlpha = true` |
| EDT-041 | Fill colour (button; Ctrl+0-9 shortcuts) | 🟡 partial | S | A2 | FILL_COLOR; editor_backcolor | EditorWindowController.swift:529 fillColorWell + "No fill" button :530. Shortcuts missing |  |
| EDT-042 | Line thickness numeric up/down (label editor_thickness) | 🟡 partial | S | A2 | LINE_THICKNESS; Designer lineThicknessUpDown | EditorWindowController.swift:531 popup of fixed values 0,1,2,3,4,5,6,8,10 (:~66). Upstream accepts any integer | NSStepper+field |
| EDT-043 | Shadow toggle ("Drop shadow (/)") | 🟡 partial | S | A2 | SHADOW; shadowButton; Surface.cs:3172 FlipShadow; editor_shadow | EditorWindowController.swift:532 checkbox. Ctrl+/ shortcut missing |  |
| EDT-044 | Font family combo (FontFamilyComboBox, previews fonts, disables bold/italic when style unavailable) | 🟡 partial | S | A2 | Controls/FontFamilyComboBox.cs; ImageEditorForm.cs:1849-1907 FontPropertyChanged | EditorWindowController.swift:202,546 NSPopUpButton of font families + "System Font". No per-family bold/italic availability handling |  |
| EDT-045 | Font size numeric up/down (editor_fontsize) | 🟡 partial | S | A2 | FONT_SIZE; fontSizeUpDown | EditorWindowController.swift:533 popup 9..96 only |  |
| EDT-046 | Bold / Italic toggles | ✅ done | - |  | FONT_BOLD, FONT_ITALIC; editor_bold, editor_italic | EditorWindowController.swift:534-535 |  |
| EDT-047 | Horizontal text alignment dropdown (left/center/right) | ✅ done | - |  | TEXT_HORIZONTAL_ALIGNMENT; editor_align_horizontal, align_left/center/right | EditorWindowController.swift:552 horizontalAlignmentControl |  |
| EDT-048 | Vertical text alignment dropdown (top/middle/bottom) | ✅ done | - |  | TEXT_VERTICAL_ALIGNMENT; editor_align_vertical, align_top/middle/bottom | EditorWindowController.swift:558; CanvasView.swift:963 AlignedTextView |  |
| EDT-049 | Arrow heads dropdown (None/Start/End/Both) with checked state (3fec76cc) | ✅ done | - |  | ARROWHEADS; Designer:1548-1570; editor_arrowheads* | EditorWindowController.swift:192,536 popup |  |
| EDT-050 | Obfuscate mode dropdown (Pixelize/Blur) | ✅ done | - |  | PREPARED_FILTER_OBFUSCATE; editor_obfuscate_mode/pixelize/blur | EditorWindowController.swift:194,538 |  |
| EDT-051 | Pixel size (pixelization) numeric | 🟡 partial | S | A2 | PIXEL_SIZE; editor_pixel_size | EditorWindowController.swift:195,539 shared "effect size" popup (2..24); stored as style.pixelSize (Annotation.swift:107) |  |
| EDT-052 | Blur radius numeric | 🟡 partial | S | A2 | BLUR_RADIUS; editor_blur_radius | same popup, style.blurRadius (Annotation.swift:108) |  |
| EDT-053 | Preview quality (blur preview resolution, 0..100%) | ❌ missing | S | A2 | PREVIEW_QUALITY; Filters/BlurFilter.cs:51; editor_preview_quality | not modelled | Only a performance knob upstream; low value on Mac |
| EDT-054 | Highlight mode dropdown (text/area/grayscale/magnify) | ✅ done | - |  | PREPARED_FILTER_HIGHLIGHT; editor_highlight_mode/text/area/grayscale/magnify | EditorWindowController.swift:193,537 |  |
| EDT-055 | Magnification factor (magnify highlight) | 🟡 partial | - | A2 | MAGNIFICATION_FACTOR; editor_magnification_factor | EditorWindowController.swift:156-160,564 (2x/3x/4x) |  |
| EDT-056 | Brightness (area highlight dimming, percentage) | ❌ missing | S | A2 | BRIGHTNESS; Filters/BrightnessFilter.cs:37; editor_brightness | AnnotationRenderer.swift:~548 area mode uses fixed 0.7 | Add style.brightness |
| EDT-057 | Highlight text-marker colour (fill colour of text highlight) | ✅ done | - |  | Filters/HighlightFilter.cs:41 FILL_COLOR | EditorWindowController.swift:~176 fill well for .highlight |  |
| EDT-058 | Cut edges style dropdown with preview pictures (None, Straight, Zig-zag, Wavy, Torn) | 🟡 partial | S | A2 | CUT_MARK_STYLE; ImageEditorForm.cs:2038 CreateCutMarkPreview; editor_cut_mark* | EditorWindowController.swift:199,579 text popup (no preview images) |  |
| EDT-059 | Tooth height and tooth range numerics | ✅ done | - |  | TOOTH_HEIGHT, TOOTH_RANGE; editor_tornedge_toothsize, editor_cut_mark_tooth_range | EditorWindowController.swift:200-201,594 |  |
| EDT-060 | Confirm / Cancel buttons shown for confirmable elements (crop); the rest of the UI is disabled while pending | 🟡 partial | S | A2 | FieldFlag.CONFIRMABLE; ImageEditorForm.cs:1760-1790, Helpers/ToolStripItemEndisabler.cs; editor_confirm | Crop/Cancel buttons EditorWindowController.swift:247-252. Rest of UI is not disabled while cropping |  |
| EDT-061 | Last-used field values remembered per element type | ✅ done | - |  | IEditorConfiguration.cs:47 LastUsedFieldValues; EditorConfigurationHelper.cs:36 | Settings.swift:127 editorStyles; EditorWindowController.swift:507 applyStyle |  |
| EDT-062 | Properties toolbar shows only fields of selected element(s)/tool; multi-selection edits all (FieldAggregator) | ✅ done | - |  | Fields/FieldAggregator.cs; ImageEditorForm.cs:1678-1732 RefreshFieldControls | EditorWindowController.swift:458 refreshProperties, :507 applyStyle on all selected |  |
| EDT-063 | Binding converters/validators between controls and fields | ⚙️ internal | - |  | Fields/Binding/** | - |  |
| EDT-064 | Freehand smoothing sensitivity setting (1..100, default 3) | 🟡 partial | S | A2 | IEditorConfiguration.cs:80 FreehandSensitivity | CanvasView.swift:372 hard-coded 3 px/2; no setting |  |

## 3. Adorners, selection, arrange, clipboard, drag/drop

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-070 | Resize handles (8 positions) on selected elements | ✅ done | - |  | Drawing/Adorners/ResizeAdorner.cs; Positions.cs; DrawableContainer.cs:393-408 | Annotation.swift:356-440 Handle |  |
| EDT-071 | Move adorners for line/arrow ends; cut-mark/crop edge-only handles | 🟡 partial | - | A2 | Adorners/MoveAdorner.cs; LineContainer.cs:59; CutMarkContainer.cs:90-96 | Annotation.swift:366-375 |  |
| EDT-072 | Rotation of selected elements via handle | ➖ not applicable | - |  | (none upstream: elements only scale/move; image rotate is image-wide) | - | Upstream has no element rotation |
| EDT-073 | Hold Shift while drawing: constrain (square/circle; line angle snap 15 degrees upstream) | 🟡 partial | S | A2 | Helpers/ShapeAngleRoundBehavior.cs, LineAngleRoundBehavior.cs:33 (15 deg step); ScaleHelper.cs:261 | CanvasView.swift:376 snap45 / squareEnd: snaps at 45 degrees not 15 | Geometry.swift:52; change step to 15 deg for lines |
| EDT-074 | Hold Ctrl while drawing/resizing: scale around the centre | ❌ missing | S | A2 | Helpers/ScaleHelper.cs:262 ScaleOptions.Centered | CanvasView.swift:362-410 only Shift handled | Use Option key on Mac |
| EDT-075 | Shift-click toggles element in selection (multi-select) | ✅ done | - |  | Surface.cs:2098 | CanvasView.swift:291 (Shift or Cmd) |  |
| EDT-076 | Rubber-band selection | ✅ done | - |  | (not upstream) | CanvasView.swift:296,169 | Mac extra |
| EDT-077 | Select all (Ctrl+A) | ✅ done | - |  | Surface.cs:3003; Designer selectAll | CanvasView.swift:779; MainMenu+Edit.swift:20 |  |
| EDT-078 | Delete element (Delete key, toolbar, menu) | ✅ done | - |  | Designer:750 | CanvasView.swift:520-523,687; MainMenu+Edit.swift:21 |  |
| EDT-079 | Arrow keys move selection 1 px, Shift 10 px | ✅ done | - |  | Surface.cs:3047-3062 | CanvasView.swift:571 nudge |  |
| EDT-080 | Arrange: Up to top (Home), Up one level (PgUp), Down one level (PgDn), Down to bottom (End), enabled by hierarchy | ✅ done | - |  | DrawableContainerList.cs:685-715; Designer:759-792; ImageEditorForm.cs:1798-1812 | MainMenu+Edit.swift:44-47; CanvasView.swift:546-557; EditorDocument.swift:208-235 | Extra shortcuts ⇧⌘F/B |
| EDT-081 | Duplicate selected element (Ctrl+D, Edit menu, context menu) offset 10,10 | ✅ done | - |  | Surface.cs:2905; DrawableContainerList.cs:721 | CanvasView.swift:769; MainMenu+Edit.swift:19 |  |
| EDT-082 | Copy/Cut/Paste elements via private clipboard format; paste offset logic | ✅ done | - |  | DrawableContainerClipboard.cs; Surface.cs:2732-2815 | CanvasView.swift:693-725; ElementTransfer.swift:64 placed(); Annotation clipboard type "elementsType" |  |
| EDT-083 | Paste an image from clipboard as image element | ✅ done | - |  | Surface.cs:2819-2850 | CanvasView.swift:719 |  |
| EDT-084 | Paste text from clipboard creates a text element | ❌ missing | S | A2 | Surface.cs:2843-2860 | CanvasView.swift:709 only elements and images; otherwise beep | Create .text annotation with default style at paste point |
| EDT-085 | Paste HTML containing an image: download the image URL | ❌ missing | M | A2 | Surface.cs:2832 GetHtmlImageUrls, AddDownloadedOrFallbackAsync | not handled | NSPasteboard .html parse + URLSession |
| EDT-086 | Paste a file list / virtual file (image files copied in Explorer) | 🟡 partial | S | A2 | ClipboardHelper.GetDrawables | Finder-copied image files are not read in paste (CanvasView.swift:709-722 reads image only). Drop of files works | add .fileURL read in paste |
| EDT-087 | Drag-and-drop images onto the canvas (fit to canvas) | ✅ done | - |  | Surface.cs:1040-1120 OnDragEnter/OnDragDrop FitContainer | CanvasView.swift:91,745-768 |  |
| EDT-088 | Dropping a URL/text starting with http downloads the image | ❌ missing | M | A2 | Surface.cs:1101-1112 | registerForDraggedTypes only .fileURL (CanvasView.swift:91) |  |
| EDT-089 | Context menu on element: arrange, duplicate, copy, cut, delete, reset size | 🟡 partial | S | A2 | DrawableContainerList.cs:679-800 | CanvasView.swift:481-515. Has arrange, cut/copy/duplicate/delete, Edit Text, emoji submenu. Missing: Reset size |  |
| EDT-090 | Context menu "Reset size" (images/icons/emoji to default size) | ❌ missing | S | A2 | DrawableContainerList.cs:776-800; editor_resetsize | no HasDefaultSize equivalent |  |
| EDT-091 | Push out submenu (top/right/bottom/left): move element fully outside the canvas and enlarge the canvas to hold it (commit 2ed60294) | ❌ missing | M | A2 | DrawableContainerList.cs:965-1020, PushOut; Surface.cs:1243 ResizeCanvas; editor_pushout, editor_align_* | no equivalent; canvas can only be enlarged via Image > Enlarge Canvas | New context submenu: expand image by element size and snap element to that edge, one undo step |
| EDT-092 | Fit submenu: fit element to image width / height | ❌ missing | S | A2 | DrawableContainerList.cs:1028-1070; editor_fit, editor_resize_width/height |  |  |
| EDT-093 | Snap submenu: dock element to top/right/bottom/left edge | ❌ missing | S | A2 | DrawableContainerList.cs:1077-1130, DrawableContainer.SnapToEdge; editor_snap |  | Menus only visible when language en-US upstream (translation gate) |
| EDT-094 | Colour keyboard shortcuts on selection: Ctrl+0..9 fill (transparent, red, green, blue, cyan, magenta, yellow, black, gray, white), Shift variants set line colour (0=orange) | ❌ missing | S | A2 | Surface.cs:3081-3118, SetSelectedElementColor :3150; editor_forecolor/backcolor text | none (grep for digit key handling in Editor empty) | Cmd+digit is free on Mac; use Ctrl+digit |
| EDT-095 | Ctrl+Num+/- line thickness +1/-1 (Shift: +5/-5) | ❌ missing | S | A2 | Surface.cs:3121-3128, ChangeLineThickness :3165 |  |  |
| EDT-096 | Ctrl+/ toggles shadow on selection | ❌ missing | S | A2 | Surface.cs:3129 FlipShadow |  |  |
| EDT-097 | Esc: deselect crop / confirm false; Enter confirm | ✅ done | - |  | Surface.cs:3075-3079 | CanvasView.swift:526-545 |  |
| EDT-098 | Elements keep inside/along image on operations (move with canvas change, rotate, crop) | ✅ done | - |  | Surface.cs ApplyBitmapEffect/Transform | EditorDocument.swift:290-310 replaceImage transform |  |
| EDT-099 | Cut-out/crop memento keeps elements and offset (SurfaceCutOutMemento) | ✅ done | - |  | Memento/SurfaceCutOutMemento.cs; Surface.cs:1882 | EditorDocument.swift:267-280 crop moves annotations |  |
| EDT-100 | Save elements to file / Load elements from file (Greenshot templates *.gst) | ✅ done | - |  | ImageEditorForm.cs:1939-1969; Surface.cs:775-860; editor_save_objects/load_objects | EditorWindowController.swift:706,723; ElementTransfer.swift:16 | Mac format `.greenshot-elements`, not cross-compatible with `.gst` |

## 4. Undo / redo (Memento)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-110 | Undo / Redo (Edit menu, toolbar buttons) | ✅ done | - |  | Memento/*.cs; Surface.cs:658-700; Designer:603-612 | EditorDocument.swift:86-96; EditorWindowController.swift:646-647; MainMenu+Edit.swift:11-13 | Snapshot-based (State) instead of mementos |
| EDT-111 | Undo steps merge (text typing, bounds changes) | 🟡 partial | - | A2 | Memento/*Memento.cs Merge; Surface.cs:698-725 | EditorDocument.swift:63-82 beginChange/endChange groups a drag as one step; text has its own UndoManager (CanvasView.swift:918) |  |
| EDT-112 | Undo bounded by memory of stored images (256 MB budget, newest step always kept); commit 60af9a27 | 🟡 partial | S | A2 | Surface.cs:730-770 LimitUndoImages, UndoImagesBudget | EditorDocument.swift:45,75 limit of 100 steps, each holding a full CGImage reference (copy-on-write, but large-image steps accumulate) | Switch to byte budget |
| EDT-113 | Undo/redo menu text shows action name ("Undo {0}") | 🟡 partial | - | A2 | editor_undo, editor_redo; ImageEditorForm.cs:1519 | Plain "Undo"/"Redo" (MainMenu+Edit.swift:11) | actions are unnamed upstream too |
| EDT-114 | Redo shortcut Ctrl+Y | 🍎 Mac equivalent | - |  | ImageEditorForm.Designer.cs:611 | Shift+Cmd+Z (MainMenu+Edit.swift:13) | Mac convention |

## 5. Editor window, menus, toolbars, status bar

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-120 | Editor window title "<capture title or file> - Greenshot image editor"; title changes to saved file name | ✅ done | - |  | ImageEditorForm.cs:785-788,867-885; editor_title | EditorWindowController.swift:437 |  |
| EDT-121 | Window placement remembered (position/size/maximized) and reset if off-screen; MatchSizeToCapture | 🟡 partial | S | A3 | IEditorConfiguration.cs:51-71 WindowPlacementFlags, ShowWindowCommand, Min/Max/NormalPosition, MatchSizeToCapture | EditorWindowController.swift:368-385 sizeWindowToImage, :412 rememberFrame via UserDefaults; Settings.swift:159 matchSizeToCapture. Stored frame only used when matchSizeToCapture is off; off-screen reset not explicit (AppKit constrains) |  |
| EDT-122 | Window size follows capture/zoom (GetOptimalWindowSize), DPI-change handling | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:2438, 2699 WmGetDpiScaledSize | Retina handled by AppKit; sizing in EditorWindowController.swift:368 |  |
| EDT-123 | Default editor size when opened without capture (500x500) | ❌ missing | S | A3 | IEditorConfiguration.cs:94 DefaultEditorSize | No "new blank editor" path. EditorManager opens only captures/files/clipboard (EditorManager.swift) | Add File > New blank image? Upstream uses it for open-from-nothing cases |
| EDT-124 | Best fit zoom on open for opened-from-file/clipboard captures | ✅ done | - |  | ImageEditorForm.cs:372-379 | EditorWindowController.swift:387 zoomToFitIfLarger (for all images) |  |
| EDT-125 | Reuse editor if possible (ReuseEditor) | ✅ done | - |  | IEditorConfiguration.cs:75; Destinations/EditorDestination.cs:130-150 | EditorManager.swift:17-28; Settings.swift:157; EditorTab.swift:15 |  |
| EDT-126 | Suppress save dialog at close | ✅ done | - |  | IEditorConfiguration.cs:84; ImageEditorForm.cs:1257-1290; editor_close_on_save(_title) | EditorWindowController.swift:861-870; EditorTab.swift:16 | Sheet instead of message box |
| EDT-127 | Close behaviour: Save changes? Yes/No/Cancel; no Cancel on shutdown | ✅ done | - |  | ImageEditorForm.cs:1263-1280 | EditorWindowController.swift:819-857 makeSaveAlert, confirmCloseBeforeQuit |  |
| EDT-128 | File menu: Close (Alt+F4) and Close all (only when >1 editor) | ✅ done | - |  | ImageEditorForm.cs:731-765, 966-992; Designer:1637; editor_close, editor_close_all | MainMenu+File.swift:12-14 (⌘W, ⌥⌘W); EditorManager.swift:35 closeAll |  |
| EDT-129 | Editor persists window geometry and saves config on close | ✅ done | - |  | ImageEditorForm.cs:1292-1294 | EditorWindowController.swift:872-875 |  |
| EDT-130 | Save open editors to temp .greenshot files on OS shutdown/restart manager and reopen after restart | 🍎 Mac equivalent | L | B13 | ImageEditorForm.cs:2655-2684 TrySaveState; CHANGELOG-1.4.md:62-63 | macOS Resume/state restoration would be the equivalent; no editor state restoration in Mac port (grep restore empty) | NSWindowRestoration + save elements/base image to Application Support |
| EDT-131 | File menu lists every export destination available (shortcut shown), dynamic sub-destinations, excluding Picker and Editor | ✅ done | - |  | ImageEditorForm.cs:731-765; Controls/DestinationMenuBuilder.cs | MainMenu+File.swift:6-40: Save, Save As, PDF, Copy, Print, OCR, Email, Share, Jira/Confluence/Box/Dropbox, Open With, QR, External Command | Destination semantics in destinations slice |
| EDT-132 | Destination toolbar buttons (save, copy to clipboard, print + dynamic destination split buttons with drop-downs, icon-only) | 🟡 partial | M | A3 | ImageEditorForm.cs:600-716 AddDestinations/AddDestinationButton; Designer:847-870 | EditorWindowController.swift:164-168,298 buttons Save, Save As, Copy, Print. Other destinations only through File menu |  |
| EDT-133 | "Add to editor" dynamic destination: add this capture as image to another open editor; editor-with-title drop-down | ❌ missing | M | A3 | Destinations/EditorDestination.cs:50-95; settings destination_editor_add | no destination to add a capture to an already open editor | Needs EditorManager API and destination entry |
| EDT-134 | Edit menu: Undo, Redo, Cut, Copy, Paste, Duplicate, Preferences, Insert window | ✅ done | - |  | Designer:581-596 | MainMenu+Edit.swift:8-27 (Preferences in app menu ⌘, MainMenu.swift:13) |  |
| EDT-135 | Edit > Insert window submenu (live list of windows with icons + thumbnail preview on hover) inserts a window capture as image element | 🟡 partial | S | A3 | ImageEditorForm.cs:2142-2268; Controls/CaptureWindowMenuBuilder.cs:30-118; editor_insertwindow | WindowInsertMenu.swift; EditorWindowController.swift:744. Missing: hover thumbnail preview (ThumnailPreview setting) |  |
| EDT-136 | Object menu: add rectangle/ellipse/line/arrow/freehand/text/speech bubble/counter, select all, delete, arrange, save/load elements | ✅ done | - |  | Designer:676-694 | MainMenu+Edit.swift:30-57 (also Highlight, Obfuscate, Emoji, Cut mark, Crop) |  |
| EDT-137 | Recipes menu in editor (editor triggers fire recipes; Recipe Manager..., Recipe Editor...) | ➖ not applicable | - |  | ImageEditorForm.cs:2900-2967 UpdateRecipesMenu; contextmenu_recipes/managerecipes/recipeeditor | Recipes are a Windows-only recipe/trigger system (RCP slice); no Mac equivalent |  |
| EDT-138 | Plugins menu (editor plugins add menu items) | ➖ not applicable | - |  | ImageEditorForm.cs:540-560; Designer:814 | Plugin host does not exist on Mac (Jira/Confluence/Box/Dropbox built in) |  |
| EDT-139 | Help menu: Help (F1), About | ✅ done | - |  | Designer:819-830, ImageEditorForm.cs:1224-1233 | MainMenu.swift:35-40 Help menu, About in app menu |  |
| EDT-140 | Zoom menu: Zoom In/Out, Best fit, presets 25/50/66/75/100/200/300/400/600, checked current | ✅ done | - |  | Designer:1692-1850; ImageEditorForm.cs:2521-2620 | MainMenu+View.swift:9-28; EditorWindowController.swift:779-808 |  |
| EDT-141 | Zoom drop-down button in status bar ("100%") | 🟡 partial | S | A3 | Designer:1845 zoomStatusDropDownBtn; ImageEditorForm.cs:2596 | Status text shows zoom % (EditorWindowController.swift:445) but is not a clickable menu |  |
| EDT-142 | Ctrl+mouse wheel zooms (100 ms throttle); step through fixed zoom values | 🟡 partial | S | A3 | ImageEditorForm.cs:1442-1460 | Pinch zoom via NSScrollView.allowsMagnification (EditorWindowController.swift:296); ⌘+/⌘- scale by 1.25 not the preset ladder (:779-780); no ⌘-scroll zoom |  |
| EDT-143 | Zoom keeps selection/centre in view | 🟡 partial | S | A3 | ImageEditorForm.cs:2567-2620 | setMagnification centres on image (EditorWindowController.swift:802) |  |
| EDT-144 | Status bar: image dimensions label | ✅ done | - |  | Designer:300 dimensionsLabel; ImageEditorForm.cs:848 | EditorWindowController.swift:445 |  |
| EDT-145 | Status bar message after save/export ("Image saved to {0}", time stamp, error in red with warning sign) | ❌ missing | S | A3 | ImageEditorForm.cs:772-798 SurfaceMessageReceived; editor_imagesaved, editor_storedtoclipboard, editor_senttoprinter | Status label shows size/zoom only; save feedback goes to Toast (Output/Toast.swift) | Add a message area in status bar |
| EDT-146 | Status bar context menu after save: Copy path to clipboard, Open directory in Explorer | ❌ missing | S | A3 | ImageEditorForm.cs:1620-1635; Designer:1642-1660; editor_copypathtoclipboard, editor_opendirinexplorer | none in editor (reveal in Finder exists elsewhere: ImageSaver.swift:134) |  |
| EDT-147 | Tool bar (left strip): cursor, rect, ellipse, line, arrow, freehand, text, speech bubble, step label, emoji, highlight, obfuscate, effects split button, crop, rotate cw/ccw, resize | ✅ done | - |  | Designer:344-365 toolsToolStrip | EditorWindowController.swift:271-290 palette; Select=V, extra Cut mark; effects/resize/rotate/crop in top bar (EditorWindowController+Image.swift:13-42) | Layout differs (vertical tool strip on left) |
| EDT-148 | Tooltips with shortcut letters (editor_drawarrow "Draw arrow (A)", ...) | ✅ done | - |  | ini [Editor] | EditorWindowController.swift:277 "(R)" tooltips |  |
| EDT-149 | Toolbar: Print, Delete, Cut, Copy, Paste, Undo, Redo, Settings, Help buttons | 🟡 partial | S | A3 | Designer:847-870 | EditorWindowController.swift:164-168 Save/Save As/Copy image/Print/Undo/Redo. Missing buttons for Delete, Cut, Copy (elements), Paste, Settings, Help (all in menus) |  |
| EDT-150 | Toolbar drop-down/up-down controls steal keys: single-letter tool shortcuts disabled while a toolbar control has focus (KeysLocked) | ✅ done | - |  | ImageEditorForm.cs:1929-1937; Surface.cs:427 KeysLocked | CanvasView only handles keys while first responder (CanvasView.swift:520; MainMenu+Edit.swift:38 comment) |  |
| EDT-151 | Tool selection resets to cursor tool after drawing (single use); Esc returns to cursor | ✅ done | - |  | Surface.cs DrawingMode; ImageEditorForm.cs:1318 | CanvasView.swift:526 |  |
| EDT-152 | Disable Settings access when `DisableSettings` policy set | ➖ not applicable | - |  | ImageEditorForm.cs:526-530 | Group policy (Windows) |  |
| EDT-153 | Editor icon scaling by IconSize config | ➖ not applicable | - |  | ICoreConfiguration.cs:410 IconSize | SF Symbols scale automatically |  |
| EDT-154 | Editor startup performance: prewarm editor in background (PrewarmEditor), minimise working set (MinimizeWorkingSetSize), EditorInitialize | ➖ not applicable | - |  | EditorPrewarm.cs; EditorInitialize.cs; expert_prewarmeditor, expert_minimizememoryfootprint | .NET JIT/font cache concerns; Mac editor opens natively |  |
| EDT-155 | Editor pre-registers file format handlers (EditorInitialize) | ⚙️ internal | - |  | EditorInitialize.cs | - |  |

## 6. Image menu entries and shortcuts (semantics live in slice IMG)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-160 | Effects drop-down: Border, Drop shadow, Torn edge, Grayscale, Invert, Remove transparency (only when image has alpha), Redact text (beta) | 🟡 partial | - | A3 | Designer:477-489; ImageEditorForm.cs:560-572 | MainMenu+Image.swift:8-22; EditorWindowController+Image.swift:19-31 | Mac has also "Adjust…" |
| EDT-161 | Drop shadow: click applies stored settings, right-click opens settings dialog | 🟡 partial | - | A3 | ImageEditorForm.cs:2320-2347 MouseUp; editor_dropshadow_settings | Always opens the settings dialog first (EditorWindowController+Image.swift:58) | No right-click gesture |
| EDT-162 | Torn edges: click applies, right-click settings | 🟡 partial | - | A3 | ImageEditorForm.cs:2364-2388 | same (EditorWindowController+Image.swift:67) |  |
| EDT-163 | Resize (Z key, toolbar): resize dialog | 🟡 partial | S | A3 | ImageEditorForm.cs:1364, 2349-2362; editor_resize | ⌥⌘R (MainMenu+Image.swift:27); plain Z not bound | Z conflicts with nothing in canvas; could add |
| EDT-164 | Rotate CW/CCW (Ctrl+. / Ctrl+,) | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:1397-1402 | ⌥⌘→ / ⌥⌘← (MainMenu+Image.swift:31-34) | ⌘, is Settings on Mac |
| EDT-165 | Grayscale (Ctrl+G), Invert (Ctrl+I), Border (Ctrl+B), Drop shadow (Ctrl+Q), Torn edge (Ctrl+T) | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:1379-1393 | ⌃⌘G/I/B/S/T (EditorWindowController+Image.swift:277-285; MainMenu+Image.swift:13) | ⌘Q conflict handled |
| EDT-166 | Enlarge canvas 25 px (Ctrl+Shift+Plus), shrink canvas to content (Ctrl+Shift+Minus) | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:1421-1435, 2290-2313 (FEATURE-919) | ⌥⌘= / ⌥⌘- (MainMenu+Image.swift:41-44; EditorWindowController+Image.swift:119,124) |  |
| EDT-167 | Clear capture to transparent (Ctrl+Delete) | 🍎 Mac equivalent | - |  | ImageEditorForm.cs:1394, 2395 | ⌘⌫ (MainMenu+Image.swift:46; EditorWindowController+Image.swift:129) |  |
| EDT-168 | Remove transparency with colour dialog | 🟡 partial | - | A3 | ImageEditorForm.cs:2416-2431; editor_remove_transparency | EditorWindowController+Image.swift:134 |  |
| EDT-169 | Redact text with OCR (beta, TextObfuscationWindow, settings TextObfuscation*) | ✅ done | - |  | ImageEditorForm.cs:2148-2226; Views/TextObfuscationWindow.xaml; IEditorConfiguration.cs:98-130; editor_obfuscate_text_* | EditorWindowController+Image.swift:193; Editor/TextObfuscationWindow.swift; Settings.swift:162; GreenshotCore/TextRecognition.swift | Vision OCR; upstream shows it only for beta testers |
| EDT-170 | Drop shadow / torn edge settings persisted | ✅ done | - |  | IEditorConfiguration.cs:87,90 | Settings.swift:160-161 |  |

## 7. Colour picker

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-180 | Colour dialog: 13x11 palette grid with tooltips (hex + RGB) | 🍎 Mac equivalent | - |  | Views/ColorPickerWindow.xaml:208; .xaml.cs:168-226 | NSColorWell/NSColorPanel (EditorWindowController.swift:21-22,528) provide palettes, sliders, hex | System panel |
| EDT-181 | Recent colours row (12 slots), persisted | 🍎 Mac equivalent | - | A2 | ColorPickerWindow.xaml.cs:241-312; IEditorConfiguration.cs:42 RecentColors | NSColorPanel keeps its own recents/swatches; not shared with Greenshot settings. No Greenshot `recentColors` setting | Optional: NSColorPanel swatches |
| EDT-182 | Pipette (eyedropper): drag from the dialog over the screen, live preview window with hex/RGB/alpha, Esc cancels | 🍎 Mac equivalent | - |  | Views/ColorPickerWindow.xaml.cs:477-545; Forms/MovableShowColorForm.cs; Controls/Pipette.cs | NSColorPanel has a built-in magnifier eyedropper; not wired specially |  |
| EDT-183 | HTML hex entry and R/G/B/Alpha numeric boxes, "Transparent" button, Apply/Cancel | 🟡 partial | S | A3 | ColorPickerWindow.xaml:242-355 | NSColorPanel has hex/RGB sliders; but alpha slider is off (no `showsAlpha`) and no Transparent button for line colour (fill has "No fill", EditorWindowController.swift:530) | Enable alpha |
| EDT-184 | Colour picker used by Remove-transparency and other colour needs | 🟡 partial | - | A3 | Forms/ColorDialog.cs:36-90 | RemoveTransparency uses colour panel (EditorWindowController+Image.swift:134) |  |
| EDT-185 | ColorPickerToolStripButton / ColorButton painting selected colour inside icon | 🍎 Mac equivalent | - |  | Forms/ColorPickerToolStripButton.cs; Controls/ColorButton.cs, ToolStripColorButton.cs | NSColorWell swatch |  |

## 8. Keyboard shortcut groups (editor)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-190 | Tool letters R E L F A T S I H O C M Z, Esc | 🟡 partial | S | A2 | ImageEditorForm.cs:1314-1368 | EditorTool.swift:89-107; CanvasView.swift:561-566. Z (resize) not bound (see EDT-163); Esc goes to Select; extra V and K |  |
| EDT-191 | Clipboard / edit: Ctrl+X/C/V/D/A, Delete, Ctrl+Z/Y | ✅ done | - |  | Designer:603-750 | MainMenu+Edit.swift:11-21 | ⌘ equivalents |
| EDT-192 | Destination shortcuts processed even when menu closed (Ctrl+S etc.) | ✅ done | - |  | ImageEditorForm.cs:1474-1500 ProcessCmdKey | MainMenu+File.swift (⌘S, ⇧⌘S, ⇧⌘C, ⌘P, ⌘E, ⌥⌘P, ⌥⌘T) |  |
| EDT-193 | Image ops shortcuts (see EDT-163..167) | 🍎 Mac equivalent | - |  |  | see above |  |
| EDT-194 | Zoom: Ctrl++ / Ctrl+- / Ctrl+0 (100%) / Ctrl+9 (best fit), also numpad | ✅ done | - |  | ImageEditorForm.cs:1403-1420 | MainMenu+View.swift:9-26 (⌘=, ⌘+, ⌘-, ⌘9, ⌘0) |  |
| EDT-195 | Selection colour/thickness/shadow shortcuts | ❌ missing | S | A2 | Surface.cs:3081-3131 | see EDT-094..096 |  |
| EDT-196 | Arrange keys Home/End/PgUp/PgDn; arrows | ✅ done | - |  | Surface.cs:3047-3074 | CanvasView.swift:546-557,543 |  |
| EDT-197 | F1 opens help | ✅ done | - |  | Designer:828 | MainMenu.swift:35 (⌘?) |  |

## 9. Editor configuration properties (IEditorConfiguration.cs)

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| EDT-200 | RecentColors | 🍎 Mac equivalent | - | A2 | IEditorConfiguration.cs:42 | see EDT-181 |  |
| EDT-201 | LastUsedFieldValues | ✅ done | - |  | :47 | Settings.swift:127 |  |
| EDT-202 | MatchSizeToCapture | ✅ done | - |  | :51 | Settings.swift:159; EditorTab.swift:14 |  |
| EDT-203 | Window placement (Flags, ShowCommand, Min/Max/Normal position) | 🟡 partial | - | A3 | :55-71 | UserDefaults frame (EditorWindowController.swift:412) |  |
| EDT-204 | ReuseEditor | ✅ done | - |  | :75 | Settings.swift:157 |  |
| EDT-205 | FreehandSensitivity | ❌ missing | S | A2 | :80 | EDT-064 |  |
| EDT-206 | SuppressSaveDialogAtClose | ✅ done | - |  | :84 | Settings.swift:158 |  |
| EDT-207 | DropShadowEffectSettings, TornEdgeEffectSettings | ✅ done | - |  | :87,90 | Settings.swift:160-161 |  |
| EDT-208 | DefaultEditorSize | ❌ missing | S | A3 | :94 | EDT-123 |  |
| EDT-209 | TextObfuscation* (pattern, regex, case, scope, effect, paddings, offsets) | ✅ done | - |  | :98-130 | Settings.swift:162; SettingsTypes.swift:185 |  |
| EDT-210 | RecentEmoji | ✅ done | - |  | :134 | Settings.swift:129 |  |
| EDT-211 | Editor-related core settings: ThumnailPreview (insert-window hover), MinimizeWorkingSetSize, PrewarmEditor | ➖ not applicable | - |  | ICoreConfiguration.cs:272,292 | see EDT-135, EDT-154 |  |

## New rows

| ID | Feature | Status | Size | Package | Upstream | Mac / what is missing | Notes |
|---|---|---|---|---|---|---|---|
| R3-002 | Hold Shift while dragging a resize handle of ANY element (rectangle, ellipse, text, speech bubble, counter...) keeps its aspect ratio; step label/counter always scales rationally; Ctrl centres (Ctrl part is EDT-074). 1.3.290 "Fixed ratio scaling" (#300, #514) | 🟡 partial | S | A2 | `Greenshot.Editor/Helpers/ScaleHelper.cs:88-96,147-205,258-266` (`GetScaleOptions`: Shift = Rational, Ctrl = Centered); `Drawing/DrawableContainer.cs:579-580`; `Drawing/Adorners/ResizeAdorner.cs:110`; `Drawing/StepLabelContainer.cs:256`; commit 6400b08a | `GreenshotMac/Editor/CanvasView.swift:394-399` keeps the ratio only when `original.kind == .image`; for a line/arrow Shift snaps the angle; every other kind ignores Shift while resizing. EDT-073 only describes Shift while DRAWING | Slice EDT. Pass `keepAspect: shift` to `handle.drag(...)` for all box-shaped kinds (not line, arrow, freehand); make `.counter` always keep a 1:1 box (renderer already uses min(w,h), `AnnotationRenderer.swift:418-420`). Add a test beside the existing resize tests |
