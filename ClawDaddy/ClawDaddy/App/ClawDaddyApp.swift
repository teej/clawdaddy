//
//  ClawDaddyApp.swift
//  ClawDaddy
//
//  Created by TJ Murphy on 2/2/26.
//

import SwiftUI

@main
struct ClawDaddyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(
                settings: SettingsStore.shared,
                onDismiss: {
                    NSApp.keyWindow?.close()
                }
            )
        }
    }
}
