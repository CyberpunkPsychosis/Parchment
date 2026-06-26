import SwiftUI

/// Static sample data mirroring the names/figures shown in the design mockups.
enum MockData {
    static let contacts: [Contact] = [
        .init(name: "Alexander Chen", initials: "AC", tint: FlowTheme.teal),
        .init(name: "陈亚历山大",       initials: "陈", tint: FlowTheme.sage),
        .init(name: "Lona Barmer",     initials: "LB", tint: FlowTheme.ink),
        .init(name: "Vaporwave Kid",   initials: "VK", tint: FlowTheme.tealDark),
        .init(name: "Thin Ironwood",   initials: "TI", tint: FlowTheme.gray),
    ]

    static let chats: [ChatSummary] = [
        .init(name: "Vaporwave Kid", initials: "VK", tint: FlowTheme.teal,
              preview: "Last message preview.", time: "11:45 AM", unread: 1, isGroup: false),
        .init(name: "Global Investment Group", initials: "GI", tint: FlowTheme.sage,
              preview: "Last message preview to what ai…", time: "1h ago", unread: 3, isGroup: true),
        .init(name: "Thin Ironacoorsuloon", initials: "J", tint: FlowTheme.ink,
              preview: "Last message preview with lwain…", time: "1h ago", unread: 4, isGroup: false),
        .init(name: "The Founders Circle", initials: "FC", tint: FlowTheme.tealDark,
              preview: "Hey its impersarcial", time: "1h ago", unread: 1, isGroup: true),
        .init(name: "Global Investment Group", initials: "GI", tint: FlowTheme.sage,
              preview: "Last message preview your econ…", time: "1h ago", unread: 2, isGroup: true),
        .init(name: "Alexander Chen, CEO", initials: "AC", tint: FlowTheme.teal,
              preview: "Last message preview your injun…", time: "1h ago", unread: 1, isGroup: false),
        .init(name: "Lona Barmer", initials: "LB", tint: FlowTheme.gray,
              preview: "Last message preview your user…", time: "1h ago", unread: 0, isGroup: false),
        .init(name: "Alexander Chen", initials: "AC", tint: FlowTheme.teal,
              preview: "Last message preview.", time: "1h ago", unread: 0, isGroup: false),
    ]

    static let conversation: [Message] = [
        .init(kind: .image, mine: false, time: "11:45 AM"),
        .init(kind: .text("Hello message received and it has a new palette now, right?"), mine: false, time: "11:45 AM"),
        .init(kind: .text("How, your seat sounds and get a rno change?"), mine: true, time: "10:45 AM"),
        .init(kind: .image, mine: true, time: "11:25 AM"),
        .init(kind: .voice(seconds: 14), mine: true, time: "10:30 PM"),
    ]

    static let services: [EliteService] = [
        .init(titleZh: "全球人脉圈", titleEn: "Global Networking Circles",
              subtitleZh: "连接全球高端人脉网络", subtitleEn: "Global the global networking circles",
              image: "svc_networking", members: "336+"),
        .init(titleZh: "专家咨询小组", titleEn: "Expert Advisory Panels",
              subtitleZh: "专属行业专家指导", subtitleEn: "Expert guideline advisory panels",
              image: "svc_advisory", members: "304"),
    ]
}
