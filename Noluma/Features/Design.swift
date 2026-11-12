import SwiftUI

extension View {
    /// Liquid Glass where the system has it, a material everywhere else.
    @ViewBuilder
    func glass(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// The standard grouped card surface.
    func card(radius: CGFloat = 24) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The small rounded "Get" / "Open" button used wherever an app is listed.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var onColor = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(minWidth: 74, minHeight: 32)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: AnyShapeStyle {
        if onColor { return AnyShapeStyle(.black) }
        return prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)
    }

    private var background: AnyShapeStyle {
        if onColor { return AnyShapeStyle(.white) }
        return prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill))
    }
}

struct AppIconView: View {
    let icon: String
    let tint: String
    var size: CGFloat = 60

    var body: some View {
        let color = AppTint.color(tint)
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(color.gradient)
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            }
            .overlay {
                Image(systemName: AppSymbol.normalized(icon))
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: size * 0.03, y: size * 0.02)
            }
            .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: max(0.5, size * 0.008)) }
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.28), radius: size * 0.1, y: size * 0.05)
            .accessibilityHidden(true)
    }
}

/// A small uppercase section title, as used above grouped content.
struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
