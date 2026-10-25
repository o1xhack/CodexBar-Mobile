import CodexBarSync
import SwiftUI
import UIKit
import XCTest
@testable import CodexBarMobile

/// Bounded containers render production components, not replicas. Actual Duo screen/rail evidence
/// comes from UsageQuotaOverviewUITests, which captures every XCUIScreen in the running app.
@MainActor
final class UsageQuotaRenderTests: XCTestCase {
    private let sizes: [(String, CGSize)] = [
        ("phone320", CGSize(width: 320, height: 568)),
        ("phone390", CGSize(width: 390, height: 844)),
        ("phone440", CGSize(width: 440, height: 956)),
        ("phone-landscape667", CGSize(width: 667, height: 375)),
        ("phone-landscape844", CGSize(width: 844, height: 390)),
        ("pad768", CGSize(width: 768, height: 1024)),
        ("duo-width768", CGSize(width: 768, height: 951)),
        ("sidebar300", CGSize(width: 300, height: 951)),
    ]

    func testProductionQuotaCardFitsAllWidthsAppearancesAndLargeText() async throws {
        let accounts = Self.accounts(now: Date())
        var regularHeights: [String: CGFloat] = [:]
        for (name, size) in self.sizes {
            for scheme in [ColorScheme.light, .dark] {
                for largeText in [false, true] {
                    let store = UsageQuotaOverviewStore.demo(accounts: accounts)
                    XCTAssertEqual(store.preferences.selections.count, 5)
                    XCTAssertEqual(store.overview(accounts: accounts).lines.filter { $0.state == .available }.count, 5)
                    let geometry = QuotaRenderGeometry()
                    let root = ScrollView {
                        UsageQuotaOverviewView(
                            store: store, accounts: accounts, linkages: [], publicationRevision: "synthetic-render")
                            .onGeometryChange(for: CGSize.self) { $0.size } action: { geometry.cardSize = $0 }
                            .padding(16)
                    }
                    .background(MobileSurfaceStyle.pageBackground)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
                    .environment(\.mobileAdaptiveLayout, MobileAdaptiveLayout(
                        width: size.width, height: size.height, largeText: largeText))
                    .defaultAppStorage(QuotaRenderDefaults())
                    .frame(width: size.width, height: size.height)
                    let hosted = self.host(root, size: size, scheme: scheme)
                    defer { self.close(hosted.window) }
                    try await Task.sleep(for: .milliseconds(250))
                    hosted.controller.view.layoutIfNeeded()
                    XCTAssertEqual(geometry.cardSize.width, size.width - 32, accuracy: 2, name)
                    XCTAssertGreaterThan(geometry.cardSize.height, largeText ? 250 : 220, name)
                    if !largeText, size.width > size.height {
                        XCTAssertLessThan(
                            geometry.cardSize.height,
                            size.height,
                            "The complete collapsed card must fit the short container; native-bar clearance is tested in the app")
                    }
                    let scroller = try XCTUnwrap(self.largestScroller(in: hosted.controller.view), name)
                    XCTAssertGreaterThan(scroller.bounds.width, size.width - 4)
                    XCTAssertLessThanOrEqual(
                        scroller.contentSize.width,
                        scroller.bounds.width + 2,
                        "The production card must not introduce horizontal overflow: \(name)")
                    let key = name + "-\(scheme)"
                    if largeText, let regular = regularHeights[key] {
                        XCTAssertGreaterThan(
                            geometry.cardSize.height,
                            regular + 20,
                            "Large text must grow content rather than squeezing it into the regular height")
                    } else {
                        regularHeights[key] = geometry.cardSize.height
                    }
                    try self.capture(
                        hosted.controller.view, size: size,
                        name: "quota-card-\(name)-\(scheme)-\(largeText ? "accessibility" : "regular")")
                }
            }
        }
    }

    func testProductionEditorKeepsFiveLongAccountRowsScrollableAtAccessibilitySizes() async throws {
        let accounts = Self.accounts(now: Date())
        for width in [CGFloat(300), 320, 390, 440, 768] {
            for scheme in [ColorScheme.light, .dark] {
                let size = CGSize(width: width, height: 568)
                let store = UsageQuotaOverviewStore.demo(accounts: accounts)
                let editor = UsageQuotaEditor(store: store, accounts: accounts)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, .accessibility2)
                    .defaultAppStorage(QuotaRenderDefaults())
                    .frame(width: size.width, height: size.height)
                let hosted = self.host(editor, size: size, scheme: scheme)
                defer { self.close(hosted.window) }
                try await Task.sleep(for: .milliseconds(300))
                hosted.controller.view.layoutIfNeeded()
                let scroller = try XCTUnwrap(self.largestScroller(in: hosted.controller.view))
                XCTAssertGreaterThan(scroller.bounds.width, 100)
                XCTAssertGreaterThan(scroller.bounds.height, 100)
                XCTAssertLessThanOrEqual(scroller.contentSize.width, scroller.bounds.width + 2)
                XCTAssertGreaterThan(
                    scroller.contentSize.height,
                    scroller.bounds.height + 40,
                    "Five complete account/metric/color rows at large text must scroll, not be clipped")
                let collections = self.subviews(in: hosted.controller.view).compactMap { $0 as? UICollectionView }
                XCTAssertFalse(
                    collections.flatMap(\.visibleCells).isEmpty,
                    "The production Form must render actual native rows")
                for collection in collections {
                    for cell in collection.visibleCells {
                        XCTAssertGreaterThan(cell.bounds.height, 30)
                        XCTAssertLessThanOrEqual(cell.bounds.width, collection.bounds.width + 2)
                    }
                }
                try self.capture(
                    hosted.controller.view,
                    size: size,
                    name: "quota-editor-\(Int(width))-\(scheme)-accessibility-top")
                // Native Form estimates offscreen row heights. Re-evaluate after each scroll
                // until the last long row is measured; one offset can stop in the middle.
                for _ in 0..<10 {
                    let previousHeight = scroller.contentSize.height
                    let bottom = max(0, previousHeight - scroller.bounds.height + scroller.adjustedContentInset.bottom)
                    scroller.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    hosted.controller.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(100))
                    if abs(scroller.contentSize.height - previousHeight) < 1 { break }
                }
                XCTAssertGreaterThan(
                    scroller.contentOffset.y,
                    0,
                    "The last controls must remain reachable by scrolling")
                let finalBottom = max(
                    0,
                    scroller.contentSize.height - scroller.bounds.height + scroller.adjustedContentInset.bottom)
                XCTAssertEqual(
                    scroller.contentOffset.y,
                    finalBottom,
                    accuracy: 2,
                    "Capture must reach the actual end of all five native rows and the Add quota section")
                XCTAssertEqual(
                    store.preferences.selections.count,
                    5,
                    "Rendering and scrolling must not change saved selections")
                try self.capture(
                    hosted.controller.view,
                    size: size,
                    name: "quota-editor-\(Int(width))-\(scheme)-accessibility-bottom")
            }
        }
    }

    func testProductionChartConnectsSameCycleObservationsAcrossSamplingGapsWithoutExtrapolation() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let duration: TimeInterval = 6 * 86400
        let samples = [
            UsageQuotaPoint(date: start.addingTimeInterval(duration / 4), remainingPercent: 80, segment: 0),
            UsageQuotaPoint(date: start.addingTimeInterval(duration * 3 / 4), remainingPercent: 40, segment: 1),
        ]
        let line = UsageQuotaResolvedLine(
            selection: UsageQuotaSelection(
                providerID: "codex", accountAnchorID: "fictional-gap-account",
                windowID: "secondary", colorHex: "FF0000"),
            provider: nil, accountTitle: "Fictional account", compactAccountTitle: nil, privateAccountTitle: nil,
            metricTitle: "Weekly", state: .available, isStale: false, currentRemainingPercent: 40,
            observedAt: samples[1].date, resetDate: start.addingTimeInterval(duration),
            observedSamples: samples, localObservationCount: samples.count)
        let overview = UsageQuotaOverview(start: start, end: start.addingTimeInterval(duration), lines: [line])
        for width in [CGFloat(390), 768] {
            for scheme in [ColorScheme.light, .dark] {
                let size = CGSize(width: width, height: 280)
                let chart = UsageQuotaHistoryChart(overview: overview, height: size.height)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, .large)
                    .frame(width: size.width, height: size.height)
                let hosted = self.host(chart, size: size, scheme: scheme)
                defer { self.close(hosted.window) }
                try await Task.sleep(for: .milliseconds(250))
                hosted.controller.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    hosted.controller.view.drawHierarchy(
                        in: CGRect(origin: .zero, size: size),
                        afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Actual production gap connector-\(Int(width))-\(scheme)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                let columns = try self.redPixelColumns(image)
                let first = try XCTUnwrap(columns.firstIndex(where: { $0 > 0 }))
                let last = try XCTUnwrap(columns.lastIndex(where: { $0 > 0 }))
                // Bounds allow the production Y-axis label gutter and endpoint symbols.
                // A fabricated line to either domain edge would violate these bounds.
                XCTAssertGreaterThan(first, columns.count / 5)
                XCTAssertLessThan(first, columns.count * 2 / 5)
                XCTAssertGreaterThan(last, columns.count * 3 / 5)
                XCTAssertLessThan(last, columns.count * 9 / 10)
                XCTAssertTrue(columns.prefix(columns.count / 10).allSatisfy { $0 == 0 })
                XCTAssertTrue(columns.suffix(columns.count / 10).allSatisfy { $0 == 0 })
                // Ignore endpoint dots. Every interior band must contain the actual red
                // stroke; the old segment-split rendering leaves all these bands empty.
                let inset = (last - first) / 5
                for x in stride(from: first + inset, to: last - inset, by: 4) {
                    XCTAssertGreaterThan(
                        columns[x..<min(x + 4, last)].reduce(0, +), 0,
                        "Missing same-cycle connector at x=\(x), width=\(width), appearance=\(scheme)")
                }
            }
        }
    }

    private func redPixelColumns(_ image: UIImage) throws -> [Int] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        var columns = [Int](repeating: 0, count: width)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if pixels[offset] > 180, pixels[offset + 1] < 80, pixels[offset + 2] < 80 {
                    columns[x] += 1
                }
            }
        }
        return columns
    }

    private static func accounts(now: Date) -> [ProviderUsageSnapshot] {
        ["claude", "codex", "grok"].enumerated().map { index, providerID in
            let session = SyncRateWindow(
                id: "primary", label: "Session", usedPercent: 25 + Double(index) * 10,
                windowMinutes: 300, period: .session, resetsAt: now.addingTimeInterval(7200), resetDescription: nil)
            let weekly = SyncRateWindow(
                id: "secondary", label: "Weekly", usedPercent: 40 + Double(index) * 10,
                windowMinutes: 10080, period: .weekly,
                resetsAt: now.addingTimeInterval(Double(index + 2) * 86400), resetDescription: nil)
            return ProviderUsageSnapshot(
                providerID: providerID, providerName: providerID.capitalized, primary: session, secondary: weekly,
                accountEmail: "long.fictional.account.\(index)@example.invalid",
                loginMethod: "Synthetic Research Team Plan",
                statusMessage: nil, isError: false, lastUpdated: now.addingTimeInterval(-60),
                rateWindows: [session, weekly],
                accountIdentities: ["\(providerID):email:long.fictional.account.\(index)@example.invalid"],
                accountRecordKey: "synthetic-quota-\(index)",
                accountOrganization: "Fictional long workspace for complete multi-line identity \(index)")
        }
    }

    private func host(_ root: some View, size: CGSize, scheme: ColorScheme)
        -> (window: UIWindow, controller: UIHostingController<AnyView>)
    {
        let controller = UIHostingController(rootView: AnyView(root))
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return (window, controller)
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    private func subviews(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { self.subviews(in: $0) }
    }

    private func largestScroller(in view: UIView) -> UIScrollView? {
        self.subviews(in: view).compactMap { $0 as? UIScrollView }
            .filter { !$0.isHidden && $0.bounds.width > 0 && $0.bounds.height > 0 }
            .max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    private func capture(_ view: UIView, size: CGSize, name: String) throws {
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let data = try XCTUnwrap(image.pngData())
        let directory = URL(
            fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UsageQuotaRenders",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = "Production component in illustrative container - " + name
        attachment.lifetime = .keepAlways
        self.add(attachment)
    }
}

/// Geometry callbacks and assertions run on the main actor; no UI is reproduced by this probe.
private final class QuotaRenderGeometry: @unchecked Sendable {
    var cardSize: CGSize = .zero
}

/// Dictionary-backed AppStorage prevents rendering from reading or changing the user's preferences.
private final class QuotaRenderDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [MobileSettingsKeys.hidePersonalInfo: false]

    init() { super.init(suiteName: "UsageQuotaRenderTests.InMemory")! }
    override func object(forKey defaultName: String) -> Any? { self.values[defaultName] }
    override func bool(forKey defaultName: String) -> Bool { self.values[defaultName] as? Bool ?? false }
    override func set(_ value: Any?, forKey defaultName: String) { self.values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { self.values.removeValue(forKey: defaultName) }
}
