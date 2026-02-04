import SwiftUI
import NetCheckerTrafficCore
import Combine

/// Main list view for traffic records
public struct NetCheckerTrafficUI_TrafficListView: View {
    @ObservedObject private var store = TrafficStore.shared
    @State private var selectedRecord: TrafficRecord?
    @State private var filter = TrafficFilter()
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var showingStatistics = false
    @State private var isRecording = true

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search and filter bar
                NetCheckerTrafficUI_TrafficSearchBar(
                    searchText: $searchText,
                    filter: $filter,
                    showingFilters: $showingFilters
                )

                // Statistics banner
                if !filteredRecords.isEmpty {
                    StatisticsBanner(records: filteredRecords)
                        .onTapGesture {
                            showingStatistics = true
                        }
                }

                // Records list
                if filteredRecords.isEmpty {
                    emptyState
                } else {
                    recordsList
                }
            }
            .navigationTitle("Network Traffic")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isRecording.toggle()
                            if isRecording {
                                TrafficInterceptor.shared.start()
                            } else {
                                TrafficInterceptor.shared.stop()
                            }
                        } label: {
                            Label(
                                isRecording ? "Pause Recording" : "Resume Recording",
                                systemImage: isRecording ? "pause.fill" : "play.fill"
                            )
                        }

                        Button(role: .destructive) {
                            store.clear()
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }

                        Divider()

                        Button {
                            showingStatistics = true
                        } label: {
                            Label("Statistics", systemImage: "chart.bar")
                        }

                        Button {
                            exportHAR()
                        } label: {
                            Label("Export HAR", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    RecordingIndicator(isRecording: isRecording)
                }
            }
            .sheet(item: $selectedRecord) { record in
                NavigationStack {
                    NetCheckerTrafficUI_TrafficDetailView(record: record)
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(filter: $filter)
            }
            .sheet(isPresented: $showingStatistics) {
                NavigationStack {
                    NetCheckerTrafficUI_TrafficStatisticsView(records: filteredRecords)
                }
            }
        }
    }

    private var filteredRecords: [TrafficRecord] {
        var records = store.records

        // Apply search text
        if !searchText.isEmpty {
            var textFilter = filter
            textFilter.searchText = searchText
            records = textFilter.apply(to: records)
        } else {
            records = filter.apply(to: records)
        }

        return records
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Traffic Recorded")
                .font(.headline)

            Text(isRecording
                 ? "Network requests will appear here"
                 : "Recording is paused")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !isRecording {
                Button {
                    isRecording = true
                    TrafficInterceptor.shared.start()
                } label: {
                    Label("Start Recording", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        List {
            ForEach(filteredRecords) { record in
                TrafficRecordRow(record: record)
                    .onTapGesture {
                        selectedRecord = record
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.remove(id: record.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            exportSingleRecord(record)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func exportHAR() {
        if let harData = HARFormatter.format(records: filteredRecords),
           let har = String(data: harData, encoding: .utf8) {
            #if canImport(UIKit)
            UIPasteboard.general.string = har
            #endif
        }
    }

    private func exportSingleRecord(_ record: TrafficRecord) {
        let curl = CURLFormatter.format(record: record)
        #if canImport(UIKit)
        UIPasteboard.general.string = curl
        #endif
    }
}

// MARK: - Traffic Record Row

struct TrafficRecordRow: View {
    let record: TrafficRecord

    var body: some View {
        HStack(spacing: 12) {
            // Method badge
            MethodBadgeCompact(method: record.method)

            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // URL path
                Text(record.path)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // Host
                Text(record.host)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Right side info
            VStack(alignment: .trailing, spacing: 4) {
                // Status or state
                if let statusCode = record.statusCode {
                    NetCheckerTrafficUI_StatusCodeBadge(statusCode: statusCode)
                } else {
                    StateBadge(state: record.state)
                }

                // Duration and size
                HStack(spacing: 8) {
                    if record.state == .completed || record.state == .mocked {
                        Text(record.formattedDuration)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if record.responseSize > 0 {
                            Text(formatSize(record.responseSize))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(record.state == .pending ? 0.7 : 1.0)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - State Badge

struct StateBadge: View {
    let state: TrafficRecordState

    var body: some View {
        HStack(spacing: 4) {
            if case .pending = state {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Text(state.displayName)
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(TrafficTheme.stateColor(for: state).opacity(0.15))
        .foregroundColor(TrafficTheme.stateColor(for: state))
        .cornerRadius(TrafficTheme.badgeCornerRadius)
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    let isRecording: Bool

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .scaleEffect(isAnimating && isRecording ? 1.2 : 1.0)
                .animation(
                    isRecording
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isAnimating
                )
                .onAppear { isAnimating = true }
        }
    }
}

// MARK: - Statistics Banner

struct StatisticsBanner: View {
    let records: [TrafficRecord]

    var body: some View {
        HStack(spacing: 16) {
            StatItem(
                value: "\(records.count)",
                label: "Requests"
            )

            Divider()
                .frame(height: 24)

            StatItem(
                value: "\(successCount)",
                label: "Success",
                color: .green
            )

            StatItem(
                value: "\(errorCount)",
                label: "Errors",
                color: .red
            )

            Spacer()

            Text(averageDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
    }

    private var successCount: Int {
        records.filter { $0.statusCode?.isSuccessStatusCode == true }.count
    }

    private var errorCount: Int {
        records.filter { $0.isError || ($0.statusCode?.isErrorStatusCode == true) }.count
    }

    private var averageDuration: String {
        let completedRecords = records.filter { if case .completed = $0.state { return true }; return false }
        guard !completedRecords.isEmpty else { return "" }

        let totalDuration = completedRecords.reduce(0.0) { $0 + $1.duration }
        let average = totalDuration / Double(completedRecords.count)

        if average < 1 {
            return "Avg: \(String(format: "%.0f", average * 1000)) ms"
        }
        return "Avg: \(String(format: "%.2f", average)) s"
    }
}

struct StatItem: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @Binding var filter: TrafficFilter
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("HTTP Methods") {
                    ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
                        Toggle(method.rawValue, isOn: methodBinding(method))
                    }
                }

                Section("Status Categories") {
                    ForEach(StatusCategory.allCases, id: \.self) { category in
                        Toggle(category.displayName, isOn: statusCategoryBinding(category))
                    }
                }

                Section("Content Types") {
                    ForEach(ContentTypeFilter.allCases, id: \.self) { type in
                        Toggle(type.displayName, isOn: contentTypeBinding(type))
                    }
                }

                Section {
                    Button("Reset Filters") {
                        filter = TrafficFilter()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func methodBinding(_ method: HTTPMethod) -> Binding<Bool> {
        Binding(
            get: { filter.methods?.contains(method) ?? true },
            set: { enabled in
                if filter.methods == nil {
                    filter.methods = Set(HTTPMethod.allCases)
                }
                if enabled {
                    filter.methods?.insert(method)
                } else {
                    filter.methods?.remove(method)
                }
                if filter.methods?.count == HTTPMethod.allCases.count {
                    filter.methods = nil
                }
            }
        )
    }

    private func statusCategoryBinding(_ category: StatusCategory) -> Binding<Bool> {
        Binding(
            get: { filter.statusCategories?.contains(category) ?? true },
            set: { enabled in
                if filter.statusCategories == nil {
                    filter.statusCategories = Set(StatusCategory.allCases)
                }
                if enabled {
                    filter.statusCategories?.insert(category)
                } else {
                    filter.statusCategories?.remove(category)
                }
                if filter.statusCategories?.count == StatusCategory.allCases.count {
                    filter.statusCategories = nil
                }
            }
        )
    }

    private func contentTypeBinding(_ type: ContentTypeFilter) -> Binding<Bool> {
        Binding(
            get: { filter.contentTypes?.contains(type) ?? true },
            set: { enabled in
                if filter.contentTypes == nil {
                    filter.contentTypes = Set(ContentTypeFilter.allCases)
                }
                if enabled {
                    filter.contentTypes?.insert(type)
                } else {
                    filter.contentTypes?.remove(type)
                }
                if filter.contentTypes?.count == ContentTypeFilter.allCases.count {
                    filter.contentTypes = nil
                }
            }
        )
    }
}

#Preview {
    NetCheckerTrafficUI_TrafficListView()
}
