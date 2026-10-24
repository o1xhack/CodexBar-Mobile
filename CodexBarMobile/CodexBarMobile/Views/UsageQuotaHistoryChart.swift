import Charts
import SwiftUI
import UIKit

/// The same real observations and date domain power the Summary tile and its detail.
struct UsageQuotaHistoryChart: View {
    let overview: UsageQuotaOverview
    let height: CGFloat
    var identifier = "usage-quota-chart"
    var selection: Binding<Date?>?

    var body: some View {
        if let selection {
            self.chart.chartOverlay { proxy in
                GeometryReader { geometry in
                    QuotaHistoryHorizontalPan { start, location in
                        guard let plotAnchor = proxy.plotFrame else { return }
                        let plot = geometry[plotAnchor]
                        guard plot.contains(start), plot.width > 0 else { return }
                        let x = min(max(location.x - plot.minX, 0), plot.width)
                        if let date: Date = proxy.value(atX: x) {
                            selection.wrappedValue = min(max(date, self.overview.start), self.overview.end)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        } else {
            self.chart
        }
    }

    private var chart: some View {
        let overview = self.overview
        let start = overview.start
        let end = overview.end
        return Chart {
            ForEach(overview.lines) { line in
                ForEach(Array(line.observedSamples.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Remaining Quota"), point.remainingPercent),
                        series: .value(String(localized: "Quota"), line.id.uuidString + "-" + String(point.segment)))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(ProviderColorPalette.color(
                            for: line.selection.providerID,
                            tintHex: line.selection.colorHex))
                }
                ForEach(Array(line.observedSamples.enumerated()), id: \.offset) { _, point in
                    PointMark(
                        x: .value(String(localized: "Date"), point.date),
                        y: .value(String(localized: "Remaining Quota"), point.remainingPercent))
                        .foregroundStyle(ProviderColorPalette.color(
                            for: line.selection.providerID,
                            tintHex: line.selection.colorHex))
                        .symbolSize(point.date == line.observedSamples.last?.date ? 16 : 4)
                }
            }
            if let selected = self.selection?.wrappedValue {
                RuleMark(x: .value(String(localized: "Date"), selected))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(overview.lines) { line in
                    if let point = UsageQuotaDetailPresentation.observation(
                        at: selected,
                        samples: line.observedSamples.filter { overview.start <= $0.date && $0.date <= overview.end })
                    {
                        PointMark(
                            x: .value(String(localized: "Date"), point.date),
                            y: .value(String(localized: "Remaining Quota"), point.remainingPercent))
                            .foregroundStyle(ProviderColorPalette.color(
                                for: line.selection.providerID,
                                tintHex: line.selection.colorHex))
                            .symbolSize(48)
                    }
                }
            }
        }
        .chartXScale(domain: start...end, range: .plotDimension(padding: 12))
        .chartYScale(domain: 0...100, range: .plotDimension(padding: 4))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text((percent / 100).formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption2)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: overview.dateTicks()) { value in
                AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(Calendar.autoupdatingCurrent.component(.day, from: date).formatted())
                            .font(.caption2).monospacedDigit()
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    }
                }
            }
        }
        .chartPlotStyle { $0.clipped() }
        .frame(height: self.height)
        .accessibilityLabel(String(localized: "Observed remaining quota by date"))
        .accessibilityIdentifier(self.identifier)
    }
}

/// UIKit rejects a vertical pan *before* recognition, allowing the ancestor scroll
/// view to claim it. Ignoring a recognized SwiftUI drag's updates is too late.
private struct QuotaHistoryHorizontalPan: UIViewRepresentable {
    var onChanged: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChanged: self.onChanged) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panChanged(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = self.onChanged
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint, CGPoint) -> Void
        private var start: CGPoint?

        init(onChanged: @escaping (CGPoint, CGPoint) -> Void) { self.onChanged = onChanged }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            // Ties and vertical gestures fail before they can compete with page scrolling.
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
        {
            // Keep the ancestor UIScrollView's recognizer eligible. Vertical pans fail
            // above; horizontal inspection does not require exclusive ownership.
            otherGestureRecognizer is UIPanGestureRecognizer
        }

        @objc func panChanged(_ pan: UIPanGestureRecognizer) {
            let location = pan.location(in: pan.view)
            switch pan.state {
            case .began:
                let translation = pan.translation(in: pan.view)
                self.start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
                if let start { self.onChanged(start, location) }
            case .changed:
                if let start { self.onChanged(start, location) }
            case .ended, .cancelled, .failed:
                self.start = nil
            default:
                break
            }
        }
    }
}
