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
        .frame(width: 340)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(model.isOn ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                Image(systemName: model.isOn ? "waveform.path" : "waveform.path.badge.minus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(model.isOn ? Color.accentColor : Color.secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Fragmentary")
                    .font(.headline)
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { model.isOn },
                set: { _ in model.toggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(model.state == .starting)
        }
        .padding(16)
    }

    private var places: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PLACE")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(Place.allCases) { place in
                Button {
                    model.selectedPlace = place
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: place.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 24)
                            .foregroundStyle(model.selectedPlace == place ? Color.accentColor : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(place.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                        if model.selectedPlace == place {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.selectedPlace == place ? Color.accentColor.opacity(0.10) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let error = model.errorMessage {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Retry") {
                        model.retry()
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Label("Presence", systemImage: "circle.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.blend, in: 0...1)
                Text("\(Int(model.blend * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(14)
    }
}
