import Foundation

extension PluginProviderSpec {
    /// Browser domains and session capabilities remain in the bundled manifest; the strategy passes them
    /// unchanged to the cookie broker. This spec owns only native source policy and settings registration.
    public struct WebSource: Sendable {
        public enum Mode: Sendable {
            case web
            case sessionOrAPI
        }

        public enum StrategySuffix: String, Sendable {
            case js
            case web
        }

        var sourceModes: Set<ProviderSourceMode> {
            self.mode == .web ? [.auto, .web] : [.auto, .web, .api]
        }

        public enum Timeout: Sendable {
            case fixed(TimeInterval)
            case web(minimum: TimeInterval, maximum: TimeInterval, padding: TimeInterval, nonFinite: TimeInterval?)

            func resolve(_ context: ProviderFetchContext) -> TimeInterval {
                switch self {
                case let .fixed(value): value
                case let .web(minimum, maximum, padding, nonFinite):
                    max(minimum, min(
                        maximum,
                        context.webTimeout.isFinite
                            ? context.webTimeout : nonFinite ?? context.webTimeout) + padding)
                }
            }
        }

        public let settingsSection: ProviderSettingsSectionRegistration?
        public var browserCookieOrder: BrowserCookieImportOrder?
        public var mode: Mode = .web
        public var strategySuffix: StrategySuffix = .js
        public var timeout: Timeout = .fixed(ProviderPluginRuntime.defaultTimeout)
        public var transport: any ProviderHTTPTransport = ProviderHTTPClient.shared
        public var browserSupportExemption: ProviderCLIConfig.BrowserSupportExemption?
        public var resolveValues: ScriptFetchStrategy.ValuesResolver = { _ in .init() }
        public let field: SecureField
        public var picker: CookiePicker?
        public var detailLine: String?
        public var showsVersionInSettings = true
        public var loginURL: String?
        public var availability: ScriptFetchStrategy.EnabledResolver = { _ in true }
    }

    public struct CookiePicker: Sendable {
        public enum Text: Sendable {
            case literal(String)
            case localized(String, argument: String? = nil)
        }

        public let id: String
        public let allowsOff: Bool
        public let auto: Text
        public let manual: Text
        public let off: Text
        public var showsRefreshAction = false
    }

    func webStrategy(_ web: WebSource, context: ProviderFetchContext) -> ScriptFetchStrategy {
        ScriptFetchStrategy(
            id: "\(self.id.rawValue).\(web.strategySuffix.rawValue)",
            provider: self.id,
            bundledPlugin: self.id.rawValue,
            sourceLabel: web.mode == .sessionOrAPI ? context.sourceMode.rawValue : "web",
            kind: web.mode == .sessionOrAPI && context.sourceMode != .web ? .apiToken : .web,
            transport: web.transport,
            timeout: web.timeout.resolve(context),
            validateContext: self.validateContext,
            resolveValues: web.resolveValues,
            isEnabled: { _ in true })
    }
}
