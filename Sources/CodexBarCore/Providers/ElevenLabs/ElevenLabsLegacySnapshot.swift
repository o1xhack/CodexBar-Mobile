import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ElevenLabsOverage: Codable, Sendable, Equatable {
    public let amount: String?
    public let currency: String?
}

public struct ElevenLabsSubscriptionResponse: Decodable, Sendable {
    public let tier: String?
    public let characterCount: Int
    public let characterLimit: Int
    public let voiceSlotsUsed: Int?
    public let professionalVoiceSlotsUsed: Int?
    public let voiceLimit: Int?
    public let professionalVoiceLimit: Int?
    public let currentOverage: ElevenLabsOverage?
    public let status: String?
    public let nextCharacterCountResetUnix: Int?

    private enum CodingKeys: String, CodingKey {
        case tier
        case characterCount = "character_count"
        case characterLimit = "character_limit"
        case voiceSlotsUsed = "voice_slots_used"
        case professionalVoiceSlotsUsed = "professional_voice_slots_used"
        case voiceLimit = "voice_limit"
        case professionalVoiceLimit = "professional_voice_limit"
        case currentOverage = "current_overage"
        case status
        case nextCharacterCountResetUnix = "next_character_count_reset_unix"
    }
}

public struct ElevenLabsUsageSnapshot: Codable, Sendable, Equatable {
    public let tier: String?
    public let characterCount: Int
    public let characterLimit: Int
    public let voiceSlotsUsed: Int?
    public let professionalVoiceSlotsUsed: Int?
    public let voiceLimit: Int?
    public let professionalVoiceLimit: Int?
    public let currentOverage: ElevenLabsOverage?
    public let status: String?
    public let resetsAt: Date?
    public let updatedAt: Date

    public init(
        tier: String?,
        characterCount: Int,
        characterLimit: Int,
        voiceSlotsUsed: Int?,
        professionalVoiceSlotsUsed: Int?,
        voiceLimit: Int?,
        professionalVoiceLimit: Int?,
        currentOverage: ElevenLabsOverage?,
        status: String?,
        resetsAt: Date?,
        updatedAt: Date)
    {
        self.tier = tier
        self.characterCount = characterCount
        self.characterLimit = characterLimit
        self.voiceSlotsUsed = voiceSlotsUsed
        self.professionalVoiceSlotsUsed = professionalVoiceSlotsUsed
        self.voiceLimit = voiceLimit
        self.professionalVoiceLimit = professionalVoiceLimit
        self.currentOverage = currentOverage
        self.status = status
        self.resetsAt = resetsAt
        self.updatedAt = updatedAt
    }

    public var usedPercent: Double {
        guard self.characterLimit > 0 else { return 0 }
        return UsagePercent(
            used: Double(self.characterCount),
            limit: Double(self.characterLimit)).displayClamped
    }

    public var remainingCharacters: Int {
        max(0, self.characterLimit - self.characterCount)
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let primary = RateWindow(
            usedPercent: self.usedPercent,
            windowMinutes: nil,
            resetsAt: self.resetsAt,
            resetDescription: self.characterSummary)
        let extraWindows = self.voiceWindows()
        let identity = ProviderIdentitySnapshot(
            providerID: .elevenlabs,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: self.displayTier)

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            extraRateWindows: extraWindows.isEmpty ? nil : extraWindows,
            elevenLabsUsage: self,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private var displayTier: String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty else {
            return status
        }
        let statusSuffix = if let status, !status.isEmpty, status.lowercased() != "active" {
            " · \(status)"
        } else {
            ""
        }
        return "\(tier.replacingOccurrences(of: "_", with: " ").capitalized)\(statusSuffix)"
    }

    private var characterSummary: String {
        "\(Self.formatCount(self.characterCount)) / \(Self.formatCount(self.characterLimit)) credits"
    }

    private func voiceWindows() -> [NamedRateWindow] {
        var windows: [NamedRateWindow] = []
        if let used = voiceSlotsUsed, let limit = voiceLimit, limit > 0 {
            windows.append(NamedRateWindow(
                id: "voice-slots",
                title: "Voice slots",
                window: RateWindow(
                    usedPercent: UsagePercent(used: Double(used), limit: Double(limit)).displayClamped,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: "\(used) / \(limit)")))
        }
        if let used = professionalVoiceSlotsUsed, let limit = professionalVoiceLimit, limit > 0 {
            windows.append(NamedRateWindow(
                id: "professional-voices",
                title: "Professional voices",
                window: RateWindow(
                    usedPercent: UsagePercent(used: Double(used), limit: Double(limit)).displayClamped,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: "\(used) / \(limit)")))
        }
        return windows
    }

    private static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
