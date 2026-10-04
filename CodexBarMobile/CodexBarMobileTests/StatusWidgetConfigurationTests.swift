import Intents
import Testing
@testable import CodexBarMobile

struct StatusWidgetConfigurationTests {
    @Test func `All four modes and both styles map to the existing renderer`() {
        let modes: [(StatusWidgetMode, CodexBarWidgetMode)] = [
            (.overview, .overview),
            (.providerFocus, .providerFocus),
            (.todayCost, .todayCost),
            (.syncHealth, .syncHealth),
        ]
        for (input, expected) in modes {
            for style in [StatusWidgetColorStyle.mono, .colorful] {
                let intent = SelectStatusWidgetIntent()
                intent.mode = input
                intent.colorStyle = style
                let result = StatusWidgetConfigurationAdapter.configuration(from: intent)
                #expect(result.mode == expected)
                #expect(result.colorStyle == (style == .colorful ? .colorful : .mono))
            }
        }
    }

    @Test func `The quota pace widget reads its own provider and color style`() {
        let intent = SelectQuotaPaceWidgetIntent()
        intent.colorStyle = .colorful
        intent.provider = StatusWidgetProvider(identifier: "claude", display: "Claude")
        let result = StatusWidgetConfigurationAdapter.configuration(from: intent)
        #expect(result.mode == .quotaPace)
        #expect(result.colorStyle == .colorful)
        #expect(result.providers?.map(\.id) == ["claude"])

        // Unset or "Not selected" picks a provider automatically.
        let automatic = SelectQuotaPaceWidgetIntent()
        #expect(StatusWidgetConfigurationAdapter.configuration(from: automatic).providers?.isEmpty == true)
        #expect(StatusWidgetConfigurationAdapter.configuration(from: automatic).colorStyle == .mono)
        automatic.provider = StatusWidgetProvider(
            identifier: StatusWidgetProviderChoice.emptyIdentifier,
            display: "Not selected")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: automatic).providers?.isEmpty == true)
    }

    @Test func `A status widget never renders quota pace`() {
        // Build 233 offered quota pace as status widget mode 5; such widgets
        // fall back to the overview now that quota pace is its own widget.
        // The stored value is not a declared case, so it cannot come from
        // `init(rawValue:)`; reinterpret the raw integer as WidgetKit would.
        let intent = SelectStatusWidgetIntent()
        intent.mode = unsafeBitCast(5, to: StatusWidgetMode.self)
        #expect(intent.mode.rawValue == 5)
        #expect(StatusWidgetConfigurationAdapter.configuration(from: intent).mode == .overview)
    }

    @Test func `Unknown enum values preserve automatic defaults`() {
        let result = StatusWidgetConfigurationAdapter.configuration(from: SelectStatusWidgetIntent())
        #expect(result.mode == .overview)
        #expect(result.colorStyle == .mono)
        #expect(result.providers?.isEmpty == true)
    }

    @Test func `Provider choices retain order and stable identifiers while removing duplicates`() {
        let intent = SelectStatusWidgetIntent()
        intent.provider1 = StatusWidgetProvider(identifier: "fictitious-b", display: "Fictitious B")
        intent.provider2 = StatusWidgetProvider(identifier: "fictitious-a", display: "Fictitious A")
        intent.provider4 = StatusWidgetProvider(identifier: "fictitious-b", display: "Duplicate")
        let providers = StatusWidgetConfigurationAdapter.configuration(from: intent).providers ?? []
        #expect(providers.map(\.id) == ["fictitious-b", "fictitious-a"])
        #expect(providers.map(\.name) == ["Fictitious B", "Fictitious A"])
    }

    @Test func `All four provider slots preserve unavailable identifiers in slot order`() {
        let intent = SelectStatusWidgetIntent()
        intent.provider1 = StatusWidgetProvider(identifier: "fictitious-retired", display: "Retired")
        intent.provider2 = StatusWidgetProvider(identifier: "fictitious-b", display: "B")
        intent.provider3 = StatusWidgetProvider(identifier: "fictitious-c", display: "C")
        intent.provider4 = StatusWidgetProvider(identifier: "fictitious-d", display: "D")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: intent).providers?.map(\.id)
            == ["fictitious-retired", "fictitious-b", "fictitious-c", "fictitious-d"])
    }

    @Test func `Nil empty identifiers and unused slots do not become provider choices`() {
        let intent = SelectStatusWidgetIntent()
        intent.provider1 = StatusWidgetProvider(identifier: nil, display: "Invalid")
        intent.provider2 = StatusWidgetProvider(identifier: "", display: "Invalid")
        intent.provider3 = StatusWidgetProvider(
            identifier: StatusWidgetProviderChoice.emptyIdentifier,
            display: "Translated")
        intent.provider4 = StatusWidgetProvider(identifier: "fictitious-b", display: "B")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: intent).providers?.map(\.id) == ["fictitious-b"])
    }

    @Test func `Clearing a chosen slot restores automatic selection without changing another widget`() {
        let first = SelectStatusWidgetIntent()
        first.provider1 = StatusWidgetProvider(identifier: "fictitious-b", display: "B")
        let second = SelectStatusWidgetIntent()
        second.provider1 = StatusWidgetProvider(identifier: "fictitious-a", display: "A")
        first.provider1 = StatusWidgetProvider(
            identifier: StatusWidgetProviderChoice.emptyIdentifier,
            display: "Not selected")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: first).providers?.isEmpty == true)
        #expect(StatusWidgetConfigurationAdapter.configuration(from: second).providers?.map(\.id) == ["fictitious-a"])
    }

    @Test func `Missing display names fall back to the stable identifier`() {
        let intent = SelectStatusWidgetIntent()
        intent.provider1 = StatusWidgetProvider(identifier: "fictitious-retired", display: "")
        #expect(StatusWidgetConfigurationAdapter.configuration(from: intent).providers?.first?
            .name == "fictitious-retired")
    }

    @Test func `Two widget configurations remain independent`() {
        let first = SelectStatusWidgetIntent()
        first.mode = .syncHealth
        first.colorStyle = .colorful
        first.provider1 = StatusWidgetProvider(identifier: "fictitious-a", display: "Fictitious A")
        let second = SelectStatusWidgetIntent()
        second.mode = .todayCost
        second.provider1 = StatusWidgetProvider(identifier: "fictitious-b", display: "Fictitious B")
        let a = StatusWidgetConfigurationAdapter.configuration(from: first)
        let b = StatusWidgetConfigurationAdapter.configuration(from: second)
        #expect(a.mode == .syncHealth && b.mode == .todayCost)
        #expect(a.providers?.first?.id == "fictitious-a" && b.providers?.first?.id == "fictitious-b")
    }
}
