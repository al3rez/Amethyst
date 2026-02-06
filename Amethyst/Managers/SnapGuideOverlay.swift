//
//  SnapGuideOverlay.swift
//  Amethyst
//
//  Created for macOS 26 compatibility improvements
//  Shows visual guides when dragging windows to indicate drop targets
//

import Cocoa
import Foundation
import SwiftyBeaver

/// Grid zone for snap guides
enum SnapZone: Equatable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// Calculate the frame for this zone on the given screen
    func frame(on screenFrame: CGRect) -> CGRect {
        let halfWidth = screenFrame.width / 2
        let halfHeight = screenFrame.height / 2

        switch self {
        case .left:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
        case .right:
            return CGRect(x: screenFrame.midX, y: screenFrame.minY, width: halfWidth, height: screenFrame.height)
        case .top:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: halfHeight)
        case .bottom:
            return CGRect(x: screenFrame.minX, y: screenFrame.midY, width: screenFrame.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: screenFrame.midX, y: screenFrame.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: screenFrame.minX, y: screenFrame.midY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: screenFrame.midX, y: screenFrame.midY, width: halfWidth, height: halfHeight)
        }
    }

    /// Determine which zone contains the given point (in top-left origin coordinates)
    static func zone(for point: CGPoint, in screenFrame: CGRect, mode: SnapGuideMode) -> SnapZone {
        let isLeft = point.x < screenFrame.midX
        let isTop = point.y < screenFrame.midY

        switch mode {
        case .quadrants:
            if isLeft {
                return isTop ? .topLeft : .bottomLeft
            } else {
                return isTop ? .topRight : .bottomRight
            }
        case .halvesVertical:
            return isLeft ? .left : .right
        case .halvesHorizontal:
            return isTop ? .top : .bottom
        }
    }
}

enum SnapGuideMode {
    case quadrants
    case halvesVertical
    case halvesHorizontal
}

/// Overlay window that shows where a dragged window will be placed
class SnapGuideOverlay {
    private var overlayWindow: NSWindow?
    private var currentZone: SnapZone?
    private var currentScreenFrame: CGRect = .zero
    private var isVisible = false

    /// Shared instance for global access
    static let shared = SnapGuideOverlay()

    private init() {}

    /// Shows a grid-based snap guide at the mouse position
    /// - Parameters:
    ///   - mouseLocation: Mouse position in top-left origin screen coordinates
    ///   - screenFrame: The usable frame of the screen (excluding dock/menu)
    ///   - mode: Guide style to display
    func showGrid(at mouseLocation: CGPoint, screenFrame: CGRect, mode: SnapGuideMode = .quadrants) {
        guard UserConfiguration.shared.enableSnapGuides() else {
            return
        }

        let zone = SnapZone.zone(for: mouseLocation, in: screenFrame, mode: mode)

        // Skip if zone hasn't changed (avoid re-rendering)
        if isVisible && currentZone == zone && currentScreenFrame.equalTo(screenFrame) {
            return
        }

        currentZone = zone
        currentScreenFrame = screenFrame

        let zoneFrame = applyWindowAdjustments(
            to: zone.frame(on: screenFrame),
            screenFrame: screenFrame,
            disableWindowMargins: false
        )

        // Find the screen for coordinate conversion
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(zoneFrame) }) ?? NSScreen.main else {
            return
        }

        // Convert from top-left origin to bottom-left origin (Cocoa coordinates)
        let globalHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? screen.frame.maxY
        let flippedY = globalHeight - zoneFrame.origin.y - zoneFrame.height
        let overlayFrame = NSRect(
            x: zoneFrame.origin.x,
            y: flippedY,
            width: zoneFrame.width,
            height: zoneFrame.height
        )

        // Reuse existing window or create new one
        if let window = overlayWindow {
            window.setFrame(overlayFrame, display: true)
            if !isVisible {
                window.orderFrontRegardless()
            }
        } else {
            let window = createOverlayWindow(frame: overlayFrame)
            window.orderFrontRegardless()
            overlayWindow = window
        }
        isVisible = true
    }

    /// Shows a highlight overlay at the given frame (legacy method for swap targets)
    func show(at frame: CGRect) {
        guard UserConfiguration.shared.enableSnapGuides() else {
            return
        }

        // Find the screen that contains this frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            return
        }

        // Convert from top-left origin to bottom-left origin (Cocoa coordinates)
        let globalHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? screen.frame.maxY
        let flippedY = globalHeight - frame.origin.y - frame.height
        let overlayFrame = NSRect(
            x: frame.origin.x,
            y: flippedY,
            width: frame.width,
            height: frame.height
        )

        // Reuse existing window or create new one
        if let window = overlayWindow {
            window.setFrame(overlayFrame, display: true)
            if !isVisible {
                window.orderFrontRegardless()
            }
        } else {
            let window = createOverlayWindow(frame: overlayFrame)
            window.orderFrontRegardless()
            overlayWindow = window
        }
        isVisible = true
    }

    /// Hides the overlay window
    func hide() {
        overlayWindow?.orderOut(nil)
        isVisible = false
        currentZone = nil
        currentScreenFrame = .zero
    }

    /// Creates a transparent overlay window with a highlight border
    private func createOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let contentView = SnapGuideView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = contentView

        return window
    }

    /// Returns the current snap zone (for use when dropping)
    func currentSnapZone() -> SnapZone? {
        return currentZone
    }
}

/// Custom view that draws the snap guide highlight
class SnapGuideView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw semi-transparent fill
        let fillColor = NSColor.systemBlue.withAlphaComponent(0.15)
        fillColor.setFill()
        let cornerRadius: CGFloat = 14
        let fillPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        fillPath.fill()

        // Draw border
        let borderColor = NSColor.systemBlue.withAlphaComponent(0.6)
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
}
