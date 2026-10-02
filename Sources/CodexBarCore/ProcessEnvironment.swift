/// Retains environment values for execution while keeping automatic diagnostics count-only.
@propertyWrapper
public struct ProcessEnvironment<Value: Sendable & Equatable>: Sendable, Equatable,
    CustomReflectable, CustomStringConvertible, CustomDebugStringConvertible
{
    public var wrappedValue: Value

    public init(wrappedValue: Value) where Value == [String: String] {
        self.wrappedValue = wrappedValue
    }

    public init(wrappedValue: Value) where Value == [String: String]? {
        self.wrappedValue = wrappedValue
    }

    public var description: String {
        "ProcessEnvironment(\(self.entryCount) entries; redacted)"
    }

    public var debugDescription: String {
        self.description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["entryCount": self.entryCount], displayStyle: .struct)
    }

    private var entryCount: Int {
        (self.wrappedValue as? [String: String])?.count ?? 0
    }
}
