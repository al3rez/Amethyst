//
//  ReflowOperation.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 3/19/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Silica

/// Apply window margins, minimum sizes, and screen clamping to a frame.
func applyWindowAdjustments(to frame: CGRect, screenFrame: CGRect, disableWindowMargins: Bool) -> CGRect {
    var ret = frame
    let padding = floor(UserConfiguration.shared.windowMarginSize() / 2)

    if UserConfiguration.shared.windowMargins() && !disableWindowMargins {
        ret.origin.x += padding
        ret.origin.y += padding
        ret.size.width -= 2 * padding
        ret.size.height -= 2 * padding
    }

    let windowMinimumWidth = UserConfiguration.shared.windowMinimumWidth()
    let windowMinimumHeight = UserConfiguration.shared.windowMinimumHeight()

    if windowMinimumWidth > ret.size.width {
        ret.origin.x -= ((windowMinimumWidth - ret.size.width) / 2)
        ret.size.width = windowMinimumWidth
    }

    if windowMinimumHeight > ret.size.height {
        ret.origin.y -= ((windowMinimumHeight - ret.size.height) / 2)
        ret.size.height = windowMinimumHeight
    }

    // Clamp to the screen frame to avoid drifting outside visible bounds.
    let minX = screenFrame.origin.x
    let maxX = screenFrame.maxX - ret.size.width
    if maxX < minX {
        ret.origin.x = minX
    } else {
        ret.origin.x = min(max(ret.origin.x, minX), maxX)
    }

    let minY = screenFrame.origin.y
    let maxY = screenFrame.maxY - ret.size.height
    if maxY < minY {
        ret.origin.y = minY
    } else {
        ret.origin.y = min(max(ret.origin.y, minY), maxY)
    }

    return ret
}

/// Possible dimensions without constraints.
enum UnconstrainedDimension: Int {
    /// The dimension along the x-axis.
    case horizontal

    /// The dimension along the y-axis.
    case vertical
}

/**
 This struct defines what adjustments to a particular window frame are allowed and tracks its size as a proportion of available space (for use in resize calculations).

 Some window resizes reflect valid adjustments to the frame layout.
 
 Some window resizes would not be allowed due to hard constraints.
 */
struct ResizeRules {
    /// Whether or not the resize rule is applying to the main frame.
    let isMain: Bool

    /// The dimension that is allowed to scale.
    let unconstrainedDimension: UnconstrainedDimension

    /// the scale factor for the unconstrained dimension.
    let scaleFactor: CGFloat

    /**
     Determines the new value of the dimension based on the scale factor.
     
     Given a new frame, decide which dimension will be honored and return its size.
     
     - Parameters:
        - frame: The frame to transform.
        - negatePadding: Whether or not to take padding into account.
     */
    func scaledDimension(_ frame: CGRect, negatePadding: Bool) -> CGFloat {
        let dimension: CGFloat = {
            switch unconstrainedDimension {
            case .horizontal: return frame.width
            case .vertical: return frame.height
            }
        }()

        let padding = UserConfiguration.shared.windowMargins() ? UserConfiguration.shared.windowMarginSize() : 0
        return negatePadding ? dimension + padding : dimension
    }
}

struct LayoutWindow<Window: WindowType>: Equatable {
    let id: Window.WindowID
    let frame: CGRect
    let isFocused: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}

struct WindowSet<Window: WindowType> {
    let windows: [LayoutWindow<Window>]
    private let isWindowWithIDActive: (Window.WindowID) -> Bool
    private let isWindowWithIDFloating: (Window.WindowID) -> Bool
    private let windowForID: (Window.WindowID) -> Window?

    init(
        windows: [LayoutWindow<Window>],
        isWindowWithIDActive: @escaping (Window.WindowID) -> Bool,
        isWindowWithIDFloating: @escaping (Window.WindowID) -> Bool,
        windowForID: @escaping (Window.WindowID) -> Window?
    ) {
        self.windows = windows
        self.isWindowWithIDActive = isWindowWithIDActive
        self.isWindowWithIDFloating = isWindowWithIDFloating
        self.windowForID = windowForID
    }

    func isWindowActive(_ window: LayoutWindow<Window>) -> Bool {
        return isWindowWithIDActive(window.id)
    }

    func isWindowFloating(_ window: LayoutWindow<Window>) -> Bool {
        return isWindowWithIDFloating(window.id)
    }

    func perform(frameAssignment: FrameAssignment<Window>) {
        guard let window = windowForID(frameAssignment.window.id) else {
            return
        }

        frameAssignment.perform(withWindow: window)
    }

    /// Get a window by ID for batched operations
    func window(withID id: Window.WindowID) -> Window? {
        return windowForID(id)
    }
}

class FrameAssignmentOperation<Window: WindowType>: Operation, @unchecked Sendable {
    let frameAssignment: FrameAssignment<Window>
    let windowSet: WindowSet<Window>

    init(frameAssignment: FrameAssignment<Window>, windowSet: WindowSet<Window>) {
        self.frameAssignment = frameAssignment
        self.windowSet = windowSet
        super.init()
    }

    override func main() {
        guard !isCancelled else {
            return
        }

        windowSet.perform(frameAssignment: frameAssignment)
    }
}

/// Batched operation that applies multiple frame assignments in a single main thread call
/// This reduces context switching overhead when reflowing many windows
class BatchedFrameAssignmentOperation<Window: WindowType>: Operation, @unchecked Sendable {
    let frameAssignments: [FrameAssignment<Window>]
    let windowSet: WindowSet<Window>

    init(frameAssignments: [FrameAssignment<Window>], windowSet: WindowSet<Window>) {
        self.frameAssignments = frameAssignments
        self.windowSet = windowSet
        super.init()
    }

    override func main() {
        guard !isCancelled else {
            return
        }

        // Batch all frame assignments in a single main thread call
        DispatchQueue.main.sync {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for frameAssignment in self.frameAssignments {
                guard !self.isCancelled else { return }
                if let window = self.windowSet.window(withID: frameAssignment.window.id) {
                    frameAssignment.performBatched(withWindow: window)
                }
            }
            CATransaction.commit()
        }
    }
}

/// Encapsulation of an assignment of a frame to a window.
struct FrameAssignment<Window: WindowType> {
    /// The frame to apply to the window.
    let frame: CGRect

    /// The window that will be moved and sized.
    let window: LayoutWindow<Window>

    /// The frame of the screen being occupied.
    let screenFrame: CGRect

    /// The rules governing constraints to frame transforms
    let resizeRules: ResizeRules

    /// If `true`, then  window margins won't be applied
    let disableWindowMargins: Bool

    init(frame: CGRect, window: LayoutWindow<Window>, screenFrame: CGRect, resizeRules: ResizeRules) {
        self.frame = frame
        self.window =  window
        self.screenFrame = screenFrame
        self.resizeRules = resizeRules
        self.disableWindowMargins = false
    }

    init(frame: CGRect, window: LayoutWindow<Window>, screenFrame: CGRect, resizeRules: ResizeRules, disableWindowMargins: Bool) {
        self.frame = frame
        self.window =  window
        self.screenFrame = screenFrame
        self.resizeRules = resizeRules
        self.disableWindowMargins = disableWindowMargins
    }

    /// The final frame is the desired frame, but transformed to provide desired padding
    var finalFrame: CGRect {
        return applyWindowAdjustments(
            to: frame,
            screenFrame: screenFrame,
            disableWindowMargins: disableWindowMargins
        )
    }

    /**
     Given a window frame and based on resizeRules, determine what the main pane ratio would be.
     
     This accounts for multiple main windows and primary vs non-primary being resized.
     
     - Parameters:
        - windowFrame: The frame of the window to test ratio against.
     
     - Returns:
     The estimate of the main pane ratio implied by how the frame would be transformed.
     */
    func impliedMainPaneRatio(windowFrame: CGRect) -> CGFloat {
        let oldDimension = resizeRules.scaledDimension(frame, negatePadding: false)
        guard oldDimension > 0, resizeRules.scaleFactor > 0 else {
            return resizeRules.isMain ? 1.0 : 0.0
        }
        let newDimension = max(resizeRules.scaledDimension(windowFrame, negatePadding: true), 0.0)
        let implied = (newDimension / oldDimension) / resizeRules.scaleFactor
        return resizeRules.isMain ? implied : 1 - implied
    }

    /// Perform the actual application of the frame to the window
    func perform(withWindow window: Window) {
        // All window operations must happen on main thread - do everything in one sync block
        DispatchQueue.main.sync {
            performOnMainThread(withWindow: window)
        }
    }

    /// Perform frame assignment without dispatching (for batched operations already on main thread)
    func performBatched(withWindow window: Window) {
        performOnMainThread(withWindow: window)
    }

    /// Core implementation that must be called from main thread
    private func performOnMainThread(withWindow window: Window) {
        let finalFrame = self.finalFrame
        let currentFrame = window.frame()

        // Skip if the frame is already effectively applied to avoid extra AX traffic.
        let deltaThreshold: CGFloat = 1.0
        let isSameFrame =
            abs(currentFrame.origin.x - finalFrame.origin.x) <= deltaThreshold &&
            abs(currentFrame.origin.y - finalFrame.origin.y) <= deltaThreshold &&
            abs(currentFrame.size.width - finalFrame.size.width) <= deltaThreshold &&
            abs(currentFrame.size.height - finalFrame.size.height) <= deltaThreshold

        guard !isSameFrame else {
            return
        }

        // Simply apply the assigned frame - don't expand focused windows
        // The "window peeking" behavior was causing focused windows to grow
        // and overlap with adjacent tiles when apps have minimum size constraints
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrame(finalFrame, withThreshold: CGSize(width: 1, height: 1))
        CATransaction.commit()
    }
}
