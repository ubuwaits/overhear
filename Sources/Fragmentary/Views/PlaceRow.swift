import SwiftUI

struct PlaceRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    var selectionColor: Color = .accentColor
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(
                        isSelected ? Color.white : Color.secondary
                    )
                    .background {
                        Circle().fill(
                            isSelected ? selectionColor : Color.secondary.opacity(0.12)
                        )
                    }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary)

                Spacer()

            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color.primary.opacity(0.10)
        }
        return .clear
    }
}
