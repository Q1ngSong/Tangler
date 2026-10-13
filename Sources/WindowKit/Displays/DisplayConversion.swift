import Contracts
import CoreGraphics
import CoreKit

/// What WindowKit reads from one `NSScreen`, still in AppKit coordinates.
struct ScreenSnapshot: Equatable {
    var displayNumber: UInt32
    var uuid: String?
    var name: String
    var frame: CGRect
    var visibleFrame: CGRect
}

enum DisplayConversion {
    /// `screens` must be in `NSScreen.screens` order: the first one is the primary display,
    /// whose top edge defines global y = 0.
    static func displays(from screens: [ScreenSnapshot]) -> [DisplayInfo] {
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.maxY
        return screens.enumerated().map { index, screen in
            DisplayInfo(id: DisplayID(rawValue: screen.uuid ?? "display-\(screen.displayNumber)"), name: screen.name,
                        frame: ScreenCoordinates.flip(screen.frame, primaryHeight: primaryHeight),
                        visibleFrame: ScreenCoordinates.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                        isMain: index == 0)
        }
    }
}
