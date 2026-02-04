/// NetCheckerTraffic — HTTP/HTTPS Traffic Interception Module
///
/// Перехват и анализ сетевого трафика iOS-приложений.
///
/// ## Быстрый старт
/// ```swift
/// // В AppDelegate или @main App:
/// TrafficInterceptor.shared.start()
///
/// // Готово! Все запросы перехватываются.
/// // Shake gesture → открывается TrafficListView
/// ```
///
/// ## Основные возможности
/// - Перехват ВСЕХ HTTP/HTTPS запросов (URLSession, Alamofire, Moya)
/// - Детальный просмотр request/response (headers, body, timing)
/// - JSON/XML подсветка и форматирование
/// - Фильтрация по хосту, методу, статус-коду
/// - Waterfall timeline (как в Chrome DevTools)
/// - Экспорт запроса как cURL / HAR / Share
/// - Mock-ответы для тестирования
/// - Breakpoints — пауза и модификация запроса
/// - SSL Certificate Inspector
/// - Environment Switching (prod/staging/dev)

import Foundation

// MARK: - Re-export Models

@_exported import struct Foundation.URL
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.UUID
@_exported import struct Foundation.TimeInterval
