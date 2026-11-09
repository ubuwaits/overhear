import SwiftUI

enum RoomSelection: Equatable {
    case room, wall(Int), corner(Int), source(UUID), listener, partition
}

struct RoomCanvas: View {
    @Binding var scene: RoomScene
    @Binding var selection: RoomSelection
    @State private var dragging: RoomSelection?
    @State private var dragOrigin: RoomScene?
    var showPaths: Bool

    private func transform(_ size: CGSize) -> (scale: Double, origin: CGPoint) {
        let scale = min((size.width-80)/scene.width,(size.height-80)/scene.depth)
        return (scale,CGPoint(x: (size.width-scene.width*scale)/2,y: (size.height-scene.depth*scale)/2))
    }
    private func screen(_ p: RoomPoint, _ size: CGSize) -> CGPoint {
        let t = transform(size)
        return CGPoint(x: t.origin.x+p.x*scene.width*t.scale,y: t.origin.y+p.y*scene.depth*t.scale)
    }
    private func normalized(_ p: CGPoint, _ size: CGSize) -> RoomPoint {
        let t = transform(size)
        return .init(x: (p.x-t.origin.x)/(scene.width*t.scale), y: (p.y-t.origin.y)/(scene.depth*t.scale))
    }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, size in
                    let t = transform(size)
                    var grid = Path()
                    for x in stride(from: 0.0,through: scene.width,by: 1) {
                        let px=t.origin.x+x*t.scale
                        grid.move(to: .init(x:px,y:t.origin.y)); grid.addLine(to: .init(x:px,y:t.origin.y+scene.depth*t.scale))
                    }
                    for y in stride(from: 0.0,through: scene.depth,by: 1) {
                        let py=t.origin.y+y*t.scale
                        grid.move(to: .init(x:t.origin.x,y:py)); grid.addLine(to: .init(x:t.origin.x+scene.width*t.scale,y:py))
                    }
                    context.stroke(grid,with: .color(.white.opacity(0.035)),lineWidth: 0.5)
                    var room = Path()
                    room.addLines(scene.corners.map { screen($0,size) }); room.closeSubpath()
                    context.fill(room,with: .color(materialColor(scene.floor).opacity(0.055)))
                    for source in scene.sources {
                        let center=screen(source.position,size)
                        var cone=Path(); cone.move(to:center)
                        cone.addArc(center:center,radius:45,startAngle:.degrees(source.heading-120),endAngle:.degrees(source.heading-60),clockwise:false)
                        cone.closeSubpath()
                        context.fill(cone,with:.color(.orange.opacity(0.07)))
                    }
                    let simulation = SceneAcoustics(scene: scene)
                    for (i,paths) in simulation.paths.enumerated() {
                        if case let .source(id) = selection, scene.sources[i].id != id { continue }
                        for (j,path) in paths.enumerated() where path.points.count >= 2 && (showPaths || j == 0) {
                            var ray=Path()
                            ray.addLines(path.points.map { screen(.init(x: $0.x/scene.width,y: $0.y/scene.depth),size) })
                            context.stroke(ray,with: .color(j == 0 ? .orange.opacity(0.4) : .white.opacity(0.12)),style: StrokeStyle(lineWidth: j == 0 ? 1 : 0.6,dash: j == 0 ? [4,4] : []))
                        }
                    }
                    for i in scene.corners.indices {
                        var wall=Path(); wall.move(to: screen(scene.corners[i],size)); wall.addLine(to: screen(scene.corners[(i+1)%scene.corners.count],size))
                        context.stroke(wall,with: .color(selection == .wall(i) ? .orange : materialColor(scene.walls[i])),style: StrokeStyle(lineWidth: 3,lineCap: .round))
                    }
                    if let ends = scene.partitionEnds, let p = scene.partition {
                        let middle=(ends.0+ends.1)*0.5, half=(ends.1-ends.0)*(p.opening/2)
                        var line=Path()
                        line.move(to: screen(ends.0,size)); line.addLine(to: screen(middle-half,size))
                        line.move(to: screen(middle+half,size)); line.addLine(to: screen(ends.1,size))
                        context.stroke(line,with: .color(selection == .partition ? .orange : materialColor(p.material)),style: StrokeStyle(lineWidth: 3,lineCap: .round))
                        var opening=Path(); opening.move(to:screen(middle-half,size)); opening.addLine(to:screen(middle+half,size))
                        context.stroke(opening,with:.color(.white.opacity(0.15)),style:StrokeStyle(lineWidth:1,dash:[3,3]))
                    }
                    let label="\(scene.width.formatted(.number.precision(.fractionLength(1)))) × \(scene.depth.formatted(.number.precision(.fractionLength(1)))) m"
                    context.draw(Text(label).font(.system(size:10,design:.monospaced)).foregroundStyle(.gray),at:.init(x:size.width/2,y:size.height-15))
                }
                forEachHandle(size)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                if dragging == nil {
                    let hit = hitTest(event.startLocation,size)
                    selection = hit; dragging = hit; dragOrigin = scene
                }
                guard let dragging, let original = dragOrigin,
                      hypot(event.translation.width,event.translation.height)>1.5 else { return }
                let p = normalized(event.location,size)
                let delta = p-normalized(event.startLocation,size)
                switch dragging {
                case let .source(id):
                    if let i = scene.sources.firstIndex(where: { $0.id == id }) { scene.sources[i].position = scene.constrained(original.sources[i].position+delta) }
                case .listener: scene.listener = scene.constrained(original.listener+delta)
                case let .corner(i): scene.moveCorner(i,to:original.corners[i]+delta)
                case let .wall(i):
                    var next=original
                    next.moveCorner(i,to:original.corners[i]+delta)
                    next.moveCorner((i+1)%original.corners.count,to:original.corners[(i+1)%original.corners.count]+delta)
                    scene=next
                case .partition: scene.partition?.position = min(max((original.partition?.position ?? 0.5)+delta.x,0.15),0.85)
                case .room: break
                }
            }.onEnded { _ in dragging=nil; dragOrigin=nil })
        }
        .background(Color(white: 0.025))
        .accessibilityLabel("Room plan. Drag speakers, listener, wall segments or corner handles.")
    }
    private func forEachHandle(_ size: CGSize) -> some View {
        ZStack {
            ForEach(scene.corners.indices,id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(selection == .corner(i) ? .orange : .white.opacity(0.8))
                    .frame(width: 7,height: 7).position(screen(scene.corners[i],size))
                    .allowsHitTesting(false)
            }
            ForEach(Array(scene.sources.enumerated()),id: \.element.id) { index, source in
                ZStack {
                    Image(systemName: "triangle.fill").font(.system(size: 7))
                        .rotationEffect(.degrees(source.heading))
                        .offset(x:sin(source.heading * .pi/180)*24,y: -cos(source.heading * .pi/180)*24)
                    Image(systemName: source.kind == .radio ? "radio" : "hifispeaker.fill").font(.system(size: 15))
                        .frame(width: 30,height: 30)
                        .background(Color(white: 0.09),in:RoundedRectangle(cornerRadius:6))
                        .overlay(RoundedRectangle(cornerRadius:6).stroke(selection == .source(source.id) ? .orange : .white.opacity(0.3)))
                    Text("\(index+1)").font(.system(size:9,design:.monospaced)).offset(x:24,y:16)
                }.foregroundStyle(.orange).position(screen(source.position,size)).allowsHitTesting(false)
            }
            Image(systemName: "headphones").font(.system(size:18,weight:.medium))
                .frame(width:34,height:34).background(.black,in:Circle())
                .overlay(Circle().stroke(selection == .listener ? .orange : .white,lineWidth:1.5))
                .overlay { Circle().fill(.white).frame(width:4,height:4).offset(x:sin(scene.listenerHeading * .pi/180)*22,y: -cos(scene.listenerHeading * .pi/180)*22) }
                .position(screen(scene.listener,size)).allowsHitTesting(false)
        }
    }
    private func hitTest(_ point: CGPoint,_ size: CGSize) -> RoomSelection {
        func distance(_ p: RoomPoint) -> Double { let q=screen(p,size); return hypot(q.x-point.x,q.y-point.y) }
        if distance(scene.listener)<22 { return .listener }
        if let source=scene.sources.first(where: { distance($0.position)<24 }) { return .source(source.id) }
        if let i=scene.corners.indices.first(where: { distance(scene.corners[$0])<13 }) { return .corner(i) }
        func segmentDistance(_ a:RoomPoint,_ b:RoomPoint)->Double {
            let a=screen(a,size),b=screen(b,size),edge=RoomPoint(x:b.x-a.x,y:b.y-a.y),p=RoomPoint(x:point.x-a.x,y:point.y-a.y)
            return (p-edge*min(max(p.dot(edge)/max(edge.dot(edge),0.001),0),1)).length
        }
        if let ends=scene.partitionEnds,segmentDistance(ends.0,ends.1)<12 { return .partition }
        if let i=scene.corners.indices.first(where: { segmentDistance(scene.corners[$0],scene.corners[($0+1)%scene.corners.count])<12 }) { return .wall(i) }
        return .room
    }
    private func materialColor(_ m: RoomMaterial)->Color {
        switch m { case .wood: Color(red:0.65,green:0.49,blue:0.32); case .glass: Color(red:0.4,green:0.65,blue:0.7); case .carpet,.curtain: Color(red:0.55,green:0.48,blue:0.6); default: Color(white:0.62) }
    }
}
