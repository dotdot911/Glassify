// swift-tools-version:5.9
//
//  Package.swift
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import PackageDescription

let package = Package(
    name: "Glassify",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Glassify", targets: ["Glassify"]),
    ],
    targets: [
        // A C++ core, an Objective-C++ UIKit layer and Metal shaders.
        .target(
            name: "Glassify",
            path: "Sources/Glassify",
            resources: [
                .process("Shaders/glass.metal"),
                .process("Shaders/blur.metal"),
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("Core/include"),
                .headerSearchPath("Platform"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
