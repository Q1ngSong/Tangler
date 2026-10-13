import SwiftUI

/// One outline in both states; lifting the lid indicates that the recycle bin is open.
public struct SettingsTrashIcon: View {
    public let isOpen: Bool

    public init(isOpen: Bool) { self.isOpen = isOpen }

    public var body: some View {
        ZStack {
            TrashOutline(lid: false)
            TrashOutline(lid: true)
                .rotationEffect(.degrees(isOpen ? -20 : 0), anchor: UnitPoint(x: 4.5 / 24, y: 6.8 / 24))
                .offset(y: isOpen ? -0.8 : 0)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct TrashOutline: View {
    let lid: Bool

    var body: some View {
        TrashPath(lid: lid).stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
}

private struct TrashPath: Shape {
    let lid: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if lid {
            path.move(to: CGPoint(x: 4.5, y: 6.8))
            path.addLine(to: CGPoint(x: 19.5, y: 6.8))
            path.move(to: CGPoint(x: 9, y: 6.8))
            path.addLine(to: CGPoint(x: 9, y: 4.5))
            path.addLine(to: CGPoint(x: 15, y: 4.5))
            path.addLine(to: CGPoint(x: 15, y: 6.8))
        } else {
            path.move(to: CGPoint(x: 6.2, y: 9))
            path.addLine(to: CGPoint(x: 7.3, y: 19.6))
            path.addQuadCurve(to: CGPoint(x: 8.8, y: 21), control: CGPoint(x: 7.4, y: 21))
            path.addLine(to: CGPoint(x: 15.2, y: 21))
            path.addQuadCurve(to: CGPoint(x: 16.7, y: 19.6), control: CGPoint(x: 16.6, y: 21))
            path.addLine(to: CGPoint(x: 17.8, y: 9))
            for x in [10.0, 14.0] {
                path.move(to: CGPoint(x: x, y: 10.5))
                path.addLine(to: CGPoint(x: x, y: 17.5))
            }
        }
        let scale = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale))
    }
}
