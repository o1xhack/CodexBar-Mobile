import AppKit
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct PersistentRefreshAccessibilityTests {
    @Test(arguments: [nil, "arrow.clockwise"] as [String?])
    func `disabled refresh row rejects accessibility press`(systemImageName: String?) {
        var pressCount = 0
        let view = PersistentRefreshMenuView(
            title: "Refresh",
            systemImageName: systemImageName,
            shortcutText: "⌘ R",
            onClick: { pressCount += 1 })

        #expect(view.accessibilityRole() == .button)
        #expect(view.accessibilityLabel() == "Refresh")
        #expect(view.isAccessibilityEnabled())
        #expect(view.accessibilityPerformPress())
        #expect(pressCount == 1)

        view.setEnabled(false)
        #expect(!view.isAccessibilityEnabled())
        #expect(!view.accessibilityPerformPress())
        #expect(pressCount == 1)

        view.setEnabled(true)
        #expect(view.isAccessibilityEnabled())
        #expect(view.accessibilityPerformPress())
        #expect(pressCount == 2)
    }
}
