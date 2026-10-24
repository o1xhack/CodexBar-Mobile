import SwiftUI

struct SummaryModuleSpan: LayoutValueKey {
    static let defaultValue = false
}

/// Row/column packing is shared by compact iPhone and the wider Duo grid.
/// A chart reserves a genuine 2 × 2 footprint, leaving neighboring slots for metrics.
enum SummaryModulePacking {
    struct Placement: Equatable {
        let row: Int
        let column: Int
        let columns: Int
        let rows: Int
    }

    static func columnCount(width: CGFloat, shortHeight: Bool, accessibility: Bool) -> Int {
        if accessibility { return 1 }
        // A short conventional phone keeps its full-width two-column chart. Taller
        // windows (including Duo portrait) use their actual width, not split-view policy.
        return shortHeight ? 2 : max(2, min(4, Int(width / 175)))
    }

    static func placements(modules: [Bool], columns: Int) -> [Placement] {
        let width = max(1, columns)
        var occupied = Set<Int>()
        // Never backfill an earlier hole: visual reading order must match the stored
        // order and VoiceOver traversal, even when a module skips a narrow row end.
        var cursor = 0
        return modules.map { module in
            let span = module && width > 1 ? 2 : 1
            var position = cursor
            while true {
                let row = position / width
                let column = position % width
                if column + span <= width {
                    let cells = (0..<span).flatMap { dy in
                        (0..<span).map { dx in (row + dy) * width + column + dx }
                    }
                    if cells.allSatisfy({ !occupied.contains($0) }) {
                        occupied.formUnion(cells)
                        cursor = position + 1
                        return Placement(row: row, column: column, columns: span, rows: span)
                    }
                }
                position += 1
            }
        }
    }
}

struct SummaryModuleGrid: Layout {
    var columns: Int
    var spacing: CGFloat = 8

    private func measurements(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let count = max(1, self.columns)
        let tileWidth = max(1, (width - CGFloat(count - 1) * self.spacing) / CGFloat(count))
        let placements = SummaryModulePacking.placements(
            modules: subviews.map { $0[SummaryModuleSpan.self] }, columns: count)
        if count == 1 {
            var y: CGFloat = 0
            let frames = subviews.map { view in
                let height = view.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height
                defer { y += height + self.spacing }
                return CGRect(x: 0, y: y, width: tileWidth, height: height)
            }
            return (frames, max(0, y - self.spacing))
        }
        let rowHeight = subviews.filter { !$0[SummaryModuleSpan.self] }.map {
            $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height
        }.reduce(CGFloat(112), max)
        let frames = placements.map { placement in
            CGRect(
                x: CGFloat(placement.column) * (tileWidth + self.spacing),
                y: CGFloat(placement.row) * (rowHeight + self.spacing),
                width: CGFloat(placement.columns) * tileWidth + CGFloat(placement.columns - 1) * self.spacing,
                height: CGFloat(placement.rows) * rowHeight + CGFloat(placement.rows - 1) * self.spacing)
        }
        return (frames, frames.map(\.maxY).max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: self.measurements(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = self.measurements(width: bounds.width, subviews: subviews).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
