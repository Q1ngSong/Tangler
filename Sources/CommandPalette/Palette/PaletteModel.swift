import Contracts
import Observation

/// What one open palette shows: the query, its results and the selection.
@MainActor
@Observable
final class PaletteModel {
    private(set) var query = ""
    private(set) var results: [PaletteItem] = []
    private(set) var selectedID: PaletteItemID?
    /// A hint under the list, e.g. that the selected command needs a number.
    var message: String?
    /// Every palette starts with the search field focused, also when a reused panel's field
    /// lost focus last time.
    var isFieldFocused = true

    /// The window commands act on: the one focused before the palette opened.
    @ObservationIgnored let target: WindowID?
    @ObservationIgnored private var candidates: PaletteSearch.Candidates
    @ObservationIgnored private let recency: RecencyLog
    /// True once the user picked a row with the arrows or the mouse; until then the top row
    /// stays selected while the list fills in.
    @ObservationIgnored private var userSelected = false

    init(candidates: PaletteSearch.Candidates, recency: RecencyLog, target: WindowID?) {
        self.candidates = candidates
        self.recency = recency
        self.target = target
        refresh()
    }

    var selectedItem: PaletteItem? { results.first { $0.id == selectedID } }

    /// A new query selects its best match.
    func setQuery(_ text: String) {
        guard text != query else { return }
        query = text
        message = nil
        userSelected = false
        refresh()
    }

    /// New candidates, e.g. the window list arriving.
    func setCandidates(_ candidates: PaletteSearch.Candidates) {
        self.candidates = candidates
        refresh()
    }

    func removeWindow(_ id: WindowID) {
        candidates.windows.removeAll { $0.id == id }
        refresh()
    }

    /// Stops at the first and last rows instead of wrapping around.
    func move(by rows: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(current + rows, 0), results.count - 1)].id
        userSelected = true
        message = nil
    }

    func select(_ id: PaletteItemID) {
        guard results.contains(where: { $0.id == id }) else { return }
        selectedID = id
        userSelected = true
    }

    private func refresh() {
        results = PaletteSearch.results(for: query, in: candidates, recency: recency, target: target)
        if userSelected, results.contains(where: { $0.id == selectedID }) { return }
        userSelected = false
        selectedID = results.first?.id
    }
}
