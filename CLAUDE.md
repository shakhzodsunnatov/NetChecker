# Claude Code Configuration — NetChecker

## Язык общения

- ВСЕГДА общайся на русском языке
- Комментарии в коде — на русском (проект уже использует русские комментарии)
- Названия переменных, типов, функций — на английском (стандарт Swift)
- Commit-сообщения — на английском (стандарт GitHub)
- Не добавляй трейлеры `Co-Authored-By` в коммиты

## Проект

**NetChecker** — Swift Package для перехвата и анализа HTTP/HTTPS трафика iOS/macOS приложений.
Встроенный аналог Charles Proxy с нативным SwiftUI интерфейсом.

- **Язык**: Swift 5.9+
- **Платформы**: iOS 16+, macOS 13+
- **Менеджер пакетов**: Swift Package Manager
- **UI**: SwiftUI
- **Архитектура**: модульная (Core + UI), Singleton-паттерн для engines
- **Зависимости**: нет (zero dependencies)

## Структура проекта

```
Sources/
  NetCheckerTraffic/         # Core-модуль (перехват, модели, логика)
    Core/                    # TrafficInterceptor, URLProtocol, Swizzler
    Models/                  # TrafficRecord, RequestData, ResponseData
    Storage/                 # TrafficStore, TrafficFilter, TrafficStatistics
    Formatters/              # cURL, HAR, JSON, Header форматирование
    Mocking/                 # MockEngine, MockRule
    Breakpoints/             # BreakpointEngine, BreakpointRule
    Retry/                   # RequestRetrier, ResponseDiffer
    SSL/                     # CertificateParser, SSLInspector
    Environment/             # EnvironmentStore, URLRewriter
  NetCheckerTrafficUI/       # UI-модуль (SwiftUI views)
    Views/                   # Экраны
    Components/              # Переиспользуемые компоненты
    Theme/                   # Стилизация
    Modifiers/               # .netChecker() модификатор
Tests/
  NetCheckerTrafficTests/    # Unit-тесты
docs/
  superpowers/specs/         # Проектные спеки
```

Публичный продукт SPM один — `NetCheckerTraffic`. Внутренний таргет `NetCheckerTrafficCore`
напрямую пользователями не импортируется.

## Правила Swift-кода

- Следуй Swift API Design Guidelines
- Используй `struct` по умолчанию, `class` только при необходимости ссылочной семантики
- `@MainActor` для всего UI-связанного кода
- `Sendable` для типов, передаваемых между контекстами
- Комментарии `///` для public API на русском языке
- Prefer immutable (`let`) over mutable (`var`)
- Используй `guard` для ранних выходов
- Ошибки — через `Result` или `throws`, не через опционалы
- Держи файлы в пределах 500 строк

## Git-флоу

- `feature/*` → `development` — **squash merge** (одна фича = один коммит)
- `development` → `main` — **merge-коммит**, не squash

Squash всей ветки `development` в `main` однажды уже сделал релиз 1.3.0 неоткатываемым:
двадцать независимых изменений схлопнулись в один коммит. Не повторять.

Теги и GitHub-релизы создаёт владелец репозитория вручную.

## Build & Test

```bash
# Сборка
swift build

# Тесты
swift test

# Сборка для iOS (проверка)
xcodebuild -scheme NetCheckerTraffic -destination 'platform=iOS Simulator,name=iPhone 16'
```

- ALWAYS run `swift build` after making code changes
- ALWAYS verify tests pass before committing

## Behavioral Rules

- Do what has been asked; nothing more, nothing less
- NEVER create files unless they're absolutely necessary for achieving your goal
- ALWAYS prefer editing an existing file to creating a new one
- NEVER proactively create documentation files (*.md) or README files unless explicitly requested
- NEVER save working files, text/mds, or tests to the root folder
- ALWAYS read a file before editing it
- NEVER commit secrets, credentials, or .env files

## Security Rules

- NEVER hardcode API keys, secrets, or credentials in source files
- NEVER commit .env files or any file containing secrets
- Не коммить локальные конфигурации инструментов с личными путями и IP-адресами
  (`.mcp.json` уже в `.gitignore`)
- Always validate user input at system boundaries
- Always sanitize file paths to prevent directory traversal
