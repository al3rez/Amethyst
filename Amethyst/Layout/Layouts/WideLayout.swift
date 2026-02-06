//
//  WideLayout.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 12/14/15.
//  Copyright © 2015 Ian Ynda-Hummel. All rights reserved.
//

import Silica

class WideLayout<Window: WindowType>: Layout<Window>, PanedLayout {
    override static var layoutName: String { return "Wide" }
    override static var layoutKey: String { return "wide" }

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

    func recommendMainPaneRawRatio(rawRatio: CGFloat) {
        mainPaneRatio = rawRatio
    }

    func increaseMainPaneCount() {
        mainPaneCount += 1
    }

    func decreaseMainPaneCount() {
        mainPaneCount = max(1, mainPaneCount - 1)
    }

    override func frameAssignments(_ windowSet: WindowSet<Window>, on screen: Screen) -> [FrameAssignmentOperation<Window>]? {
        let windows = windowSet.windows

        guard !windows.isEmpty else {
            return []
        }

        let secondaryPaneCount = windows.count - mainPaneCount
        let hasSecondaryPane = secondaryPaneCount > 0

        let screenFrame = screen.adjustedFrame()

        let effectiveRatio = clampedMainPaneRatio(hasSecondaryPane: hasSecondaryPane)
        let mainPaneWindowHeight = round(screenFrame.height * CGFloat(hasSecondaryPane ? effectiveRatio : 1))
        let secondaryPaneWindowHeight = screenFrame.height - mainPaneWindowHeight
        let safeMainPaneWindowHeight = max(mainPaneWindowHeight, 1)
        let safeSecondaryPaneWindowHeight = max(secondaryPaneWindowHeight, 1)

        let mainPaneWindowWidth = round(screenFrame.width / CGFloat(mainPaneCount))
        let secondaryPaneWindowWidth = hasSecondaryPane ? round(screenFrame.width / CGFloat(secondaryPaneCount)) : 0.0

        var assignments: [FrameAssignmentOperation<Window>] = []
        assignments.reserveCapacity(windows.count)

        for (index, window) in windows.enumerated() {
            var windowFrame = CGRect.zero
            let isMain = index < mainPaneCount
            let secondaryIndex = index - mainPaneCount
            let scaleFactor: CGFloat

            if isMain {
                scaleFactor = screenFrame.height / safeMainPaneWindowHeight
                windowFrame.origin.x = screenFrame.origin.x + (mainPaneWindowWidth * CGFloat(index))
                windowFrame.origin.y = screenFrame.origin.y
                windowFrame.size.width = mainPaneWindowWidth
                windowFrame.size.height = mainPaneWindowHeight
            } else {
                scaleFactor = screenFrame.height / safeSecondaryPaneWindowHeight
                windowFrame.origin.x = screenFrame.origin.x + (secondaryPaneWindowWidth * CGFloat(secondaryIndex))
                windowFrame.origin.y = screenFrame.origin.y + mainPaneWindowHeight
                windowFrame.size.width = secondaryPaneWindowWidth
                windowFrame.size.height = secondaryPaneWindowHeight
            }

            let resizeRules = ResizeRules(isMain: isMain, unconstrainedDimension: .vertical, scaleFactor: scaleFactor)
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
