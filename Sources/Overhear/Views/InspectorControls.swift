import SwiftUI

struct InspectorNumber: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = ""
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var dragOrigin: Double?
    private var step: Double { unit == "m" ? 0.1 : 1 }
    private func display(_ v: Double) -> String { v.formatted(.number.grouping(.never).precision(.fractionLength(0...1))) }
    private func commit() {
        guard text != display(value) else { return }
        // Fields display no grouping; accept either decimal separator when typing.
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if let number = Double(input), number.isFinite {
            value = min(max(number,range.lowerBound),range.upperBound)
        }
        text = display(value)
    }
    private func increment(_ direction: Double, large: Bool) -> KeyPress.Result {
        guard focused else { return .ignored }
        commit()
        let next = ((value + direction * step * (large ? 10 : 1)) * 10).rounded() / 10
        value = min(max(next, range.lowerBound), range.upperBound)
        text = display(value)
        return .handled
    }
    private var numberDrag: some Gesture {
        DragGesture(minimumDistance: 6)
                    .onChanged { drag in
                        if dragOrigin == nil {
                            commit()
                            dragOrigin = value
                            focused = false
                        }
                        let steps = (drag.translation.width / 6).rounded(.towardZero)
                        let next = ((dragOrigin! + steps * step) * 10).rounded() / 10
                        value = min(max(next, range.lowerBound), range.upperBound)
                        text = display(value)
                    }
                    .onEnded { _ in dragOrigin = nil }
    }
    var body: some View {
        HStack(spacing: 5) {
            if !label.isEmpty { Text(label).foregroundStyle(.secondary) }
            TextField(label,text:$text).textFieldStyle(.plain).multilineTextAlignment(.leading)
                .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
                    increment(key.key == .upArrow ? 1 : -1, large: key.modifiers.contains(.shift))
                }
                .focused($focused).onSubmit { commit(); focused=false }
                .onChange(of:focused) { _, active in if !active { commit() } }
                .onChange(of:value) { _, v in text=display(v) }
                .onAppear { text=display(value) }
                .accessibilityLabel(label.isEmpty ? unit : label)
                .overlay {
                    if !focused {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { focused = true }
                            .gesture(numberDrag)
                            .accessibilityHidden(true)
                    }
                }
            if !unit.isEmpty { Text(unit).foregroundStyle(.tertiary) }
        }
        .font(.system(size:11,design:.monospaced)).padding(.horizontal,8).frame(height:27)
        .background(Color.white.opacity(focused ? 0.10 : 0.065),in:RoundedRectangle(cornerRadius:4))
        .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(.white.opacity(focused ? 0.25 : 0.045)))
    }
}

struct InspectorMenu<Value: Hashable>: View {
    let label: String
    @Binding var value: Value
    let options: [(Value,String)]
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(label).font(.system(size:10)).foregroundStyle(.secondary)
            Menu {
                ForEach(options,id:\.0) { option in
                    Button { value=option.0 } label: {
                        if value==option.0 { Label(option.1,systemImage:"checkmark") } else { Text(option.1) }
                    }
                }
            } label: {
                HStack(spacing:6) {
                    Text(options.first(where:{$0.0==value})?.1 ?? "").lineLimit(1)
                    Spacer(minLength:0)
                    Image(systemName:"chevron.down").font(.system(size:8)).foregroundStyle(.secondary)
                }
                .font(.system(size:11)).padding(.horizontal,8).frame(height:27)
                .frame(maxWidth:.infinity)
                .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:4))
                .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(.white.opacity(0.045)))
                .contentShape(Rectangle())
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .accessibilityLabel(label)
        }
    }
}

struct InspectorGroup<Content:View>:View {
    let title: String
    var initiallyExpanded = true
    var reveal = false
    @ViewBuilder var content: Content
    @State private var expanded = true
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title).font(.system(size:11,weight:.semibold))
                    Spacer()
                    Image(systemName:expanded ? "chevron.down" : "chevron.right").font(.system(size:8)).foregroundStyle(.tertiary)
                }.frame(height:16).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded { VStack(alignment:.leading,spacing:8) { content } }
        }.padding(.horizontal,12).padding(.vertical,10)
        .overlay(alignment:.bottom) { Rectangle().fill(.white.opacity(0.065)).frame(height:1) }
        .onAppear { expanded=initiallyExpanded }
        .onChange(of:reveal) { _, show in if show { expanded=true } }
    }
}
