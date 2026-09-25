// swift-tools-version: 6.2
import PackageDescription

// Platform-independent core of calto: event models, calendar rules, date logic, response mapping.
// No UI, no networking, no EventKit — everything here is unit-testable with `swift test`.
let package = Package(
    name: "CaltoKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "CaltoKit", targets: ["CaltoKit"]),
    ],
    targets: [
        .target(name: "CaltoKit"),
        .testTarget(name: "CaltoKitTests", dependencies: ["CaltoKit"]),
    ]
)
