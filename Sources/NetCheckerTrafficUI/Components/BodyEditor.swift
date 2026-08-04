import SwiftUI
import NetCheckerTrafficCore

/// Редактор тела запроса или ответа.
///
/// Один компонент на все формы. Раньше то же поле рисовалось тремя разными
/// способами — `TextEditor` в одних формах и `TextField(axis: .vertical)`
/// в других, — из-за чего высота, отступы и поведение при вводе отличались
/// от экрана к экрану.
public struct NetCheckerTrafficUI_BodyEditor: View {
    let title: String
    @Binding var text: String

    /// Исходное тело записи. Нужно, чтобы отличить «тела нет»
    /// от «тело есть, но это не текст»
    let sourceBody: Data?

    let minHeight: CGFloat
    let showsFormatButton: Bool

    public init(
        title: String,
        text: Binding<String>,
        sourceBody: Data? = nil,
        minHeight: CGFloat = 120,
        showsFormatButton: Bool = true
    ) {
        self.title = title
        self._text = text
        self.sourceBody = sourceBody
        self.minHeight = minHeight
        self.showsFormatButton = showsFormatButton
    }

    /// Тело записано, но текстом не представимо
    private var isBinary: Bool {
        guard let body = sourceBody, !body.isEmpty else { return false }
        return String(data: body, encoding: .utf8) == nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isBinary {
                binaryNotice
            } else {
                editor
            }
        }
    }

    // MARK: - Части

    private var header: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if !text.isEmpty {
                Text("\(text.utf8.count) Б")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: minHeight)
                .overlay(alignment: .topLeading) {
                    // TextEditor не умеет placeholder — иначе пустое поле
                    // выглядит как «ничего не загрузилось»
                    if text.isEmpty {
                        Text("Пусто")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            if showsFormatButton {
                Button("Format JSON") {
                    formatJSON()
                }
                .font(.caption)
                .disabled(!isFormattableJSON)
            }
        }
    }

    private var binaryNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Двоичное тело — \(sourceBody?.count ?? 0) Б")
                    .font(.caption)
                Text("Не представимо текстом, поэтому не редактируется")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - JSON

    private var isFormattableJSON: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    private func formatJSON() {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let formatted = String(data: pretty, encoding: .utf8) else {
            return
        }
        text = formatted
    }
}
