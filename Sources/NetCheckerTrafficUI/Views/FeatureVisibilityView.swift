import SwiftUI
import NetCheckerTrafficCore

/// Выбор разделов, показываемых во вкладках инспектора
public struct NetCheckerTrafficUI_FeatureVisibilityView: View {
    @ObservedObject private var settings = InspectorFeatureSettings.shared

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(InspectorFeature.allCases) { feature in
                    Toggle(isOn: binding(for: feature)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                Text(feature.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.systemImage)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .disabled(feature.isRequired)
                }
            } header: {
                Text("Разделы инспектора")
            } footer: {
                Text("Выключенные разделы не занимают место в панели вкладок. Traffic отключить нельзя — без него инспектор бессмыслен, а Settings доступны всегда.")
            }

            if !settings.hidden.isEmpty {
                Section {
                    Button {
                        settings.showAll()
                    } label: {
                        Label("Показать все разделы", systemImage: "eye")
                    }
                }
            }
        }
        .navigationTitle("Разделы")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func binding(for feature: InspectorFeature) -> Binding<Bool> {
        Binding(
            get: { settings.isVisible(feature) },
            set: { settings.setVisible($0, for: feature) }
        )
    }
}
