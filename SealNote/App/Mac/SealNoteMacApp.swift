import SwiftUI
import AppKit

@main
struct SealNoteMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

    init() {
        MacAaronUITheme.apply(SettingsStore.shared.appTheme)
    }

    var body: some Scene {
        Settings {
            MacSettingsView()
        }
    }
}
