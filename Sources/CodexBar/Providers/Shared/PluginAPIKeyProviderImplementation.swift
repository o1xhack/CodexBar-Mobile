import CodexBarCore
import Foundation
import SwiftUI

struct PluginAPIKeyProviderImplementation: ProviderImplementation {
    let spec: PluginProviderSpec
    var id: UsageProvider {
        self.spec.id
    }

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            self.spec.showsAPIDetail ? "api" : ProviderPresentation.standardDetailLine(context: context)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings[providerConfig: self.id, field: .apiKey]
        if self.spec.workspaceField != nil {
            _ = settings[providerConfig: self.id, field: .workspace]
        }
        if self.spec.observesTokenAccounts {
            _ = settings.tokenAccountsData(for: self.id)
        }
        if self.spec.endpoint != nil {
            _ = settings[providerConfig: self.id, field: .endpoint]
        }
        if let config = settings.providerConfig(for: self.id) {
            for toggle in self.spec.toggles {
                _ = toggle.value(config)
            }
        }
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if self.spec.availability == .always { return true }
        guard self.spec.endpoint?.isAvailable(environment: context.environment) ?? true else { return false }
        if self.spec.apiKey(environment: context.environment) != nil ||
            ProviderDescriptorRegistry.descriptor(for: self.id).credentials?
            .resolveToken(environment: context.environment) != nil { return true }
        if self.spec.availability == .environmentKey { return false }
        if !context.settings[providerConfig: self.id, field: .apiKey]
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return self.spec.availability == .configuredKeyOrAccount &&
            !context.settings.tokenAccounts(for: self.id).isEmpty
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        self.spec.toggles.map { toggle in
            ProviderSettingsToggleDescriptor(
                id: toggle.id,
                title: toggle.title,
                subtitle: toggle.subtitle,
                binding: Binding(
                    get: { context.settings.providerConfig(for: self.id).flatMap(toggle.value) ?? false },
                    set: { value in
                        context.settings.updateProviderConfig(provider: self.id) { toggle.setValue(&$0, value) }
                    }),
                statusText: nil,
                actions: [],
                isVisible: nil,
                isEnabled: nil,
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil)
        }
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        guard let field = self.spec.apiKeyField else { return [] }
        var fields = [ProviderSettingsFieldDescriptor(
            id: field.id,
            title: field.title,
            subtitle: field.subtitle,
            kind: .secure,
            placeholder: field.placeholder,
            binding: context.providerConfigBinding(.apiKey),
            actions: field.action.map { [.openURL(id: $0.id, title: $0.title, url: URL(string: $0.url))] } ?? [],
            isVisible: nil)]
        if let workspace = self.spec.workspaceField {
            fields.append(self.textField(workspace.field, binding: context.providerConfigBinding(.workspace)))
        }
        if let endpoint = self.spec.endpoint {
            fields.append(self.textField(
                endpoint.field,
                binding: context.providerConfigBinding(.endpoint),
                actions: endpoint.action.map { action in
                    [.openURL(id: action.id, title: action.title, url: endpoint.url(environment: [
                        endpoint.environmentKey: context.settings[providerConfig: self.id, field: .endpoint],
                    ]))]
                } ?? []))
        }
        return fields
    }

    @MainActor
    private func textField(
        _ field: PluginProviderSpec.TextField,
        binding: Binding<String>,
        actions: [ProviderSettingsActionDescriptor] = []) -> ProviderSettingsFieldDescriptor
    {
        ProviderSettingsFieldDescriptor(
            id: field.id,
            title: field.title,
            subtitle: field.subtitle,
            kind: .plain,
            placeholder: field.placeholder,
            binding: binding,
            actions: actions,
            isVisible: nil)
    }
}
