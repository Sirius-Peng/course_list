import Foundation

public struct SnapshotStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var fileURL: URL { directory.appendingPathComponent("schedule-v1.json") }
    public func load() throws -> ScheduleSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try ScheduleSnapshot.decode(Data(contentsOf: fileURL))
    }
    public func save(_ snapshot: ScheduleSnapshot) throws {
        let data = try snapshot.encoded()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
