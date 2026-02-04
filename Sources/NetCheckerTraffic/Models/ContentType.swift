import Foundation

/// Тип контента HTTP
public enum ContentType: Codable, Sendable, Hashable {
    case json
    case xml
    case html
    case formUrlEncoded
    case multipartFormData
    case plainText
    case image(ImageType)
    case pdf
    case protobuf
    case msgpack
    case graphql
    case binary
    case unknown(String)

    // MARK: - Image Types

    public enum ImageType: String, Codable, Sendable {
        case png
        case jpeg
        case gif
        case webp
        case svg
        case ico
        case bmp
        case tiff
        case heic
        case unknown
    }

    // MARK: - Initialization

    /// Создать из MIME-типа
    public init(mimeType: String?) {
        guard let mimeType = mimeType?.lowercased() else {
            self = .binary
            return
        }

        // JSON
        if mimeType.contains("application/json") || mimeType.contains("+json") {
            self = .json
            return
        }

        // XML
        if mimeType.contains("application/xml") || mimeType.contains("text/xml") || mimeType.contains("+xml") {
            self = .xml
            return
        }

        // HTML
        if mimeType.contains("text/html") {
            self = .html
            return
        }

        // Form data
        if mimeType.contains("application/x-www-form-urlencoded") {
            self = .formUrlEncoded
            return
        }

        if mimeType.contains("multipart/form-data") {
            self = .multipartFormData
            return
        }

        // Plain text
        if mimeType.contains("text/plain") {
            self = .plainText
            return
        }

        // Images
        if mimeType.hasPrefix("image/") {
            let imageType = mimeType.replacingOccurrences(of: "image/", with: "")
            switch imageType {
            case "png": self = .image(.png)
            case "jpeg", "jpg": self = .image(.jpeg)
            case "gif": self = .image(.gif)
            case "webp": self = .image(.webp)
            case "svg+xml", "svg": self = .image(.svg)
            case "x-icon", "vnd.microsoft.icon": self = .image(.ico)
            case "bmp": self = .image(.bmp)
            case "tiff": self = .image(.tiff)
            case "heic", "heif": self = .image(.heic)
            default: self = .image(.unknown)
            }
            return
        }

        // PDF
        if mimeType.contains("application/pdf") {
            self = .pdf
            return
        }

        // Protobuf
        if mimeType.contains("application/protobuf") || mimeType.contains("application/x-protobuf") {
            self = .protobuf
            return
        }

        // MessagePack
        if mimeType.contains("application/msgpack") || mimeType.contains("application/x-msgpack") {
            self = .msgpack
            return
        }

        // GraphQL
        if mimeType.contains("application/graphql") {
            self = .graphql
            return
        }

        // Binary / octet-stream
        if mimeType.contains("application/octet-stream") {
            self = .binary
            return
        }

        // Unknown but recorded
        self = .unknown(mimeType)
    }

    /// Создать из заголовков
    public init(headers: [String: String]?) {
        let contentType = headers?["Content-Type"] ?? headers?["content-type"]
        self.init(mimeType: contentType)
    }

    // MARK: - Properties

    /// MIME-тип
    public var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .xml: return "application/xml"
        case .html: return "text/html"
        case .formUrlEncoded: return "application/x-www-form-urlencoded"
        case .multipartFormData: return "multipart/form-data"
        case .plainText: return "text/plain"
        case .image(let type): return "image/\(type.rawValue)"
        case .pdf: return "application/pdf"
        case .protobuf: return "application/protobuf"
        case .msgpack: return "application/msgpack"
        case .graphql: return "application/graphql"
        case .binary: return "application/octet-stream"
        case .unknown(let mime): return mime
        }
    }

    /// Название для отображения
    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .formUrlEncoded: return "Form URL Encoded"
        case .multipartFormData: return "Multipart Form"
        case .plainText: return "Plain Text"
        case .image(let type): return "Image (\(type.rawValue.uppercased()))"
        case .pdf: return "PDF"
        case .protobuf: return "Protocol Buffers"
        case .msgpack: return "MessagePack"
        case .graphql: return "GraphQL"
        case .binary: return "Binary"
        case .unknown(let mime): return mime
        }
    }

    /// Является ли контент текстовым
    public var isText: Bool {
        switch self {
        case .json, .xml, .html, .formUrlEncoded, .plainText, .graphql:
            return true
        case .multipartFormData, .image, .pdf, .protobuf, .msgpack, .binary, .unknown:
            return false
        }
    }

    /// Можно ли отформатировать для отображения
    public var isFormattable: Bool {
        switch self {
        case .json, .xml, .html:
            return true
        default:
            return false
        }
    }

    /// Является ли контент изображением
    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    /// SF Symbol для типа
    public var systemImage: String {
        switch self {
        case .json: return "curlybraces"
        case .xml: return "chevron.left.forwardslash.chevron.right"
        case .html: return "globe"
        case .formUrlEncoded: return "list.bullet.rectangle"
        case .multipartFormData: return "doc.on.doc"
        case .plainText: return "doc.text"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .protobuf: return "cube"
        case .msgpack: return "shippingbox"
        case .graphql: return "point.3.connected.trianglepath.dotted"
        case .binary: return "01.square"
        case .unknown: return "questionmark.square"
        }
    }
}
