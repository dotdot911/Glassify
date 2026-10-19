//
//  AppDelegate.swift
//  Comparison
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let home = Components.navigationController(root: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house.fill"), tag: 0)
        let library = Components.navigationController(root: page(ListViewController(entries: Self.libraryEntries), title: "Library"))
        library.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "square.stack.fill"), tag: 1)
        let settings = Components.navigationController(root: page(ListViewController(entries: Self.settingsEntries), title: "Settings"))
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape.fill"), tag: 2)
        let tabs = Components.tabBarController()
        tabs.viewControllers = [home, library, settings]

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    private static let libraryEntries: [ListViewController.Entry] = [
        .init(name: "Mia Chen", detail: "FaceTime Video (3)", outgoing: true, date: "Yesterday", action: "video.fill", missed: false),
        .init(name: "Bach Nguyen", detail: "Mobile", outgoing: false, date: "Yesterday", action: "video.fill", missed: false),
        .init(name: "Linh Tran - Driver on the airport run", detail: "WhatsApp Audio", outgoing: false, date: "Yesterday", action: "phone.fill", missed: false),
        .init(name: "Phong Le", detail: "Messenger Audio", outgoing: false, date: "Yesterday", action: "phone.fill", missed: true),
        .init(name: "Ana Souza", detail: "FaceTime Video", outgoing: false, date: "Monday", action: "video.fill", missed: false),
        .init(name: "Kenji Sato", detail: "Mobile", outgoing: true, date: "Monday", action: "phone.fill", missed: false),
    ]

    private static let settingsEntries: [ListViewController.Entry] = [
        .init(name: "Home", detail: "Mobile", outgoing: true, date: "10:24", action: "phone.fill", missed: false),
        .init(name: "Office Front Desk", detail: "Work", outgoing: false, date: "09:02", action: "phone.fill", missed: true),
        .init(name: "Sara Ivanova", detail: "FaceTime Audio", outgoing: false, date: "Yesterday", action: "phone.fill", missed: false),
        .init(name: "Tom Becker", detail: "FaceTime Video (2)", outgoing: true, date: "Yesterday", action: "video.fill", missed: false),
        .init(name: "Delivery", detail: "Unknown", outgoing: false, date: "Sunday", action: "phone.fill", missed: true),
    ]

    private func page(_ controller: UIViewController, title: String) -> UIViewController {
        controller.title = title
        return controller
    }
}
