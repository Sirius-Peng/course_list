import Foundation
import ScheduleCore

enum PlatformStore {
    static var groupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "CourseListAppGroupIdentifier") as? String ?? "group.dev.courselist.shared"
    }
    static func make() throws -> SnapshotStore {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            throw ScheduleError.invalid("共享容器未配置，请检查 App Groups 签名")
        }
        return SnapshotStore(directory: directory.appendingPathComponent("Schedule", isDirectory: true))
    }
}
