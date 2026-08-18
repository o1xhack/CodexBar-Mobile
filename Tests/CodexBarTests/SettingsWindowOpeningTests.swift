import AppKit
import Testing
@testable import CodexBar

@MainActor
struct SettingsWindowOpeningTests {
    @Test
    func `modern Settings action opens first`() {
        var selectors: [String] = []
        var prepareCount = 0
        let opener = SettingsWindowOpener(
            prepare: { prepareCount += 1 },
            sendAction: { selector in
                selectors.append(NSStringFromSelector(selector))
                return true
            })

        let outcome = opener.open()

        #expect(outcome == .settingsSelector)
        #expect(prepareCount == 1)
        #expect(selectors == ["showSettingsWindow:"])
    }

    @Test
    func `legacy Preferences action is the fallback`() {
        var selectors: [String] = []
        let opener = SettingsWindowOpener(sendAction: { selector in
            let name = NSStringFromSelector(selector)
            selectors.append(name)
            return name == "showPreferencesWindow:"
        })

        let outcome = opener.open()

        #expect(outcome == .preferencesSelector)
        #expect(selectors == ["showSettingsWindow:", "showPreferencesWindow:"])
    }

    @Test
    func `unhandled Settings actions report failure`() {
        var selectors: [String] = []
        let opener = SettingsWindowOpener(sendAction: { selector in
            selectors.append(NSStringFromSelector(selector))
            return false
        })

        let outcome = opener.open()

        #expect(outcome == .failed)
        #expect(selectors == ["showSettingsWindow:", "showPreferencesWindow:"])
    }
}
