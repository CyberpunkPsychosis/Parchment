import SwiftUI

/// 全局登录态。启动时尝试用 Keychain 里的 token 恢复会话。
@MainActor
final class AuthStore: ObservableObject {
    @Published var user: AppUser?
    @Published var isBootstrapping = true   // 启动校验 token 中

    var isLoggedIn: Bool { user != nil }
    var isPro: Bool { user?.isPro ?? false }

    init() {
        if let token = Keychain.load() {
            APIClient.shared.token = token
            ChatSocket.shared.connect(token: token)
            Task { await bootstrap() }
        } else {
            isBootstrapping = false
        }
    }

    private func bootstrap() async {
        do {
            user = try await APIClient.shared.me()
        } catch {
            // token 失效 → 清掉
            Keychain.clear()
            APIClient.shared.token = nil
        }
        isBootstrapping = false
    }

    func register(email: String, password: String, nickname: String) async throws {
        let res = try await APIClient.shared.register(email: email, password: password, nickname: nickname)
        apply(res)
    }

    func login(email: String, password: String) async throws {
        let res = try await APIClient.shared.login(email: email, password: password)
        apply(res)
    }

    func logout() {
        Keychain.clear()
        APIClient.shared.token = nil
        ChatSocket.shared.disconnect()
        user = nil
    }

    func refreshUser() async {
        if let u = try? await APIClient.shared.me() { user = u }
    }

    func purchase(planId: String) async throws {
        user = try await APIClient.shared.purchase(planId: planId)
    }

    func setAutoSendStickers(_ on: Bool) {
        Task { if let u = try? await APIClient.shared.updateSettings(autoSendStickers: on) { user = u } }
    }

    private func apply(_ res: AuthResponse) {
        Keychain.save(res.token)
        APIClient.shared.token = res.token
        ChatSocket.shared.connect(token: res.token)
        user = res.user
    }
}
