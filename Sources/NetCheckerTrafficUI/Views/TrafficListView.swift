import SwiftUI
import NetCheckerTrafficCore
import Combine

/// Main list view for traffic records
public struct NetCheckerTrafficUI_TrafficListView: View {
    @ObservedObject private var store = TrafficStore.shared
    @ObservedObject private var interceptor = TrafficInterceptor.shared
    @State private var filter = TrafficFilter()
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var showingStatistics = false
    @State private var showCopiedToast = false
    @State private var showingImporter = false
    @State private var importOutcome: HARImportOutcome?

    public init() {}

    public var body: some View {
        // Экран намеренно не создаёт собственный NavigationStack — его даёт
        // вызывающая сторона. Раньше стек был здесь, а инспектор оборачивал экран
        // во второй: из-за вложенности кнопка Done уходила на внешнюю панель,
        // перекрытую внутренней, и переставала отображаться.
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
            // Одна группа вместо двух отдельных ToolbarItem с одинаковым
            // placement: при совпадающем placement порядок не определён,
            // а на узкой панели часть элементов схлопывается или пропадает.
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    RecordingIndicator(isRecording: interceptor.isRunning)
                    actionsMenu
                }
            }
            .sheet(isPresented: $showingFilters) {
                FilterSheet(filter: $filter)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: HARDocumentType.allowed,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(importOutcome?.title ?? "", isPresented: importAlertBinding) {
                Button("OK", role: .cancel) { importOutcome = nil }
            } message: {
                Text(importOutcome?.message ?? "")
            }
            .sheet(isPresented: $showingStatistics) {
                NavigationStack {
                    NetCheckerTrafficUI_TrafficStatisticsView(records: filteredRecords)
                }
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text("Copied!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.green))
                        .shadow(color: .green.opacity(0.3), radius: 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .animation(.spring(duration: 0.3), value: showCopiedToast)
            .onChange(of: showCopiedToast) { newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopiedToast = false
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

            Text(interceptor.isRunning
                 ? "Network requests will appear here"
                 : "Recording is paused")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if !interceptor.isRunning {
                Button {
                    interceptor.start()
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
            // NavigationLink вместо onTapGesture: жест без contentShape ловился
            // только по непрозрачным пикселям, то есть по тексту, и пустое место
            // строки не реагировало. Push-переход к тому же и есть штатный
            // системный способ раскрыть элемент списка — шеврон, подсветка
            // при нажатии и кнопка «Назад» появляются сами.
            ForEach(filteredRecords, id: \.compositeId) { record in
                NavigationLink(value: record.id) {
                    TrafficRecordRow(record: record)
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
        .navigationDestination(for: UUID.self) { id in
            if let record = store.record(for: id) {
                NetCheckerTrafficUI_TrafficDetailView(record: record)
            }
        }
    }

    private func exportHAR() {
        if let harData = HARFormatter.format(records: filteredRecords),
           let har = String(data: harData, encoding: .utf8) {
            #if canImport(UIKit)
            UIPasteboard.general.string = har
            #endif
            showCopiedToast = true
        }
    }

    /// Меню действий в тулбаре.
    /// Вынесено из тела `body`: встроенным оно раздувало выражение до предела,
    /// за которым компилятор перестаёт выводить типы за разумное время.
    private var actionsMenu: some View {
        Menu {
            Button {
                if interceptor.isRunning {
                    interceptor.stop()
                } else {
                    interceptor.start()
                }
            } label: {
                Label(
                    interceptor.isRunning ? "Pause Recording" : "Resume Recording",
                    systemImage: interceptor.isRunning ? "pause.fill" : "play.fill"
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

            Button {
                showingImporter = true
            } label: {
                Label("Import HAR", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    /// Показ алерта завязан на наличие результата импорта
    private var importAlertBinding: Binding<Bool> {
        Binding(
            get: { importOutcome != nil },
            set: { if !$0 { importOutcome = nil } }
        )
    }

    /// Обработать выбранный в пикере HAR-файл
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importOutcome = .failure(error.localizedDescription)

        case .success(let urls):
            guard let url = urls.first else { return }

            // Файл лежит вне песочницы приложения — нужен доступ к защищённому ресурсу
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let outcome = try HARImporter.importRecords(from: data)
                importOutcome = .success(count: outcome.importedCount, fileName: url.lastPathComponent)
            } catch {
                importOutcome = .failure(error.localizedDescription)
            }
        }
    }

    private func exportSingleRecord(_ record: TrafficRecord) {
        SharePresenter.present(items: [CURLFormatter.format(record: record)])
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

                // Теги потока — сразу видно, к какой фиче относится вызов
                if !record.metadata.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(record.metadata.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
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

    var body: some View {
        Circle()
            .fill(isRecording ? Color.red : Color.gray)
            .frame(width: 8, height: 8)
            .opacity(isRecording ? 1.0 : 0.4)
    }
}

// MARK: - Statistics Banner

struct StatisticsBanner: View {
    let records: [TrafficRecord]
    @ObservedObject private var store = TrafficStore.shared

    var body: some View {
        HStack(spacing: 16) {
            StatItem(
                value: "\(records.count)",
                label: "Requests"
            )

            Divider()
                .frame(height: 24)

            StatItem(
                value: "\(records.count - store.errorCount - store.pendingCount)",
                label: "Success",
                color: .green
            )

            StatItem(
                value: "\(store.errorCount)",
                label: "Errors",
                color: .red
            )

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
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
    @ObservedObject private var tagger = TrafficTagger.shared
    @ObservedObject private var store = TrafficStore.shared

    /// Теги из правил и из уже записанного трафика
    private var availableTags: [String] {
        let fromTraffic = store.records.flatMap(\.metadata.tags)
        return Array(Set(tagger.knownTags + fromTraffic)).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !availableTags.isEmpty {
                    Section {
                        ForEach(availableTags, id: \.self) { tag in
                            Toggle(tag, isOn: tagBinding(tag))
                        }
                    } header: {
                        Text("Flow Tags")
                    } footer: {
                        Text("Tag related endpoints under one flow name in Settings, then filter the list down to just that flow.")
                    }
                }

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

    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { filter.tags?.contains(tag) ?? false },
            set: { isOn in
                var tags = filter.tags ?? []
                if isOn { tags.insert(tag) } else { tags.remove(tag) }
                filter.tags = tags.isEmpty ? nil : tags
            }
        )
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
