import AppKit
import SwiftUI

struct PlacePopoverView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            places
            Divider()
            controls
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(model.isOn ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                Image(systemName: model.isOn ? "waveform.path" : "waveform.path.badge.minus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.isOn ? Color.accentColor : Color.secondary)
            }
            .frame(width: 26, height: 26)

            Text("Fragmentary")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.isOn },
                set: { _ in model.toggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(model.state == .starting)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var places: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PLACE")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            ForEach(Place.allCases) { place in
                PlaceRow(
                    place: place,
                    isSelected: model.selectedPlace == place
                ) {
                    model.selectedPlace = place
                }
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
                Image(systemName: "circle.lefthalf.filled")
                    .frame(width: 20)
                Text("Presence")
                Slider(value: $model.blend, in: 0...1)
                Text("\(Int(model.blend * 100))%")
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            Divider()

            QuitMenuRow {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
    }
}
