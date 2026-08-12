// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StandYouUp",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, UI-free logic (schedule parsing, working-hours checks) — unit-tested.
        .target(name: "StandYouUpCore"),

        // The AppKit menu-bar app. build.sh wraps this executable into StandYouUp.app.
        .executableTarget(
            name: "StandYouUp",
            dependencies: ["StandYouUpCore"]
        ),

        .testTarget(
            name: "StandYouUpCoreTests",
            dependencies: ["StandYouUpCore"]
        ),
    ]
)
