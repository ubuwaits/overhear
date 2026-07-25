import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Audio") {
                LabeledContent("Current place", value: model.selectedPlace.title)
                LabeledContent("Status", value: model.statusText)
                Slider(value: $model.blend, in: 0...1) {
                    Text("Presence")
                }
            }

            Section {
                Text("Fragmentary uses macOS system-audio recording permission to catch the sound already playing on this Mac. Audio never leaves the computer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 260)
    }
}
