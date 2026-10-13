import Contracts

/// What a declared layout command does.
enum LayoutCommand: Equatable, Sendable {
    case place(LayoutAction)
    /// "回到上一次的位置".
    case goBack
    case moveToDisplay(Direction)
    /// `.number` takes the digit from `CommandContext.argument` when it runs.
    case moveToDesktop(DesktopStep)

    /// Every command in `LayoutCommands.all`; a test checks that the two lists agree.
    static let byID: [CommandID: LayoutCommand] = [
        "layout.leftHalf": .place(.leftHalf),
        "layout.rightHalf": .place(.rightHalf),
        "layout.topHalf": .place(.topHalf),
        "layout.bottomHalf": .place(.bottomHalf),
        "layout.topLeft": .place(.topLeft),
        "layout.topRight": .place(.topRight),
        "layout.bottomLeft": .place(.bottomLeft),
        "layout.bottomRight": .place(.bottomRight),
        "layout.maximize": .place(.maximize),
        "layout.center": .place(.center),
        "layout.restore": .goBack,
        "layout.displayLeft": .moveToDisplay(.left),
        "layout.displayRight": .moveToDisplay(.right),
        "layout.displayUp": .moveToDisplay(.up),
        "layout.displayDown": .moveToDisplay(.down),
        "layout.spaceLeft": .moveToDesktop(.left),
        "layout.spaceRight": .moveToDesktop(.right),
        "layout.spaceNumber": .moveToDesktop(.number(nil)),
    ]
}
