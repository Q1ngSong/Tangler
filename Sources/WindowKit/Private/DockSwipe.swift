import CoreGraphics
import Darwin
import Foundation

/// Posts the gesture events the Dock takes for a trackpad swipe between Spaces, with a velocity
/// so high that the Space changes without the animation (measured on 26.6.1: 47 ms, against
/// 536–702 ms for the system's own Control-arrow; `scripts/probes/SwitchSpeedProbe.swift`,
/// variant B). The event fields are undocumented, so nothing here says whether the swipe took
/// effect: the caller reads the Space list.
enum DockSwipe {
    private static let began: Int64 = 1
    private static let changed: Int64 = 2
    private static let ended: Int64 = 4

    /// One swipe to the neighbouring Space; `sign` is +1 or −1, see `DesktopSwipe.sign`.
    static func post(sign: Double) {
        for phase in [began, changed, ended] {
            guard let event = CGEvent(source: nil) else { return }
            event.setIntegerValueField(field(55), value: 30)       // event type: Dock control
            event.setIntegerValueField(field(110), value: 23)      // gesture kind: Dock swipe
            event.setIntegerValueField(field(132), value: phase)
            event.setIntegerValueField(field(134), value: phase)
            event.setIntegerValueField(field(123), value: 1)       // horizontal
            event.setDoubleValueField(field(124), value: sign * 0.000016) // progress
            event.setDoubleValueField(field(138), value: 3.0)
            event.setDoubleValueField(field(169), value: Double(mach_absolute_time()))
            event.setDoubleValueField(field(125), value: 0.1)
            if phase == ended { event.setDoubleValueField(field(129), value: sign * 9999) } // velocity
            event.post(tap: .cgSessionEventTap)
            // The companion gesture event newer systems want after each one.
            guard let companion = CGEvent(source: nil) else { return }
            companion.setIntegerValueField(field(55), value: 29)
            companion.post(tap: .cgSessionEventTap)
        }
    }

    /// The "natural scrolling" preference; nil when it was never set, which the system takes for on.
    static func naturalScrolling() -> Bool? {
        CFPreferencesCopyValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
    }

    private static func field(_ number: UInt32) -> CGEventField {
        CGEventField(rawValue: number)!
    }
}
