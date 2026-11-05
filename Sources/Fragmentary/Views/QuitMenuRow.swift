import SwiftUI

struct QuitMenuRow: View {
    let quit: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: quit) {
            HStack(spacing: 10) {
                Text("Quit Fragmentary")
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(isHovered ? .white : .primary)
        .background(
            isHovered ? Color.accentColor : .clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onHover { isHovered = $0 }
        .keyboardShortcut("q", modifiers: .command)
    }
}
