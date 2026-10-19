//
//  CatalogViewController.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

final class CatalogViewController: UITableViewController {
    private let pages: [(title: String, subtitle: String, make: () -> UIViewController)] = [
        ("Glass", "Regular, clear, tinted, interactive, containers", { GlassPage() }),
        ("Glass Buttons", "Four styles, three sizes", { ButtonsPage() }),
        ("Controls", "Switch, slider, segmented control", { ControlsPage() }),
        ("Bars", "Navigation bar and toolbar over a list", { BarsPage() }),
    ]

    init() {
        super.init(style: .insetGrouped)
        title = "Glassify"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // In DEBUG, `-page N` opens page N at launch for screenshots.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        let page = UserDefaults.standard.integer(forKey: "page")
        if UserDefaults.standard.object(forKey: "page") != nil, pages.indices.contains(page), !openedAtLaunch {
            openedAtLaunch = true
            navigationController?.pushViewController(pages[page].make(), animated: false)
        }
        #endif
    }

    #if DEBUG
    private var openedAtLaunch = false
    #endif

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { pages.count }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "iOS 26 Liquid Glass, rendered with Metal on iOS 13 and later."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "page")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "page")
        cell.textLabel?.text = pages[indexPath.row].title
        cell.detailTextLabel?.text = pages[indexPath.row].subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(pages[indexPath.row].make(), animated: true)
    }
}
