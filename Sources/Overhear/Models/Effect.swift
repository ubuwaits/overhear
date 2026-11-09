import Foundation
import OverhearDSP

struct Effect: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var values: [Double]
    var presence: Double = 1
    var scene: RoomScene?
    var room: RoomScene {
        get {
            if let scene { return scene }
            let place = Place.allCases.first { "factory-\($0.dspValue.rawValue)" == id } ?? .emptyMall
            var room = RoomScene.factory(place)
            if !isFactory, values.count > 1 {
                room.sources[0].kind = values[0] < 3500 ? .radio : .hifi
            }
            return room
        }
        set { scene = newValue }
    }
    var isFactory: Bool { id.hasPrefix("factory-") }

    static func factory(_ place: Place) -> Effect {
        Effect(id: "factory-\(place.dspValue.rawValue)", name: place.title,
               values: (0..<62).map { Double(OverhearDSPPresetParameter(place.dspValue, UInt32($0))) }, scene: .factory(place))
    }

    var validated: Effect {
        var copy = self
        copy.values = Parameter.all.map { p in
            guard values.indices.contains(p.id), values[p.id].isFinite else {
                return Double(OverhearDSPPresetParameter(OverhearPlaceEmptyMall, UInt32(p.id)))
            }
            return min(max(values[p.id], p.range.lowerBound), p.range.upperBound)
        }
        copy.presence = presence.isFinite ? min(max(presence, 0), 1) : 1
        copy.scene = room.validated
        return copy
    }
}

struct Parameter: Identifiable {
    let id: Int
    let name: String
    let range: ClosedRange<Double>
    var unit: String = ""
    var logarithmic = false

    func normalized(_ value: Double) -> Double {
        if logarithmic { return log(max(value, range.lowerBound) / range.lowerBound) / log(range.upperBound / range.lowerBound) }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    func value(_ fraction: Double) -> Double {
        if logarithmic { return range.lowerBound * pow(range.upperBound / range.lowerBound, fraction) }
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
    static let all: [Parameter] = {
        var p: [Parameter] = [
            .init(id: 0, name: "Low-pass", range: 20...20000, unit: "Hz", logarithmic: true),
            .init(id: 1, name: "High-pass", range: 20...20000, unit: "Hz", logarithmic: true),
            .init(id: 2, name: "Width", range: 0...2),
            .init(id: 3, name: "Pan", range: -1...1),
            .init(id: 4, name: "Drive", range: 0.1...6),
            .init(id: 5, name: "Flutter depth", range: 0...0.99),
            .init(id: 6, name: "Original source", range: 0...2),
            .init(id: 7, name: "Direct", range: 0...2),
            .init(id: 8, name: "Early reflections", range: 0...2),
            .init(id: 9, name: "Window returns", range: 0...2),
            .init(id: 10, name: "Late / reverb", range: 0...2),
            .init(id: 11, name: "Output gain", range: 0...2),
            .init(id: 12, name: "Damping", range: 0...0.99),
            .init(id: 13, name: "Feedback", range: 0...0.96),
            .init(id: 14, name: "Slow flutter", range: 0.05...20, unit: "Hz", logarithmic: true),
            .init(id: 15, name: "Fast flutter", range: 0.05...20, unit: "Hz", logarithmic: true),
            .init(id: 16, name: "Echo → diffuse", range: 0...1)
        ]
        for (start, count, name, range, unit) in [
            (17,8,"Early",1.0...1850.0,"ms"), (25,8,"Early gain",0.0...2.0,""),
            (33,3,"Window",1.0...1850.0,"ms"), (36,3,"Window gain",0.0...2.0,""),
            (39,3,"Window pan",0.0...1.0,""), (42,8,"Late",1.0...1850.0,"ms"),
            (50,8,"Late gain",0.0...2.0,""), (58,4,"Room line",5.0...500.0,"ms")
        ] {
            for i in 0..<count { p.append(.init(id: start+i, name: "\(name) \(i+1)", range: range, unit: unit)) }
        }
        return p.sorted { $0.id < $1.id }
    }()
}
