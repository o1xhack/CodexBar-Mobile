import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
struct MistralMonthlyPlanAvailabilityTests {
    @Test
    func `the existing Monthly Plan capability remains reachable in every icon style`() {
        let layout = MenuBarLayout(lines: [[.icon]])
        let options = MenuBarPercentWindowPreference.available(for: .mistral, layout: layout)
        #expect(options.map(\.rawValue) == ["automatic", "monthlyPlan"])
        for style in [MenuBarIconStyle.critters, .bars, .iconAndPercent] {
            #expect(MenuBarPercentWindowPreference.isVisible(
                iconStyle: style, layout: layout, provider: .mistral))
        }
    }
}
