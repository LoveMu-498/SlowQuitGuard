import AppKit
import CoreGraphics
import QuitGuardCore

enum OverlayScreenPlacement {
    static func screenIndex(window: CGRect?, screens: [CGRect], pointer: CGPoint) -> Int? {
        if let window, !window.isEmpty {
            let areas = screens.map { rect -> CGFloat in
                let overlap = rect.intersection(window)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }
            if let largest = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[largest] > 0 { return largest }
        }
        return screens.firstIndex { $0.contains(pointer) } ?? screens.indices.first
    }

    static func appKitRect(fromQuartz rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
enum OverlayScreenResolver {
    static func visibleFrame(for target: QuitTarget) -> CGRect? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let window = windows.first { info in
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.identity.processID &&
            (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
            ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0
        }
        let quartzRect = (window?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let rect = quartzRect.map { OverlayScreenPlacement.appKitRect(fromQuartz: $0, primaryTop: primary.frame.maxY) }
        guard let index = OverlayScreenPlacement.screenIndex(window: rect, screens: screens.map(\.frame),
                                                             pointer: NSEvent.mouseLocation) else { return nil }
        return screens[index].visibleFrame
    }
}
