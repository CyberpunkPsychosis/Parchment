import Foundation

// MARK: - 传输模型

struct AppUser: Codable, Equatable {
    let id: Int
    let email: String
    var nickname: String
    var avatar_url: String?
    var bio: String?
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

    func updateSettings(autoSendStickers: Bool? = nil, nickname: String? = nil,
                        avatarURL: String? = nil, bio: String? = nil) async throws -> AppUser {
        struct Body: Encodable { let auto_send_stickers: Bool?; let nickname: String?; let avatar_url: String?; let bio: String? }
        let req = try makeRequest("/me/settings", method: "PATCH",
                                  body: Body(auto_send_stickers: autoSendStickers, nickname: nickname,
                                             avatar_url: avatarURL, bio: bio))
        return try await send(req, as: AppUser.self)
    }

    // MARK: 搭子 + 记忆

    func listCompanions() async throws -> [Companion] {
        struct Result: Decodable { let companions: [Companion] }
        let req = try makeRequest("/companions", method: "GET")
        return try await send(req, as: Result.self).companions
    }

    func createCompanion(name: String, persona: String, avatar: String,
                         tint: String, greeting: String, avatarURL: String? = nil) async throws -> Companion {
        struct Body: Encodable {
            let name: String; let persona: String; let avatar: String
            let avatar_url: String?; let tint: String; let greeting: String
        }
        let req = try makeRequest("/companions", method: "POST",
                                  body: Body(name: name, persona: persona, avatar: avatar,
                                             avatar_url: avatarURL, tint: tint, greeting: greeting))
        return try await send(req, as: Companion.self)
    }

    func updateCompanion(id: Int, name: String, persona: String, avatar: String,
                         tint: String, greeting: String, avatarURL: String?) async throws -> Companion {
        struct Body: Encodable {
            let name: String; let persona: String; let avatar: String
            let avatar_url: String?; let tint: String; let greeting: String
        }
        let req = try makeRequest("/companions/\(id)", method: "PATCH",
                                  body: Body(name: name, persona: persona, avatar: avatar,
                                             avatar_url: avatarURL ?? "", tint: tint, greeting: greeting))
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

    // MARK: 搭子成长档案（亲密度 / 里程碑 / 动态 / 家谱）

    func companionAffinity(_ cid: Int) async throws -> AffinityDTO {
        let req = try makeRequest("/companions/\(cid)/affinity", method: "GET")
        return try await send(req, as: AffinityDTO.self)
    }

    func companionMilestones(_ cid: Int) async throws -> [MilestoneDTO] {
        struct Result: Decodable { let milestones: [MilestoneDTO] }
        let req = try makeRequest("/companions/\(cid)/milestones", method: "GET")
        return try await send(req, as: Result.self).milestones
    }

    func companionDiary(_ cid: Int) async throws -> [DiaryDTO] {
        struct Result: Decodable { let diary: [DiaryDTO] }
        let req = try makeRequest("/companions/\(cid)/diary", method: "GET")
        return try await send(req, as: Result.self).diary
    }

    func companionLineage(_ cid: Int) async throws -> LineageDTO {
        let req = try makeRequest("/companions/\(cid)/lineage", method: "GET")
        return try await send(req, as: LineageDTO.self)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.checkStatus(resp, data)   // 发布门槛不够会 400，抛出后端文案
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

    // MARK: 会话 / 消息（统一聊天底座）

    func listConversations() async throws -> [ConversationDTO] {
        struct R: Decodable { let conversations: [ConversationDTO] }
        let req = try makeRequest("/conversations", method: "GET")
        return try await send(req, as: R.self).conversations
    }

    func openDirect(peerUserId: Int) async throws -> ConversationDTO {
        struct B: Encodable { let type = "direct"; let peer_user_id: Int }
        let req = try makeRequest("/conversations", method: "POST", body: B(peer_user_id: peerUserId))
        return try await send(req, as: ConversationDTO.self)
    }

    /// 羊皮纸助手：自然语言 → 站内动作提案。
    func assistantAct(text: String) async throws -> AssistantProposal {
        let req = try makeRequest("/assistant/act", method: "POST", body: ["text": text])
        return try await send(req, as: AssistantProposal.self)
    }

    /// 打开（或创建）与某搭子的 1:1 持久化会话。
    func openCompanionConversation(companionId: Int) async throws -> ConversationDTO {
        let req = try makeRequest("/conversations/companion", method: "POST", body: ["companion_id": companionId])
        return try await send(req, as: ConversationDTO.self)
    }

    /// 清空某搭子的全部记忆。
    func clearMemories(companionId: Int) async throws {
        let req = try makeRequest("/companions/\(companionId)/memories", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }

    func openGroupConversation(groupId: Int) async throws -> ConversationDTO {
        struct B: Encodable { let type = "group"; let group_id: Int }
        let req = try makeRequest("/conversations", method: "POST", body: B(group_id: groupId))
        return try await send(req, as: ConversationDTO.self)
    }

    /// 好友内部群（不挂社群）。
    func createFriendGroup(name: String, memberIds: [Int]) async throws -> ConversationDTO {
        struct B: Encodable { let name: String; let member_ids: [Int] }
        let req = try makeRequest("/conversations/group", method: "POST", body: B(name: name, member_ids: memberIds))
        return try await send(req, as: ConversationDTO.self)
    }

    func listMessages(conversationId: Int, afterId: Int = 0) async throws -> [MessageDTO] {
        struct R: Decodable { let messages: [MessageDTO] }
        let req = try makeRequest("/conversations/\(conversationId)/messages?after_id=\(afterId)", method: "GET")
        return try await send(req, as: R.self).messages
    }

    @discardableResult
    func sendMessage(conversationId: Int, kind: String = "text", content: String,
                     replyToId: Int? = nil) async throws -> MessageDTO {
        struct Body: Encodable { let kind: String; let content: String; let reply_to_id: Int? }
        let req = try makeRequest("/conversations/\(conversationId)/messages", method: "POST",
                                  body: Body(kind: kind, content: content, reply_to_id: replyToId))
        return try await send(req, as: MessageDTO.self)
    }

    func togglePin(conversationId: Int) async throws {
        let req = try makeRequest("/conversations/\(conversationId)/pin", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func toggleMute(conversationId: Int) async throws {
        let req = try makeRequest("/conversations/\(conversationId)/mute", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func markConversationRead(conversationId: Int) async throws {
        let req = try makeRequest("/conversations/\(conversationId)/read", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func recallMessage(_ mid: Int) async throws {
        let req = try makeRequest("/messages/\(mid)/recall", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func reactMessage(_ mid: Int, emoji: String) async throws {
        let req = try makeRequest("/messages/\(mid)/react", method: "POST", body: ["emoji": emoji])
        _ = try await URLSession.shared.data(for: req)
    }

    func conversationMembers(_ cid: Int) async throws -> [ConvMemberDTO] {
        struct R: Decodable { let members: [ConvMemberDTO] }
        let req = try makeRequest("/conversations/\(cid)/members", method: "GET")
        return try await send(req, as: R.self).members
    }

    func addCompanionToConversation(_ cid: Int, companionId: Int) async throws {
        let req = try makeRequest("/conversations/\(cid)/members", method: "POST", body: ["companion_id": companionId])
        _ = try await URLSession.shared.data(for: req)
    }

    func addUserToConversation(_ cid: Int, userId: Int) async throws {
        let req = try makeRequest("/conversations/\(cid)/members", method: "POST", body: ["user_id": userId])
        _ = try await URLSession.shared.data(for: req)
    }

    @discardableResult
    func aiReply(conversationId cid: Int, companionId: Int) async throws -> MessageDTO {
        let req = try makeRequest("/conversations/\(cid)/ai-reply", method: "POST", body: ["companion_id": companionId])
        return try await send(req, as: MessageDTO.self)
    }

    func uploadImage(_ data: Data, mime: String = "image/jpeg") async throws -> String {
        struct R: Decodable { let url: String }
        guard let url = URL(string: AppConfig.baseURL.absoluteString + "/upload/image") else { throw APIError.network("无效 URL") }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url); req.httpMethod = "POST"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let ext = mime.contains("png") ? "png" : "jpg"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"img.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await send(req, as: R.self).url
    }

    /// 语音音频上传（m4a）。返回稳定 URL。
    func uploadAudio(_ data: Data, ext: String = "m4a", mime: String = "audio/m4a") async throws -> String {
        struct R: Decodable { let url: String }
        guard let url = URL(string: AppConfig.baseURL.absoluteString + "/upload/audio") else { throw APIError.network("无效 URL") }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url); req.httpMethod = "POST"
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"voice.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await send(req, as: R.self).url
    }

    @discardableResult
    func shareCompanion(conversationId cid: Int, companionId: Int) async throws -> MessageDTO {
        let req = try makeRequest("/conversations/\(cid)/share-companion", method: "POST", body: ["companion_id": companionId])
        return try await send(req, as: MessageDTO.self)
    }

    @discardableResult
    func updateConversation(_ cid: Int, title: String? = nil, avatar: String? = nil, announcement: String? = nil) async throws -> ConversationDTO {
        struct B: Encodable { let title: String?; let avatar: String?; let announcement: String? }
        let req = try makeRequest("/conversations/\(cid)", method: "PATCH", body: B(title: title, avatar: avatar, announcement: announcement))
        return try await send(req, as: ConversationDTO.self)
    }

    func leaveConversation(_ cid: Int) async throws {
        let req = try makeRequest("/conversations/\(cid)/leave", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func removeMember(_ cid: Int, userId: Int? = nil, companionId: Int? = nil) async throws {
        struct B: Encodable { let user_id: Int?; let companion_id: Int? }
        let req = try makeRequest("/conversations/\(cid)/remove-member", method: "POST", body: B(user_id: userId, companion_id: companionId))
        _ = try await URLSession.shared.data(for: req)
    }

    func summarize(messages: [ChatMessageDTO]) async throws -> String {
        struct Body: Encodable { let messages: [ChatMessageDTO] }
        let req = try makeRequest("/chat/summarize", method: "POST", body: Body(messages: messages))
        return try await send(req, as: TextResult.self).result
    }

    // MARK: 好友

    func searchUsers(_ q: String) async throws -> [FriendUser] {
        struct R: Decodable { let users: [FriendUser] }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let req = try makeRequest("/users/search?q=\(enc)", method: "GET")
        return try await send(req, as: R.self).users
    }

    func userProfile(_ id: Int) async throws -> FriendUser {
        let req = try makeRequest("/users/\(id)", method: "GET")
        return try await send(req, as: FriendUser.self)
    }

    func sendFriendRequest(toUserId: Int) async throws {
        let req = try makeRequest("/friends/request", method: "POST", body: ["to_user_id": toUserId])
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: 拉黑 / 举报

    func blockUser(_ uid: Int) async throws {
        let req = try makeRequest("/blocks", method: "POST", body: ["user_id": uid])
        _ = try await URLSession.shared.data(for: req)
    }

    func unblockUser(_ uid: Int) async throws {
        let req = try makeRequest("/blocks/\(uid)", method: "DELETE")
        _ = try await URLSession.shared.data(for: req)
    }

    func listBlocks() async throws -> [BlockedUser] {
        struct R: Decodable { let blocks: [BlockedUser] }
        let req = try makeRequest("/blocks", method: "GET")
        return try await send(req, as: R.self).blocks
    }

    func report(targetType: String, targetId: Int, reason: String) async throws {
        struct Body: Encodable { let target_type: String; let target_id: Int; let reason: String }
        let req = try makeRequest("/reports", method: "POST",
                                  body: Body(target_type: targetType, target_id: targetId, reason: reason))
        _ = try await URLSession.shared.data(for: req)
    }

    func listFriendRequests() async throws -> [IncomingRequest] {
        struct R: Decodable { let requests: [IncomingRequest] }
        let req = try makeRequest("/friends/requests", method: "GET")
        return try await send(req, as: R.self).requests
    }

    func acceptFriendRequest(id: Int) async throws {
        let req = try makeRequest("/friends/requests/\(id)/accept", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func rejectFriendRequest(id: Int) async throws {
        let req = try makeRequest("/friends/requests/\(id)/reject", method: "POST")
        _ = try await URLSession.shared.data(for: req)
    }

    func listFriends() async throws -> [FriendUser] {
        struct R: Decodable { let friends: [FriendUser] }
        let req = try makeRequest("/friends", method: "GET")
        return try await send(req, as: R.self).friends
    }

    func search(_ q: String) async throws -> SearchResults {
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let req = try makeRequest("/search?q=\(enc)", method: "GET")
        return try await send(req, as: SearchResults.self)
    }

    // MARK: 朋友圈 / 动态 + 推送

    func momentsFeed() async throws -> [MomentPost] {
        struct R: Decodable { let posts: [MomentPost] }
        let req = try makeRequest("/moments", method: "GET")
        return try await send(req, as: R.self).posts
    }

    func createPost(content: String, imageURL: String? = nil) async throws -> MomentPost {
        struct B: Encodable { let content: String; let image_url: String? }
        let req = try makeRequest("/moments", method: "POST", body: B(content: content, image_url: imageURL))
        return try await send(req, as: MomentPost.self)
    }

    @discardableResult
    func toggleLike(postId: Int) async throws -> LikeResult {
        let req = try makeRequest("/moments/\(postId)/like", method: "POST")
        return try await send(req, as: LikeResult.self)
    }

    func listComments(postId: Int) async throws -> [MomentComment] {
        struct R: Decodable { let comments: [MomentComment] }
        let req = try makeRequest("/moments/\(postId)/comments", method: "GET")
        return try await send(req, as: R.self).comments
    }

    func addComment(postId: Int, content: String) async throws -> MomentComment {
        let req = try makeRequest("/moments/\(postId)/comments", method: "POST", body: ["content": content])
        return try await send(req, as: MomentComment.self)
    }

    func postDetail(postId: Int) async throws -> PostDetailDTO {
        let req = try makeRequest("/moments/\(postId)", method: "GET")
        return try await send(req, as: PostDetailDTO.self)
    }

    func registerDevice(token: String) async throws {
        let req = try makeRequest("/devices", method: "POST", body: ["token": token, "platform": "ios"])
        _ = try await URLSession.shared.data(for: req)
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
