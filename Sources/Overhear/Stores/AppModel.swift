import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case off
        case starting
        case active
        case error(String)
    }

    private(set) var selectedPlace: Place = .emptyMall
    var draft: Effect = .factory(.emptyMall) {
        didSet {
            if state == .active { engine.setEffect(draft) }
            persist()
        }
    }
    private(set) var saved: [Effect] = []
    var storageError: String?
    var blend: Double {
        get { draft.presence }
        set { draft.presence = newValue }
    }
    var baseline: Effect {
        (Place.allCases.map(Effect.factory) + saved).first { $0.id == draft.id } ?? .factory(.emptyMall)
    }
    var isModified: Bool { draft != baseline }
    private struct Library: Codable { var saved: [Effect]; var draft: Effect }
    private let libraryURL: URL

    init(libraryURL: URL = URL.applicationSupportDirectory.appending(path: "Overhear/effects.json")) {
        self.libraryURL = libraryURL
        guard FileManager.default.fileExists(atPath: libraryURL.path) else { return }
        do {
            let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL))
            saved = library.saved.filter { !$0.isFactory }.map(\.validated)
            draft = library.draft.validated
        } catch { storageError = "Could not read saved effects: \(error.localizedDescription)" }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: libraryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Library(saved: saved, draft: draft)).write(to: libraryURL, options: .atomic)
            storageError = nil
        } catch { storageError = "Could not save effects: \(error.localizedDescription)" }
    }

    func load(_ effect: Effect) { draft = effect }
    func reset() { draft = baseline }
    @discardableResult
    func saveAs(_ name: String) -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        var effect = draft
        effect.id = UUID().uuidString
        effect.name = title
        saved.append(effect)
        draft = effect
        return storageError == nil
    }
    func save() {
        guard let index = saved.firstIndex(where: { $0.id == draft.id }) else { return }
        saved[index] = draft
        persist()
    }
    func deleteSaved() {
        guard !draft.isFactory else { return }
        saved.removeAll { $0.id == draft.id }
        draft = .factory(.emptyMall)
    }
    func toggle() { isOn ? turnOff() : turnOn() }

    private(set) var state: State = .off
    private let engine = SystemAudioEngine()
    private var transitionTask: Task<Void, Never>?
    private var transitionRevision = 0

    var isOn: Bool {
        state == .starting || state == .active
    }

    var statusText: String {
        switch state {
        case .off: "Off"
        case .starting: "Starting…"
        case .active: draft.name
        case .error: "Needs attention"
        }
    }

    var errorMessage: String? {
        if case let .error(message) = state { message } else { nil }
    }

    func select(_ place: Place) {
        if isOn && draft.id == Effect.factory(place).id {
            turnOff()
            return
        }
        let presence = blend
        if draft.room != baseline.room && !saveAs(draft.name + " copy") { return }
        selectedPlace = place
        var effect = Effect.factory(place)
        effect.presence = presence
        load(effect)
        if !isOn { turnOn() }
    }

    private func turnOn() {
        guard state != .starting && state != .active else { return }
        // Bring privacy prompts forward for this otherwise accessory-only app.
        NSApplication.shared.activate(ignoringOtherApps: true)
        state = .starting
        transitionRevision += 1
        let revision = transitionRevision
        let previousTransition = transitionTask
        let effect = draft

        transitionTask = Task { [weak self] in
            await previousTransition?.value
            guard let self else { return }
            do {
                try await engine.start(effect: effect)
                guard revision == transitionRevision else { return }
                // Selection and Presence may have changed while start awaited
                // the hardware. Apply the latest values before reporting active.
                engine.setEffect(draft)
                state = .active
            } catch {
                guard revision == transitionRevision else { return }
                state = .error(error.localizedDescription)
            }
        }
    }

    func turnOff() {
        guard state != .off else { return }
        state = .off
        transitionRevision += 1
        let previousTransition = transitionTask

        transitionTask = Task { [weak self] in
            await previousTransition?.value
            guard let self else { return }
            await engine.stop()
        }
    }

    func retry() {
        turnOn()
    }
}
