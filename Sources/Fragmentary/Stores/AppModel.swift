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

    var selectedPlace: Place = .afterClosing {
        didSet {
            guard selectedPlace != oldValue else { return }
            engine.setPlace(selectedPlace)
            if state == .off || isError {
                turnOn()
            }
        }
    }

    var blend: Double = 0.72 {
        didSet {
            engine.setBlend(blend)
        }
    }

    private(set) var state: State = .off
    private let engine = SystemAudioEngine()

    var isOn: Bool {
        state == .starting || state == .active
    }

    var isError: Bool {
        if case .error = state { true } else { false }
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

    func toggle() {
        isOn ? turnOff() : turnOn()
    }

    func turnOn() {
        guard state != .starting && state != .active else { return }
        // Bring privacy prompts forward for this otherwise accessory-only app.
        NSApplication.shared.activate(ignoringOtherApps: true)
        state = .starting
        Task {
            do {
                try await engine.start(place: selectedPlace, blend: blend)
                state = .active
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    func turnOff() {
        state = .off
        Task {
            await engine.stop()
        }
    }

    func retry() {
        state = .off
        turnOn()
    }
}
