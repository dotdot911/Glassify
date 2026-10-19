//
//  ShowcasePage.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

// Rows are direct subviews of the page's view, so glass that snapshots its superview sees the artwork.
class ShowcasePage: UIViewController {
    let background = ArtworkScrollView()
    private var rows: [(caption: UILabel, height: CGFloat, views: [UIView])] = []
    private let hint = ShowcasePage.makeCaption("Scroll the background to move it under the glass")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        background.frame = view.bounds
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(background)
        view.addSubview(hint)
    }

    func addRow(_ caption: String, height: CGFloat, _ views: [UIView]) {
        loadViewIfNeeded()
        let label = ShowcasePage.makeCaption(caption)
        view.addSubview(label)
        for v in views {
            view.addSubview(v)
            follow(background, with: v)
        }
        rows.append((label, height, views))
        view.setNeedsLayout()
    }

    func follow(_ source: UIView, with view: UIView) {
        switch view {
        case let glass as GLSGlassView:
            glass.backdropSourceView = source
            glass.tracksBackdropMotion = true
        case let container as GLSGlassContainerView:
            container.backdropSourceView = source
            container.tracksBackdropMotion = true
        case let button as GLSGlassButton:
            button.backdropSourceView = source
            button.tracksBackdropMotion = true
        case let segmented as GLSSegmentedControl:
            segmented.backdropSourceView = source
        default:
            break
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        var y = view.safeAreaInsets.top + 12
        let hintSize = hint.sizeThatFits(CGSize(width: width, height: 20))
        hint.frame = CGRect(x: (width - hintSize.width - 16) / 2, y: y, width: hintSize.width + 16, height: 22)
        y += 34
        for row in rows {
            let size = row.caption.sizeThatFits(CGSize(width: width, height: 20))
            row.caption.frame = CGRect(x: (width - size.width - 16) / 2, y: y, width: size.width + 16, height: 22)
            y += 28
            let spacing: CGFloat = 12
            let total = row.views.reduce(0) { $0 + $1.bounds.width } + spacing * CGFloat(row.views.count - 1)
            var x = (width - total) / 2
            for v in row.views {
                v.center = CGPoint(x: x + v.bounds.width / 2, y: y + row.height / 2)
                x += v.bounds.width + spacing
            }
            y += row.height + 14
        }
    }

    static func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.textColor = .label
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        label.layer.cornerRadius = 11
        label.clipsToBounds = true
        return label
    }
}
