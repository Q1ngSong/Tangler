import Contracts

/// The windows the switcher can list, most recently focused first. It follows the window
/// events, so opening the switcher does not have to wait for a full window scan.
struct WindowCatalog {
    private var infos: [WindowID: WindowInfo] = [:]
    /// Focus history, most recent first. May name a window whose info has not arrived yet.
    private var recent: [WindowID] = []
    /// Every known window in the window service's order, newest first.
    private var listed: [WindowID] = []
    /// False until the first scan; the events alone do not describe the windows that existed before.
    private(set) var isPrimed = false

    /// Focused windows by recency, then the others in the window service's order.
    var windows: [WindowInfo] {
        let focused = Set(recent)
        return (recent + listed.filter { !focused.contains($0) }).compactMap { infos[$0] }
    }

    func window(_ id: WindowID) -> WindowInfo? { infos[id] }

    /// Takes a full scan; the focus history stays for windows that still exist.
    mutating func replace(with windows: [WindowInfo]) {
        infos = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        var seen = Set<WindowID>()
        listed = windows.map(\.id).filter { seen.insert($0).inserted }
        recent.removeAll { infos[$0] == nil }
        isPrimed = true
    }

    mutating func noteFocus(_ id: WindowID) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    mutating func apply(_ event: WindowEvent) {
        switch event {
        case .appeared(let info):
            infos[info.id] = info
            listed.removeAll { $0 == info.id }
            listed.insert(info.id, at: 0)
        case .disappeared(let id):
            forget([id])
        case .moved(let id, let frame), .resized(let id, let frame):
            infos[id]?.frame = frame
        case .focused(let id):
            noteFocus(id)
        case .minimized(let id):
            infos[id]?.isMinimized = true
        case .restored(let id):
            infos[id]?.isMinimized = false
        case .titleChanged(let id, let title):
            infos[id]?.title = title
        case .appTerminated(let pid):
            forget(infos.values.filter { $0.pid == pid }.map(\.id))
        case .currentSpaceChanged, .spacesChanged, .displaysChanged, .exposeChanged, .appLaunched, .appHidden,
             .appUnhidden:
            break
        }
    }

    private mutating func forget(_ ids: [WindowID]) {
        let gone = Set(ids)
        for id in gone { infos[id] = nil }
        listed.removeAll { gone.contains($0) }
        recent.removeAll { gone.contains($0) }
    }
}
