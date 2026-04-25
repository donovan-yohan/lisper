// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .path

let whisperBuildRoot = "\(packageRoot)/.tools/whisper.cpp/build"
let whisperSrcDir = "\(whisperBuildRoot)/src"
let ggmlSrcDir = "\(whisperBuildRoot)/ggml/src"
let ggmlBlasDir = "\(ggmlSrcDir)/ggml-blas"
let ggmlMetalDir = "\(ggmlSrcDir)/ggml-metal"

let package = Package(
    name: "Lisper",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LisperCore", targets: ["LisperCore"]),
        .executable(name: "lisper-demo", targets: ["lisper-demo"]),
        .executable(name: "lisper-app", targets: ["lisper-app"])
    ],
    targets: [
        .target(
            name: "CWhisper",
            publicHeadersPath: ".",
            cSettings: [
                .unsafeFlags([
                    "-I\(packageRoot)/.tools/whisper.cpp/include",
                    "-I\(packageRoot)/.tools/whisper.cpp/ggml/include"
                ])
            ]
        ),
        .target(
            name: "LisperCore",
            dependencies: ["CWhisper"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", whisperSrcDir,
                    "-Xlinker", "-rpath", "-Xlinker", ggmlSrcDir,
                    "-Xlinker", "-rpath", "-Xlinker", ggmlBlasDir,
                    "-Xlinker", "-rpath", "-Xlinker", ggmlMetalDir,
                    "\(whisperSrcDir)/libwhisper.1.8.4.dylib",
                    "\(ggmlSrcDir)/libggml.0.9.8.dylib",
                    "\(ggmlSrcDir)/libggml-cpu.0.9.8.dylib",
                    "\(ggmlSrcDir)/libggml-base.0.9.8.dylib",
                    "\(ggmlBlasDir)/libggml-blas.0.9.8.dylib",
                    "\(ggmlMetalDir)/libggml-metal.0.9.8.dylib"
                ])
            ]
        ),
        .executableTarget(
            name: "lisper-demo",
            dependencies: ["LisperCore"]
        ),
        .executableTarget(
            name: "lisper-app",
            dependencies: ["LisperCore"]
        ),
        .testTarget(
            name: "LisperCoreTests",
            dependencies: ["LisperCore"]
        )
    ]
)
