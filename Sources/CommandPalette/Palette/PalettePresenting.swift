import CoreGraphics

/// What the palette view asks the controller to do.
@MainActor
struct PaletteActions {
    var setQuery: (String) -> Void
    /// Moves the selection by rows; negative is up.
    var move: (Int) -> Void
    /// Return: runs the selected row.
    var submit: () -> Void
    /// A click on a row runs it.
    var choose: (PaletteItemID) -> Void
    /// Esc: closes and gives the keyboard back to the window the palette acts on.
    var cancel: () -> Void
    /// The panel lost the keyboard because the user clicked elsewhere: closes and leaves focus alone.
    var dismiss: () -> Void
}

/// Puts the palette on screen; tests record it instead.
@MainActor
protocol PalettePresenting: AnyObject {
    /// Shows the palette in `frame` (global coordinates) and gives it the keyboard; when it is
    /// already shown, moves it there.
    func show(_ model: PaletteModel, in frame: CGRect, actions: PaletteActions)
    func hide()
}
