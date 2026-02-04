import SwiftUI
import NetCheckerTrafficCore

/// Search bar for traffic filtering
public struct NetCheckerTrafficUI_TrafficSearchBar: View {
    @Binding var searchText: String
    @Binding var filter: TrafficFilter
    @Binding var showingFilters: Bool

    @State private var isSearching = false

    public init(
        searchText: Binding<String>,
        filter: Binding<TrafficFilter>,
        showingFilters: Binding<Bool>
    ) {
        self._searchText = searchText
        self._filter = filter
        self._showingFilters = showingFilters
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Main search bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search URL, host, path...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onTapGesture {
                            isSearching = true
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)

                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.title2)
                        .foregroundColor(hasActiveFilters ? .accentColor : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Quick filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickFilterChip(
                        label: "Errors",
                        isActive: filter.onlyErrors,
                        action: {
                            filter.onlyErrors.toggle()
                        }
                    )

                    QuickFilterChip(
                        label: "Slow (>1s)",
                        isActive: filter.onlySlowRequests,
                        action: {
                            if filter.onlySlowRequests {
                                filter.onlySlowRequests = false
                            } else {
                                filter.onlySlowRequests = true
                                filter.slowThreshold = 1.0
                            }
                        }
                    )

                    Divider()
                        .frame(height: 20)

                    ForEach(HTTPMethod.allCases, id: \.rawValue) { method in
                        QuickMethodChip(
                            method: method,
                            isActive: filter.methods?.contains(method) ?? true,
                            action: {
                                toggleMethod(method)
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(Color.gray.opacity(0.05))
    }

    private var hasActiveFilters: Bool {
        filter.methods != nil ||
        filter.statusCodeRange != nil ||
        filter.contentTypes != nil ||
        filter.hosts != nil ||
        filter.onlyErrors ||
        filter.onlySlowRequests
    }

    private func toggleMethod(_ method: HTTPMethod) {
        if filter.methods == nil {
            filter.methods = Set(HTTPMethod.allCases)
        }

        if filter.methods!.contains(method) {
            filter.methods!.remove(method)
        } else {
            filter.methods!.insert(method)
        }

        // Reset if all methods are selected
        if filter.methods!.count == HTTPMethod.allCases.count {
            filter.methods = nil
        }
    }
}

// MARK: - Quick Filter Chip

struct QuickFilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isActive ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct QuickMethodChip: View {
    let method: HTTPMethod
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(method.rawValue)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? TrafficTheme.methodBackgroundColor(for: method)
                        : Color.gray.opacity(0.2)
                )
                .foregroundColor(
                    isActive
                        ? TrafficTheme.methodColor(for: method)
                        : .secondary
                )
                .cornerRadius(4)
        }
    }
}

#Preview {
    VStack {
        NetCheckerTrafficUI_TrafficSearchBar(
            searchText: .constant(""),
            filter: .constant(TrafficFilter()),
            showingFilters: .constant(false)
        )
        Spacer()
    }
}
