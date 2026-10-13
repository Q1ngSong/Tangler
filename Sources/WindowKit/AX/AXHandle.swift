import ApplicationServices

/// An Accessibility element usable as a dictionary key. Two handles are equal when they
/// name the same element of the same process.
struct AXHandle: Hashable, @unchecked Sendable {
    let element: AXUIElement

    static func == (lhs: AXHandle, rhs: AXHandle) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}
