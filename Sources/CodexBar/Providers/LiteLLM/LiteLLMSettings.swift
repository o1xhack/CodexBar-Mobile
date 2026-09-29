import CodexBarCore
import Foundation

extension SettingsStore {
    var litellmModelUsageEnabled: Bool {
        get { self.configSnapshot.providerConfig(for: .litellm)?.litellmModelUsageEnabled ?? false }
        set {
            self.updateProviderConfig(provider: .litellm) { $0.litellmModelUsageEnabled = newValue }
        }
    }
}
