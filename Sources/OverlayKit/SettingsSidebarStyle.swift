import SwiftUI

public extension View {
    /// The native List owns selection and keyboard handling; this draws its selected and hover states.
    func settingsSidebarRow(selected: Bool, compact: Bool = false) -> some View {
        modifier(SettingsSidebarRow(selected: selected, compact: compact))
    }
}

private struct SettingsSidebarRow: ViewModifier {
    let selected: Bool
    let compact: Bool
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .font(SettingsTypography.sidebarItem)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .frame(height: 36)
            .background {
                if selected {
                    shape.fill(LinearGradient(colors: [Color(red: 0.15, green: 0.55, blue: 1),
                                                       Color(red: 0.03, green: 0.44, blue: 0.94)],
                                              startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(.white.opacity(contrast == .increased ? 0.8 : 0.35), lineWidth: 1))
                        .overlay(shape.inset(by: 1).strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.5))
                        .shadow(color: .blue.opacity(0.13), radius: 4, y: 3)
                } else if hovering {
                    shape.fill(.primary.opacity(0.055))
                }
            }
            .background(SettingsListSelection().allowsHitTesting(false))
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
