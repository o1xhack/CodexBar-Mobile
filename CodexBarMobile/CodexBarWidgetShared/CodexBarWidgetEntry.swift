import Foundation
import WidgetKit

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: CodexBarWidgetConfigurationIntent
    let snapshot: CodexBarWidgetSnapshot
}
