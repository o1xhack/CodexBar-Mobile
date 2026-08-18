import AppKit

@MainActor
struct SettingsWindowOpener {
    enum Outcome: Equatable {
        case settingsSelector
        case preferencesSelector
        case failed
    }

    private let prepare: @MainActor () -> Void
    private let sendAction: @MainActor (Selector) -> Bool

    init(
        prepare: @escaping @MainActor () -> Void = {},
        sendAction: @escaping @MainActor (Selector) -> Bool)
    {
        self.prepare = prepare
        self.sendAction = sendAction
    }

    static func live() -> Self {
        Self(
            prepare: {
                DockIconController.shared.prepareToOpenSettings()
            },
            sendAction: { selector in
                NSApp.sendAction(selector, to: nil, from: nil)
            })
    }

    func open() -> Outcome {
        self.prepare()
        if self.sendAction(Selector(("showSettingsWindow:"))) {
            return .settingsSelector
        }
        if self.sendAction(Selector(("showPreferencesWindow:"))) {
            return .preferencesSelector
        }
        return .failed
    }
}
