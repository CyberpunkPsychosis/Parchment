import Foundation

// MARK: - 传输模型

struct AppUser: Codable, Equatable {
    let id: Int
    let email: String
    var nickname: String
    var tier: String          // "free" | "pro"
    var tier_expiry: String?
    var auto_send_stickers: Bool?   // null=首次未选

    var isPro: Bool { tier == "pro" }
}

struct Sticker: Codable, Identifiable, Hashable {
    let id: Int
    let url: String
    let prompt: String
    var is_favorite: Bool
    let created_at: String
}

struct AuthResponse: Codable {
    let token: String
    let user: AppUser
}

struct ChatMessageDTO: Codable {
    let role: String          // "user" | "assistant"
    let content: String
}

struct MembershipPlan: Codable, Identifiable, Hashable {
    let id: String
    let name_zh: String
    let name_en: String
    let price_cny: Int
    let days: Int
    let desc_zh: String
    let desc_en: String

    func name(_ lang: Lang) -> String { lang == .zh ? name_zh : name_en }
    func desc(_ lang: Lang) -> String { lang == .zh ? desc_zh : desc_en }
}

struct MembershipBenefit: Codable, Hashable {
    let zh: String
    let en: String
    func text(_ lang: Lang) -> String { lang == .zh ? zh : en }
}

struct MembershipInfo: Codable {
    let plans: [MembershipPlan]
    let benefits: [MembershipBenefit]
}

enum APIError: LocalizedError {
    case http(Int, String)
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .http(_, let msg): return msg
        case .network(let msg): return msg
        case .decoding: return "数据解析失败"
        }
    }
}

/// 无第三方依赖的 API 客户端（URLSession）。
final class APIClient {
    static let shared = APIClient()
    private init() {}

    var token: String?

    // MARK: 通用请求

    private func makeRequest(_ path: String, method: String, body: Encodable? = nil) throws -> URLRequest {
        // 用字符串拼接而非 appendingPathComponent —— 后者会把查询参数的 "?" 转义成 %3F
        guard let url = URL(string: AppConfig.baseURL.absoluteString + path) else {
            throw APIError.network("无效 URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONEncoder().encode(AnyEncodable(body)) }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            try Self.checkStatus(resp, data)
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw APIError.decoding }
        } catch let e as APIError { throw e }
        catch { throw APIError.network(error.localizedDescription) }
    }

    private static func checkStatus(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
                ?? String(data: data, encoding: .utf8) ?? "请求失败"
            throw APIError.http(http.statusCode, detail)
        }
    }

    // MARK: Auth

    func register(email: String, password: String, nickname: String) async throws -> AuthResponse {
        let req = try makeRequest("/auth/register", method: "POST",
                                  body: ["email": email, "password": password, "nickname": nickname])
        return try await send(req, as: AuthResponse.self)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let req = try makeRequest("/auth/login", method: "POST",
                                  body: ["email": email, "password": password])
        return try await send(req, as: AuthResponse.self)
    }

    func me() async throws -> AppUser {
        let req = try makeRequest("/me", method: "GET")
        return try await send(req, as: AppUser.self)
    }

    // MARK: 会员

    func membershipInfo() async throws -> MembershipInfo {
        let req = try makeRequest("/membership/plans", method: "GET")
        return try await send(req, as: MembershipInfo.self)
    }

    func purchase(planId: String) async throws -> AppUser {
        struct Result: Decodable { let ok: Bool; let user: AppUser }
        let req = try makeRequest("/membership/purchase", method: "POST", body: ["plan_id": planId])
        return try await send(req, as: Result.self).user
    }

    // MARK: AI 助手（非流式）

    private struct TextResult: Decodable { let result: String }
    private struct SuggestResult: Decodable { let suggestions: [String] }

    func rewrite(text: String, tone: String) async throws -> String {
        let req = try makeRequest("/chat/rewrite", method: "POST",
                                  body: ["text": text, "tone": tone])
        return try await send(req, as: TextResult.self).result
    }

    func translate(text: String) async throws -> String {
        let req = try makeRequest("/chat/translate", method: "POST", body: ["text": text])
        return try await send(req, as: TextResult.self).result
    }

    func replySuggest(messages: [ChatMessageDTO]) async throws -> [String] {
        struct Body: Encodable { let messages: [ChatMessageDTO] }
        let req = try makeRequest("/chat/reply-suggest", method: "POST", body: Body(messages: messages))
        return try await send(req, as: SuggestResult.self).suggestions
    }

    // MARK: 贴纸

    func generateSticker(prompt: String, context: [ChatMessageDTO]? = nil) async throws -> Sticker {
        struct Body: Encodable { let prompt: String; let context: [ChatMessageDTO]? }
        let req = try makeRequest("/image/sticker", method: "POST", body: Body(prompt: prompt, context: context))
        return try await send(req, as: Sticker.self)
    }

    func listStickers(favorite: Bool = false) async throws -> [Sticker] {
        struct Result: Decodable { let stickers: [Sticker] }
        let req = try makeRequest("/stickers?favorite=\(favorite)", method: "GET")
        return try await send(req, as: Result.self).stickers
    }

    func toggleStickerFavorite(id: Int) async throws -> Sticker {
        let req = try makeRequest("/stickers/\(id)/favorite", method: "POST")
        return try await send(req, as: Sticker.self)
    }

    func deleteSticker(id: Int) async throws {
        let req = try makeRequest("/stickers/\(id)", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }

    func updateSettings(autoSendStickers: Bool? = nil, nickname: String? = nil) async throws -> AppUser {
        struct Body: Encodable { let auto_send_stickers: Bool?; let nickname: String? }
        let req = try makeRequest("/me/settings", method: "PATCH",
                                  body: Body(auto_send_stickers: autoSendStickers, nickname: nickname))
        return try await send(req, as: AppUser.self)
    }

    // MARK: 搭子 + 记忆

    func listCompanions() async throws -> [Companion] {
        struct Result: Decodable { let companions: [Companion] }
        let req = try makeRequest("/companions", method: "GET")
        return try await send(req, as: Result.self).companions
    }

    func createCompanion(name: String, persona: String, avatar: String,
                         tint: String, greeting: String) async throws -> Companion {
        let req = try makeRequest("/companions", method: "POST",
                                  body: ["name": name, "persona": persona, "avatar": avatar,
                                         "tint": tint, "greeting": greeting])
        return try await send(req, as: Companion.self)
    }

    func deleteCompanion(id: Int) async throws {
        let req = try makeRequest("/companions/\(id)", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }

    func listMemories(companionId: Int) async throws -> [Memory] {
        struct Result: Decodable { let memories: [Memory] }
        let req = try makeRequest("/companions/\(companionId)/memories", method: "GET")
        return try await send(req, as: Result.self).memories
    }

    func addMemory(companionId: Int, content: String) async throws -> Memory {
        let req = try makeRequest("/companions/\(companionId)/memories", method: "POST",
                                  body: ["content": content])
        return try await send(req, as: Memory.self)
    }

    func deleteMemory(id: Int) async throws {
        let req = try makeRequest("/memories/\(id)", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }

    func setMemoryVisibility(id: Int, shareable: Bool) async throws -> Memory {
        let req = try makeRequest("/memories/\(id)", method: "PATCH",
                                  body: ["visibility": shareable ? "shareable" : "private"])
        return try await send(req, as: Memory.self)
    }

    // MARK: 认领市场

    func listMarket() async throws -> [MarketItem] {
        struct Result: Decodable { let items: [MarketItem] }
        let req = try makeRequest("/market", method: "GET")
        return try await send(req, as: Result.self).items
    }

    func marketDetail(id: Int) async throws -> MarketItem {
        let req = try makeRequest("/market/\(id)", method: "GET")
        return try await send(req, as: MarketItem.self)
    }

    func adopt(snapshotId: Int) async throws -> Companion {
        let req = try makeRequest("/market/\(snapshotId)/adopt", method: "POST")
        return try await send(req, as: Companion.self)
    }

    func publishCompanion(id: Int) async throws {
        let req = try makeRequest("/companions/\(id)/publish", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: 群组广场

    func groupPlaza() async throws -> [PlazaGroup] {
        struct Result: Decodable { let groups: [PlazaGroup] }
        let req = try makeRequest("/groups/plaza", method: "GET")
        return try await send(req, as: Result.self).groups
    }

    func myGroups() async throws -> [PlazaGroup] {
        struct Result: Decodable { let groups: [PlazaGroup] }
        let req = try makeRequest("/groups/mine", method: "GET")
        return try await send(req, as: Result.self).groups
    }

    func groupDetail(id: Int) async throws -> PlazaGroup {
        let req = try makeRequest("/groups/\(id)", method: "GET")
        return try await send(req, as: PlazaGroup.self)
    }

    struct JoinResult: Decodable { let joined: Bool?; let pending: Bool? }

    func joinGroup(id: Int) async throws -> JoinResult {
        let req = try makeRequest("/groups/\(id)/join", method: "POST")
        return try await send(req, as: JoinResult.self)
    }

    func joinGroupByCode(code: String) async throws -> PlazaGroup {
        struct Result: Decodable { let group: PlazaGroup }
        let req = try makeRequest("/groups/join-by-code", method: "POST", body: ["code": code])
        return try await send(req, as: Result.self).group
    }

    func createGroup(name: String, description: String, avatar: String, tint: String,
                     joinMode: String, memberCap: Int) async throws -> PlazaGroup {
        struct Body: Encodable {
            let name: String; let description: String; let avatar: String
            let tint: String; let join_mode: String; let member_cap: Int
        }
        let req = try makeRequest("/groups", method: "POST",
                                  body: Body(name: name, description: description, avatar: avatar,
                                             tint: tint, join_mode: joinMode, member_cap: memberCap))
        return try await send(req, as: PlazaGroup.self)
    }

    // MARK: 流式对话（SSE）

    /// 调 /chat/stream，逐增量回调文本片段。companionId 不为空则后端注入其记忆并自动提取。
    func streamChat(messages: [ChatMessageDTO],
                    system: String? = nil,
                    companionId: Int? = nil,
                    onDelta: @escaping (String) -> Void) async throws {
        struct Body: Encodable { let messages: [ChatMessageDTO]; let system: String?; let companion_id: Int? }
        let req = try makeRequest("/chat/stream", method: "POST",
                                  body: Body(messages: messages, system: system, companion_id: companionId))

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, "对话请求失败 (\(http.statusCode))")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let delta = obj["delta"] as? String {
                let chunk = delta
                await MainActor.run { onDelta(chunk) }
            }
            // obj["meta"] 含模型信息，Phase 4 会用到
        }
    }
}

/// 让任意 Encodable 可装箱编码。
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
