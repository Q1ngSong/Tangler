import CoreGraphics
import CoreKit

/// Where a group's bar and windows go, and how windows are matched (tab groups design 4).
/// Global coordinates, origin at the top-left, y down.
enum TabGeometry {
    /// "T T" groups windows that overlap the current one at least this much (intersection over union).
    static let sameAreaOverlap: CGFloat = 0.6
    /// Snapping counts as landing on a window when every edge is at most this far from it.
    static let snapTolerance: CGFloat = 4
    /// A window may take a size this far, each way, from the one a group writes it and still be a
    /// tab: about one text cell of an application that sizes its windows in steps, as Terminal does.
    static let sizeStep: CGFloat = 24
    /// "T X" moves the window this far down and to the right.
    static let detachOffset: CGFloat = 32
    /// A window shorter than this below the bar is made this tall.
    static let minimumMemberHeight: CGFloat = 60
    /// Where a dragged-out tab's pointer sits on its new window: inside the title bar, near the left.
    static let dropGrip = CGSize(width: 40, height: 12)

    static func barFrame(of area: CGRect, barHeight: CGFloat) -> CGRect {
        CGRect(x: area.minX, y: area.minY, width: area.width, height: min(barHeight, area.height))
    }

    static func memberFrame(of area: CGRect, barHeight: CGFloat) -> CGRect {
        let bar = min(barHeight, area.height)
        return CGRect(x: area.minX, y: area.minY + bar, width: area.width, height: area.height - bar)
    }

    /// 4.1: the bar goes right above the active window; where the visible area's top is in the way,
    /// the window's top edge moves down instead and its bottom edge stays. Applied to its own
    /// result it changes nothing, so the echoes of Tangler's own moves settle at once.
    static func area(forWindowAt frame: CGRect, visibleTop: CGFloat, barHeight: CGFloat) -> CGRect {
        let barTop = max(frame.minY - barHeight, visibleTop)
        let memberTop = barTop + barHeight
        let bottom = max(frame.maxY, memberTop + minimumMemberHeight)
        return CGRect(x: frame.minX, y: barTop, width: frame.width, height: bottom - barTop)
    }

    /// The area after the active window reported `frame`, given `rested`, the area as it was when
    /// that window last rested: not the area that has followed the window since, which a bar stopped
    /// at the visible top has already shifted against the window. A window at the size it rested at
    /// only moved: the group keeps that size and carries the bar above the window, and where the
    /// visible area's top is in the way the bar stops there and the window goes below it, so a
    /// drag never costs height. A window that was put somewhere new, both resized and with its top
    /// moved (a snap, a layout command, maximizing, the top edge dragged), takes the bar inside its
    /// own top, so the group fills exactly that place and never reaches over the window above it.
    /// One resized with its top where it was has the bar above it (`area(forWindowAt:)`).
    static func area(following frame: CGRect, rested: CGRect, visibleTop: CGFloat, barHeight: CGFloat) -> CGRect {
        let member = memberFrame(of: rested, barHeight: barHeight)
        if sameSize(frame, member) {
            return CGRect(x: frame.minX, y: max(frame.minY - barHeight, visibleTop), width: frame.width,
                          height: barHeight + max(frame.height, minimumMemberHeight))
        }
        let placed = abs(frame.minY - member.minY) > 1
        return placed ? frame : area(forWindowAt: frame, visibleTop: visibleTop, barHeight: barHeight)
    }

    /// The frame a group goes by when one of its windows is at `frame` and that window's application
    /// sizes windows in steps, as Terminal does in character cells: written `asked`, the size of the
    /// group's windows, it took `took`. The area is the place the user chose and that window's limit
    /// is its own, so at the size it took it stands for the size written. Put somewhere new, its top
    /// away from `memberTop`, at the size the group had with its bar, no farther from it than `took`
    /// is from `asked`, it stands for that size there: the place asked for was as large as the
    /// group, and what the window made of it is all that is known of it. That second rule is a
    /// guess, for places Tangler did not choose: macOS's own tiling, another window manager. Where
    /// Tangler's layout put the window, the frame it asked is known and comes first
    /// (`TabsController.resting`).
    static func intended(_ frame: CGRect, asked: CGSize, took: CGSize, memberTop: CGFloat, barHeight: CGFloat) -> CGRect {
        func near(_ a: CGSize, _ b: CGSize, by slack: CGSize = .zero) -> Bool {
            abs(a.width - b.width) <= slack.width + 1 && abs(a.height - b.height) <= slack.height + 1
        }
        if near(frame.size, took) { return CGRect(origin: frame.origin, size: asked) }
        let whole = CGSize(width: asked.width, height: asked.height + barHeight)
        let slack = CGSize(width: abs(asked.width - took.width), height: abs(asked.height - took.height))
        let placed = abs(frame.minY - memberTop) > 1 && near(frame.size, whole, by: slack)
        return placed ? CGRect(origin: frame.origin, size: whole) : frame
    }

    /// Intersection over union: 1 for the same rectangle, 0 when they do not overlap.
    static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return 0 }
        let shared = overlap.width * overlap.height
        let union = a.width * a.height + b.width * b.height - shared
        return union > 0 ? shared / union : 0
    }

    static func sharesArea(_ a: CGRect, _ b: CGRect) -> Bool { overlapRatio(a, b) >= sameAreaOverlap }

    static func coincides(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = snapTolerance) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    /// Frames are written in whole points and read back up to half a point off.
    static func same(_ a: CGRect, _ b: CGRect) -> Bool { coincides(a, b, tolerance: 1) }

    static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    /// Whether a window written `frame` and now at `actual` can be a tab there: its top-left is where
    /// it was put, and its size is no farther from the one written than `sizeStep`. The difference
    /// is that window's own: the group's area and its other windows go by the frame written
    /// (`intended`). A window farther off, as one whose minimum size is larger, cannot.
    /// `pushedBack` is for a frame the layout asked: a window that grew past the visible area is
    /// moved back inside by the layout, and then its right or bottom edge is where it was put. Only
    /// a window that grew: a smaller one whose far edge is in place was moved there by another hand.
    static func takesPlace(_ actual: CGRect, of frame: CGRect, pushedBack: Bool = false) -> Bool {
        func held(_ near: CGFloat, _ far: CGFloat, grew: Bool) -> Bool {
            abs(near) <= snapTolerance || pushedBack && grew && abs(far) <= snapTolerance
        }
        return held(actual.minX - frame.minX, actual.maxX - frame.maxX, grew: actual.width > frame.width)
            && held(actual.minY - frame.minY, actual.maxY - frame.maxY, grew: actual.height > frame.height)
            && abs(actual.width - frame.width) <= sizeStep && abs(actual.height - frame.height) <= sizeStep
    }

    /// 4.7: "T X" gives the window the whole area, nudged down and right; at the screen's edge
    /// it gives up what would stick out rather than land back where it was.
    static func detachedFrame(area: CGRect, visible: CGRect) -> CGRect {
        let moved = area.offsetBy(dx: detachOffset, dy: detachOffset)
        let inside = moved.intersection(visible)
        guard !inside.isNull, inside.width >= minimumMemberHeight, inside.height >= minimumMemberHeight else { return moved }
        return inside
    }

    /// 4.3: a tab dragged out of the bars opens as a window of `size` under the pointer.
    static func droppedFrame(size: CGSize, at point: CGPoint, visible: CGRect) -> CGRect {
        let frame = CGRect(x: point.x - dropGrip.width, y: point.y - dropGrip.height, width: size.width, height: size.height)
        return RectMath.clamp(frame, to: visible)
    }
}
