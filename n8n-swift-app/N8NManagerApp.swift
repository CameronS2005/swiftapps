import SwiftUI

@main
struct N8NManagerApp: App {
    @StateObject private var settings = SettingsStore()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainView()
                    .environmentObject(settings)
            }
        }
    }
}
