import SwiftUI

/// Keeps a setting's explanation inside its label rather than in an unrelated form row.
public struct SettingsControlLabel: View {
    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(SettingsTypography.body).foregroundStyle(.primary)
            if let detail {
                Text(detail).font(SettingsTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, detail == nil ? 0 : 2)
    }
}

/// A shared value column and a stacked fallback keep sliders readable in narrow windows.
/// This view only edits its binding; each module retains its existing save/debounce policy.
public struct SettingsSlider: View {
    private let title: String
    private let value: Binding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private let formattedValue: String

    public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                step: Double, formattedValue: String) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.formattedValue = formattedValue
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 12)
                slider.frame(width: 168)
                readout.fixedSize().frame(minWidth: 64, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    readout.fixedSize()
                }
                slider
            }
        }
        .font(SettingsTypography.body)
        .padding(.vertical, 3)
    }

    private var readout: some View {
        Text(formattedValue).monospacedDigit().foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var slider: some View {
        Slider(value: value, in: range, step: step) { Text(title) }
            .labelsHidden()
            .accessibilityValue(formattedValue)
    }
}
