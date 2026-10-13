import SwiftUI

/// All demonstration movement uses the same eight-second rhythm and eased transitions.
public struct SettingsDemoPhase {
    public static let duration = 8.0
    public let time: Double

    public init(time: Double, repeats: Bool = true) {
        self.time = repeats ? max(0, time).truncatingRemainder(dividingBy: Self.duration)
            : min(Self.duration, max(0, time))
    }

    public func ramp(_ start: Double, _ end: Double) -> Double {
        let value = min(1, max(0, (time - start) / max(0.001, end - start)))
        return value * value * (3 - 2 * value)
    }

    public var entered: Double { ramp(0.2, 1.4) }
    public var action: Double { ramp(1.8, 2.8) * (1 - ramp(6.3, 7.5)) }
    public var travel: Double { ramp(0.6, 1.8) * (1 - ramp(6.5, 7.6)) }
    public var cursorOpacity: Double { ramp(0.2, 0.6) * (1 - ramp(6.2, 7.2)) }
    public var click: Double { time >= 1.8 && time <= 2.35 ? (time - 1.8) / 0.55 : -1 }
    public var inputActive: Bool { time >= 1.7 && time < 3.1 }
}

private struct SettingsPreviewTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

public extension EnvironmentValues {
    /// A fixed timestamp for native gallery captures. Normal settings use the live clock.
    var settingsPreviewTime: Double? {
        get { self[SettingsPreviewTimeKey.self] }
        set { self[SettingsPreviewTimeKey.self] = newValue }
    }
}

public struct SettingsPreviewPlayback<Content: View>: View {
    private let replay: Int
    private let repeats: Bool
    private let content: (SettingsDemoPhase) -> Content
    @State private var started = Date()
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsPreviewTime) private var fixedTime

    public init(replay: Int = 0, repeats: Bool = true, @ViewBuilder content: @escaping (SettingsDemoPhase) -> Content) {
        self.replay = replay
        self.repeats = repeats
        self.content = content
    }

    public var body: some View {
        Group {
            if let fixedTime {
                content(SettingsDemoPhase(time: fixedTime, repeats: repeats))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || finished)) { context in
                    content(SettingsDemoPhase(time: reduceMotion ? 4.2 : context.date.timeIntervalSince(started), repeats: repeats))
                }
            }
        }
        .task(id: replay) {
            started = Date()
            finished = false
            guard !repeats, fixedTime == nil else { return }
            try? await Task.sleep(for: .seconds(SettingsDemoPhase.duration))
            guard !Task.isCancelled else { return }
            finished = true
        }
    }
}

/// An illustrative pointer, including a brief click ripple. It never handles real input.
public struct SettingsPreviewCursor: View {
    private let click: Double

    public init(click: Double = -1) { self.click = click }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if click >= 0 {
                Circle().stroke(.white.opacity(1 - click), lineWidth: 1.5)
                    .frame(width: 28, height: 28).scaleEffect(0.5 + click)
                    .offset(x: -14, y: -14)
            }
            PointerShape().fill(Color(white: 0.12))
                .overlay(PointerShape().stroke(.white, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)))
                .frame(width: 14, height: 21)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
        }
        .frame(width: 14, height: 21, alignment: .topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [(CGFloat, CGFloat)] = [(0.08, 0.02), (0.94, 0.61), (0.56, 0.65), (0.81, 0.94),
                                            (0.57, 1), (0.36, 0.7), (0.08, 0.91)]
        path.addLines(points.map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) })
        path.closeSubpath()
        return path
    }
}
