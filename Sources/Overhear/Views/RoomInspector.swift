import SwiftUI

struct RoomInspector: View {
    @Binding var scene: RoomScene
    @Binding var selection: RoomSelection
    @Binding var presence: Double
    @Binding var audioEnabled: Bool
    @Binding var showPaths: Bool
    @State private var cornerIndex = 0
    private var sourceIndex: Int {
        if case let .source(id)=selection, let index=scene.sources.firstIndex(where:{$0.id==id}) { return index }
        return 0
    }
    private func switchRow(_ label:String,_ value:Binding<Bool>)->some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Toggle(label,isOn:value).labelsHidden() }.frame(height:22)
    }
    private func number(_ label:String,_ value:Binding<Double>,_ range:ClosedRange<Double>,unit:String="")->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(label).font(.system(size:10)).foregroundStyle(.secondary)
            InspectorNumber(label:"",value:value,range:range,unit:unit).accessibilityLabel(label)
        }.frame(maxWidth:.infinity)
    }
    private func material(_ label:String,_ value:Binding<RoomMaterial>)->some View {
        InspectorMenu(label:label,value:value,options:RoomMaterial.allCases.map { ($0,$0.title) })
    }
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                InspectorGroup(title:"Playback") {
                    HStack(alignment:.bottom,spacing:6) {
                        VStack(alignment:.leading,spacing:4) {
                            Text("Audio").font(.system(size:10)).foregroundStyle(.secondary)
                            Toggle("Enabled",isOn:$audioEnabled).toggleStyle(.checkbox).frame(maxWidth:.infinity,alignment:.leading).frame(height:27)
                        }
                        number("Presence",Binding(get:{presence*100},set:{presence=$0/100}),0...100,unit:"%")
                    }
                    Toggle("Reflection paths",isOn:$showPaths).toggleStyle(.checkbox).frame(maxWidth:.infinity,alignment:.leading)
                }
                InspectorGroup(title:"Room") {
                    HStack(spacing:6) {
                        dimension("Width",$scene.width,3...30)
                        dimension("Depth",$scene.depth,3...30)
                        dimension("Height",$scene.height,2...10)
                    }
                }
                InspectorGroup(title:"Surfaces",initiallyExpanded:false,reveal:wallSelected) {
                    LazyVGrid(columns:[GridItem(.flexible(),spacing:6),GridItem(.flexible(),spacing:6)],spacing:8) {
                        material("Floor",$scene.floor)
                        material("Ceiling",$scene.ceiling)
                        ForEach(scene.walls.indices,id:\.self) { i in material("Wall \(i+1)",$scene.walls[i]) }
                    }
                    Menu("Apply to all walls") {
                        ForEach(RoomMaterial.allCases) { m in Button(m.title) { scene.walls=Array(repeating:m,count:scene.corners.count) } }
                    }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
                }
                InspectorGroup(title:"Speakers",reveal:sourceSelected) {
                    HStack(spacing:5) {
                        ForEach(Array(scene.sources.enumerated()),id:\.element.id) { i,s in
                            Button { selection = .source(s.id) } label: {
                                Text("\(i+1)").frame(width:27,height:25)
                                    .background(.white.opacity(sourceIndex==i ? 0.12 : 0.025),in:RoundedRectangle(cornerRadius:4))
                            }.buttonStyle(.plain).help("Speaker \(i+1)")
                        }
                        Spacer()
                        Button {
                            let source=RoomSource(position:scene.constrained(.init(x:0.65,y:0.3)))
                            scene.sources.append(source); selection = .source(source.id)
                        } label: { Image(systemName:"plus") }.disabled(scene.sources.count>=RoomScene.maximumSources).help("Add speaker")
                        Button {
                            scene.sources.remove(at:sourceIndex); selection = .source(scene.sources[0].id)
                        } label: { Image(systemName:"minus") }.disabled(scene.sources.count<=1).help("Remove selected speaker")
                    }.buttonStyle(.borderless)
                    speaker(sourceIndex)
                }
                InspectorGroup(title:"Listener",reveal:selection == .listener) {
                    position(x:Binding(get:{scene.listener.x*scene.width},set:{scene.listener=scene.constrained(.init(x:$0/scene.width,y:scene.listener.y))}),
                             y:Binding(get:{scene.listener.y*scene.depth},set:{scene.listener=scene.constrained(.init(x:scene.listener.x,y:$0/scene.depth))}))
                    number("Facing",$scene.listenerHeading,0...360,unit:"°")
                }
                InspectorGroup(title:"Partition",initiallyExpanded:false,reveal:selection == .partition) {
                    switchRow("Enabled",Binding(get:{scene.partition != nil},set:{ scene.partition = $0 ? RoomPartition() : nil }))
                    if scene.partition != nil {
                        material("Material",Binding(get:{scene.partition?.material ?? .plaster},set:{scene.partition?.material=$0}))
                        HStack(spacing:6) {
                        number("Opening",Binding(get:{(scene.partition?.opening ?? 0)*100},set:{scene.partition?.opening=$0/100}),0...100,unit:"%")
                        number("Position",Binding(get:{(scene.partition?.position ?? 0.5)*scene.width},set:{scene.partition?.position=$0/scene.width}),scene.width*0.15...scene.width*0.85,unit:"m")
                        }
                    }
                }
                InspectorGroup(title:"Floor plan",initiallyExpanded:false,reveal:cornerSelected) {
                    InspectorMenu(label:"Corner",value:$cornerIndex,options:scene.corners.indices.map { ($0,"\($0+1)") })
                    if scene.corners.indices.contains(cornerIndex) {
                        position(x:Binding(get:{scene.corners[cornerIndex].x*scene.width},set:{scene.moveCorner(cornerIndex,to:.init(x:$0/scene.width,y:scene.corners[cornerIndex].y))}),
                                 y:Binding(get:{scene.corners[cornerIndex].y*scene.depth},set:{scene.moveCorner(cornerIndex,to:.init(x:scene.corners[cornerIndex].x,y:$0/scene.depth))}))
                        HStack {
                            Button("Add corner") { scene.splitWall(cornerIndex); cornerIndex=min(cornerIndex+1,scene.corners.count-1); selection = .corner(cornerIndex) }.disabled(scene.corners.count>=8)
                            Spacer()
                            Button("Remove") {
                                scene.corners.remove(at:cornerIndex); scene.walls.remove(at:cornerIndex)
                                cornerIndex=min(cornerIndex,scene.corners.count-1)
                                scene.listener=scene.constrained(scene.listener)
                                for i in scene.sources.indices { scene.sources[i].position=scene.constrained(scene.sources[i].position) }
                                selection = .room
                            }.disabled(scene.corners.count<=3)
                        }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.system(size:11)).controlSize(.mini).toggleStyle(.switch)
        .onChange(of:selection) { _, selected in
            if case let .corner(i)=selected { cornerIndex=i }
            if case let .wall(i)=selected { cornerIndex=i }
        }
        .onChange(of:scene.corners.count) { _, count in cornerIndex=min(cornerIndex,count-1) }
    }
    private var sourceSelected:Bool { if case .source=selection { true } else { false } }
    private var wallSelected:Bool { if case .wall=selection { true } else { false } }
    private var cornerSelected:Bool { if case .corner=selection { true } else { false } }
    private func dimension(_ title:String,_ value:Binding<Double>,_ range:ClosedRange<Double>)->some View {
        number(title,value,range,unit:"m")
    }
    private func position(x:Binding<Double>,y:Binding<Double>)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text("Position").font(.system(size:10)).foregroundStyle(.secondary)
            HStack(spacing:6) {
                InspectorNumber(label:"X",value:x,range:0...scene.width,unit:"m")
                InspectorNumber(label:"Y",value:y,range:0...scene.depth,unit:"m")
            }
        }
    }
    private func speaker(_ i:Int)->some View {
        VStack(spacing:8) {
            InspectorMenu(label:"Type",value:$scene.sources[i].kind,options:SpeakerKind.allCases.map { ($0,$0.title) })
            position(x:Binding(get:{scene.sources[i].position.x*scene.width},set:{scene.sources[i].position=scene.constrained(.init(x:$0/scene.width,y:scene.sources[i].position.y))}),
                     y:Binding(get:{scene.sources[i].position.y*scene.depth},set:{scene.sources[i].position=scene.constrained(.init(x:scene.sources[i].position.x,y:$0/scene.depth))}))
            HStack(spacing:6) {
                number("Direction",$scene.sources[i].heading,0...360,unit:"°")
                number("Level",Binding(get:{scene.sources[i].level*100},set:{scene.sources[i].level=$0/100}),0...150,unit:"%")
            }
        }
    }
}
