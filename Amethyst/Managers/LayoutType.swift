//
//  LayoutManager.swift
//  Amethyst
//
//  Created by Ian Ynda-Hummel on 5/15/16.
//  Copyright © 2016 Ian Ynda-Hummel. All rights reserved.
//

import Foundation

extension FileManager {
    func layoutsDirectory() throws -> URL {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let layoutsDirectory = applicationSupportDirectory
            .appendingPathComponent("Amethyst", isDirectory: true)
            .appendingPathComponent("Layouts", isDirectory: true)

        if !FileManager.default.fileExists(atPath: layoutsDirectory.path, isDirectory: nil) {
            try FileManager.default.createDirectory(
                at: layoutsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return layoutsDirectory
    }

    func layoutFile(key: String) throws -> URL {
        let layoutsDirectory = try self.layoutsDirectory()
        return layoutsDirectory.appendingPathComponent("\(key).js")
    }
}

enum LayoutType<Window: WindowType> {
    enum Error: Swift.Error {
        case unknownLayout
    }

    case tall
    case tallRight
    case wide
    case twoPane
    case twoPaneRight
    case threeColumnLeft
    case threeColumnMiddle
    case threeColumnRight
    case fourColumnLeft
    case fourColumnRight
    case fullscreen
    case column
    case row
    case floating
    case widescreenTallLeft
    case widescreenTallRight
    case binarySpacePartitioning
    case manual

    case custom(key: String)

    static var standardLayouts: [LayoutType<Window>] {
        return [
            .tall,
            .tallRight,
            .wide,
            .twoPane,
            .twoPaneRight,
            .threeColumnLeft,
            .threeColumnMiddle,
            .threeColumnRight,
            .fourColumnLeft,
            .fourColumnRight,
            .fullscreen,
            .column,
            .row,
            .floating,
            .widescreenTallLeft,
            .widescreenTallRight,
            .binarySpacePartitioning,
            .manual
        ]
    }

    var key: String {
        switch self {
        case .tall:
            return "tall"
        case .tallRight:
            return "tall-right"
        case .wide:
            return "wide"
        case .twoPane:
            return "two-pane"
        case .twoPaneRight:
            return "two-pane-right"
        case .threeColumnLeft:
            return "3column-left"
        case .threeColumnMiddle:
            return "middle-wide"
        case .threeColumnRight:
            return "3column-right"
        case .fourColumnLeft:
            return "4column-left"
        case .fourColumnRight:
            return "4column-right"
        case .fullscreen:
            return "fullscreen"
        case .column:
            return "column"
        case .row:
            return "row"
        case .floating:
            return "floating"
        case .widescreenTallLeft:
            return "widescreen-tall"
        case .widescreenTallRight:
            return "widescreen-tall-right"
        case .binarySpacePartitioning:
            return "bsp"
        case .manual:
            return "manual"
        case .custom(let key):
            return key
        }
    }

    private static var layoutClassByKey: [String: Layout<Window>.Type] {
        return [
            "tall": TallLayout<Window>.self,
            "tall-right": TallRightLayout<Window>.self,
            "wide": WideLayout<Window>.self,
            "two-pane": TwoPaneLayout<Window>.self,
            "two-pane-right": TwoPaneRightLayout<Window>.self,
            "3column-left": ThreeColumnLeftLayout<Window>.self,
            "middle-wide": ThreeColumnMiddleLayout<Window>.self,
            "3column-right": ThreeColumnRightLayout<Window>.self,
            "4column-left": FourColumnLeftLayout<Window>.self,
            "4column-right": FourColumnRightLayout<Window>.self,
            "fullscreen": FullscreenLayout<Window>.self,
            "column": ColumnLayout<Window>.self,
            "row": RowLayout<Window>.self,
            "floating": FloatingLayout<Window>.self,
            "widescreen-tall": WidescreenTallLayoutLeft<Window>.self,
            "widescreen-tall-right": WidescreenTallLayoutRight<Window>.self,
            "bsp": BinarySpacePartitioningLayout<Window>.self,
            "manual": ManualLayout<Window>.self
        ]
    }

    private static var typeByKey: [String: LayoutType<Window>] {
        return [
            "tall": .tall,
            "tall-right": .tallRight,
            "wide": .wide,
            "two-pane": .twoPane,
            "two-pane-right": .twoPaneRight,
            "3column-left": .threeColumnLeft,
            "middle-wide": .threeColumnMiddle,
            "3column-right": .threeColumnRight,
            "4column-left": .fourColumnLeft,
            "4column-right": .fourColumnRight,
            "fullscreen": .fullscreen,
            "column": .column,
            "row": .row,
            "floating": .floating,
            "widescreen-tall": .widescreenTallLeft,
            "widescreen-tall-right": .widescreenTallRight,
            "bsp": .binarySpacePartitioning,
            "manual": .manual
        ]
    }

    var layoutClass: Layout<Window>.Type {
        return LayoutType.layoutClassByKey[key] ?? CustomLayout<Window>.self
    }

    static func from(key: String) -> LayoutType<Window> {
        return typeByKey[key] ?? .custom(key: key)
    }

    static func layoutForKey(_ layoutKey: String) -> Layout<Window>? {
        let type = LayoutType<Window>.from(key: layoutKey)

        guard case .custom = type else {
            return type.layoutClass.init()
        }

        do {
            let layoutFile = try FileManager.default.layoutFile(key: layoutKey)

            guard FileManager.default.fileExists(atPath: layoutFile.path) else {
                return nil
            }

            return CustomLayout<Window>(key: layoutKey, fileURL: layoutFile)
        } catch {
            return nil
        }
    }

    static func layoutNameForKey(_ layoutKey: String) -> String? {
        let type = LayoutType<Window>.from(key: layoutKey)

        guard case .custom = type else {
            return type.layoutClass.layoutName
        }

        return layoutForKey(layoutKey)?.layoutName
    }

    static func standardLayoutClasses() -> [Layout<Window>.Type] {
        return standardLayouts.compactMap { $0.layoutClass }
    }

    // Returns a list of (key, name) pairs
    static func availableLayoutStrings() -> [(key: String, name: String)] {
        var layoutTypes = standardLayouts
            .compactMap { $0.layoutClass }
            .map { ($0.layoutKey, $0.layoutName) }

        do {
            let layoutsDirectory = try FileManager.default.layoutsDirectory()
            let customLayoutFiles = try FileManager.default.contentsOfDirectory(
                at: layoutsDirectory,
                includingPropertiesForKeys: nil,
                options: []
            ).filter { $0.pathExtension == "js" }

            let customLayouts = customLayoutFiles
                .map { $0.deletingPathExtension().lastPathComponent }
                .map { ($0, layoutNameForKey($0)!) }
            layoutTypes.append(contentsOf: customLayouts)
        } catch {
            log.error("failed to parse custom layouts")
        }

        return layoutTypes
    }

    static func layoutsWithConfiguration(_ userConfiguration: UserConfiguration) -> [Layout<Window>] {
        let layoutKeys: [String] = userConfiguration.layoutKeys()
        let layouts = layoutKeys.map { layoutKey -> Layout<Window>? in
            guard let layout = LayoutType.layoutForKey(layoutKey) else {
                log.warning("Unrecognized layout key \(layoutKey)")
                return nil
            }

            return layout
        }

        return layouts.compactMap { $0 }
    }

    static func encoded(layout: Layout<Window>) throws -> Data {
        return try JSONEncoder().encode(layout)
    }

    static func decoded(data: Data, key: String) throws -> Layout<Window> {
        let layoutType = LayoutType<Window>.from(key: key)
        let decoder = JSONDecoder()
        return try decoder.decode(layoutType.layoutClass, from: data)
    }
}
