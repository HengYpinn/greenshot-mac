// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import GreenshotCore
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(store: settings, status: SystemStatus()))
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.title = "\(AppInfo.name) Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    /// A backstop for the shortcut recorder: whatever happened, the hotkeys are on again once Settings closes.
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: ShortcutRecorderButton.recordingDidEnd, object: self)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    /// Owned by the window controller, so it lives as long as the window.
    @ObservedObject var status: SystemStatus
    /// Shows one fixed tab (for `--snapshot`); nil lets the user switch tabs.
    var initialTab: Int?

    var body: some View {
        Group {
            if let initialTab {
                TabView(selection: .constant(initialTab)) { tabs }
            } else {
                TabView { tabs }
            }
        }
        .frame(width: 580, height: 600)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var tabs: some View {
        GeneralSettings(store: store, status: status).tabItem { Label("General", systemImage: "gearshape") }.tag(0)
        CaptureSettings(store: store).tabItem { Label("Capture", systemImage: "camera.viewfinder") }.tag(1)
        OutputSettings(store: store).tabItem { Label("Output", systemImage: "square.and.arrow.down") }.tag(2)
    }
}

/// What the General tab shows about the system. (An ObservableObject rather than `@State`: SwiftUI's `@State`
/// is a macro whose plugin only ships with Xcode, and the app builds with the Command Line Tools alone.)
@MainActor
final class SystemStatus: ObservableObject {
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var canRecordScreen = CGPreflightScreenCaptureAccess()

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        canRecordScreen = CGPreflightScreenCaptureAccess()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct GeneralSettings: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: SystemStatus

    var body: some View {
        Form {
            Section {
                LabeledContent("Capture region") { ShortcutRecorder(combo: store.binding(\.hotkeys.region)) }
                LabeledContent("Capture window") { ShortcutRecorder(combo: store.binding(\.hotkeys.window)) }
                LabeledContent("Capture full screen") { ShortcutRecorder(combo: store.binding(\.hotkeys.fullScreen)) }
                LabeledContent("Capture last region") { ShortcutRecorder(combo: store.binding(\.hotkeys.lastRegion)) }
                LabeledContent("Open image from clipboard") { ShortcutRecorder(combo: store.binding(\.hotkeys.clipboard)) }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Click a shortcut, then type the new one. ⌫ clears it, ⎋ cancels. Keyboards with an F13 key can use it like Print Screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { status.launchAtLogin }, set: { status.setLaunchAtLogin($0) }))
                if let loginError = status.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Permissions") {
                LabeledContent("Screen recording") {
                    HStack {
                        Text(status.canRecordScreen ? "Allowed" : "Not allowed yet")
                            .foregroundStyle(status.canRecordScreen ? Color.secondary : Color.orange)
                        if !status.canRecordScreen {
                            Button("Open System Settings") { NSWorkspace.shared.open(Permissions.screenCaptureSettingsURL) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { status.refresh() }
    }
}

private struct CaptureSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Capturing") {
                Toggle("Capture the mouse pointer", isOn: store.binding(\.captureMousePointer))
                Toggle("Use interactive window capture mode", isOn: store.binding(\.interactiveWindowCapture))
                    .help("The window hotkey opens the capture screen in window mode instead of capturing the active window.")
                Toggle("Keep the window shadow in window captures", isOn: store.binding(\.includeWindowShadow))
                Toggle("Show the zoomer on the capture screen", isOn: store.binding(\.zoomerEnabled))
                Toggle("Play the camera sound", isOn: store.binding(\.playCameraSound))
                Stepper(value: store.binding(\.captureDelayMilliseconds), in: 0...10_000, step: 100) {
                    Text("Wait before capturing: \(store.value.captureDelayMilliseconds) ms")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct OutputSettings: View {
    @ObservedObject var store: SettingsStore
    private static let others: [CaptureDestination] = [.editor, .clipboard, .file, .fileAs, .printer]

    var body: some View {
        Form {
            Section("After a capture") {
                Toggle("Ask every time (destination menu)", isOn: destination(.picker))
                ForEach(Self.others, id: \.self) { candidate in
                    Toggle(candidate.displayName, isOn: destination(candidate))
                        .disabled(store.value.destinations.contains(.picker))
                }
            }
            Section("Files") {
                LabeledContent("Folder") {
                    HStack {
                        Text((store.value.outputFolderURL.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                TextField("File name pattern", text: store.binding(\.filenamePattern))
                Text("Example: \(example)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                DisclosureGroup("Pattern variables") {
                    Text(Self.patternHelp).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                Picker("Format", selection: store.binding(\.outputFormat)) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if store.value.outputFormat == .jpg {
                    Slider(value: Binding(get: { Double(store.value.jpegQuality) },
                                          set: { value in store.update { $0.jpegQuality = Int(value.rounded()) } }),
                           in: 10...100, step: 5) {
                        Text("JPEG quality: \(store.value.jpegQuality)")
                    }
                }
                Toggle("Copy the file path to the clipboard after “Save directly”", isOn: store.binding(\.copyPathToClipboard))
                Toggle("Show a message after saving or copying", isOn: store.binding(\.showNotifications))
            }
        }
        .formStyle(.grouped)
    }

    private var example: String {
        let name = FilenamePattern.fill(store.value.filenamePattern,
                                        context: store.patternContext(title: "Safari", date: Date(), consumeNumber: false))
        return "\(name).\(store.value.outputFormat.fileExtension)"
    }

    /// "Ask every time" excludes the others, like upstream's picker; without any destination it comes back.
    private func destination(_ candidate: CaptureDestination) -> Binding<Bool> {
        Binding(
            get: { store.value.destinations.contains(candidate) },
            set: { on in
                store.update { s in
                    if on {
                        s.destinations = candidate == .picker ? [.picker] : s.destinations.filter { $0 != .picker } + [candidate]
                    } else {
                        s.destinations.removeAll { $0 == candidate }
                    }
                    if s.destinations.isEmpty { s.destinations = [.picker] }
                }
            })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.value.outputFolderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.update { $0.outputFolder = (url.path as NSString).abbreviatingWithTildeInPath }
    }

    private static let patternHelp = """
        ${capturetime:d"yyyy-MM-dd HH_mm_ss"}  capture time, .NET date format
        ${title}  window title    ${user}  user name    ${hostname}  computer name
        ${YYYY} ${MM} ${DD} ${hh} ${mm} ${ss}  date and time parts
        ${NUM}  counter (000001)    ${RRRR}  random characters
        ${Desktop} ${MyPictures} ${MyDocuments}  folders    ${HOME} or any environment variable
        Options after a colon, separated by ';': p<width>[,char] pad, s<start>[,length] substring, r<old>,<new> replace
        A '/' in the pattern makes sub folders, e.g. ${YYYY}/${MM}/${title}
        """
}
