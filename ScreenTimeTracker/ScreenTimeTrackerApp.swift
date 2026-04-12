import SwiftUI

@main
struct ScreenTimeTrackerApp: App {
    @StateObject private var tracker = ScreenTimeTracker()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(tracker)
        } label: {
            MenuBarLabel()
                .environmentObject(tracker)
        }
        .menuBarExtraStyle(.window)
    }
}
