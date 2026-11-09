import Foundation
import Testing
@testable import Overhear

@Test("Saved effects and unsaved drafts survive relaunch")
@MainActor func effectPersistence() throws {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "effects.json")
    let model = AppModel(libraryURL: url)
    model.load(.factory(.kitchenRadio))
    model.draft.room.width = 12
    model.blend = 0.7
    #expect(model.saveAs("Custom radio"))
    model.draft.room.listener.x = 0.4
    let restored = AppModel(libraryURL: url)
    #expect(restored.saved.count == 1)
    #expect(restored.saved[0].room.width == 12)
    #expect(restored.saved[0].presence == 0.7)
    #expect(restored.draft.room.listener.x == 0.4)
    #expect(restored.isModified)
    restored.reset()
    #expect(!restored.isModified)
    restored.draft.room.sources[0].kind = .phone
    restored.save()
    let updated = AppModel(libraryURL: url)
    #expect(updated.saved[0].room.sources[0].kind == .phone)
    #expect(!updated.isModified)
    updated.deleteSaved()
    #expect(AppModel(libraryURL: url).saved.isEmpty)
}

@Test("Factory presets stay immutable and malformed values are bounded")
@MainActor func factoryProtection() {
    let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = AppModel(libraryURL: root.appending(path: "effects.json"))
    model.draft.values[0] = 2000
    model.save()
    #expect(model.saved.isEmpty)
    model.reset()
    #expect(model.draft == .factory(.emptyMall))
    var malformed = Effect.factory(.emptyMall)
    malformed.values = [.infinity, -500]
    let valid = malformed.validated
    #expect(valid.values.count == 62)
    #expect(valid.values.allSatisfy { $0.isFinite })
    #expect(valid.values[1] == 20)
}
