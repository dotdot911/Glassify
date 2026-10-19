//
//  Artwork.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import UIKit

// Drawn in standard-range sRGB: an extended-range image would not show up in the glass snapshot.
enum Artwork {
    private static var cache: (width: CGFloat, image: UIImage)?

    static func image(width: CGFloat) -> UIImage {
        if let cache = cache, cache.width == width { return cache.image }
        let section: CGFloat = 520
        let size = CGSize(width: width, height: section * 5)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 2
        format.opaque = true
        if #available(iOS 12.0, *) { format.preferredRange = .standard }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(in: context.cgContext, width: width, section: section)
        }
        cache = (width, image)
        return image
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    private static func draw(in ctx: CGContext, width: CGFloat, section: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        func linear(_ rect: CGRect, _ colors: [UIColor], from a: CGPoint, to b: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        func radial(_ center: CGPoint, _ radius: CGFloat, _ color: UIColor) {
            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: nil) else { return }
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        var y: CGFloat = 0
        linear(CGRect(x: 0, y: y, width: width, height: section),
               [rgb(46, 49, 146), rgb(214, 87, 120), rgb(255, 170, 90), rgb(255, 222, 150)],
               from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + section * 0.75))
        let sun = CGPoint(x: width * 0.62, y: y + section * 0.55)
        radial(sun, 160, rgb(255, 245, 210).withAlphaComponent(0.9))
        rgb(255, 250, 230).setFill()
        ctx.fillEllipse(in: CGRect(x: sun.x - 42, y: sun.y - 42, width: 84, height: 84))
        for (color, level, peaks) in [(rgb(120, 70, 120), 0.58, 9), (rgb(70, 45, 95), 0.7, 6), (rgb(35, 28, 60), 0.83, 4)] {
            let path = UIBezierPath()
            let base = y + section * CGFloat(level)
            path.move(to: CGPoint(x: 0, y: y + section))
            for i in 0...(peaks * 2) {
                let x = width * CGFloat(i) / CGFloat(peaks * 2)
                let h = i % 2 == 1 ? 70 + 40 * sin(Double(i) * 1.7 + Double(peaks)) : 10 * cos(Double(i) * 2.3)
                path.addLine(to: CGPoint(x: x, y: base - CGFloat(h)))
            }
            path.addLine(to: CGPoint(x: width, y: y + section))
            path.close()
            color.setFill()
            path.fill()
        }

        y += section
        rgb(250, 248, 243).setFill()
        ctx.fill(CGRect(x: 0, y: y, width: width, height: section))
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34, weight: .bold),
                                                    .foregroundColor: rgb(20, 20, 24)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: rgb(50, 50, 56)]
        ("Liquid Glass" as NSString).draw(in: CGRect(x: 20, y: y + 30, width: width - 40, height: 44), withAttributes: title)
        let text = "Glass bends the light of whatever lies behind it: text, photos, colour. Scroll the page " +
            "to watch the backdrop slide under the components. The quick brown fox jumps over the lazy dog. 0123456789."
        (text as NSString).draw(in: CGRect(x: 20, y: y + 90, width: width - 40, height: 200), withAttributes: body)
        let swatches: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue,
                                   .systemIndigo, .systemPink]
        let swatchWidth = (width - 40) / CGFloat(swatches.count)
        for (i, color) in swatches.enumerated() {
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 20 + CGFloat(i) * swatchWidth + 2, y: y + 320, width: swatchWidth - 4, height: 120),
                         cornerRadius: 10).fill()
        }

        y += section
        linear(CGRect(x: 0, y: y, width: width, height: section), [rgb(150, 215, 245), rgb(30, 130, 200), rgb(6, 50, 110)],
               from: CGPoint(x: 0, y: y), to: CGPoint(x: 0, y: y + section))
        for k in 0..<14 {
            let path = UIBezierPath()
            let base = y + 40 + CGFloat(k) * 36
            path.move(to: CGPoint(x: 0, y: base))
            for x in stride(from: CGFloat(0), through: width, by: 6) {
                path.addLine(to: CGPoint(x: x, y: base + 8 * CGFloat(sin(Double(x) / 28 + Double(k)))))
            }
            path.lineWidth = 3
            UIColor(white: 1, alpha: 0.25 + 0.03 * CGFloat(k)).setStroke()
            path.stroke()
        }

        y += section
        rgb(18, 18, 28).setFill()
        ctx.fill(CGRect(x: 0, y: y, width: width, height: section))
        let blobs = [rgb(255, 60, 120), rgb(60, 200, 255), rgb(255, 210, 60), rgb(130, 90, 255), rgb(60, 255, 160)]
        for i in 0..<9 {
            let fx = (Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let fy = (Double(i) * 0.61).truncatingRemainder(dividingBy: 1)
            radial(CGPoint(x: width * CGFloat(0.15 + 0.7 * fx), y: y + section * CGFloat(0.1 + 0.8 * fy)),
                   CGFloat(90 + 30 * (i % 3)), blobs[i % blobs.count])
        }

        y += section
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: y, width: width, height: section))
        let names = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "drop.fill", "moon.fill",
                     "sun.max.fill", "cloud.fill", "camera.fill", "music.note", "paperplane.fill"]
        let columns = 4
        let cell = width / CGFloat(columns)
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        for i in 0..<16 {
            guard let symbol = UIImage(systemName: names[i % names.count], withConfiguration: config)?
                .withTintColor(swatches[i % swatches.count]) else { continue }
            let rect = CGRect(x: CGFloat(i % columns) * cell + (cell - symbol.size.width) / 2,
                              y: y + 30 + CGFloat(i / columns) * 120 + (60 - symbol.size.height) / 2,
                              width: symbol.size.width, height: symbol.size.height)
            symbol.draw(in: rect)
        }
    }
}

// Draws in `draw(_:)` so the glass snapshot, which uses `-renderInContext:`, sees it.
final class ArtworkView: UIView {
    var image: UIImage? { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) { image?.draw(in: bounds) }
}

final class ArtworkScrollView: UIScrollView {
    private var tiles: [ArtworkView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        alwaysBounceVertical = true
        contentInsetAdjustmentBehavior = .never
        showsVerticalScrollIndicator = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, tiles.first?.bounds.width != width else { return }
        tiles.forEach { $0.removeFromSuperview() }
        let image = Artwork.image(width: width)
        tiles = (0..<2).map { i in
            let tile = ArtworkView(frame: CGRect(x: 0, y: CGFloat(i) * image.size.height, width: width, height: image.size.height))
            tile.image = image
            tile.isOpaque = true
            insertSubview(tile, at: 0)
            return tile
        }
        contentSize = CGSize(width: width, height: 2 * image.size.height)
    }
}
