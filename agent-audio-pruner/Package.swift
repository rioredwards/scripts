// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentAudioPruner",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentAudioPrunerCore", targets: ["AgentAudioPrunerCore"]),
        .executable(name: "agent-audio-prune", targets: ["AgentAudioPrune"]),
    ],
    targets: [
        .target(name: "AgentAudioPrunerCore"),
        .executableTarget(
            name: "AgentAudioPrune",
            dependencies: ["AgentAudioPrunerCore"]
        ),
        .testTarget(
            name: "AgentAudioPrunerCoreTests",
            dependencies: ["AgentAudioPrunerCore"]
        ),
    ]
)
