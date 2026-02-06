//
//  WidescreenTallLayout.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 12/15/15.
//  Copyright © 2015 Ian Ynda-Hummel. All rights reserved.
//

import Silica

class WidescreenTallLayout<Window: WindowType>: Layout<Window> {
    class var isRight: Bool { fatalError("Must be implemented by subclass") }

    enum CodingKeys: String, CodingKey {
        case mainPaneCount
        case mainPaneRatio
    }

    private(set) var mainPaneCount: Int = 1
    private(set) var mainPaneRatio: CGFloat = 0.5

    required init() {
        super.init()
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.mainPaneCount = try values.decode(Int.self, forKey: .mainPaneCount)
        self.mainPaneRatio = try values.decode(CGFloat.self, forKey: .mainPaneRatio)
        super.init()
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mainPaneCount, forKey: .mainPaneCount)
        try container.encode(mainPaneRatio, forKey: .mainPaneRatio)
    }

    override func frameAssignments(_ windowSet: WindowSet<Window>, on screen: Screen) -> [FrameAssignmentOperation<Window>]? {
        let windows = windowSet.windows

        if windows.count == 0 {
            return []
        }

        let mainPaneCount = min(windows.count, self.mainPaneCount)
        let secondaryPaneCount = windows.count - mainPaneCount

        let hasSecondaryPane = secondaryPaneCount > 0

        let screenFrame = screen.adjustedFrame()

        let mainPaneWindowHeight = screenFrame.height
        let secondaryPaneWindowHeight = hasSecondaryPane ? round(screenFrame.height / CGFloat(secondaryPaneCount)) : 0.0

        let effectiveRatio = clampedMainPaneRatio(hasSecondaryPane: hasSecondaryPane)
        let mainPaneWidth = round(screenFrame.size.width * (hasSecondaryPane ? CGFloat(effectiveRatio) : 1.0))
        let mainPaneWindowWidth = round(mainPaneWidth / CGFloat(mainPaneCount))
        let secondaryPaneWindowWidth = screenFrame.width - mainPaneWidth
        let safeMainPaneWindowWidth = max(mainPaneWindowWidth, 1)
        let safeSecondaryPaneWindowWidth = max(secondaryPaneWindowWidth, 1)

        var assignments: [FrameAssignmentOperation<Window>] = []
        assignments.reserveCapacity(windows.count)

        for (index, window) in windows.enumerated() {
            var windowFrame = CGRect.zero
            let isMain = index < mainPaneCount
            let secondaryIndex = index - mainPaneCount
            let scaleFactor: CGFloat

            if isMain {
                scaleFactor = CGFloat(screenFrame.size.width / safeMainPaneWindowWidth) / CGFloat(mainPaneCount)
                windowFrame.origin.x = screenFrame.origin.x + mainPaneWindowWidth * CGFloat(index)
                if type(of: self).isRight {
                    windowFrame.origin.x += secondaryPaneWindowWidth
                }
                windowFrame.origin.y = screenFrame.origin.y
                windowFrame.size.width = mainPaneWindowWidth
                windowFrame.size.height = mainPaneWindowHeight
            } else {
                scaleFactor = CGFloat(screenFrame.size.width / safeSecondaryPaneWindowWidth)
                windowFrame.origin.x = screenFrame.origin.x + mainPaneWidth
                windowFrame.origin.y = screenFrame.origin.y + (secondaryPaneWindowHeight * CGFloat(secondaryIndex))
                windowFrame.size.width = secondaryPaneWindowWidth
                windowFrame.size.height = secondaryPaneWindowHeight
                if type(of: self).isRight {
                    windowFrame.origin.x = screenFrame.origin.x
                }
            }

            let resizeRules = ResizeRules(isMain: isMain, unconstrainedDimension: .horizontal, scaleFactor: scaleFactor)
            let frameAssignment = FrameAssignment<Window>(
                frame: windowFrame,
                window: window,
                screenFrame: screenFrame,
                resizeRules: resizeRules
            )

            assignments.append(FrameAssignmentOperation(frameAssignment: frameAssignment, windowSet: windowSet))
        }

        return assignments
    }
}

extension WidescreenTallLayout: PanedLayout {
    func recommendMainPaneRawRatio(rawRatio: CGFloat) {
        mainPaneRatio = rawRatio
    }

    func increaseMainPaneCount() {
        mainPaneCount += 1
    }

    func decreaseMainPaneCount() {
        mainPaneCount = max(1, mainPaneCount - 1)
    }
}

class WidescreenTallLayoutLeft<Window: WindowType>: WidescreenTallLayout<Window> {
    override class var isRight: Bool { return false }
    override static var layoutName: String { return "Widescreen Tall" }
    override static var layoutKey: String { return "widescreen-tall" }
}

class WidescreenTallLayoutRight<Window: WindowType>: WidescreenTallLayout<Window> {
    override class var isRight: Bool { return true }
    override static var layoutName: String { return "Widescreen Tall Right" }
    override static var layoutKey: String { return "widescreen-tall-right" }
}
