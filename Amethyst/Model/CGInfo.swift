//
//  CGInfo.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 3/29/19.
//  Copyright © 2019 Ian Ynda-Hummel. All rights reserved.
//

import Foundation
import Silica
import SwiftyJSON

/// Helper to check if CGS private APIs are available at runtime
enum CGSPrivateAPIAvailability {
    private static var _isAvailable: Bool?
    private static var _spaceAPIsAvailable: Bool?
    private static var _hasLoggedWarning: Bool = false

    /// Returns true if CGS private APIs appear to be working on this system
    static var isAvailable: Bool {
        if let cached = _isAvailable {
            return cached
        }
        // Test by checking if CGSMainConnectionID returns a valid connection
        let connectionID = CGSMainConnectionID()
        let available = connectionID != 0
        _isAvailable = available
        if !available && !_hasLoggedWarning {
            _hasLoggedWarning = true
            log.warning("CGS private APIs are not available on this system. Some features will be limited.")
            log.warning("This may be due to macOS version incompatibility or security restrictions.")
        }
        return available
    }

    /// Returns true if space-related CGS APIs are working
    static var spaceAPIsAvailable: Bool {
        if let cached = _spaceAPIsAvailable {
            return cached
        }
        guard isAvailable else {
            _spaceAPIsAvailable = false
            return false
        }
        // Test by trying to get managed display spaces
        let available = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) != nil
        _spaceAPIsAvailable = available
        if !available {
            log.warning("CGS space APIs are not available. Space-related features will be limited.")
        }
        return available
    }

    /// Resets the cached availability status (useful for testing or after system changes)
    static func resetCache() {
        _isAvailable = nil
        _spaceAPIsAvailable = nil
        _hasLoggedWarning = false
    }

    /// Returns a human-readable status of private API availability
    static var statusDescription: String {
        var status: [String] = []
        if isAvailable {
            status.append("Core CGS APIs: Available")
        } else {
            status.append("Core CGS APIs: Unavailable")
        }
        if spaceAPIsAvailable {
            status.append("Space APIs: Available")
        } else {
            status.append("Space APIs: Unavailable")
        }
        return status.joined(separator: ", ")
    }
}

/// Windows info as taken from the underlying system.
struct CGWindowsInfo<Window: WindowType> {
    /// An array of dictionaries of window information
    let descriptions: [[String: AnyObject]]

    /**
     - Parameters:
     - options: Any options for getting info.
     - windowID: ID of window to find windows relative to. 0 gets all windows.
     */
    init?(options: CGWindowListOption, windowID: CGWindowID) {
        guard let cfWindowDescriptions = CGWindowListCopyWindowInfo(options, windowID) else {
            return nil
        }

        guard let windowDescriptions = cfWindowDescriptions as? [[String: AnyObject]] else {
            return nil
        }

        self.descriptions = windowDescriptions
    }

    /**
     - Returns:
     The set of windows that are currently active.
     */
    func activeIDs() -> Set<CGWindowID> {
        var ids: Set<CGWindowID> = Set()

        for windowDescription in descriptions {
            guard let windowID = windowDescription[kCGWindowNumber as String] as? NSNumber else {
                continue
            }

            ids.insert(CGWindowID(windowID.uint64Value))
        }

        return ids
    }

    static func windowIDsArray(_ window: Window) -> NSArray {
        return [NSNumber(value: window.cgID() as UInt32)] as NSArray
    }

    static func windowSpace(_ window: Window) -> Int? {
        guard CGSPrivateAPIAvailability.isAvailable else {
            log.debug("windowSpace: CGS APIs unavailable, returning nil")
            return nil
        }
        let windowIDsArray = CGWindowsInfo.windowIDsArray(window)

        guard let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), kCGSAllSpacesMask, windowIDsArray)?.takeRetainedValue() else {
            log.debug("windowSpace: CGSCopySpacesForWindows returned nil for window \(window.cgID())")
            return nil
        }

        return (spaces as NSArray as? [NSNumber])?.first?.intValue
    }
}

struct CGScreensInfo<Window: WindowType> {
    typealias Screen = Window.Screen

    let descriptions: [JSON]

    init?() {
        guard let descriptions = Screen.screenDescriptions() else {
            return nil
        }

        self.descriptions = descriptions
    }

    func space(at index: Int) -> Space {
        return CGSpacesInfo<Window>.space(fromScreenDescription: descriptions[index])
    }
}

struct CGSpacesInfo<Window: WindowType> {
    typealias Screen = Window.Screen

    static func spacesForAllScreens(includeOnlyUserSpaces: Bool = false) -> [Space]? {
        guard let screenDescriptions = Screen.screenDescriptions() else {
            return nil
        }

        guard !screenDescriptions.isEmpty else {
            return nil
        }

        let spaces = screenDescriptions.map { screenDescription -> [Space] in
            return allSpaces(fromScreenDescription: screenDescription) ?? []
        }.reduce([], {acc, spaces in acc + spaces})

        if includeOnlyUserSpaces {
            return spaces.filter { $0.type == CGSSpaceTypeUser }
        }

        return spaces
    }

    static func spacesForScreen(_ screen: Screen, includeOnlyUserSpaces: Bool = false) -> [Space]? {
        guard let screenDescriptions = Screen.screenDescriptions() else {
            return nil
        }

        guard !screenDescriptions.isEmpty else {
            return nil
        }

        let screenID = screen.screenID()
        let spaces: [Space]?

        if Screen.screensHaveSeparateSpaces {
            spaces = screenDescriptions
                .first { $0["Display Identifier"].string == screenID }
                .flatMap { screenDescription -> [Space]? in
                    return allSpaces(fromScreenDescription: screenDescription)
                }
        } else {
            spaces = allSpaces(fromScreenDescription: screenDescriptions[0])
        }

        if includeOnlyUserSpaces {
            return spaces?.filter { $0.type == CGSSpaceTypeUser }
        }

        return spaces
    }

    static func spacesForFocusedScreen() -> [Space]? {
        guard let focusedWindow = Window.currentlyFocused(), let screen = focusedWindow.screen() else {
            return nil
        }

        return spacesForScreen(screen)
    }

    static func currentSpaceForScreen(_ screen: Screen) -> Space? {
        guard let screenDescriptions = Screen.screenDescriptions(), let screenID = screen.screenID() else {
            return nil
        }

        guard screenDescriptions.count > 0 else {
            return nil
        }

        if Screen.screensHaveSeparateSpaces {
            for screenDescription in screenDescriptions {
                guard screenDescription["Display Identifier"].string == screenID else {
                    continue
                }

                return space(fromScreenDescription: screenDescription)
            }
        } else {
            return space(fromScreenDescription: screenDescriptions[0])
        }

        return nil
    }

    static func currentFocusedSpace() -> Space? {
        guard let focusedWindow = Window.currentlyFocused(), let screen = focusedWindow.screen() else {
            return nil
        }

        return currentSpaceForScreen(screen)
    }

    static func screenForSpace(space: Space) -> Screen? {
        return Screen.availableScreens.first { spacesForScreen($0)?.contains { $0.id == space.id } ?? false }
    }

    static func space(fromScreenDescription screenDictionary: JSON) -> Space {
        return space(fromSpaceDescription: screenDictionary["Current Space"])
    }

    static func space(fromSpaceDescription spaceDictionary: JSON) -> Space {
        let id: CGSSpaceID = spaceDictionary["ManagedSpaceID"].intValue
        let type = CGSSpaceType(rawValue: spaceDictionary["type"].uInt32Value)
        let uuid = spaceDictionary["uuid"].stringValue
        return Space(id: id, type: type, uuid: uuid)
    }

    static func allSpaces(fromScreenDescription screenDictionary: JSON) -> [Space]? {
        return screenDictionary["Spaces"].array?.map {
            space(fromSpaceDescription: $0)
        }
    }
}
