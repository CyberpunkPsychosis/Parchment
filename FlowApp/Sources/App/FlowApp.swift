import SwiftUI

@main
struct FlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var loc = Localization()
    @StateObject private var auth = AuthStore()
    @StateObject private var theme = Theme()
    @StateObject private var ui = UIState()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                AuthGateView()
                    .environmentObject(loc)
                    .environmentObject(auth)
                    .environmentObject(theme)
                    .environmentObject(ui)
                    .tint(FlowTheme.teal)
                if showSplash {
                    SplashView()
                        .environmentObject(loc)
                        .transition(.opacity)
                        .zIndex(1)
                        .task {
                            // 展示约 1.6s 后淡出进入 App
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            withAnimation(.easeOut(duration: 0.5)) { showSplash = false }
                        }
                }
            }
        }
    }
}
