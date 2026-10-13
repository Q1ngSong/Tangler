import CoreKit
import Contracts
import CoreGraphics
import Foundation

/// Pointer and key input from the picker's panels, in global coordinates.
enum WindowPickerInput: Equatable, Sendable {
    case moved(CGPoint)
    case clicked(CGPoint)
    /// Esc or a right click.
    case cancelled
}

/// Puts the picker on screen. The real one covers every display with panels; tests use a recorder.
@MainActor
protocol WindowPickerPresenter: AnyObject {
    /// Shows `model.candidate` on every display and reports input until `dismiss()`.
    func present(model: WindowPickerModel, prompt: String, onInput: @escaping (WindowPickerInput) -> Void)
    func dismiss()
}

/// Lets the user point at a window on any display and click it. It only reads the window
/// list; the window under the pointer is never activated or moved.
@MainActor
public final class WindowPicker {
    let model: WindowPickerModel
    private let windows: any WindowService
    private let presenter: any WindowPickerPresenter
    private var continuation: CheckedContinuation<WindowInfo?, Never>?
    /// Counts picks, so late answers and cancellations of an earlier pick change nothing.
    private var session = 0

    public convenience init(windows: any WindowService) {
        self.init(windows: windows, presenter: ScreenPickerPresenter(),
                  ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    init(windows: any WindowService, presenter: any WindowPickerPresenter, ownPID: Int32) {
        self.windows = windows
        self.presenter = presenter
        model = WindowPickerModel(resolve: WindowPickerModel.resolver(for: windows, ignoring: ownPID))
    }

    public var isPicking: Bool { continuation != nil }

    /// The clicked window; nil after Esc, a right click, `cancel()`, cancelling the calling
    /// task, or right away without window access. Starting a new pick ends the current one.
    public func pick(prompt: String = L10n.text("overlaykit.click.a.window.to.select.it")) async -> WindowInfo? {
        cancel()
        guard windows.isAuthorized, !Task.isCancelled else { return nil }
        session += 1
        let current = session
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                model.reset()
                presenter.present(model: model, prompt: prompt) { [weak self] input in
                    Task { await self?.handle(input) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(nil, session: current) }
        }
    }

    public func cancel() {
        finish(nil, session: session)
    }

    func handle(_ input: WindowPickerInput) async {
        guard isPicking else { return }
        let current = session
        switch input {
        case .moved(let point):
            await model.hover(at: point)
        case .clicked(let point):
            guard let window = await model.window(at: point) else { return }
            finish(window, session: current)
        case .cancelled:
            finish(nil, session: current)
        }
    }

    private func finish(_ window: WindowInfo?, session expected: Int) {
        guard expected == session, let continuation else { return }
        self.continuation = nil
        model.reset()
        presenter.dismiss()
        continuation.resume(returning: window)
    }
}
