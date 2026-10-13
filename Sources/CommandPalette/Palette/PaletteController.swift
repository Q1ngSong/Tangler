import CoreKit
import Contracts
import CoreGraphics

/// The search palette (design section 4.2): windows and commands in one list. Return switches to
/// the window, or runs the command on the window that was focused before the palette opened.
@MainActor
final class PaletteController {
    /// Off while the module is stopped.
    var isEnabled = false {
        didSet { if !isEnabled { close() } }
    }

    private let windows: any WindowService
    private let commands: any CommandRegistry
    private let presenter: any PalettePresenting
    private let hud: LeaderHUD
    private let areas: OverlayAreaFinder
    private let recency: RecencyLog
    private var model: PaletteModel?
    private var area = CGRect.zero
    private var frame: CGRect?
    /// The last window list, shown at once on the next open while a fresh one is read.
    private var knownWindows: [WindowInfo] = []

    init(context: ModuleContext, presenter: any PalettePresenting, hud: LeaderHUD, areas: OverlayAreaFinder,
         recency: RecencyLog) {
        windows = context.windows
        commands = context.commands
        self.presenter = presenter
        self.hud = hud
        self.areas = areas
        self.recency = recency
    }

    var isOpen: Bool { model != nil }

    /// Shows the palette acting on `target`; does nothing while it is open.
    func open(target: WindowID?) async {
        guard isEnabled, model == nil else { return }
        let model = PaletteModel(candidates: candidates(windows: knownWindows, dynamic: []), recency: recency,
                                 target: target)
        self.model = model
        area = await areas.area(for: target)
        guard self.model === model else { return }
        present(force: true)
        // A full window scan can take a moment, so the list fills in once it is done.
        let fresh = await windows.windows()
        knownWindows = fresh
        let dynamic = await commands.dynamicCommands()
        guard self.model === model else { return }
        model.setCandidates(candidates(windows: fresh, dynamic: dynamic))
        present()
    }

    /// Esc, or the leader key while open: closes and hands the keyboard back to the window the
    /// user was in, which the panel had taken.
    func cancel() {
        guard let model else { return }
        close()
        if let target = model.target { Task { _ = await windows.focus(target) } }
    }

    func close() {
        guard model != nil else { return }
        model = nil
        frame = nil
        presenter.hide()
    }

    func windowDisappeared(_ id: WindowID) {
        knownWindows.removeAll { $0.id == id }
        model?.removeWindow(id)
        present()
    }

    private var actions: PaletteActions {
        PaletteActions(
            setQuery: { [weak self] text in
                self?.model?.setQuery(text)
                self?.present()
            },
            move: { [weak self] rows in
                self?.model?.move(by: rows)
                self?.present()
            },
            submit: { [weak self] in self?.submit() },
            choose: { [weak self] id in
                self?.model?.select(id)
                self?.submit()
            },
            cancel: { [weak self] in self?.cancel() },
            dismiss: { [weak self] in self?.close() })
    }

    /// Shows the palette sized to its rows; only when that changes the frame, unless forced.
    private func present(force: Bool = false) {
        guard let model else { return }
        let frame = PaletteLayout.frame(rows: model.results.count, hasMessage: model.message != nil, in: area)
        guard force || frame != self.frame else { return }
        self.frame = frame
        presenter.show(model, in: frame, actions: actions)
    }

    private func submit() {
        guard let model, let item = model.selectedItem else { return }
        if item.needsNumber {
            model.message = model.query.isEmpty ? L10n.text("commandpalette.add.a.number.after.the.name.then") : L10n.text("commandpalette.add.a.number.for.example", String(describing: (model.query)))
            present()
            return
        }
        let target = model.target
        let area = self.area
        close()
        recency.touch(item.id)
        Task { [weak self] in await self?.run(item, target: target, area: area) }
    }

    private func run(_ item: PaletteItem, target: WindowID?, area: CGRect) async {
        let result: CommandResult
        switch item.kind {
        case .window(let window):
            switch await windows.focus(window.id) {
            case .success: result = .done
            case .failure(let error): result = .failed(reason: WindowErrorText.describe(error))
            }
        case .command(let spec, let argument):
            await giveKeyboardBack(to: target)
            result = await commands.perform(spec.id, context: CommandContext(targetWindow: target, argument: argument))
        case .dynamic(let command):
            await giveKeyboardBack(to: target)
            result = await commands.performDynamic(command)
        }
        guard isEnabled else { return }
        hud.report(result, title: item.title, in: area)
    }

    private func giveKeyboardBack(to target: WindowID?) async {
        if let target { _ = await windows.focus(target) }
    }

    private func candidates(windows: [WindowInfo], dynamic: [DynamicCommand]) -> PaletteSearch.Candidates {
        PaletteSearch.Candidates(windows: windows, commands: commands.commands, dynamicCommands: dynamic)
    }
}
