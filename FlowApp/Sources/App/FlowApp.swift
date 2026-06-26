import SwiftUI

@main
struct FlowApp: App {
    @StateObject private var loc = Localization()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(loc)
                .tint(FlowTheme.teal)
        }
    }
}
