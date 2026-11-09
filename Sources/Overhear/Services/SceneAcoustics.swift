import Foundation
import OverhearDSP

struct AcousticPath: Sendable {
    var points: [RoomPoint] // World coordinates, also used by the canvas.
    var delay: Double
    var gain: Double
    var pan: Double
    var cutoff: Double
}

struct SceneAcoustics: Sendable {
    var paths: [[AcousticPath]]
    var decay: Double
    var configuration: [Float]

    init(scene raw: RoomScene) {
        let scene = raw.validated
        let listener = scene.meters(scene.listener)
        let vertices = scene.corners.map(scene.meters)
        let area = scene.area
        var surface = 2*area
        var absorbed = area*(scene.floor.absorption+scene.ceiling.absorption)
        var highAbsorbed = area*(scene.floor.highAbsorption+scene.ceiling.highAbsorption)
        for i in vertices.indices {
            let wallArea = (vertices[(i+1)%vertices.count]-vertices[i]).length*scene.height
            surface += wallArea
            absorbed += wallArea*scene.walls[i].absorption
            highAbsorbed += wallArea*scene.walls[i].highAbsorption
        }
        if let ends = scene.partitionEnds, let partition = scene.partition {
            let a = (scene.meters(ends.1)-scene.meters(ends.0)).length*scene.height*2*(1-partition.opening)
            surface += a; absorbed += a*partition.material.absorption; highAbsorbed += a*partition.material.highAbsorption
        }
        // Sabine diffuse decay; bounded for this real-time artistic model.
        decay = min(max(0.161*area*scene.height/max(absorbed,0.1),0.12),8)
        paths = []
        var data = [Float](repeating: 0,count: Int(OVERHEAR_SCENE_VALUE_COUNT))
        for (index, source) in scene.sources.enumerated() {
            let origin = scene.meters(source.position)
            let tone = source.kind.tone
            var sourcePaths: [AcousticPath] = []
            func path(_ points: [RoomPoint], material: RoomMaterial? = nil, extraDistance: Double = 0) -> AcousticPath {
                var distance = extraDistance
                var transmission = 1.0
                var cutoff = 20000.0
                for i in 1..<points.count {
                    distance += (points[i]-points[i-1]).length
                    if let partition = scene.partition, let ends = scene.partitionEnds {
                        let a = scene.meters(ends.0), b = scene.meters(ends.1)
                        if let hit = Self.intersection(points[i-1],points[i],a,b), hit.t > 0.0001 && hit.t < 0.9999 {
                            // Opening is a centered gap in the partition.
                            let throughOpening = abs(hit.u-0.5) < partition.opening/2
                            if !throughOpening {
                                transmission *= partition.material.transmission
                                cutoff = min(cutoff, 450+3000*partition.material.transmission)
                            }
                        }
                    }
                }
                let ray = points[1]-points[0]
                let heading = source.heading * .pi/180
                let facing = RoomPoint(x: sin(heading), y: -cos(heading))
                let directional = 0.25+0.75*max(0, facing.dot(ray)/max(ray.length,0.001))
                let arrival = points[points.count-2]-listener
                let earAngle = scene.listenerHeading * .pi/180
                let pan = arrival.dot(.init(x: cos(earAngle),y: sin(earAngle)))/max(arrival.length,0.001)
                var gain = directional*transmission/sqrt(1+distance*distance)
                if let material {
                    gain *= sqrt(1-material.absorption)
                    cutoff = min(cutoff, 20000*pow(1-material.highAbsorption,2))
                }
                cutoff = max(200,min(cutoff,20000*exp(-0.012*distance)))
                return .init(points: points, delay: distance/343, gain: gain, pan: pan, cutoff: cutoff)
            }
            sourcePaths.append(path([origin,listener]))
            for i in vertices.indices {
                let a = vertices[i], b = vertices[(i+1)%vertices.count], edge = b-a
                let projection = a+edge*((origin-a).dot(edge)/max(edge.dot(edge),0.001))
                let image = projection*2-origin
                if let hit = Self.intersection(image,listener,a,b), hit.t > 0 && hit.t < 1 && hit.u >= 0 && hit.u <= 1 {
                    let bounce = image+(listener-image)*hit.t
                    sourcePaths.append(path([origin,bounce,listener],material: scene.walls[i]))
                } else {
                    // Keep wall-to-path indices stable while geometry changes.
                    sourcePaths.append(.init(points: [],delay: 0,gain: 0,pan: 0,cutoff: 20000))
                }
            }
            // Floor and ceiling image paths assume source and ears at 1.2 m.
            let horizontal = (origin-listener).length
            for (height, material) in [(2.4,scene.floor),(2*max(scene.height-1.2,0.2),scene.ceiling)] {
                sourcePaths.append(path([origin,listener],material: material,extraDistance: hypot(horizontal,height)-horizontal))
            }
            if let ends = scene.partitionEnds, let partition = scene.partition {
                let a = scene.meters(ends.0), b = scene.meters(ends.1)
                if (origin.x-a.x)*(listener.x-a.x) > 0 {
                    let image = RoomPoint(x: 2*a.x-origin.x,y: origin.y)
                    if let hit = Self.intersection(image,listener,a,b), abs(hit.u-0.5) >= partition.opening/2 {
                        sourcePaths.append(path([origin,image+(listener-image)*hit.t,listener],material: partition.material))
                    }
                }
            }
            sourcePaths = Array(sourcePaths.prefix(12))
            paths.append(sourcePaths)
            let base = index*Int(OVERHEAR_SCENE_SOURCE_STRIDE)
            data[base] = Float(tone.low); data[base+1] = Float(tone.high)
            data[base+2] = Float(tone.drive); data[base+3] = Float(source.level)
            for (j,p) in sourcePaths.enumerated() {
                data[base+4+j*4] = Float(p.delay)
                data[base+5+j*4] = Float(p.gain)
                data[base+6+j*4] = Float(p.pan)
                data[base+7+j*4] = Float(p.cutoff)
            }
        }
        let roomOffset = Int(OVERHEAR_SCENE_ROOM_OFFSET)
        let meanFreeTime = 4*area*scene.height/surface/343
        for (i,ratio) in [0.79,0.97,1.13,1.31].enumerated() {
            let seconds = min(max(meanFreeTime*ratio,0.007),0.3)
            data[roomOffset+i] = Float(seconds)
            data[roomOffset+4+i] = Float(min(0.985,pow(0.001,seconds/decay)))
        }
        data[roomOffset+8] = Float(min(0.9, highAbsorbed/surface))
        data[roomOffset+9] = Float(min(2,(1-absorbed/surface)*sqrt(area)/3))
        let activeSources = max(1,scene.sources.filter { $0.level > 0 }.count)
        data[roomOffset+10] = Float(1/sqrt(Double(activeSources)))
        // Static broadband makeup gain compensates propagation/filter losses.
        // Deliberately exclude speaker levels: turning a speaker down must still
        // turn it down. No signal-dependent AGC, so silence/tails do not pump.
        let bands: [(Double,Double)] = [(63,0.06),(125,0.052),(250,0.045),(500,0.038),(1000,0.032),(2000,0.026),(4000,0.020),(8000,0.014),(12000,0.009)]
        var referenceEnergy = 0.0, processedEnergy = 0.0
        for (frequency, amplitude) in bands {
            let cosine = cos(2 * Double.pi * frequency / 48000)
            func lowpassPower(_ cutoff: Double) -> Double {
                let a = exp(-2 * Double.pi * cutoff / 48000)
                return pow(1-a,2)/(1+a*a-2*a*cosine)
            }
            var bandEnergy = 0.0
            for (i, source) in scene.sources.enumerated() {
                let tone = source.kind.tone
                let hp = exp(-2 * Double.pi * tone.high / 48000)
                let highpassPower = hp*hp*(2-2*cosine)/(1+hp*hp-2*hp*cosine)
                let sourcePower = pow(lowpassPower(tone.low),2)*highpassPower*tone.drive*tone.drive
                for path in paths[i] {
                    bandEnergy += path.gain*path.gain*lowpassPower(path.cutoff)*sourcePower
                }
            }
            referenceEnergy += amplitude*amplitude
            processedEnergy += amplitude*amplitude*bandEnergy*0.5
        }
        // Leave headroom for correlated early reflections and the diffuse tail,
        // which are not included in the independent-path power estimate.
        data[roomOffset+11] = Float(min(128,max(0.25,0.75*sqrt(referenceEnergy/max(processedEnergy,0.00000001)))))
        configuration = data
    }

    static func intersection(_ a: RoomPoint,_ b: RoomPoint,_ c: RoomPoint,_ d: RoomPoint) -> (t: Double,u: Double)? {
        let ab = b-a, cd = d-c, det = ab.cross(cd)
        guard abs(det)>0.000001 else { return nil }
        let t = (c-a).cross(cd)/det, u = (c-a).cross(ab)/det
        guard t >= 0 && t <= 1 && u >= 0 && u <= 1 else { return nil }
        return (t,u)
    }
}
