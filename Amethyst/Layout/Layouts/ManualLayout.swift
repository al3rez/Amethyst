//
//  ManualLayout.swift
//  Amethyst
//
//  i3-style manual tiling layout with split support
//

import CoreGraphics
import Foundation

/// i3-style manual tiling layout - drops windows to grid zones
class ManualLayout<Window: WindowType>: Layout<Window> {
    override static var layoutName: String { return "Manual" }
    override static var layoutKey: String { return "manual" }

    override var layoutDescription: String { return "i3-style manual tiling" }

    required init() {
        super.init()
    }

    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    override func frameAssignments(_ windowSet: WindowSet<Window>, on screen: Screen) -> [FrameAssignmentOperation<Window>]? {
        let windows = windowSet.windows
        guard !windows.isEmpty else { return [] }

        let screenFrame = screen.adjustedFrame()

        // For now, use simple tall layout as base
        // Windows will be manually positioned when dropped to zones
        let mainWidth = screenFrame.width * 0.5
        var assignments: [FrameAssignmentOperation<Window>] = []

        for (index, window) in windows.enumerated() {
            let frame: CGRect
            if index == 0 {
                // Main window takes left half
                frame = CGRect(x: screenFrame.minX, y: screenFrame.minY, width: mainWidth, height: screenFrame.height)
            } else {
                // Secondary windows stack on right
                let secondaryCount = windows.count - 1
                let secondaryHeight = screenFrame.height / CGFloat(secondaryCount)
                let secondaryY = screenFrame.minY + CGFloat(index - 1) * secondaryHeight
                frame = CGRect(x: screenFrame.minX + mainWidth, y: secondaryY, width: screenFrame.width - mainWidth, height: secondaryHeight)
            }

            let resizeRules = ResizeRules(isMain: index == 0, unconstrainedDimension: .horizontal, scaleFactor: 1)
            let frameAssignment = FrameAssignment<Window>(
                frame: frame,
                window: window,
                screenFrame: screenFrame,
                resizeRules: resizeRules,
                disableWindowMargins: false
            )
            assignments.append(FrameAssignmentOperation(frameAssignment: frameAssignment, windowSet: windowSet))
        }

        return assignments
    }
}
