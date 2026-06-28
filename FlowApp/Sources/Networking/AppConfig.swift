import Foundation

/// 全局配置。本地开发指向本机后端；上线后改 productionBaseURL。
enum AppConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:8000")!
    #else
    static let baseURL = URL(string: "https://api.flow.app")! // TODO: 买服务器后换成真实域名
    #endif
}
