import UIKit
import UserNotifications

/// 推送注册：请求权限 → 注册远程通知 → 上报 device token。
/// 真实投递需在后端配置 Apple APNs 凭证（见 backend/app/push.py）。
final class PushManager {
    static let shared = PushManager()
    private init() {}

    func register() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }
}

/// 接收 APNs token 回调并上报后端。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await APIClient.shared.registerDevice(token: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // 模拟器/未配置时会走这里，忽略即可
    }
}
