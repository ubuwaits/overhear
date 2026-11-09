import SwiftUI

struct EditorView: View {
    @Bindable var model: AppModel
    @State private var selection: RoomSelection = .room
    @State private var showPaths = false
    @State private var naming = false
    @State private var name = ""
    @State private var pending: Effect?
    @State private var confirmSwitch = false
    @State private var confirmDelete = false
    private var room: Binding<RoomScene> {
        Binding(get: { model.draft.room }, set: { model.draft.room = $0 })
    }

    var body: some View {
        HSplitView {
            library.frame(minWidth: 170, idealWidth: 190, maxWidth: 220)
            VStack(spacing: 0) {
                RoomCanvas(scene: room, selection: $selection, showPaths: showPaths)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }.frame(minWidth: 360, maxWidth: .infinity)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.draft.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if model.isModified { Circle().fill(.orange).frame(width: 4,height: 4) }
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Button("Save") { model.draft.isFactory ? saveCopy() : model.save() }.keyboardShortcut("s")
                        Button("Save As…") { saveCopy() }.keyboardShortcut("s",modifiers:[.command,.shift])
                        Button("Revert") { model.reset(); selection = .room }.disabled(!model.isModified)
                        if !model.draft.isFactory {
                            Menu("More") { Button("Delete Scene…",role:.destructive) { confirmDelete=true } }
                        }
                    }.font(.system(size: 11)).buttonStyle(.borderless)
                }.padding(14)
                Divider()
                RoomInspector(scene: room, selection: $selection, presence: $model.blend,
                              audioEnabled: Binding(get: { model.isOn }, set: { if $0 != model.isOn { model.toggle() } }),
                              showPaths: $showPaths)
            }
            .frame(minWidth: 280, idealWidth: 300, maxWidth: 320)
            .background(Color(white: 0.075))
        }
        .navigationTitle("Overhear")
        .preferredColorScheme(.dark)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: model.draft.id) { _, _ in selection = .room }
        .alert("Save scene", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.saveAs(name) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Unsaved changes", isPresented: $confirmSwitch) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Discard changes", role: .destructive) { if let pending { model.load(pending) }; pending = nil }
            Button("Save copy & switch") {
                if model.saveAs(model.draft.name + " copy"), let pending { model.load(pending) }
                pending = nil
            }
        } message: { Text("Save a copy before selecting another effect?") }
        .alert("Delete \(model.draft.name)?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { model.deleteSaved() }
        }
    }

    private var library: some View {
        List(selection: Binding<String?>(get: { model.draft.id }, set: { id in
            guard let id, id != model.draft.id,
                  let effect = (Place.allCases.map(Effect.factory) + model.saved).first(where: { $0.id == id }) else { return }
            if model.isModified { pending = effect; confirmSwitch = true } else { model.load(effect) }
        })) {
            Section("Presets") {
                ForEach(Place.allCases) { place in
                    Label(place.title, systemImage: place.symbol).tag(Effect.factory(place).id)
                }
            }
            Section("My Scenes") {
                ForEach(model.saved) { effect in
                    Label(effect.name, systemImage: "waveform").tag(effect.id)
                }
                Button("Save Current Scene…") { saveCopy() }
                    .font(.callout).foregroundStyle(.secondary).buttonStyle(.plain)
            }
        }.listStyle(.sidebar).scrollContentBackground(.hidden).background(Color(white: 0.075))
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                Circle().fill(model.isOn ? Color.orange : Color.secondary).frame(width: 5, height: 5)
                Text(model.isOn ? "System audio active" : "Audio bypassed")
                Spacer()
                if let error = model.errorMessage ?? model.storageError {
                    Text(error).foregroundStyle(.orange).lineLimit(2)
                    if model.errorMessage != nil { Button("Retry") { model.retry() } }
                } else {
                    Text("\(model.draft.room.sources.count) \(model.draft.room.sources.count == 1 ? "speaker" : "speakers")")
                    Text("·")
                    Text("\(model.draft.room.area.formatted(.number.precision(.fractionLength(1)))) m²")
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).frame(minHeight: 30)
        }.background(.bar)
    }
    private func saveCopy() { name = model.draft.name + " copy"; naming = true }
}
