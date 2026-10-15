// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CourseList",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v15)],
    products: [.library(name: "ScheduleCore", targets: ["ScheduleCore"])],
    targets: [
        .target(name: "ScheduleCore"),
        .testTarget(name: "ScheduleCoreTests", dependencies: ["ScheduleCore"], resources: [.copy("Fixtures")])
    ]
)
