import Contracts

/// What each slot of a bar shows while something is dragged over it (tab drop preview design
/// 4.2, 4.3): the bar as it would be after the drop. A window from outside adds a slot; a tab of
/// the bar only changes places.
struct TabBarArrangement: Equatable {
    struct Slot: Equatable, Identifiable {
        enum Kind: Equatable {
            case tab
            /// One of the bar's own tabs, dragged to this slot.
            case moving
            /// A window or tab from outside that would join here.
            case incoming
        }

        var tab: TabItem
        var kind: Kind
        /// Dragged away from this bar: drawn faded, still in its place.
        var isFaded: Bool

        var id: WindowID { tab.id }
    }

    /// Left to right.
    let slots: [Slot]
    /// Something from outside would join this bar: the bar is ringed.
    let isJoining: Bool

    /// The windows left to right; the tabs slide when this changes.
    var order: [WindowID] { slots.map(\.id) }

    init(tabs: [TabItem], incoming: IncomingTab?, leaving: WindowID?) {
        var slots = tabs.map { Slot(tab: $0, kind: .tab, isFaded: $0.id == leaving) }
        guard let incoming else {
            self.slots = slots
            isJoining = false
            return
        }
        var arriving = Slot(tab: incoming.tab, kind: .incoming, isFaded: false)
        let own = slots.firstIndex { $0.id == incoming.tab.id }
        if let own { arriving = Slot(tab: slots.remove(at: own).tab, kind: .moving, isFaded: false) }
        slots.insert(arriving, at: min(max(incoming.slot, 0), slots.count))
        self.slots = slots
        isJoining = own == nil
    }
}
