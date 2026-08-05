import SwiftUI
import NetCheckerTrafficCore

/// Свободное полотно сценария: панорама, масштаб и провода между шагами.
///
/// Связь создаётся перетаскиванием от кружка под шагом к другому шагу —
/// то же движение, что в любом редакторе схем. Раскладку по рядам считает
/// движок: ряд означает одновременность, и двигать узлы руками нельзя,
/// иначе этот смысл потеряется.
struct FlowGraphView: View {
    let flow: Flow
    let outcomes: [UUID: FlowStepOutcome]
    let isRunning: Bool

    var onSelect: (FlowStep) -> Void
    var onConnect: (UUID, UUID) -> Void
    var onDelete: (UUID) -> Void

    @State private var zoom: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: CGSize = .zero

    @State private var wireSource: UUID?
    @State private var wirePoint: CGPoint = .zero
    @State private var dropTarget: UUID?

    @State private var dashPhase: CGFloat = 0
    @State private var didFit = false
    @AppStorage("netchecker.flowLegendHidden") private var legendHidden = false

    private let space = "netchecker.flowGraph"

    private var layout: FlowGraphLayout { FlowGraphLayoutBuilder.layout(flow) }
    private var scale: CGFloat { min(max(zoom * pinch, 0.35), 2.2) }

    private var offset: CGSize {
        CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                grid

                canvas
                    .frame(width: layout.size.width, height: layout.size.height)
                    .coordinateSpace(name: space)
                    .scaleEffect(scale)
                    .offset(offset)
            }
            // Именно фиксированный размер: с maxWidth контейнер вырастал
            // по полотну, и граф уезжал за правый край экрана
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture.simultaneously(with: zoomGesture))
            .overlay(alignment: .bottomTrailing) { controls(in: geometry.size) }
            .overlay(alignment: .top) { legend }
            .onAppear {
                guard !didFit else { return }
                didFit = true
                fit(in: geometry.size)
            }
            .onChange(of: isRunning) { running in
                if running {
                    withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                        dashPhase = -24
                    }
                } else {
                    withAnimation(.default) { dashPhase = 0 }
                }
            }
        }
    }

    // MARK: - Полотно

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            parallelBands
            wiresLayer
            liveWire
            nodesLayer
            portsLayer
        }
    }

    /// Подложка под рядом, где несколько шагов: одновременность
    /// показывается не только раскладкой, но и словом
    private var parallelBands: some View {
        ForEach(parallelRows, id: \.level) { row in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.accentColor.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                    .frame(width: row.rect.width + 20, height: row.rect.height + 20)
            }
            .position(x: row.rect.midX, y: row.rect.midY)
            .overlay(alignment: .top) {
                Text("ОДНОВРЕМЕННО")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                    .position(x: row.rect.midX, y: row.rect.minY - 20)
            }
        }
    }

    private var wiresLayer: some View {
        ForEach(wires) { wire in
            ZStack {
                FlowWireShape(from: wire.from, to: wire.to)
                    .stroke(
                        wire.state.color,
                        style: StrokeStyle(
                            lineWidth: wire.state.lineWidth,
                            lineCap: .round,
                            dash: wire.state.dash,
                            dashPhase: wire.state == .active ? dashPhase : 0
                        )
                    )

                FlowArrowShape(tip: wire.to)
                    .fill(wire.state.color)

                if !wire.labels.isEmpty {
                    Text(caption(wire.labels))
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(wire.state.labelBackground)
                        .background(.background, in: Capsule())
                        .foregroundStyle(wire.state.color)
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .position(wire.midpoint)
                }
            }
        }
    }

    /// Провод, который тянут пальцем прямо сейчас
    @ViewBuilder
    private var liveWire: some View {
        if let sourceId = wireSource, let source = layout.frame(of: sourceId) {
            let valid = dropTarget.map { canConnect(from: sourceId, to: $0) } ?? true

            FlowWireShape(from: source.outlet, to: wirePoint)
                .stroke(
                    valid ? Color.accentColor : Color.red,
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [6, 5])
                )

            Circle()
                .fill(valid ? Color.accentColor : Color.red)
                .frame(width: 9, height: 9)
                .position(wirePoint)
        }
    }

    private var nodesLayer: some View {
        ForEach(orderedNodes, id: \.frame.id) { item in
            FlowNodeView(
                step: item.step,
                outcome: outcomes[item.step.id],
                index: item.index,
                isFireAndForget: flow.isFireAndForget(item.step)
            )
            .frame(width: item.frame.size.width, height: item.frame.size.height, alignment: .top)
            .overlay(dropRing(for: item.frame.id))
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onTapGesture { onSelect(item.step) }
            .contextMenu {
                Button {
                    onSelect(item.step)
                } label: {
                    Label("Настроить", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    onDelete(item.step.id)
                } label: {
                    Label("Удалить шаг", systemImage: "trash")
                }
            }
            .position(item.frame.center)
        }
    }

    @ViewBuilder
    private func dropRing(for id: UUID) -> some View {
        if let sourceId = wireSource, dropTarget == id {
            let valid = canConnect(from: sourceId, to: id)
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(valid ? Color.green : Color.red, lineWidth: 3)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill((valid ? Color.green : Color.red).opacity(0.1))
                )
        }
    }

    /// Кружки-выходы. Отдельным слоем поверх узлов, иначе их перекрывает
    /// соседний узел и потянуть провод не выходит
    private var portsLayer: some View {
        ForEach(Array(layout.nodes.enumerated()), id: \.element.id) { offset, node in
            outlet(node, index: offset + 1)
        }
    }

    private func outlet(_ node: FlowNodeFrame, index: Int) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 15, height: 15)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(.background, lineWidth: 2.5))
            .scaleEffect(wireSource == node.id ? 1.35 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: wireSource)
            // Кружок мелкий, поэтому область нажатия расширена до 44 pt
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(node.outlet)
            .highPriorityGesture(wireGesture(from: node))
            .accessibilityLabel("Связать шаг \(index) с другим")
            .accessibilityIdentifier("netchecker.flowOutlet.\(index)")
    }

    private func wireGesture(from node: FlowNodeFrame) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { value in
                if wireSource == nil {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
                wireSource = node.id
                wirePoint = value.location
                dropTarget = layout.node(at: value.location).map(\.id)
            }
            .onEnded { value in
                if let target = layout.node(at: value.location),
                   canConnect(from: node.id, to: target.id) {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                    onConnect(node.id, target.id)
                }
                wireSource = nil
                dropTarget = nil
            }
    }

    // MARK: - Фон

    private var grid: some View {
        Canvas { context, size in
            let step: CGFloat = 26
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.7, height: 1.7)),
                        with: .color(Color.gray.opacity(0.28))
                    )
                    x += step
                }
                y += step
            }
        }
        .background(Color.secondary.opacity(0.07))
        .allowsHitTesting(false)
    }

    // MARK: - Управление

    private func controls(in size: CGSize) -> some View {
        VStack(spacing: 8) {
            controlButton("questionmark", label: "Как это работает") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    legendHidden.toggle()
                }
            }

            controlButton("plus.magnifyingglass", label: "Увеличить") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    zoom = min(zoom * 1.3, 2.2)
                }
            }

            controlButton("minus.magnifyingglass", label: "Уменьшить") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    zoom = max(zoom / 1.3, 0.35)
                }
            }

            controlButton("arrow.up.left.and.arrow.down.right", label: "Показать целиком") {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    fit(in: size)
                }
            }
        }
        .padding(12)
    }

    private func controlButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var legend: some View {
        if !legendHidden && !flow.steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                legendRow("rectangle.on.rectangle", "Ряд — шаги, которые уходят одновременно")
                legendRow("arrow.down", "Провод — ответ верхнего шага нужен нижнему")
                legendRow("hand.draw", "Потяните от синего кружка к другому шагу, чтобы передать значение")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        legendHidden = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Скрыть подсказку")
            }
            .padding(12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func legendRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 18)
        }
    }

    // MARK: - Жесты полотна

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
                drag = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { pinch = $0 }
            .onEnded { value in
                zoom = min(max(zoom * value, 0.35), 2.2)
                pinch = 1
            }
    }

    private func fit(in size: CGSize) {
        guard layout.size.width > 0, size.width > 0, size.height > 0 else { return }

        let horizontal = size.width / layout.size.width
        let vertical = size.height / layout.size.height
        zoom = min(max(min(horizontal, vertical), 0.35), 1)
        pan = .zero
    }

    // MARK: - Данные

    private struct NodeItem {
        let step: FlowStep
        let frame: FlowNodeFrame
        let index: Int
    }

    private var orderedNodes: [NodeItem] {
        layout.nodes.enumerated().compactMap { offset, frame in
            guard let step = flow.step(id: frame.id) else { return nil }
            return NodeItem(step: step, frame: frame, index: offset + 1)
        }
    }

    private struct ParallelRow {
        let level: Int
        let rect: CGRect
    }

    private var parallelRows: [ParallelRow] {
        Dictionary(grouping: layout.nodes, by: \.level)
            .filter { $0.value.count > 1 }
            .map { level, nodes in
                let rects = nodes.map(\.rect)
                let minX = rects.map(\.minX).min() ?? 0
                let maxX = rects.map(\.maxX).max() ?? 0
                let minY = rects.map(\.minY).min() ?? 0
                let maxY = rects.map(\.maxY).max() ?? 0
                return ParallelRow(
                    level: level,
                    rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                )
            }
            .sorted { $0.level < $1.level }
    }

    private var wires: [FlowWire] {
        var result: [FlowWire] = []

        for step in flow.steps {
            guard let target = layout.frame(of: step.id) else { continue }

            for dependencyId in step.dependsOn {
                guard let source = layout.frame(of: dependencyId),
                      let sourceStep = flow.step(id: dependencyId) else { continue }

                // Подпись — только имена, которые этот шаг действительно
                // отдаёт, а получатель действительно берёт
                let published = Set(sourceStep.outputs.map(\.name))
                let labels = step.inputs.map(\.name).filter(published.contains)

                result.append(
                    FlowWire(
                        id: "\(dependencyId)-\(step.id)",
                        from: source.outlet,
                        to: target.inlet,
                        labels: labels,
                        state: edgeState(from: dependencyId, to: step.id)
                    )
                )
            }
        }

        return result
    }

    private func edgeState(from sourceId: UUID, to targetId: UUID) -> FlowEdgeState {
        if case .failed = outcomes[sourceId]?.state { return .failed }
        if outcomes[targetId]?.state == .notRun { return .notRun }
        if outcomes[sourceId]?.state == .succeeded { return .active }
        return .idle
    }

    /// Связь назад по графу замкнула бы его в кольцо — такой бросок отклоняется
    private func canConnect(from source: UUID, to target: UUID) -> Bool {
        guard source != target else { return false }
        return flow.possibleDependencies(for: target).contains { $0.id == source }
    }

    private func caption(_ labels: [String]) -> String {
        labels.count <= 2
            ? labels.joined(separator: " · ")
            : "\(labels[0]) +\(labels.count - 1)"
    }
}
