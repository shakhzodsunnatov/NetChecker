import Foundation
import UniformTypeIdentifiers

/// Типы файлов, принимаемые импортом HAR.
///
/// У `.har` нет зарегистрированного системного UTI, поэтому Files показывает
/// такие файлы как обычные данные. Принимаем и JSON, и произвольные данные —
/// корректность проверит уже парсер.
enum HARDocumentType {
    static var allowed: [UTType] {
        var types: [UTType] = [.json, .data]
        if let har = UTType(filenameExtension: "har") {
            types.insert(har, at: 0)
        }
        return types
    }
}

/// Итог импорта для показа пользователю
enum HARImportOutcome {
    case success(count: Int, fileName: String)
    case failure(String)

    var title: String {
        switch self {
        case .success: return "HAR импортирован"
        case .failure: return "Не удалось импортировать"
        }
    }

    var message: String {
        switch self {
        case .success(let count, let fileName):
            return "\(fileName): загружено записей — \(count)"
        case .failure(let reason):
            return reason
        }
    }
}
