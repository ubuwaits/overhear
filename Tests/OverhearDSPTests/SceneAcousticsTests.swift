import Foundation
import Testing
import OverhearDSP
@testable import Overhear

@Test("Distance determines arrival time and attenuation")
func geometricDistance() {
    var room=RoomScene.factory(.kitchenRadio)
    room.sources[0].position = .init(x:0.5,y:0.1)
    room.sources[0].heading=180
    room.listener = .init(x:0.5,y:0.4)
    let near=SceneAcoustics(scene:room).paths[0][0]
    room.listener.y=0.8
    let far=SceneAcoustics(scene:room).paths[0][0]
    #expect(abs(near.delay-1.2/343)<0.00001)
    #expect(far.delay>near.delay)
    #expect(far.gain<near.gain)
}

@Test("Soft materials shorten decay and darken reflections")
func materialResponse() {
    var room=RoomScene.factory(.parkingGarage)
    let hard=SceneAcoustics(scene:room)
    room.walls=Array(repeating:.curtain,count:room.corners.count)
    room.floor = .carpet; room.ceiling = .curtain
    let soft=SceneAcoustics(scene:room)
    #expect(soft.decay<hard.decay)
    #expect(soft.paths[0][1].cutoff<hard.paths[0][1].cutoff)
    #expect(soft.paths[0][1].gain<hard.paths[0][1].gain)
}

@Test("Opening a partition restores direct transmission")
func partitionTransmission() {
    var room=RoomScene.factory(.thinWall)
    room.sources[0].position = .init(x:0.25,y:0.5)
    room.listener = .init(x:0.75,y:0.5)
    room.sources[0].heading=90
    let closed=SceneAcoustics(scene:room).paths[0][0]
    room.partition?.opening=1
    let open=SceneAcoustics(scene:room).paths[0][0]
    #expect(open.gain>closed.gain*3)
    #expect(open.cutoff>closed.cutoff*3)
}

@Test("Speaker and listener directions affect the acoustic paths")
func directionalPaths() {
    var room=RoomScene.factory(.kitchenRadio)
    room.sources[0].position = .init(x:0.2,y:0.5)
    room.listener = .init(x:0.8,y:0.5)
    room.sources[0].heading=90
    let facing=SceneAcoustics(scene:room)
    room.sources[0].heading=270
    let away=SceneAcoustics(scene:room)
    #expect(facing.paths[0][0].gain>away.paths[0][0].gain*3)
    #expect(facing.paths[0][0].pan < -0.99)
    room.listenerHeading=180
    #expect(SceneAcoustics(scene:room).paths[0][0].pan > 0.99)
}

@Test("Scene DSP renders independent sources and stays finite during edits")
func renderScenes() {
    let dsp=OverhearDSPCreate(48000)!
    defer { OverhearDSPDestroy(dsp) }
    var room=RoomScene.factory(.kitchenRadio)
    room.sources[0].position = .init(x:0.25,y:0.3)
    room.listener = .init(x:0.5,y:0.7)
    room.sources.append(.init(position:.init(x:0.8,y:0.3),kind:.phone))
    for index in 0..<6 {
        room.width=Double(5+index*3)
        room.sources[0].level = index==5 ? 0 : 1
        let config=SceneAcoustics(scene:room).configuration
        OverhearDSPSetScene(dsp,config,UInt32(config.count))
        var input=[Float](repeating:0,count:48000)
        for i in 0..<24000 { input[i*2]=sin(Float(i)*0.08)*0.2; input[i*2+1]=input[i*2] }
        var output=[Float](repeating:0,count:input.count)
        OverhearDSPProcessInterleavedStereo(dsp,input,&output,24000)
        #expect(output.allSatisfy { $0.isFinite && abs($0)<=1 })
        #expect(output.contains { abs($0)>0.001 })
        #expect(output != input)
    }
}

@Test("Scene audio is silent before the first geometric arrival")
func geometricArrival() {
    let dsp=OverhearDSPCreate(48000)!
    defer { OverhearDSPDestroy(dsp) }
    var room=RoomScene.factory(.kitchenRadio)
    room.sources[0].position = .init(x:0.5,y:0.1)
    room.listener = .init(x:0.5,y:0.9)
    let config=SceneAcoustics(scene:room).configuration
    OverhearDSPSetScene(dsp,config,UInt32(config.count))
    var input=[Float](repeating:0,count:4000); input[0]=0.5; input[1]=0.5
    var output=[Float](repeating:0,count:4000)
    OverhearDSPProcessInterleavedStereo(dsp,input,&output,2000)
    let first=Int(config[4]*48000)-2
    #expect(output.prefix(first*2).allSatisfy { abs($0)<0.000001 })
    #expect(output.dropFirst(first*2).contains { abs($0)>0.00001 })
}

@Test("Room edits reject inverted geometry and contain occupants")
func roomGeometry() {
    var room=RoomScene.factory(.emptyMall)
    let original=room.corners
    room.moveCorner(0,to:.init(x:1,y:1))
    #expect(room.corners==original)
    room.moveCorner(0,to:.init(x:0.2,y:0.1))
    #expect(room.contains(room.listener))
    #expect(room.sources.allSatisfy { room.contains($0.position) })
    room.splitWall(0)
    #expect(room.corners.count==5)
    #expect(room.walls.count==5)
    #expect(SceneAcoustics(scene:room).configuration.allSatisfy { $0.isFinite })
}

@Test("Each speaker contributes its own rendered sound")
func independentSourceAudio() {
    func render(_ scene:RoomScene)->[Float] {
        let dsp=OverhearDSPCreate(48000)!
        defer { OverhearDSPDestroy(dsp) }
        let config=SceneAcoustics(scene:scene).configuration
        OverhearDSPSetScene(dsp,config,UInt32(config.count))
        var input=[Float](repeating:0,count:8000)
        input[0]=0.4; input[1]=0.4
        var output=[Float](repeating:0,count:8000)
        OverhearDSPProcessInterleavedStereo(dsp,input,&output,4000)
        return output
    }
    var room=RoomScene.factory(.kitchenRadio)
    room.sources.append(.init(position:.init(x:0.8,y:0.25),kind:.phone,level:0))
    let single=render(room)
    room.sources[1].level=1
    let both=render(room)
    #expect(zip(single,both).contains { abs($0-$1)>0.0001 })
    room.sources[0].level=0
    let secondOnly=render(room)
    #expect(secondOnly.contains { abs($0)>0.0001 })
    #expect(secondOnly != single)
}

@Test("Scene presets retain useful output loudness")
func sceneLoudness() {
    let count=96000
    // Deterministic broadband material with a gently falling spectrum.
    var seed:UInt32=42
    var low:Float=0
    var input=[Float](repeating:0,count:count*2)
    for i in 0..<count {
        seed = seed &* 1664525 &+ 1013904223
        let noise=Float(Double(seed)/Double(UInt32.max)*2-1)
        low=0.95*low+0.05*noise
        input[i*2]=low*0.7; input[i*2+1]=low*0.7
    }
    func energy(_ samples:ArraySlice<Float>)->Double { samples.reduce(0) { $0+Double($1*$1) } }
    for place in Place.allCases {
        let dsp=OverhearDSPCreate(48000)!
        defer { OverhearDSPDestroy(dsp) }
        let config=SceneAcoustics(scene:.factory(place)).configuration
        OverhearDSPSetScene(dsp,config,UInt32(config.count))
        var output=[Float](repeating:0,count:input.count)
        OverhearDSPProcessInterleavedStereo(dsp,input,&output,UInt32(count))
        let ratio=sqrt(energy(output.suffix(96000))/energy(input.suffix(96000)))
        print("Scene loudness \(place.title): \(ratio), makeup \(config[Int(OVERHEAR_SCENE_ROOM_OFFSET)+11])")
        #expect(ratio > 0.65 && ratio < 1.8, "\(place.title): RMS ratio \(ratio)")
    }
}

@Test("Makeup gain preserves explicit speaker level changes")
func sceneMakeupPreservesLevels() {
    var scene=RoomScene.factory(.thinWall)
    let original=SceneAcoustics(scene:scene).configuration[Int(OVERHEAR_SCENE_ROOM_OFFSET)+11]
    scene.sources[0].level=0.2
    #expect(SceneAcoustics(scene:scene).configuration[Int(OVERHEAR_SCENE_ROOM_OFFSET)+11] == original)
    scene.sources[0].level=0
    #expect(SceneAcoustics(scene:scene).configuration[Int(OVERHEAR_SCENE_ROOM_OFFSET)+11] == original)
}

@Test("All six speakers survive saving and render independent audio")
func sixSpeakers() throws {
    var room=RoomScene.factory(.kitchenRadio)
    room.sources=(0..<6).map { i in
        RoomSource(position:.init(x:0.1+Double(i)*0.15,y:0.2),level:0)
    }
    let saved=try JSONEncoder().encode(room)
    room=try JSONDecoder().decode(RoomScene.self,from:saved).validated
    #expect(room.sources.count == 6)
    for active in 0..<6 {
        for i in room.sources.indices { room.sources[i].level = i == active ? 1 : 0 }
        let dsp=OverhearDSPCreate(48000)!
        defer { OverhearDSPDestroy(dsp) }
        let config=SceneAcoustics(scene:room).configuration
        #expect(config.count == Int(OVERHEAR_SCENE_VALUE_COUNT))
        OverhearDSPSetScene(dsp,config,UInt32(config.count))
        var input=[Float](repeating:0,count:8000)
        input[0]=0.4; input[1]=0.4
        var output=[Float](repeating:0,count:input.count)
        OverhearDSPProcessInterleavedStereo(dsp,input,&output,4000)
        #expect(output.allSatisfy { $0.isFinite && abs($0)<=1 })
        #expect(output.contains { abs($0)>0.00001 }, "Speaker \(active+1) must produce sound")
    }
    room.sources.append(.init(position:.init(x:0.5,y:0.5)))
    #expect(room.validated.sources.count == 6)
}
