//
//  Windows.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 9/15/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Silica

extension WindowManager {
    class Windows {
        private(set) var windows: [Window] = []
        private(set) var lastMainWindows: [CGSSpaceID: Window?] = [:]
        private var windowsByID: [Window.WindowID: Window] = [:]
        private var activeIDCache: Set<CGWindowID> = Set()
        private var activeIDCacheDirty: Bool = true  // Lazy invalidation flag
        private var deactivatedPIDs: Set<pid_t> = Set()
        private var floatingMap: [Window.WindowID: Bool] = [:]

        // Cached space info for batch queries - invalidated on space change
        private var windowSpaceCache: [CGWindowID: Int] = [:]
        private var windowSpaceCacheDirty: Bool = true

        // MARK: Window Filters

        func window(withID id: Window.WindowID) -> Window? {
            return windowsByID[id]
        }

        func windows(forApplicationWithPID applicationPID: pid_t) -> [Window] {
            return windows.filter { $0.pid() == applicationPID }
        }

        func windows(onScreen screen: Screen) -> [Window] {
            return windows.filter { $0.screen() == screen }
        }

        func activeWindows(onScreen screen: Screen) -> [Window] {
            guard let screenID = screen.screenID() else {
                return []
            }

            guard let currentSpace = CGSpacesInfo<Window>.currentSpaceForScreen(screen) else {
                log.warning("Could not find a space for screen: \(screenID)")
                return []
            }

            // Single-pass filter with cached space lookups
            let currentSpaceID = currentSpace.id
            let screenWindows = windows.filter { window in
                // Use cached space lookup instead of per-window CGS API call
                let space = self.cachedWindowSpace(window)

                guard let windowScreen = window.screen(), currentSpaceID == space else {
                    return false
                }

                // Combine all checks in single pass
                guard windowScreen.screenID() == screenID else {
                    return false
                }

                return self.isWindowActive(window) && !self.isWindowHidden(window) && !self.isWindowFloating(window)
            }

            return screenWindows
        }

        func activeWindowOnCurrentScreen(atIndex: Int) -> Window? {
            guard let focusedWindow = Window.currentlyFocused(),
                  let currentScreen = focusedWindow.screen() else {
                return nil
            }
            let activeWindows = activeWindows(onScreen: currentScreen)

            return activeWindows.indices.contains(atIndex) ? activeWindows[atIndex] : nil
        }

        // MARK: Adding and Removing

        func add(window: Window, atFront shouldInsertAtFront: Bool) {
            let windowID = window.id()
            windowsByID[windowID] = window

            if shouldInsertAtFront {
                if let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace(),
                   let firstActiveWindow = activeWindowOnCurrentScreen(atIndex: 0) {
                    lastMainWindows[currentFocusedSpace.id] = firstActiveWindow
                }

                windows.insert(window, at: 0)
            } else {
                windows.append(window)
            }
        }

        func remove(window: Window) {
            let windowID = window.id()
            let windowTitle = window.title() ?? "<unknown>"
            windowsByID.removeValue(forKey: windowID)

            for (_, lastMainWindow) in lastMainWindows where lastMainWindow == window {
                if let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace() {
                    let secondWindow = activeWindowOnCurrentScreen(atIndex: 1)
                    lastMainWindows[currentFocusedSpace.id] = secondWindow
                }
            }

            guard let windowIndex = windows.firstIndex(of: window) else {
                log.debug("Attempted to remove untracked window: '\(windowTitle)'")
                return
            }

            windows.remove(at: windowIndex)
            log.debug("Removed window: '\(windowTitle)' (cgID: \(window.cgID()))")
        }

        /// Removes windows that are no longer valid (destroyed or inaccessible)
        /// Returns the number of windows removed
        @discardableResult func cleanupInvalidWindows() -> Int {
            let invalidWindows = windows.filter { !$0.isValid() }
            for window in invalidWindows {
                log.info("Cleaning up invalid window: '\(window.title() ?? "<unknown>")' (cgID: \(window.cgID()))")
                remove(window: window)
            }
            if !invalidWindows.isEmpty {
                regenerateActiveIDCache()
            }
            return invalidWindows.count
        }

        @discardableResult func swap(window: Window, withWindow otherWindow: Window) -> Bool {
            if let currentFocusedSpace = CGSpacesInfo<Window>.currentFocusedSpace(),
               let firstActiveWindow = activeWindowOnCurrentScreen(atIndex: 0) {
                if firstActiveWindow == window || firstActiveWindow == otherWindow {
                    lastMainWindows[currentFocusedSpace.id] = firstActiveWindow
                }
            }

            guard let windowIndex = windows.firstIndex(of: window), let otherWindowIndex = windows.firstIndex(of: otherWindow) else {
                return false
            }

            guard windowIndex != otherWindowIndex else {
                return false
            }

            windows[windowIndex] = otherWindow
            windows[otherWindowIndex] = window

            return true
        }

        // MARK: Window States

        func isWindowTracked(_ window: Window) -> Bool {
            return windows.contains(window)
        }

        func isWindowActive(_ window: Window) -> Bool {
            // Lazy regeneration - only regenerate when actually needed
            if activeIDCacheDirty {
                regenerateActiveIDCacheNow()
            }
            return window.isActive() && activeIDCache.contains(window.cgID())
        }

        func isWindowHidden(_ window: Window) -> Bool {
            return deactivatedPIDs.contains(window.pid())
        }

        func isWindowFloating(_ window: Window) -> Bool {
            return floatingMap[window.id()] ?? false
        }

        func setFloating(_ floating: Bool, forWindow window: Window) {
            floatingMap[window.id()] = floating
        }

        func activateApplication(withPID pid: pid_t) {
            deactivatedPIDs.remove(pid)
        }

        func deactivateApplication(withPID pid: pid_t) {
            deactivatedPIDs.insert(pid)
        }

        /// Marks the active ID cache as needing regeneration (lazy invalidation)
        func regenerateActiveIDCache() {
            activeIDCacheDirty = true
        }

        /// Actually regenerates the cache - called lazily when needed
        private func regenerateActiveIDCacheNow() {
            let windowDescriptions = CGWindowsInfo<Window>(options: .optionOnScreenOnly, windowID: CGWindowID(0))
            activeIDCache = windowDescriptions?.activeIDs() ?? Set()
            activeIDCacheDirty = false
        }

        /// Invalidates the window-to-space cache (call on space change)
        func invalidateSpaceCache() {
            windowSpaceCacheDirty = true
            windowSpaceCache.removeAll()
        }

        /// Gets the space for a window, using cache when possible
        func cachedWindowSpace(_ window: Window) -> Int? {
            let cgID = window.cgID()
            if !windowSpaceCacheDirty, let cached = windowSpaceCache[cgID] {
                return cached
            }
            // Cache miss - fetch and store
            if let space = CGWindowsInfo<Window>.windowSpace(window) {
                windowSpaceCache[cgID] = space
                return space
            }
            return nil
        }

        // MARK: Window Sets

        func windowSet(forWindowsOnScreen screen: Screen) -> WindowSet<Window> {
            return windowSet(forWindows: windows(onScreen: screen))
        }

        func windowSet(forActiveWindowsOnScreen screen: Screen) -> WindowSet<Window> {
            return windowSet(forWindows: activeWindows(onScreen: screen))
        }

        func windowSet(forWindows windows: [Window]) -> WindowSet<Window> {
            let layoutWindows: [LayoutWindow<Window>] = windows.map {
                LayoutWindow(id: $0.id(), frame: $0.frame(), isFocused: $0.isFocused())
            }

            return WindowSet<Window>(
                windows: layoutWindows,
                isWindowWithIDActive: { [weak self] id -> Bool in
                    guard let window = self?.window(withID: id) else {
                        return false
                    }
                    return self?.isWindowActive(window) ?? false
                },
                isWindowWithIDFloating: { [weak self] windowID -> Bool in
                    guard let window = self?.window(withID: windowID) else {
                        return false
                    }
                    return self?.isWindowFloating(window) ?? false
                },
                windowForID: { [weak self] windowID -> Window? in
                    return self?.window(withID: windowID)
                }
            )
        }
    }
}
