//
//  Components.swift
//  Comparison
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import UIKit
#if GLASSIFY
import Glassify
#endif

// The same screen is built twice: with UIKit's iOS 26 classes, and with Glassify when GLASSIFY is set.
enum Components {
    static func tabBarController() -> UITabBarController {
        #if GLASSIFY
        return GLSTabBarController()
        #else
        return UITabBarController()
        #endif
    }

    static func navigationController(root: UIViewController) -> UINavigationController {
        #if GLASSIFY
        return GLSNavigationController(rootViewController: root)
        #else
        return UINavigationController(rootViewController: root)
        #endif
    }

    static func glassCard(size: CGSize, content: UIView) -> UIView {
        #if GLASSIFY
        let glass = GLSGlassView(frame: CGRect(origin: .zero, size: size))
        glass.style = .clear
        glass.cornerRadius = 28
        content.frame = glass.contentView.bounds
        glass.contentView.addSubview(content)
        return glass
        #else
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
        glass.frame = CGRect(origin: .zero, size: size)
        glass.cornerConfiguration = .uniformCorners(radius: 28)
        content.frame = glass.contentView.bounds
        glass.contentView.addSubview(content)
        return glass
        #endif
    }

    static func glassButton(title: String?, image: String? = nil) -> UIControl {
        #if GLASSIFY
        let button = GLSGlassButton(style: .clearGlass)
        button.setTitle(title, for: .normal)
        if let image = image { button.setImage(UIImage(systemName: image), for: .normal) }
        button.size = .large
        button.sizeToFit()
        return button
        #else
        var configuration: UIButton.Configuration = .clearGlass()
        configuration.title = title
        if let image = image { configuration.image = UIImage(systemName: image) }
        configuration.buttonSize = .large
        let button = UIButton(configuration: configuration)
        button.sizeToFit()
        return button
        #endif
    }

    // Glassify snapshots the view behind the glass; a scroll view has to be named so the glass follows it.
    static func follow(_ scrollView: UIScrollView, with view: UIView) {
        #if GLASSIFY
        switch view {
        case let glass as GLSGlassView:
            glass.backdropSourceView = scrollView
            glass.tracksBackdropMotion = true
        case let button as GLSGlassButton:
            button.backdropSourceView = scrollView
            button.tracksBackdropMotion = true
        default:
            view.subviews.forEach { follow(scrollView, with: $0) }
        }
        #endif
    }

    static func toggle(on: Bool) -> UIControl {
        #if GLASSIFY
        let toggle = GLSSwitch()
        #else
        let toggle = UISwitch()
        #endif
        toggle.isOn = on
        toggle.sizeToFit()
        return toggle
    }

    static func slider(width: CGFloat, value: Float) -> UIControl {
        #if GLASSIFY
        let slider = GLSSlider(frame: CGRect(x: 0, y: 0, width: width, height: 34))
        #else
        let slider = UISlider(frame: CGRect(x: 0, y: 0, width: width, height: 34))
        #endif
        slider.value = value
        return slider
    }

    static func segmentedControl(items: [String]) -> UIControl {
        #if GLASSIFY
        let control = GLSSegmentedControl(items: items)
        #else
        let control = UISegmentedControl(items: items)
        #endif
        control.selectedSegmentIndex = 0
        control.sizeToFit()
        return control
    }
}
