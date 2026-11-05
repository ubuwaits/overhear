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

    var blend: Double = 1.0 {
        didSet {
            if blend != oldValue, state == .active {
                engine.setBlend(blend)
            }
        }
    }

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
        case .active: selectedPlace.title
        case .error: "Needs attention"
        }
    }

    var errorMessage: String? {
        if case let .error(message) = state { message } else { nil }
    }

    func select(_ place: Place) {
        if isOn && selectedPlace == place {
            turnOff()
            return
        }
        selectedPlace = place
        if state == .active {
            engine.setPlace(place)
        } else {
            turnOn()
        }
    }

    private func turnOn() {
        guard state != .starting && state != .active else { return }
        // Bring privacy prompts forward for this otherwise accessory-only app.
        NSApplication.shared.activate(ignoringOtherApps: true)
        state = .starting
        transitionRevision += 1
        let revision = transitionRevision
        let previousTransition = transitionTask
        let place = selectedPlace
        let presence = blend

        transitionTask = Task { [weak self] in
            await previousTransition?.value
            guard let self else { return }
            do {
                try await engine.start(place: place, blend: presence)
                guard revision == transitionRevision else { return }
                // Selection and Presence may have changed while start awaited
                // the hardware. Apply the latest values before reporting active.
                if selectedPlace != place { engine.setPlace(selectedPlace) }
                if blend != presence { engine.setBlend(blend) }
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
