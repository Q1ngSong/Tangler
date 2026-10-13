import Contracts
import CoreGraphics
import Foundation

/// One entry of `CGWindowListCopyWindowInfo`, in global coordinates.
struct WindowServerRecord: Equatable {
    var id: WindowID
    var pid: Int32
    var layer: Int
    /// Empty without Screen Recording permission.
    var title: String
    var frame: CGRect
    var isOnScreen: Bool
    var alpha: Double
    /// Position in the list, which runs front to back.
    var order: Int

    init(id: WindowID, pid: Int32, layer: Int, title: String, frame: CGRect, isOnScreen: Bool, alpha: Double, order: Int) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.alpha = alpha
        self.order = order
    }

    init?(_ entry: [String: Any], order: Int) {
        guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        self.init(id: WindowID(rawValue: number), pid: pid, layer: layer,
                  title: entry[kCGWindowName as String] as? String ?? "", frame: frame,
                  isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
                  alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1, order: order)
    }

    /// The legacy inventory rule: a normal-layer window larger than 40×24 points.
    var hasManageableShape: Bool { layer == 0 && frame.width > 40 && frame.height > 24 }
}
