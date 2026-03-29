// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EidosAssistant",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "EidosAssistant",
            path: "Sources/EidosAssistant",
            exclude: ["Info.plist", "Resources"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/EidosAssistant/Info.plist"])
            ]
        )
    ]
)
