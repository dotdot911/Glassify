//
//  GlassPage.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

final class GlassPage: ShowcasePage {
    private var circles: [GLSGlassView] = []
    private var apart = false
    private var panel: GLSGlassView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Glass"

        addRow("Regular · Clear · Tinted", height: 52, [
            glass(CGSize(width: 104, height: 50), text: "Regular"),
            glass(CGSize(width: 104, height: 50), text: "Clear") { $0.style = .clear },
            glass(CGSize(width: 104, height: 50), text: "Tinted") { $0.glassTintColor = UIColor.systemBlue.withAlphaComponent(0.6) },
        ])

        let container = GLSGlassContainerView(frame: CGRect(x: 0, y: 0, width: 220, height: 72))
        container.spacing = 20
        for i in 0..<2 {
            let circle = GLSGlassView(frame: CGRect(x: 52 + CGFloat(i) * 52, y: 8, width: 64, height: 64))
            container.addSubview(circle)
            circles.append(circle)
        }
        container.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleMerge)))
        addRow("Container: tap to split and merge", height: 80, [container])

        addRow("Interactive: press and drag", height: 56, [
            glass(CGSize(width: 180, height: 56), text: "Press me") { $0.isInteractive = true },
        ])

        let panel = glass(CGSize(width: 320, height: 120), text: nil) { $0.cornerRadius = 28 }
        let stack = UIStackView(arrangedSubviews: [
            label("Glass panel", size: 22, weight: .bold),
            label("Content on the glass is tinted like UIGlassEffect's: black in light mode, white in dark mode.",
                  size: 15, weight: .regular),
        ])
        stack.axis = .vertical
        stack.spacing = 4
        stack.frame = panel.contentView.bounds.insetBy(dx: 18, dy: 16)
        stack.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.contentView.addSubview(stack)
        self.panel = panel
        addRow("Panel with content", height: 120, [panel])

        let materialize = GLSGlassButton(style: .glass)
        materialize.setTitle("Hide / show the panel glass", for: .normal)
        materialize.sizeToFit()
        materialize.addTarget(self, action: #selector(toggleGlass), for: .primaryActionTriggered)
        addRow("Materialize", height: materialize.bounds.height, [materialize])

    }

    private func glass(_ size: CGSize, text: String?, configure: (GLSGlassView) -> Void = { _ in }) -> GLSGlassView {
        let glass = GLSGlassView(frame: CGRect(origin: .zero, size: size))
        configure(glass)
        if let text = text {
            let l = label(text, size: 17, weight: .semibold)
            l.textAlignment = .center
            l.frame = glass.contentView.bounds
            l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glass.contentView.addSubview(l)
        }
        return glass
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = .label
        l.numberOfLines = 0
        return l
    }

    @objc private func toggleGlass() {
        guard let panel = panel else { return }
        UIView.animate(withDuration: 0.5) { panel.isGlassEnabled.toggle() }
    }

    @objc private func toggleMerge() {
        apart.toggle()
        let d: CGFloat = apart ? 40 : 0
        GLSAnimateWithSpring(0.75, 0.6, {
            self.circles[0].transform = CGAffineTransform(translationX: -d, y: 0)
            self.circles[1].transform = CGAffineTransform(translationX: d, y: 0)
        }, nil)
    }
}
