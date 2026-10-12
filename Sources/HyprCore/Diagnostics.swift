import Foundation

public struct SourceLocation: Equatable, Hashable, Codable, Sendable {
    public var file: String
    public var line: Int
    public init(file: String, line: Int) { self.file = file; self.line = line }
}

public struct Diagnostic: Equatable, Sendable, CustomStringConvertible {
    public var location: SourceLocation
    public var message: String
    public var isWarning: Bool
    public init(_ location: SourceLocation, _ message: String, isWarning: Bool = false) {
        self.location = location; self.message = message; self.isWarning = isWarning
    }
    public var description: String {
        "\((location.file as NSString).lastPathComponent):\(location.line): \(message)"
    }
}
