//
//  BarsPage.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

final class BarsPage: UITableViewController {
    private let items = (1...60).map { "Item \($0)" }
    private let symbols = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "flame.fill", "drop.fill"]
    private let colors: [UIColor] = [.systemOrange, .systemPink, .systemTeal, .systemIndigo, .systemGreen, .systemPurple]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bars"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Select", style: .plain, target: self,
                                                            action: #selector(toggleEditing))
        toolbarItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: nil, action: nil),
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    @objc private func toggleEditing() {
        setEditing(!isEditing, animated: true)
        navigationItem.rightBarButtonItem?.title = isEditing ? "Done" : "Select"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        cell.imageView?.image = UIImage(systemName: symbols[indexPath.row % symbols.count])
        cell.imageView?.tintColor = colors[indexPath.row % colors.count]
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let detail = DetailPage()
        detail.title = items[indexPath.row]
        navigationController?.pushViewController(detail, animated: true)
    }
}

final class DetailPage: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let background = ArtworkScrollView(frame: view.bounds)
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(background)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain,
                                                            target: nil, action: nil)
    }
}
