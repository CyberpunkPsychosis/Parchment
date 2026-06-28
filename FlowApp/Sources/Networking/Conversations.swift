import SwiftUI

// MARK: - 会话 / 消息 DTO（统一聊天底座）

struct ConversationDTO: Codable, Identifiable, Hashable {
    let id: Int
    let type: String          // direct | group | companion
    let group_id: Int?
    let title: String
    let avatar: String
    let tint: String
    let is_group: Bool
    let member_count: Int
    let preview: String
    let time: String          // ISO8601
    var unread: Int

    var tintColor: Color { FlowTheme.tint(tint) }

    var shortTime: String {
        // 后端给的是 ISO（含 "T"）；取 HH:mm 简单展示
        if let t = time.split(separator: "T").last { return String(t.prefix(5)) }
        return ""
    }

    var asSummary: ChatSummary {
        ChatSummary(name: title, initials: avatar, tint: tintColor,
                    preview: preview, time: shortTime, unread: unread, isGroup: is_group)
    }
}

struct MessageDTO: Codable, Identifiable, Hashable {
    let id: Int
    let conversation_id: Int
    let kind: String          // text|image|sticker|file|voice|system|companion
    let content: String
    let created_at: String
    let sender_user_id: Int?
    let companion_id: Int?
    let sender_name: String
    let sender_avatar: String
    let sender_tint: String
    let is_ai: Bool

    var senderColor: Color { FlowTheme.tint(sender_tint) }
    var shortTime: String {
        if let t = created_at.split(separator: "T").last { return String(t.prefix(5)) }
        return ""
    }
}

// MARK: - WebSocket 实时投递

extension Notification.Name {
    static let flowMessage = Notification.Name("flow.message")
}

private struct SocketEnvelope: Decodable {
    let type: String
    let conversation_id: Int?
    let message: MessageDTO?
}

/// 单例 WebSocket。收到消息后用 NotificationCenter 广播 MessageDTO；
/// 各聊天/列表页按 conversation_id 自行过滤。断线 3s 重连。
final class ChatSocket {
    static let shared = ChatSocket()
    private init() {}

    private var task: URLSessionWebSocketTask?
    private var token: String?
    private var isOpen = false

    func connect(token: String) {
        self.token = token
        if !isOpen { open() }
    }

    func disconnect() {
        isOpen = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private static func wsURL(_ token: String) -> URL? {
        var c = URLComponents(url: AppConfig.baseURL, resolvingAgainstBaseURL: false)
        c?.scheme = (AppConfig.baseURL.scheme == "https") ? "wss" : "ws"
        c?.path = "/ws"
        c?.queryItems = [URLQueryItem(name: "token", value: token)]
        return c?.url
    }

    private func open() {
        guard let token, let url = Self.wsURL(token) else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        isOpen = true
        t.resume()
        listen()
        ping()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case let .string(text) = msg { self.dispatch(text) }
                self.listen()
            case .failure:
                self.isOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.open() }
            }
        }
    }

    private func dispatch(_ text: String) {
        guard let data = text.data(using: .utf8),
              let env = try? JSONDecoder().decode(SocketEnvelope.self, from: data),
              env.type == "message", let m = env.message else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .flowMessage, object: m)
        }
    }

    private func ping() {
        task?.sendPing { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            if self?.isOpen == true { self?.ping() }
        }
    }
}
