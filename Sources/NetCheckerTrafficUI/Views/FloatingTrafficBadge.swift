import SwiftUI
import NetCheckerTrafficCore

/// Floating badge showing traffic summary
public struct NetCheckerTrafficUI_FloatingTrafficBadge: View {
    @ObservedObject private var store = TrafficStore.shared
    @State private var isExpanded = false
    @State private var showingTrafficList = false

    public init() {}

    public var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                if isExpanded {
                    expandedView
                } else {
                    compactView
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingTrafficList) {
            NavigationStack {
                NetCheckerTrafficUI_TrafficListView()
            }
        }
    }

    private var compactView: some View {
        Button {
            withAnimation(.spring()) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text("\(store.records.count)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.white.opacity(0.95))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
    }

    private var expandedView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Close button
            Button {
                withAnimation(.spring()) {
                    isExpanded = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }

            // Stats
            VStack(spacing: 4) {
                HStack {
                    Text("Requests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.records.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                HStack {
                    Text("Success")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(successCount)")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.errorCount)")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Text("Pending")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(store.pendingCount)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 120)

            Divider()

            // Actions
            HStack(spacing: 12) {
                Button {
                    showingTrafficList = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                }

                Button {
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    private var statusColor: Color {
        if store.pendingCount > 0 {
            return .orange
        } else if store.errorCount > 0 {
            return .red
        }
        return .green
    }

    private var successCount: Int {
        store.count - store.errorCount - store.pendingCount
    }
}

/// Mini floating indicator for quick traffic info
public struct TrafficIndicator: View {
    @ObservedObject private var store = TrafficStore.shared

    @State private var lastRequestStatus: Int?
    @State private var showStatus = false

    public init() {}

    public var body: some View {
        HStack(spacing: 4) {
            // Activity indicator
            if hasPendingRequests {
                ProgressView()
                    .scaleEffect(0.6)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            // Count
            Text("\(store.records.count)")
                .font(.system(size: 10, design: .monospaced))

            // Last status flash
            if showStatus, let status = lastRequestStatus {
                Text("\(status)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(TrafficTheme.statusColor(for: status))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .onReceive(store.$records.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { records in
            if let lastRecord = records.last,
               lastRecord.state == .completed,
               let status = lastRecord.statusCode,
               status != lastRequestStatus {
                lastRequestStatus = status
                withAnimation {
                    showStatus = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showStatus = false
                    }
                }
            }
        }
    }

    private var hasPendingRequests: Bool {
        store.pendingCount > 0
    }

    private var statusColor: Color {
        if store.errorCount > 0 {
            return .red
        }
        return .green
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        NetCheckerTrafficUI_FloatingTrafficBadge()
    }
}
