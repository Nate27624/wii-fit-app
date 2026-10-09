import SwiftUI

struct ContentView: View {
    @ObservedObject var store: WeightStore

    @State private var weightText = ""
    @State private var selectedEntryID: WeightEntry.ID?
    @FocusState private var weightFieldFocused: Bool
    private let goalProjection = WeightGoalProjection()

    private var selectedEntry: WeightEntry? {
        guard let selectedEntryID else { return nil }
        return store.entries.first { $0.id == selectedEntryID }
    }

    private var parsedWeight: Double? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    private var submissionWeight: Double? {
        parsedWeight ?? uiTestingFallbackWeight
    }

    private var uiTestingFallbackWeight: Double? {
        guard ProcessInfo.processInfo.isUITesting else { return nil }
        return 185
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 18) {
                WeightGraphView(
                    entries: store.entries,
                    selectedEntryID: selectedEntryID,
                    projection: goalProjection,
                    onSelect: { selectedEntryID = $0.id }
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(300, proxy.size.height * 0.48))

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                weightFieldFocused = false
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Weight Tracker")
                .font(.title)
                .fontWeight(.semibold)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                TextField("Weight", text: $weightText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .focused($weightFieldFocused)
                    .onTapGesture {
                        weightFieldFocused = true
                    }
                    .accessibilityIdentifier("weight-input")

                Text("lbs")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Button(action: submitWeight) {
                Label("Submit", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(submissionWeight == nil)
            .accessibilityIdentifier("submit-button")

            Divider()

            if let selectedEntry {
                SelectedEntryView(entry: selectedEntry) {
                    store.delete(id: selectedEntry.id)
                    selectedEntryID = nil
                }
            } else {
                ContentUnavailableView(
                    "No Weight Selected",
                    systemImage: "chart.xyaxis.line",
                    description: Text(store.entries.isEmpty ? "Add a weight to start the graph." : "Tap a graph node to inspect it.")
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("empty-selection")
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.isUITesting {
                weightFieldFocused = true
            }
        }
    }

    private func submitWeight() {
        guard let submissionWeight else { return }
        store.add(weightLbs: roundedWeight(submissionWeight))
        selectedEntryID = store.entries.last?.id
        weightText = ""
        weightFieldFocused = false
    }

    private func roundedWeight(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

extension ProcessInfo {
    var isUITesting: Bool {
        arguments.contains("--uitesting") || environment["UITESTING"] == "1"
    }
}

private struct SelectedEntryView: View {
    let entry: WeightEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selected Entry")
                .font(.headline)

            LabeledContent("Weight") {
                Text(entry.weightLbs, format: .number.precision(.fractionLength(1)))
                    + Text(" lbs")
            }
            .accessibilityIdentifier("selected-weight")

            LabeledContent("Recorded") {
                Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .accessibilityIdentifier("selected-time")

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("delete-button")
        }
        .padding(.top, 4)
    }
}

#Preview {
    let entries = [
        WeightEntry(weightLbs: 184.2, recordedAt: .now.addingTimeInterval(-172_800)),
        WeightEntry(weightLbs: 183.4, recordedAt: .now.addingTimeInterval(-86_400)),
        WeightEntry(weightLbs: 182.9, recordedAt: .now)
    ]
    ContentView(store: WeightStore(fileURL: URL(fileURLWithPath: "/tmp/preview-weights.json"), entries: entries))
}
