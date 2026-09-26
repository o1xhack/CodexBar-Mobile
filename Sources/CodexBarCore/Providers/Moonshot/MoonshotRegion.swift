import Foundation

public enum MoonshotRegion: String, CaseIterable, Sendable {
    case international
    case china

    public var displayName: String {
        switch self {
        case .international:
            "International (api.moonshot.ai)"
        case .china:
            "China (api.moonshot.cn)"
        }
    }

    public var apiBaseURLString: String {
        switch self {
        case .international:
            "https://api.moonshot.ai"
        case .china:
            "https://api.moonshot.cn"
        }
    }

    public var consoleURL: URL {
        switch self {
        case .international:
            URL(string: "https://platform.moonshot.ai/console/account")!
        case .china:
            URL(string: "https://platform.kimi.com/console/account")!
        }
    }
}
