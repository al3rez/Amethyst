//
//  LayoutNameWindow.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 5/15/16.
//  Copyright © 2016 Ian Ynda-Hummel. All rights reserved.
//

import Cocoa
import Foundation
import QuartzCore

class LayoutNameWindow: NSWindow {
    @IBOutlet weak var layoutNameField: NSTextField?
    @IBOutlet weak var layoutDescriptionLabel: NSTextField?
    private var effectView: NSVisualEffectView?

    @IBOutlet override var contentView: NSView? {
        didSet {
            contentView?.wantsLayer = true
            contentView?.layer?.frame = NSRectToCGRect(contentView!.frame)
            contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    @IBOutlet var containerView: NSView?

    override func awakeFromNib() {
        super.awakeFromNib()

        isOpaque = false
        ignoresMouseEvents = true
        backgroundColor = NSColor.clear
        level = .floating

        setUpVisualEffect()
        applyTahoeTypography()
    }

    func animateIn() {
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: completion)
    }

    private func setUpVisualEffect() {
        guard let contentView = contentView else { return }

        effectView?.removeFromSuperview()

        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true

        contentView.addSubview(visualEffect, positioned: .below, relativeTo: containerView)
        effectView = visualEffect
    }

    private func applyTahoeTypography() {
        if let nameField = layoutNameField {
            nameField.textColor = NSColor.labelColor
            nameField.font = roundedSystemFont(ofSize: 20, weight: .semibold)
        }

        if let descriptionField = layoutDescriptionLabel {
            descriptionField.textColor = NSColor.secondaryLabelColor
            descriptionField.font = roundedSystemFont(ofSize: 12, weight: .regular)
        }
    }

    private func roundedSystemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = baseFont.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? baseFont
        }
        return baseFont
    }

    // Display custom notification with dynamic sizing
    func displayNotification(title: String, description: String) {
        // layoutDescriptionLabel?.isHidden = false
        layoutNameField?.stringValue = title
        layoutDescriptionLabel?.stringValue = description

        // Calculate size needed for both name and description
        let longerText = title.count > description.count ? title : description
        resizeToFitText(text: longerText)
    }

    // Dynamic window resizing based on text content
    private func resizeToFitText(text: String) {
        guard let textField = layoutNameField else { return }

        // Calculate text width with current font
        let font = textField.font ?? NSFont.systemFont(ofSize: 20)
        let textSize = text.size(withAttributes: [.font: font])

        // Add padding (40px on each side + extra space)
        let minWidth: CGFloat = 200
        let maxWidth: CGFloat = 500
        let padding: CGFloat = 80
        let calculatedWidth = textSize.width + padding

        // Constrain width between min and max
        let newWidth = max(minWidth, min(maxWidth, calculatedWidth))

        // Keep the same height
        let currentFrame = frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y,
            width: newWidth,
            height: currentFrame.height
        )

        setFrame(newFrame, display: true, animate: false)

        // Update content view layer frame
        contentView?.layer?.frame = NSRectToCGRect(contentView!.frame)
        effectView?.frame = contentView!.bounds
    }
}
