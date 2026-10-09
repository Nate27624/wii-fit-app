import SwiftUI

struct WeightGraphView: View {
    let entries: [WeightEntry]
    let selectedEntryID: WeightEntry.ID?
    let projection: WeightGoalProjection
    let onSelect: (WeightEntry) -> Void

    @State private var visibleTimeWindow: GraphTimeWindow?
    @State private var zoomGestureStartWindow: GraphTimeWindow?
    @State private var panGestureStartWindow: GraphTimeWindow?

    private let graphInsets = EdgeInsets(top: 24, leading: 54, bottom: 42, trailing: 24)

    var body: some View {
        GeometryReader { geometry in
            let fullScale = GraphScale(entries: entries, projectionPoints: projection.points)
            let timeWindow = resolvedTimeWindow(for: fullScale)
            let scale = GraphScale(
                entries: entries,
                projectionPoints: projection.points,
                visibleTimeLower: timeWindow.visibleLower,
                visibleTimeUpper: timeWindow.visibleUpper
            )
            let plotRect = CGRect(
                x: graphInsets.leading,
                y: graphInsets.top,
                width: max(1, geometry.size.width - graphInsets.leading - graphInsets.trailing),
                height: max(1, geometry.size.height - graphInsets.top - graphInsets.bottom)
            )

            ZStack {
                graphBackground(scale: scale, plotRect: plotRect)
                plotContent(scale: scale, plotRect: plotRect)
                    .mask {
                        Path { path in
                            path.addRect(plotRect)
                        }
                    }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(zoomGesture(timeWindow: timeWindow))
            .simultaneousGesture(panGesture(timeWindow: timeWindow, plotWidth: plotRect.width))
            .accessibilityIdentifier("weight-graph")
        }
    }

    @ViewBuilder
    private func plotContent(scale: GraphScale, plotRect: CGRect) -> some View {
        ZStack {
            projectionLayer(scale: scale, plotRect: plotRect)

            if entries.isEmpty {
                Text("No weights yet")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("empty-graph")
            } else {
                pathLayer(scale: scale, plotRect: plotRect)
                nodeLayer(scale: scale, plotRect: plotRect)
            }
        }
    }

    private func resolvedTimeWindow(for fullScale: GraphScale) -> GraphTimeWindow {
        GraphTimeWindow(
            fullLower: fullScale.timeLower,
            fullUpper: fullScale.timeUpper,
            visibleLower: visibleTimeWindow?.visibleLower,
            visibleUpper: visibleTimeWindow?.visibleUpper
        )
    }

    private func zoomGesture(timeWindow: GraphTimeWindow) -> some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                if zoomGestureStartWindow == nil {
                    zoomGestureStartWindow = timeWindow
                }

                let baseWindow = zoomGestureStartWindow ?? timeWindow
                setVisibleTimeWindow(baseWindow.zoomed(by: magnification, anchorRatio: 0.5))
            }
            .onEnded { magnification in
                let baseWindow = zoomGestureStartWindow ?? timeWindow
                setVisibleTimeWindow(baseWindow.zoomed(by: magnification, anchorRatio: 0.5))
                zoomGestureStartWindow = nil
            }
    }

    private func panGesture(timeWindow: GraphTimeWindow, plotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if panGestureStartWindow == nil {
                    panGestureStartWindow = timeWindow
                }

                let baseWindow = panGestureStartWindow ?? timeWindow
                setVisibleTimeWindow(baseWindow.panned(byXTranslation: value.translation.width, plotWidth: plotWidth))
            }
            .onEnded { value in
                let baseWindow = panGestureStartWindow ?? timeWindow
                setVisibleTimeWindow(baseWindow.panned(byXTranslation: value.translation.width, plotWidth: plotWidth))
                panGestureStartWindow = nil
            }
    }

    private func setVisibleTimeWindow(_ timeWindow: GraphTimeWindow) {
        visibleTimeWindow = timeWindow.isFullRange ? nil : timeWindow
    }

    private func projectionLayer(scale: GraphScale, plotRect: CGRect) -> some View {
        ZStack {
            let points = projection.points
            let leftEdgeProjectionPoint = projection.point(at: scale.timeLower)
            let start = scale.point(for: leftEdgeProjectionPoint, in: plotRect)
            let target = scale.point(for: points[1], in: plotRect)

            Path { path in
                path.move(to: start)
                path.addLine(to: target)
            }
            .stroke(
                Color.green.opacity(0.8),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7])
            )
            .accessibilityHidden(true)

            Circle()
                .fill(Color.green)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .frame(width: 14, height: 14)
                .position(target)
                .accessibilityHidden(true)

            if scale.contains(date: points[1].recordedAt) {
                Text("150 lbs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.background.opacity(0.85), in: Capsule())
                    .position(x: min(plotRect.maxX - 26, target.x + 28), y: max(plotRect.minY + 14, target.y - 18))
                    .accessibilityIdentifier("goal-projection-label")
            }
        }
    }

    private func graphBackground(scale: GraphScale, plotRect: CGRect) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
                path.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
            }
            .stroke(Color.secondary.opacity(0.55), lineWidth: 1)

            ForEach(0..<5, id: \.self) { index in
                let ratio = CGFloat(index) / 4
                let y = plotRect.maxY - plotRect.height * ratio
                let weight = scale.weightLower + (scale.weightUpper - scale.weightLower) * Double(ratio)

                Path { path in
                    path.move(to: CGPoint(x: plotRect.minX, y: y))
                    path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                }
                .stroke(Color.secondary.opacity(index == 0 ? 0.25 : 0.12), lineWidth: 1)

                Text(weight, format: .number.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .position(x: plotRect.minX - 28, y: y)
            }

            Text(scale.timeLower.formatted(date: .numeric, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
                .position(x: plotRect.minX + 34, y: plotRect.maxY + 24)

            Text(scale.timeUpper.formatted(date: .numeric, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
                .position(x: plotRect.maxX - 34, y: plotRect.maxY + 24)
        }
    }

    private func pathLayer(scale: GraphScale, plotRect: CGRect) -> some View {
        Path { path in
            for (index, entry) in entries.enumerated() {
                let point = scale.point(for: entry, in: plotRect)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .accessibilityHidden(true)
    }

    private func nodeLayer(scale: GraphScale, plotRect: CGRect) -> some View {
        ZStack {
            ForEach(entries.filter { scale.contains(date: $0.recordedAt) }) { entry in
                let point = scale.point(for: entry, in: plotRect)
                Button {
                    onSelect(entry)
                } label: {
                    Text("Node")
                        .font(.caption2)
                        .foregroundStyle(.clear)
                        .frame(width: entry.id == selectedEntryID ? 20 : 16, height: entry.id == selectedEntryID ? 20 : 16)
                        .background(
                            Circle()
                                .fill(entry.id == selectedEntryID ? Color.orange : Color.accentColor)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: entry.id == selectedEntryID ? 5 : 2)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .frame(width: 44, height: 44)
                .position(point)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight \(entry.weightLbs, specifier: "%.1f") pounds")
                .accessibilityIdentifier("weight-node")
            }
        }
    }
}
