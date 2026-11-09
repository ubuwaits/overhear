import Foundation
import OverhearDSP

struct RoomPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    static func +(a: Self, b: Self) -> Self { .init(x: a.x+b.x, y: a.y+b.y) }
    static func -(a: Self, b: Self) -> Self { .init(x: a.x-b.x, y: a.y-b.y) }
    static func *(a: Self, b: Double) -> Self { .init(x: a.x*b, y: a.y*b) }
    var length: Double { hypot(x,y) }
    func dot(_ b: Self) -> Double { x*b.x+y*b.y }
    func cross(_ b: Self) -> Double { x*b.y-y*b.x }
}

enum RoomMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case concrete, glass, wood, plaster, carpet, curtain
    var id: Self { self }
    var title: String { rawValue.capitalized }
    // Broad artistic material profiles (mid/high absorption), not measured products.
    var absorption: Double {
        switch self { case .concrete: 0.04; case .glass: 0.07; case .wood: 0.18; case .plaster: 0.12; case .carpet: 0.55; case .curtain: 0.65 }
    }
    var highAbsorption: Double {
        switch self { case .concrete: 0.07; case .glass: 0.05; case .wood: 0.3; case .plaster: 0.18; case .carpet: 0.85; case .curtain: 0.9 }
    }
    var transmission: Double {
        switch self { case .concrete: 0.04; case .glass: 0.18; case .wood: 0.13; case .plaster: 0.22; case .carpet: 0.32; case .curtain: 0.55 }
    }
}

enum SpeakerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hifi, radio, phone, pa
    var id: Self { self }
    var title: String { switch self { case .hifi: "Hi-fi"; case .radio: "Radio"; case .phone: "Phone"; case .pa: "PA speaker" } }
    var tone: (low: Double, high: Double, drive: Double) {
        switch self {
        case .hifi: (18000, 35, 1)
        case .radio: (2600, 350, 2.3)
        case .phone: (4500, 650, 1.5)
        case .pa: (6500, 140, 1.3)
        }
    }
}

struct RoomSource: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var position: RoomPoint
    var heading: Double = 180
    var kind: SpeakerKind = .hifi
    var level: Double = 1
}

struct RoomPartition: Codable, Equatable, Sendable {
    var position: Double = 0.5
    var material: RoomMaterial = .plaster
    var opening: Double = 0
}

struct RoomScene: Codable, Equatable, Sendable {
    static let maximumSources = Int(OVERHEAR_SCENE_SOURCE_COUNT)
    var width: Double = 8
    var depth: Double = 6
    var height: Double = 3
    var corners: [RoomPoint] = [.init(x: 0,y: 0), .init(x: 1,y: 0), .init(x: 1,y: 1), .init(x: 0,y: 1)]
    var walls: [RoomMaterial] = Array(repeating: .plaster, count: 4)
    var floor: RoomMaterial = .wood
    var ceiling: RoomMaterial = .plaster
    var sources: [RoomSource] = [.init(position: .init(x: 0.3,y: 0.25))]
    var listener: RoomPoint = .init(x: 0.65,y: 0.7)
    var listenerHeading: Double = 0
    var partition: RoomPartition?
    func meters(_ p: RoomPoint) -> RoomPoint { .init(x: p.x*width, y: p.y*depth) }
    var center: RoomPoint { corners.reduce(.init(x: 0,y: 0), +) * (1/Double(corners.count)) }
    var area: Double {
        abs(corners.indices.reduce(0) { $0 + meters(corners[$1]).cross(meters(corners[($1+1)%corners.count])) })/2
    }
    func contains(_ p: RoomPoint) -> Bool {
        corners.indices.allSatisfy { i in (corners[(i+1)%corners.count]-corners[i]).cross(p-corners[i]) >= -0.00001 }
    }
    func constrained(_ p: RoomPoint) -> RoomPoint {
        var q = RoomPoint(x: min(max(p.x,0.02),0.98), y: min(max(p.y,0.02),0.98))
        for _ in 0..<80 { if contains(q) { return q }; q = q*0.9 + center*0.1 }
        return center
    }
    mutating func moveCorner(_ index: Int, to point: RoomPoint) {
        var candidate = self
        candidate.corners[index] = .init(x: min(max(point.x,0),1), y: min(max(point.y,0),1))
        guard candidate.area > width*depth*0.12,
              candidate.corners.indices.allSatisfy({ i in
                  let a = candidate.corners[i], b = candidate.corners[(i+1)%corners.count], c = candidate.corners[(i+2)%corners.count]
                  return (b-a).length > 0.06 && (b-a).cross(c-b) >= -0.00001
              }) else { return }
        self = candidate
        listener = constrained(listener)
        for i in sources.indices { sources[i].position = constrained(sources[i].position) }
    }
    mutating func splitWall(_ index: Int) {
        guard corners.count < 8 else { return }
        corners.insert((corners[index]+corners[(index+1)%corners.count])*0.5, at: index+1)
        walls.insert(walls[index], at: index+1)
    }
    var partitionEnds: (RoomPoint, RoomPoint)? {
        guard let partition else { return nil }
        let x = partition.position
        var ys: [Double] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i+1)%corners.count]
            if abs(b.x-a.x) > 0.0001 {
                let t = (x-a.x)/(b.x-a.x)
                if t >= 0 && t <= 1 { ys.append(a.y+t*(b.y-a.y)) }
            }
        }
        guard let lo = ys.min(), let hi = ys.max(), hi-lo > 0.01 else { return nil }
        return (.init(x: x,y: lo), .init(x: x,y: hi))
    }
    static func factory(_ place: Place) -> Self {
        var s = Self()
        // Stable source identity keeps factory comparison and reset deterministic.
        s.sources[0].id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        switch place {
        case .emptyMall:
            s.width = 24; s.depth = 16; s.height = 7; s.walls = Array(repeating: .glass,count: 4); s.floor = .concrete; s.sources[0].kind = .pa
        case .movieTheater:
            s.width = 16; s.depth = 22; s.height = 6; s.walls = Array(repeating: .curtain,count: 4); s.floor = .carpet; s.sources[0].position = .init(x: 0.5,y: 0.15)
        case .openWindow:
            s.width = 12; s.depth = 10; s.height = 4; s.walls = Array(repeating: .concrete,count: 4); s.partition = .init(position: 0.5,material: .glass,opening: 0.8)
        case .thinWall:
            s.width = 9; s.depth = 6; s.partition = .init(position: 0.5,material: .plaster,opening: 0); s.floor = .carpet
        case .hotelCorridor:
            s.width = 5; s.depth = 18; s.floor = .carpet; s.partition = .init(position: 0.45,material: .wood,opening: 0.08)
        case .parkingGarage:
            s.width = 22; s.depth = 18; s.height = 3; s.walls = Array(repeating: .concrete,count: 4); s.floor = .concrete; s.ceiling = .concrete
            s.corners = [.init(x: 0.1,y: 0),.init(x: 1,y: 0.15),.init(x: 0.9,y: 1),.init(x: 0,y: 1)]
        case .kitchenRadio:
            s.width = 5; s.depth = 4; s.height = 2.6; s.floor = .wood; s.sources[0].kind = .radio
        }
        return s
    }
    var validated: Self {
        var s = self
        func bound(_ x: Double, _ lo: Double, _ hi: Double) -> Double { x.isFinite ? min(max(x,lo),hi) : lo }
        s.width = bound(width,3,30); s.depth = bound(depth,3,30); s.height = bound(height,2,10)
        if !(3...8).contains(corners.count) || walls.count != corners.count || corners.contains(where: { !$0.x.isFinite || !$0.y.isFinite || !(0...1).contains($0.x) || !(0...1).contains($0.y) }) {
            s.corners = Self().corners; s.walls = Self().walls
        }
        if s.area < 1 || !s.corners.indices.allSatisfy({ i in
            let a = s.corners[i], b = s.corners[(i+1)%s.corners.count], c = s.corners[(i+2)%s.corners.count]
            return (b-a).length > 0.01 && (b-a).cross(c-b) >= -0.00001
        }) { s.corners = Self().corners; s.walls = Self().walls }
        s.listener = s.constrained(.init(x: bound(listener.x,0,1), y: bound(listener.y,0,1)))
        s.listenerHeading = bound(listenerHeading,0,360)
        s.sources = Array(sources.prefix(Self.maximumSources))
        if s.sources.isEmpty { s.sources = Self().sources }
        for i in s.sources.indices {
            s.sources[i].position = s.constrained(.init(x: bound(s.sources[i].position.x,0,1),y: bound(s.sources[i].position.y,0,1)))
            s.sources[i].heading = bound(s.sources[i].heading,0,360)
            s.sources[i].level = bound(s.sources[i].level,0,1.5)
        }
        if s.partition != nil {
            s.partition!.position = bound(s.partition!.position,0.15,0.85)
            s.partition!.opening = bound(s.partition!.opening,0,1)
        }
        return s
    }
}
