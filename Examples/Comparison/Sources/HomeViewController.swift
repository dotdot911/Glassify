//
//  HomeViewController.swift
//  Comparison
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import UIKit

final class HomeViewController: UIViewController {
    private let background = ArtworkScrollView()
    private var components: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Home"
        view.backgroundColor = .black
        view.addSubview(background)

        let text = UILabel()
        text.text = "Clear glass over a scrolling picture."
        text.font = .systemFont(ofSize: 17, weight: .semibold)
        text.textAlignment = .center
        text.numberOfLines = 0
        components = [
            Components.glassCard(size: CGSize(width: 300, height: 110), content: text),
            row([Components.glassButton(title: "Clear glass"), Components.glassButton(title: nil, image: "heart.fill")]),
            row([Components.toggle(on: true), Components.toggle(on: false)]),
            Components.slider(width: 300, value: 0.4),
            Components.segmentedControl(items: ["Day", "Week", "Month"]),
        ]
        for v in components {
            view.addSubview(v)
            Components.follow(background, with: v)
        }
    }

    private func row(_ views: [UIView]) -> UIView {
        let spacing: CGFloat = 16
        let width = views.reduce(0) { $0 + $1.bounds.width } + spacing * CGFloat(views.count - 1)
        let height = views.map(\.bounds.height).max() ?? 0
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        var x: CGFloat = 0
        for v in views {
            v.frame.origin = CGPoint(x: x, y: (height - v.bounds.height) / 2)
            holder.addSubview(v)
            x += v.bounds.width + spacing
        }
        return holder
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame = view.bounds
        let width = view.bounds.width
        let top = view.safeAreaInsets.top + 24
        let bottom = view.bounds.height - view.safeAreaInsets.bottom - 24
        let total = components.reduce(0) { $0 + $1.bounds.height }
        let gap = max((bottom - top - total) / CGFloat(max(components.count - 1, 1)), 16)
        var y = top
        for v in components {
            v.center = CGPoint(x: width / 2, y: y + v.bounds.height / 2)
            y += v.bounds.height + gap
        }
    }
}

// A Phone-style recents list: avatar, name and detail on the left, date and a round call button on the right.
final class ListViewController: UITableViewController {
    struct Entry {
        let name: String
        let detail: String
        let outgoing: Bool
        let date: String
        let action: String
        let missed: Bool
    }

    private let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"),
                                                            style: .plain, target: nil, action: nil)
        tableView.register(RecentCell.self, forCellReuseIdentifier: "cell")
        tableView.rowHeight = 97
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 98, bottom: 0, right: 0)
        let header = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
        header.text = "Recents"
        header.font = .systemFont(ofSize: 22, weight: .bold)
        let holder = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 52))
        header.frame = CGRect(x: 20, y: 12, width: 300, height: 34)
        holder.addSubview(header)
        tableView.tableHeaderView = holder
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count * 4 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! RecentCell
        cell.configure(entries[indexPath.row % entries.count], index: indexPath.row)
        return cell
    }
}

final class RecentCell: UITableViewCell {
    private let avatar = UIView()
    private let initials = UILabel()
    private let name = UILabel()
    private let detail = UILabel()
    private let date = UILabel()
    private let call = UIButton(type: .system)
    private let palette: [(UIColor, UIColor)] = [
        (UIColor(red: 0.62, green: 0.66, blue: 0.82, alpha: 1), UIColor(red: 0.45, green: 0.50, blue: 0.70, alpha: 1)),
        (UIColor(red: 0.98, green: 0.64, blue: 0.45, alpha: 1), UIColor(red: 0.93, green: 0.40, blue: 0.33, alpha: 1)),
        (UIColor(red: 0.47, green: 0.85, blue: 0.68, alpha: 1), UIColor(red: 0.18, green: 0.62, blue: 0.45, alpha: 1)),
        (UIColor(red: 0.80, green: 0.60, blue: 0.95, alpha: 1), UIColor(red: 0.56, green: 0.36, blue: 0.84, alpha: 1)),
    ]
    private let gradient = CAGradientLayer()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatar.layer.cornerRadius = 32
        avatar.clipsToBounds = true
        avatar.layer.addSublayer(gradient)
        initials.font = .systemFont(ofSize: 24, weight: .semibold)
        initials.textColor = .white
        initials.textAlignment = .center
        avatar.addSubview(initials)
        name.font = .systemFont(ofSize: 17, weight: .semibold)
        name.numberOfLines = 2
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabel
        date.font = .systemFont(ofSize: 15)
        date.textColor = .secondaryLabel
        date.textAlignment = .right
        call.backgroundColor = .secondarySystemBackground
        call.layer.cornerRadius = 24
        call.tintColor = .systemBlue
        [avatar, name, detail, date, call].forEach(contentView.addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ entry: ListViewController.Entry, index: Int) {
        let colors = palette[index % palette.count]
        gradient.colors = [colors.0.cgColor, colors.1.cgColor]
        initials.text = String(entry.name.split(separator: " ").compactMap(\.first).prefix(2))
        name.text = entry.name
        name.textColor = entry.missed ? .systemRed : .label
        detail.text = (entry.outgoing ? "\u{2197} " : "\u{2199} ") + entry.detail
        date.text = entry.date
        call.setImage(UIImage(systemName: entry.action), for: .normal)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = contentView.bounds.height, w = contentView.bounds.width
        avatar.frame = CGRect(x: 20, y: (h - 64) / 2, width: 64, height: 64)
        gradient.frame = avatar.bounds
        initials.frame = avatar.bounds
        call.frame = CGRect(x: w - 20 - 48, y: (h - 48) / 2, width: 48, height: 48)
        let dateWidth: CGFloat = 86
        date.frame = CGRect(x: call.frame.minX - 12 - dateWidth, y: (h - 20) / 2, width: dateWidth, height: 20)
        let textX: CGFloat = 98, textWidth = date.frame.minX - 8 - textX
        let nameHeight = min(name.sizeThatFits(CGSize(width: textWidth, height: 60)).height, 44)
        let total = nameHeight + 4 + 20
        name.frame = CGRect(x: textX, y: (h - total) / 2, width: textWidth, height: nameHeight)
        detail.frame = CGRect(x: textX, y: name.frame.maxY + 4, width: textWidth, height: 20)
    }
}
