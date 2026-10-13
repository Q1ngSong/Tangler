// swift-tools-version: 6.2
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]
let base: [Target.Dependency] = ["Contracts", "CoreKit"]
let feature: [Target.Dependency] = ["Contracts", "CoreKit", "OverlayKit"]
let services = ["WindowKit", "InputKit", "CaptureKit", "CommandKit", "SettingsKit"]
let features = ["WindowLayout", "TabGroups", "Switcher", "DockPreview", "CommandPalette", "Workspaces"]

func library(_ name: String, _ dependencies: [Target.Dependency] = []) -> Target {
    .target(name: name, dependencies: dependencies, swiftSettings: swift5)
}


var targets: [Target] = [
    .target(name: "CoreKit", resources: [.process("Resources")], swiftSettings: swift5),
    library("Contracts", ["CoreKit"]),
    library("OverlayKit", base),
    .executableTarget(name: "Tangler",
                      dependencies: feature + [.product(name: "Sparkle", package: "Sparkle")]
                        + (services + features).map { .target(name: $0) },
                      path: "Sources/App", swiftSettings: swift5,
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
] + services.map { library($0, base) } + features.map { library($0, feature) }


let package = Package(
    name: "Tangler",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Tangler", targets: ["Tangler"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: targets
)
