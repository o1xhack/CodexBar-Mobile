import Foundation
import WidgetKit

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: CodexBarWidgetConfigurationIntent
    let snapshot: CodexBarWidgetSnapshot
    /// Quota pace widget window choice (Research/071), kept outside the
    /// legacy App Intent so its stored schema does not change.
    var paceWindowChoice: String?
}
