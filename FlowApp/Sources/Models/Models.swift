import SwiftUI

struct Contact: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let initials: String
    let tint: Color
}

struct ChatSummary: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let initials: String
    let tint: Color
    let preview: String
    let time: String
    let unread: Int
    let isGroup: Bool
}

enum MessageKind: Hashable {
    case text(String)
    case image              // 设计稿占位图
    case imageURL(String)   // AI 生成的贴纸（远程 URL）
    case localImage(Data)   // 用户从相册发的照片（本地）
    case file(name: String) // 用户发的文件
    case voice(seconds: Int)
}

struct Message: Identifiable, Hashable {
    let id: UUID
    var kind: MessageKind        // var: 流式时原地更新文本
    let mine: Bool
    var time: String

    init(id: UUID = UUID(), kind: MessageKind, mine: Bool, time: String) {
        self.id = id
        self.kind = kind
        self.mine = mine
        self.time = time
    }
}

struct EliteService: Identifiable, Hashable {
    let id = UUID()
    let titleZh: String
    let titleEn: String
    let subtitleZh: String
    let subtitleEn: String
    let image: String      // asset name
    let members: String
}
