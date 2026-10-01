// swift-tools-version: 5.7
import PackageDescription
import Foundation

#if swift(<5.9)
// swift-testing needs the Swift 6 toolchain, so on this branch's 5.7 compiler
// the files that import it are left out of the test target instead of run.
// The manifest runs with an unrelated working directory, so anchor to this file.
let testSourceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Tests/StatusTrioCoreTests", isDirectory: true)

let swiftTestingFiles: [String] = (try? FileManager.default.contentsOfDirectory(
    atPath: testSourceDirectory.path
))?.filter { name in
    guard name.hasSuffix(".swift"),
          let source = try? String(
            contentsOfFile: testSourceDirectory.appendingPathComponent(name).path,
            encoding: .utf8
          )
    else { return false }
    return source.contains("import Testing")
} ?? []
#else
let swiftTestingFiles: [String] = []
#endif

let package = Package(
    name: "StatusTrio",
    defaultLocalization: "en",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "StatusTrio", targets: ["StatusTrio"])
    ],
    targets: [
        .target(
            name: "StatusTrioCore",
            dependencies: [
                "DDCPrivateAPI"
            ],
            path: "Sources/StatusTrioCore",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreDisplay"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .target(
            name: "DDCPrivateAPI",
            path: "Sources/DDCPrivateAPI",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "StatusTrio",
            dependencies: ["StatusTrioCore"],
            path: "Sources/StatusTrio"
        ),
        .testTarget(
            name: "StatusTrioCoreTests",
            dependencies: ["StatusTrioCore"],
            path: "Tests/StatusTrioCoreTests",
            exclude: swiftTestingFiles
        )
    ]
)
