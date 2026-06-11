import SwiftUI

struct FitsButton: View {
    enum Variant {
        case primary
        case secondary
    }

    enum Size {
        case header
        case modal
        case compact
        case fullWidth
    }

    let title: String
    let systemImage: String
    var variant: Variant = .primary
    var size: Size = .modal
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(font)
                .foregroundStyle(foreground)
                .frame(maxWidth: size == .fullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(border, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private var font: Font {
        switch size {
        case .header, .modal, .fullWidth:
            .system(size: 12, weight: .bold)
        case .compact:
            .system(size: 11.5, weight: .bold)
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .header:
            13
        case .modal:
            12
        case .compact:
            10
        case .fullWidth:
            12
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .header, .modal:
            8
        case .compact, .fullWidth:
            7
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .header:
            8
        case .modal, .compact, .fullWidth:
            7
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary:
            Color.black.opacity(0.88)
        case .secondary:
            Color.fitsText
        }
    }

    private var background: Color {
        switch variant {
        case .primary:
            Color.white
        case .secondary:
            Color.fitsElevated
        }
    }

    private var border: Color {
        switch variant {
        case .primary:
            Color.white.opacity(0.12)
        case .secondary:
            Color.fitsLine
        }
    }
}
