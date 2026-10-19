//
//  ControlsPage.swift
//  GlassifyDemo
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

import Glassify
import UIKit

final class ControlsPage: ShowcasePage {
    private let valueLabel = ShowcasePage.makeCaption("")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Controls"

        let off = GLSSwitch()
        let on = GLSSwitch()
        on.isOn = true
        let orange = GLSSwitch()
        orange.isOn = true
        orange.onTintColor = .systemOrange
        [off, on, orange].forEach { $0.sizeToFit() }
        addRow("Switch", height: 31, [off, on, orange])

        let slider = GLSSlider(frame: CGRect(x: 0, y: 0, width: 300, height: 34))
        slider.value = 0.4
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        addRow("Slider", height: 34, [slider])
        sliderChanged(slider)
        valueLabel.bounds.size = CGSize(width: 90, height: 22)
        addRow("Value", height: 22, [valueLabel])

        let volume = GLSSlider(frame: CGRect(x: 0, y: 0, width: 320, height: 34))
        volume.minimumValueImage = UIImage(systemName: "speaker.fill")
        volume.maximumValueImage = UIImage(systemName: "speaker.wave.3.fill")
        volume.minimumTrackTintColor = .systemPink
        volume.value = 0.7
        addRow("Slider with images and a custom tint", height: 34, [volume])

        let two = GLSSegmentedControl(items: ["Day", "Week"])
        two.selectedSegmentIndex = 0
        two.sizeToFit()
        let three = GLSSegmentedControl(items: ["First", "Second", "Third"])
        three.selectedSegmentIndex = 1
        three.sizeToFit()
        addRow("Segmented control: tap, or drag the selection", height: two.bounds.height, [two])
        addRow("Three segments", height: three.bounds.height, [three])
    }

    @objc private func sliderChanged(_ slider: GLSSlider) {
        valueLabel.text = String(format: "%.2f", slider.value)
    }
}
