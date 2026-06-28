import SwiftUI

// MARK: - 会话 / 消息 DTO（统一聊天底座）

struct ConversationDTO: Codable, Identifiable, Hashable {
    let id: Int
    let type: String          // direct | group | companion
    let group_id: Int?
    let title: String
    let avatar: String
    var avatar_url: String?
    let tint: String
    let is_group: Bool
    let member_count: Int
    var member_cap: Int?
    var announcement: String?
    let preview: String
    let time: String          // ISO8601
    var unread: Int
    var pinned: Bool?
    var muted: Bool?

    var tintColor: Color { FlowTheme.tint(tint) }

    var shortTime: String {
        if let t = time.split(separator: "T").last { return String(t.prefix(5)) }
        return ""
    }

    var asSummary: ChatSummary {
        ChatSummary(name: title, initials: avatar, tint: tintColor,
                    preview: preview, time: shortTime, unread: unread, isGroup: is_group,
                    imageURL: avatar_url)
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
    var sender_avatar_url: String?
    let sender_tint: String
    let is_ai: Bool
    var reactions: [MsgReaction]? = nil
    // —— 搭子成长（仅 ai-reply 响应带）——
    var companion_growth: CompanionGrowth? = nil
    var leveled_up: Bool? = nil

    var senderColor: Color { FlowTheme.tint(sender_tint) }
    var day: String { String(created_at.prefix(10)) }
    var shortTime: String {
        if let t = created_at.split(separator: "T").last { return String(t.prefix(5)) }
        return ""
    }
}

struct CompanionGrowth: Codable, Hashable {
    let exp: Int
    let level: Int
    let stage: String
    let level_min_exp: Int
    let level_max_exp: Int
}

struct ConvMemberDTO: Codable, Identifiable, Hashable {
    let is_ai: Bool
    let user_id: Int?
    let companion_id: Int?
    let name: String
    let initials: String
    let tint: String
    var role: String? = nil
    var avatar_url: String? = nil

    var id: String { is_ai ? "c\(companion_id ?? 0)" : "u\(user_id ?? 0)" }
    var tintColor: Color { FlowTheme.tint(tint) }
}

// MARK: - WebSocket 实时投递

struct MsgReaction: Codable, Hashable {
    let emoji: String
    let count: Int
}

extension Notification.Name {
    static let flowMessage = Notification.Name("flow.message")
    static let flowRecall = Notification.Name("flow.recall")
    static let flowReaction = Notification.Name("flow.reaction")
    static let flowTyping = Notification.Name("flow.typing")
}

struct SocketEnvelope: Decodable {
    let type: String
    let conversation_id: Int?
    let message: MessageDTO?
    let message_id: Int?
    let reactions: [MsgReaction]?
    let user_id: Int?
    let name: String?
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
              let env = try? JSONDecoder().decode(SocketEnvelope.self, from: data) else { return }
        DispatchQueue.main.async {
            switch env.type {
            case "message": if let m = env.message { NotificationCenter.default.post(name: .flowMessage, object: m) }
            case "recall":  NotificationCenter.default.post(name: .flowRecall, object: env)
            case "reaction": NotificationCenter.default.post(name: .flowReaction, object: env)
            case "typing":  NotificationCenter.default.post(name: .flowTyping, object: env)
            default: break
            }
        }
    }

    /// 发送"正在输入"。
    func sendTyping(conversationId: Int) {
        let payload: [String: Any] = ["type": "typing", "conversation_id": conversationId]
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            task?.send(.string(s)) { _ in }
        }
    }

    private func ping() {
        task?.sendPing { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            if self?.isOpen == true { self?.ping() }
        }
    }
}
