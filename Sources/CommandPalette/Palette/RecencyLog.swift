/// When each window or command was last used, as increasing stamps. Windows count as used when
/// they gain focus; commands when they run from the leader or the palette.
@MainActor
final class RecencyLog {
    private var stamps: [PaletteItemID: Int] = [:]
    private var clock = 0

    func touch(_ id: PaletteItemID) {
        clock += 1
        stamps[id] = clock
    }

    func forget(_ id: PaletteItemID) {
        stamps[id] = nil
    }

    /// Larger is more recent; nil when never used.
    func stamp(of id: PaletteItemID) -> Int? {
        stamps[id]
    }
}
