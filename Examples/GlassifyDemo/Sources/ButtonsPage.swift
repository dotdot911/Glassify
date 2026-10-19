//
//  ButtonsPage.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

final class ButtonsPage: ShowcasePage {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glass Buttons"
        let styles: [(String, GLSGlassButtonStyle)] = [("Glass", .glass), ("Prominent glass", .prominentGlass),
                                                      ("Clear glass", .clearGlass), ("Prominent clear glass", .prominentClearGlass)]
        for (name, style) in styles {
            let sizes: [GLSGlassButtonSize] = [.small, .medium, .large]
            let buttons = sizes.map { button(style, size: $0, title: ["Small", "Medium", "Large"][$0.rawValue]) }
            addRow(name, height: buttons.map(\.bounds.height).max() ?? 44, buttons)
        }
        let icons = [button(.glass, title: nil, image: "heart.fill"), button(.prominentGlass, title: nil, image: "plus"),
                     button(.glass, title: "Share", image: "square.and.arrow.up")]
        addRow("Images", height: icons.map(\.bounds.height).max() ?? 44, icons)
        let disabled = button(.prominentGlass, title: "Disabled")
        disabled.isEnabled = false
        addRow("Disabled", height: disabled.bounds.height, [disabled])
    }

    private func button(_ style: GLSGlassButtonStyle, size: GLSGlassButtonSize = .medium, title: String?,
                        image: String? = nil) -> GLSGlassButton {
        let b = GLSGlassButton(style: style)
        b.size = size
        b.setTitle(title, for: .normal)
        if let image = image { b.setImage(UIImage(systemName: image), for: .normal) }
        b.sizeToFit()
        return b
    }
}
