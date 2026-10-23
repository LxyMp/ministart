import SwiftUI

/// Tinycast's own menu-bar item. It carries no feature state, so no feature can hide or reshape it.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image("MenuBarIcon")
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    var body: some View {
        Button("Open") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        Button("Settings") { AppCore.shared.settingsCoordinator.showSettings() }
        Button("Restart") { AppCore.shared.relaunch() }
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button("Quit") { NSApp.terminate(nil) }
    }
}
