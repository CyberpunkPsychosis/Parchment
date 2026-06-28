import SwiftUI

@main
struct FlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loc = Localization()
    @StateObject private var auth = AuthStore()
    @StateObject private var theme = Theme()
    @StateObject private var ui = UIState()

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(loc)
                .environmentObject(auth)
                .environmentObject(theme)
                .environmentObject(ui)
                .tint(FlowTheme.teal)
        }
    }
}
