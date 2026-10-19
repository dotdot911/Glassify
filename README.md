# Glassify

iOS 26 Liquid Glass for iOS 13 and later. Glassify re-implements `UIGlassEffect`,
`UIGlassContainerEffect` and the glass controls and bars of iOS 26 with a C++17 core and Metal
shaders. The constants and formulas come from Apple's own frameworks, so the glass looks and moves like the
system's on every iOS version.

| Glassify | iOS 26 counterpart |
|---|---|
| `GLSGlassView` | `UIVisualEffectView` + `UIGlassEffect` (regular, clear, tinted, interactive) |
| `GLSGlassContainerView` | `UIGlassContainerEffect` (shapes that merge) |
| `GLSGlassButton` | `UIButton.Configuration` `.glass()`, `.prominentGlass()`, `.clearGlass()`, `.prominentClearGlass()` |
| `GLSSwitch`, `GLSSlider`, `GLSSegmentedControl` | `UISwitch`, `UISlider`, `UISegmentedControl` |
| `GLSNavigationController` | `UINavigationController` with the glass navigation bar and toolbar |
| `GLSLiquidLensView` | the liquid "drop" of the tab bar, switch and slider |

Requirements: iOS 13+, a Metal device (every iPhone that runs iOS 13).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/dotdot911/Glassify.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "Glassify", package: "Glassify")]),
]
```

Or in Xcode: File › Add Package Dependencies… with the repository URL.

### CocoaPods

```ruby
pod 'Glassify', '~> 0.1'
```

Works with and without `use_frameworks!`.

### Bazel

```python
# MODULE.bazel
bazel_dep(name = "glassify", version = "0.1.0")
git_override(module_name = "glassify", remote = "https://github.com/dotdot911/Glassify.git", tag = "0.1.0")
```

```python
# BUILD.bazel
objc_library(name = "MyAppLib", srcs = [...], deps = ["@glassify//:Glassify"])
```

The shaders come with the library as `GlassifyShaders.bundle` (rules_apple compiles them).

## Usage

```swift
import Glassify

let glass = GLSGlassView(frame: CGRect(x: 20, y: 100, width: 200, height: 56))
glass.style = .regular                      // or .clear
glass.glassTintColor = .systemBlue.withAlphaComponent(0.6)
glass.isInteractive = true                  // lifts and glows under the finger
view.addSubview(glass)                      // refracts its superview
glass.contentView.addSubview(label)         // content is tinted like UIGlassEffect's

// Glass over a scroll view that moves under it:
glass.backdropSourceView = scrollView
glass.tracksBackdropMotion = true

// Drop-in replacements: keep the UIKit code, change the class.
let navigation = GLSNavigationController(rootViewController: root)
let toggle = GLSSwitch()
let slider = GLSSlider()
let segments = GLSSegmentedControl(items: ["Day", "Week"])
let button = GLSGlassButton(style: .prominentGlass)
```

Objective-C: `#import <Glassify/Glassify.h>`.

## Example app

`Examples/GlassifyDemo` shows every component over a scrolling picture.

```sh
cd Examples/GlassifyDemo && xcodegen generate && open GlassifyDemo.xcodeproj
# or with Bazel:
bazel build //Examples/GlassifyDemo:GlassifyDemo --ios_multi_cpus=sim_arm64
```

## Repository layout

```
Sources/Glassify/include/Glassify   public headers
Sources/Glassify/Core               C++17 core: glass parameters, colour matrices, springs
Sources/Glassify/Platform           UIKit layer: views, controls, Metal renderer, backdrop capture
Sources/Glassify/Shaders            Metal shaders
Tests/Core                          unit tests of the core (CMake or `bazel test //:core_tests`)
Examples/GlassifyDemo               example app
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
