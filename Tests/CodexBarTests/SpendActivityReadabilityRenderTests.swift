import AppKit
import Observation
import SwiftUI
import XCTest
@testable import CodexBar

@MainActor
final class SpendActivityReadabilityRenderTests: XCTestCase {
    func test_scrollTargetsKeepCalendarOrderInRightToLeftLayouts() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let selection = ScrollSelection()
            let hosting = NSHostingView(rootView: ScrollRevealFixture(selection: selection)
                .frame(width: 339)
                .environment(\.layoutDirection, direction))
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            window.layoutIfNeeded()
            try await self.settle(hosting) { !Self.scrollViews(in: hosting).isEmpty }
            let scroll = try XCTUnwrap(Self.scrollViews(in: hosting).first)
            try await self.settle(hosting) { abs(scroll.contentView.bounds.minX - 350) < 1 }
            XCTAssertEqual(scroll.contentView.bounds.minX, 350, accuracy: 1, "\(direction): recent end")

            selection.index = 0
            try await self.settle(hosting) { abs(scroll.contentView.bounds.minX) < 1 }
            XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 1, "\(direction): first week")

            selection.index = 364
            try await self.settle(hosting) { scroll.contentView.bounds.maxX >= 688 }
            XCTAssertEqual(scroll.contentView.bounds.minX, 350, accuracy: 1, "\(direction): last week")
        }
    }

    private func settle(_ hosting: NSView, until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func test_navigationButtonsPageInBothDirectionsAndStopAtEnds() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_ACTIVITY_READABILITY_PROOF_DIR"] else {
            throw XCTSkip("Enable native activity proof for navigation button validation")
        }
        let app = NSApplication.shared
        guard app.delegate == nil else { return XCTFail("Use a standalone native test host") }
        let oldPolicy = app.activationPolicy()
        let hosting = NSHostingView(rootView: ScrollRevealFixture(selection: ScrollSelection()).frame(width: 339))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 339, height: hosting.frame.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            window.close()
            _ = app.setActivationPolicy(oldPolicy)
        }
        XCTAssertTrue(app.setActivationPolicy(.accessory))
        app.finishLaunching()
        window.orderFront(nil)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.setContentSize(hosting.fittingSize)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let scroll = try XCTUnwrap(Self.scrollViews(in: hosting).first)
        XCTAssertEqual(scroll.contentView.bounds.minX, 350, accuracy: 1)
        var offsets = [scroll.contentView.bounds.minX]
        let buttonY = hosting.isFlipped ? hosting.bounds.maxY - 12 : hosting.bounds.minY + 12
        for _ in 0..<3 {
            try self.click(at: CGPoint(x: 16, y: buttonY), in: hosting, window: window)
            offsets.append(scroll.contentView.bounds.minX)
        }
        XCTAssertLessThan(offsets[1], offsets[0])
        XCTAssertEqual(offsets[2], 0, accuracy: 1)
        XCTAssertEqual(offsets[3], 0, accuracy: 1)
        for _ in 0..<3 {
            try self.click(at: CGPoint(x: hosting.bounds.maxX - 16, y: buttonY), in: hosting, window: window)
            offsets.append(scroll.contentView.bounds.minX)
        }
        XCTAssertGreaterThan(offsets[4], offsets[3])
        XCTAssertEqual(offsets[5], 350, accuracy: 1)
        XCTAssertEqual(offsets[6], 350, accuracy: 1)
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["nativeMouseClickOffsets": offsets], options: [.prettyPrinted])
            .write(to: output.appendingPathComponent("navigation-button-interaction.json"))
    }

    func test_scrollRevealsChangedDayEvenWithinTheSameWeek() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_ACTIVITY_READABILITY_PROOF_DIR"] != nil else {
            throw XCTSkip("Enable native activity proof for scroll reveal validation")
        }
        let selection = ScrollSelection()
        let hosting = NSHostingView(rootView: ScrollRevealFixture(selection: selection).frame(width: 339))
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.setContentSize(hosting.fittingSize)
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let scroll = try XCTUnwrap(Self.scrollViews(in: hosting).first)
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)

        selection.index = 364
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 1)

        // The next day remains in week 52, but must still reveal that week after a manual scroll.
        selection.index = 365
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, 0)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.maxX, 689)

        selection.index = 14
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertLessThanOrEqual(scroll.contentView.bounds.minX, 26)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.maxX, 39)
    }

    func test_renderSyntheticActivity() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_ACTIVITY_READABILITY_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_ACTIVITY_READABILITY_PROOF_DIR for synthetic native heatmap proof")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let points = try (0..<365).map { offset -> SpendDashboardModel.TokenActivityPoint in
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
            let tokens = offset < 100 && offset % 3 != 0 ? (offset % 4 + 1) * 1_000_000 : 0
            return .init(day: day, totalTokens: tokens)
        }
        for language in ["en", "zh-Hans", "ar"] {
            let direction: LayoutDirection = language == "ar" ? .rightToLeft : .leftToRight
            try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                for scheme in [ColorScheme.light, .dark] {
                    for width: CGFloat in [339, 520, 760] {
                        for mode in SpendActivityViewMode.allCases {
                            let name = "\(language)-\(scheme)-\(Int(width))-\(mode.rawValue)"
                            try self.render(
                                points: points,
                                now: now,
                                calendar: calendar,
                                options: RenderOptions(mode: mode, width: width, scheme: scheme, direction: direction),
                                output: output.appendingPathComponent("\(name).png"))
                        }
                    }
                    let partial = points.enumerated().map { index, point in
                        index >= 30 || index == 10
                            ? SpendDashboardModel.TokenActivityPoint(
                                day: point.day, totalTokens: nil, isScanned: index < 30)
                            : point
                    }
                    for width: CGFloat in [339, 520] {
                        let name = width == 520 ? "partial" : "partial-339"
                        try self.render(
                            points: partial,
                            now: now,
                            calendar: calendar,
                            options: RenderOptions(mode: .daily, width: width, scheme: scheme, direction: direction),
                            output: output.appendingPathComponent("\(language)-\(scheme)-\(name).png"))
                    }
                    try self.render(
                        points: points.map { .init(day: $0.day, totalTokens: 0) },
                        now: now,
                        calendar: calendar,
                        options: RenderOptions(mode: .daily, width: 339, scheme: scheme, direction: direction),
                        output: output.appendingPathComponent("\(language)-\(scheme)-zero.png"))
                }
            }
        }
    }

    private func render(
        points: [SpendDashboardModel.TokenActivityPoint],
        now: Date,
        calendar: Calendar,
        options: RenderOptions,
        output: URL) throws
    {
        let appearance = try XCTUnwrap(NSAppearance(named: options.scheme == .dark ? .darkAqua : .aqua))
        let defaults = InMemoryUserDefaults()
        defaults.set(options.mode.rawValue, forKey: "spendActivityViewMode")
        let view = SpendActivityHeatmapView(points: points, now: now, calendar: calendar)
            .defaultAppStorage(defaults)
            .environment(\.colorScheme, options.scheme)
            .environment(\.layoutDirection, options.direction)
            .padding(16)
            .background(
                Color(nsColor: .textBackgroundColor).opacity(0.74),
                in: RoundedRectangle(cornerRadius: 12))
            .padding(10)
            .frame(width: options.width + 52)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        XCTAssertEqual(size.width, options.width + 52, accuracy: 1)
        XCTAssertGreaterThan(size.height, 80)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        defer { window.close() }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        window.setContentSize(hosting.fittingSize)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try self.capture(hosting, to: output)

        guard points.contains(where: { $0.totalTokens != 0 }) else { return }
        let scroll = try XCTUnwrap(Self.scrollViews(in: hosting).first)
        let document = try XCTUnwrap(scroll.documentView)
        let bounds = scroll.contentView.bounds
        let minimumWidth: CGFloat = 689
        XCTAssertEqual(document.frame.width, max(options.width, minimumWidth), accuracy: 1)
        XCTAssertEqual(bounds.width, options.width, accuracy: 1)
        XCTAssertEqual(bounds.minX, max(document.frame.width - bounds.width, 0), accuracy: 1)
        XCTAssertGreaterThanOrEqual(bounds.height, options.mode == .daily ? 112 : 91)

        let receipt: [String: CGFloat] = [
            "contentWidth": document.frame.width,
            "viewportWidth": bounds.width,
            "initialOffset": bounds.minX,
            "viewportHeight": bounds.height,
        ]
        try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.deletingPathExtension().appendingPathExtension("json"))
        guard options.width < minimumWidth else { return }
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 1)
        try self.capture(hosting, to: output.deletingPathExtension().appendingPathExtension("leading.png"))
    }

    private func capture(_ hosting: NSView, to output: URL) throws {
        let representation = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        try XCTUnwrap(representation.representation(using: .png, properties: [:])).write(to: output)
    }

    private func click(at point: CGPoint, in hosting: NSView, window: NSWindow) throws {
        let app = NSApplication.shared
        let location = hosting.convert(point, to: nil)
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: kind,
                location: location,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1))
            app.postEvent(event, atStart: false)
        }
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline {
            if let event = app.nextEvent(
                matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true)
            { app.sendEvent(event) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { self.scrollViews(in: $0) }
    }

    private struct RenderOptions {
        let mode: SpendActivityViewMode
        let width: CGFloat
        let scheme: ColorScheme
        let direction: LayoutDirection
    }

    @Observable
    final class ScrollSelection {
        var index: Int?
    }

    private struct ScrollRevealFixture: View {
        let selection: ScrollSelection

        var body: some View {
            SpendActivityScrollableGrid(scrollToIndex: self.selection.index) { _, _ in
                Color.clear
            }
        }
    }
}
