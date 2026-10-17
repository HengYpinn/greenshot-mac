// Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
// Copyright (C) 2026 Greenshot for Mac (Community) contributors
// Based on Greenshot, Copyright (C) 2007-2026 Thomas Braun, Jens Klingen, Robin Krom
// SPDX-License-Identifier: GPL-3.0-or-later

import GreenshotCore
import SwiftUI

/// Settings › Capture › Messages and the notifications after a capture (upstream's notification options on the Capture tab).
struct NotificationSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Section("Messages") {
            Picker("Show messages", selection: level) {
                ForEach(NotificationLevel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var level: Binding<NotificationLevel> {
        Binding(get: { store.value.showNotifications ? store.value.notificationLevel : .none },
                set: { newValue in
                    store.update { values in
                        values.notificationLevel = newValue
                        values.showNotifications = newValue != .none
                    }
                })
    }
}
