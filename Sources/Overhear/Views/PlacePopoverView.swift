import AppKit
import SwiftUI

struct PlacePopoverView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            places
            Divider()
                .padding(.horizontal, 18)
            controls
        }
        .frame(width: 300)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private var places: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Place.allCases) { place in
                PlaceRow(
                    title: place.title,
                    symbol: place.symbol,
                    isSelected: model.isOn && model.selectedPlace == place
                ) {
                    model.select(place)
                }
            }
            PlaceRow(title: "No filter", symbol: "speaker.wave.2", isSelected: model.state == .off, selectionColor: .gray) {
                model.turnOff()
            }
        }
        .padding(10)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") {
                        model.retry()
                    }
                    .controlSize(.small)
                }
                .font(.system(size: 12))
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 10) {
                Text("Presence")
                Slider(value: $model.blend, in: 0...1)
                    .disabled(!model.isOn)
                Text("\(Int(model.blend * 100))%")
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            Divider()
                .padding(.horizontal, 8)

            QuitMenuRow {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
    }
}
