import Contracts
import CoreGraphics
import CoreKit

/// One app's preview data: its windows, then their thumbnails as they arrive. Loading starts
/// while the pointer still rests on the icon, so the thumbnails are usually there when the
/// preview opens.
@MainActor
final class DockPreviewSession {
    var item: DockItem
    /// When loading began, for the trace.
    let startedAt = ContinuousClock.now
    private let log = DiagnosticLog("dock")
    /// nil until loaded.
    private(set) var windows: [WindowInfo]?
    private(set) var thumbnails: [WindowID: CGImage] = [:]
    /// Whether the preview has shown this session; the single-window rule only applies before.
    var hasBeenShown = false
    /// Called when the windows or a thumbnail arrive.
    var onChange: (() -> Void)?
    var task: Task<Void, Never>?

    init(item: DockItem) {
        self.item = item
    }

    func load(windows service: any WindowService, capture: any CaptureService) async {
        log.trace("开始加载「\(item.appName)」")
        let all = await service.windows()
        guard !Task.isCancelled else { return }
        let own = Self.appWindows(in: all, pid: item.pid)
        log.trace("「\(item.appName)」列出 \(own.count) 个窗口（全部 \(all.count) 个），\(elapsed)")
        windows = own
        onChange?()
        guard capture.isAuthorized else { return }
        await withTaskGroup(of: (WindowID, CGImage?).self) { group in
            for window in own {
                let size = DockPreviewLayout.thumbnailPixelSize(for: window.frame.size)
                group.addTask { (window.id, await capture.thumbnail(of: window.id, maxPixelSize: size)) }
            }
            for await (id, image) in group where !Task.isCancelled {
                log.trace("「\(item.appName)」窗口 \(id.rawValue) 缩略图\(image == nil ? "没拿到" : "到了")，\(elapsed)")
                guard let image, windows?.contains(where: { $0.id == id }) == true else { continue }
                thumbnails[id] = image
                onChange?()
            }
        }
    }

    /// "距开始加载 120ms", for the trace.
    var elapsed: String {
        let duration = startedAt.duration(to: .now)
        let ms = Int((Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18) * 1000)
        return "距开始加载 \(ms)ms"
    }

    func cancel() {
        task?.cancel()
        onChange = nil
    }

    /// False when the window is not in this session.
    @discardableResult
    func remove(_ id: WindowID) -> Bool {
        guard let index = windows?.firstIndex(where: { $0.id == id }) else { return false }
        windows?.remove(at: index)
        thumbnails[id] = nil
        return true
    }

    @discardableResult
    func update(_ id: WindowID, _ change: (inout WindowInfo) -> Void) -> Bool {
        guard let index = windows?.firstIndex(where: { $0.id == id }) else { return false }
        change(&windows![index])
        return true
    }

    /// The app's windows in the service's order, minimized ones last.
    static func appWindows(in all: [WindowInfo], pid: Int32?) -> [WindowInfo] {
        guard let pid else { return [] }
        let own = all.filter { $0.pid == pid }
        return own.filter { !$0.isMinimized } + own.filter(\.isMinimized)
    }
}
