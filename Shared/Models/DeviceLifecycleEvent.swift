import Foundation

/// User-confirmed lifecycle event for Mac sync device identities.
///
/// These records are intentionally additive and non-destructive. iOS replays
/// them over raw CloudKit device snapshots to decide which devices are active,
/// which identities are aliases of the same physical Mac, and which real
/// devices are archived. Existing provider/device records are never deleted or
/// rewritten by this model.
public struct DeviceLifecycleEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case alias
        case unalias
        case archive
        case unarchive
    }

    public let recordID: String
    public let kind: Kind
    public let primaryDeviceID: String
    public let relatedDeviceIDs: [String]
    public let confirmedAt: Date
    public let confirmedFromDeviceID: String
    public let note: String?

    public var id: String { self.recordID }

    public init(
        recordID: String = UUID().uuidString,
        kind: Kind,
        primaryDeviceID: String,
        relatedDeviceIDs: [String] = [],
        confirmedAt: Date = Date(),
        confirmedFromDeviceID: String,
        note: String? = nil)
    {
        self.recordID = recordID
        self.kind = kind
        self.primaryDeviceID = primaryDeviceID
        self.relatedDeviceIDs = relatedDeviceIDs
        self.confirmedAt = confirmedAt
        self.confirmedFromDeviceID = confirmedFromDeviceID
        self.note = note
    }

    public static func recordName(for recordID: String) -> String {
        "device-lifecycle-\(recordID)"
    }

    public func inverseUnalias(confirmedFromDeviceID: String) -> DeviceLifecycleEvent {
        DeviceLifecycleEvent(
            kind: .unalias,
            primaryDeviceID: self.primaryDeviceID,
            relatedDeviceIDs: self.relatedDeviceIDs,
            confirmedFromDeviceID: confirmedFromDeviceID,
            note: self.note)
    }

    public func inverseUnarchive(confirmedFromDeviceID: String) -> DeviceLifecycleEvent {
        DeviceLifecycleEvent(
            kind: .unarchive,
            primaryDeviceID: self.primaryDeviceID,
            confirmedFromDeviceID: confirmedFromDeviceID,
            note: self.note)
    }
}
