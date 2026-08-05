import Foundation
import Combine

/// Отправка запроса шага.
///
/// Отдельный протокол, чтобы семантика графа проверялась без обращения к сети —
/// это самая рискованная часть, и она не должна зависеть от бэкенда.
public protocol FlowExecuting: Sendable {
    func execute(_ request: RequestData) async -> (ResponseData?, FlowRunError?)
}

/// Боевой исполнитель поверх существующего повтора запросов.
/// Через него же работает подстановка активного окружения.
public struct LiveFlowExecutor: FlowExecuting {
    public init() {}

    public func execute(_ request: RequestData) async -> (ResponseData?, FlowRunError?) {
        let result = await RequestRetrier.retry(request: request)

        if let error = result.error {
            return (nil, .transport(error.localizedDescription))
        }
        guard let response = result.response else {
            return (nil, .transport("Пустой ответ"))
        }
        return (response, nil)
    }
}

/// Выполнение сценария
@MainActor
public final class FlowRunner: ObservableObject {
    @Published public private(set) var outcomes: [UUID: FlowStepOutcome] = [:]
    @Published public private(set) var isRunning = false
    @Published public private(set) var failedStepId: UUID?

    /// Причина отказа выполнять сценарий, например цикл в графе
    @Published public private(set) var refusalReason: String?

    public private(set) var context = FlowRunContext()

    private let executor: FlowExecuting

    public init(executor: FlowExecuting = LiveFlowExecutor()) {
        self.executor = executor
    }

    // MARK: - Публичные действия

    /// Выполнить сценарий с нуля
    public func run(_ flow: Flow) async {
        guard !flow.hasCycle else {
            refusalReason = "Сценарий содержит цикл и не может быть выполнен"
            outcomes = [:]
            return
        }

        refusalReason = nil
        failedStepId = nil
        context.reset()
        outcomes = Dictionary(uniqueKeysWithValues: flow.steps.map { ($0.id, FlowStepOutcome(stepId: $0.id)) })

        await execute(flow, resuming: false)
    }

    /// Повторить с указанного шага, сохранив уже собранные значения.
    ///
    /// Именно ради этого контекст переживает падение: логиниться заново не нужно.
    public func retry(from stepId: UUID, in flow: Flow) async {
        failedStepId = nil
        outcomes[stepId]?.state = .pending
        markDependentsPending(of: stepId, in: flow)

        await execute(flow, resuming: true)
    }

    /// Пометить шаг пропущенным и продолжить дальше
    public func skip(_ stepId: UUID, in flow: Flow) async {
        failedStepId = nil
        outcomes[stepId]?.state = .skipped
        markDependentsPending(of: stepId, in: flow)

        await execute(flow, resuming: true)
    }

    // MARK: - Ядро

    private func execute(_ flow: Flow, resuming: Bool) async {
        isRunning = true
        defer { isRunning = false }

        for level in flow.levels() {
            let pending = level.filter { step in
                // При возобновлении уже отработавшие шаги не трогаем
                guard resuming else { return true }
                switch outcomes[step.id]?.state {
                case .succeeded, .skipped: return false
                default: return true
                }
            }

            guard !pending.isEmpty else { continue }

            var toRun: [(FlowStep, Result<RequestData, FlowRunError>, [String: String])] = []

            for step in pending {
                guard shouldRun(step, in: flow) else {
                    outcomes[step.id]?.state = .skipped
                    continue
                }

                let substitutions = context.substitutions(for: step)
                let prepared: Result<RequestData, FlowRunError>
                do {
                    prepared = .success(try context.prepared(step))
                } catch let error as FlowRunError {
                    prepared = .failure(error)
                } catch {
                    prepared = .failure(.transport(error.localizedDescription))
                }

                outcomes[step.id]?.state = .running
                toRun.append((step, prepared, substitutions))
            }

            guard !toRun.isEmpty else { continue }

            // Уровень целиком идёт параллельно: его шаги по построению
            // не зависят друг от друга
            let results = await withTaskGroup(
                of: (UUID, FlowStepOutcome, ResponseData?).self
            ) { group -> [(UUID, FlowStepOutcome, ResponseData?)] in
                for (step, prepared, substitutions) in toRun {
                    let executor = self.executor
                    group.addTask {
                        await Self.perform(step, prepared: prepared,
                                           substitutions: substitutions, executor: executor)
                    }
                }

                var collected: [(UUID, FlowStepOutcome, ResponseData?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

            for (id, outcome, response) in results {
                outcomes[id] = outcome

                if case .failed = outcome.state, failedStepId == nil {
                    failedStepId = id
                }
                if case .succeeded = outcome.state,
                   let step = flow.step(id: id),
                   let response = response {
                    context.record(response, for: step)
                }
            }

            // Падение останавливает прогон: иначе посыпались бы все следующие
            // шаги и стало бы неясно, что сломалось на самом деле
            if failedStepId != nil { break }
        }

        markUnreached(flow)
    }

    /// Шаг выполняется, если все его зависимости успешны и условие истинно
    private func shouldRun(_ step: FlowStep, in flow: Flow) -> Bool {
        for dependency in step.dependsOn {
            // Ссылка на удалённый шаг ничего не блокирует
            guard flow.step(id: dependency) != nil else { continue }
            guard case .succeeded = outcomes[dependency]?.state else { return false }
        }

        guard let condition = step.condition else { return true }
        return condition.evaluate(values: context.values)
    }

    /// Сбросить в ожидание всё, что зависит от изменённого шага
    private func markDependentsPending(of stepId: UUID, in flow: Flow) {
        var frontier: Set<UUID> = [stepId]

        while !frontier.isEmpty {
            var next: Set<UUID> = []
            for step in flow.steps where !step.dependsOn.isEmpty {
                guard !frontier.isDisjoint(with: step.dependsOn) else { continue }
                guard outcomes[step.id]?.state != .pending else { continue }
                outcomes[step.id]?.state = .pending
                next.insert(step.id)
            }
            frontier = next
        }
    }

    private func markUnreached(_ flow: Flow) {
        for step in flow.steps where outcomes[step.id]?.state == .pending {
            outcomes[step.id]?.state = .notRun
        }
    }

    // MARK: - Выполнение одного шага

    /// Возвращает ответ вместе с исходом: общий изменяемый словарь ответов
    /// мутировался бы из параллельных задач — ровно та гонка,
    /// которую этот runner и должен исключать
    private static func perform(
        _ step: FlowStep,
        prepared: Result<RequestData, FlowRunError>,
        substitutions: [String: String],
        executor: FlowExecuting
    ) async -> (UUID, FlowStepOutcome, ResponseData?) {
        var outcome = FlowStepOutcome(stepId: step.id, substitutions: substitutions)

        let request: RequestData
        switch prepared {
        case .success(let value):
            request = value
            outcome.sentRequest = value
        case .failure(let error):
            outcome.state = .failed(error.message)
            return (step.id, outcome, nil)
        }

        if step.delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(step.delay * 1_000_000_000))
        }

        let started = Date()
        let (response, error) = await executor.execute(request)
        outcome.duration = Date().timeIntervalSince(started)

        if let error = error {
            outcome.state = .failed(error.message)
            return (step.id, outcome, nil)
        }

        guard let response = response else {
            outcome.state = .failed(FlowRunError.transport("Пустой ответ").message)
            return (step.id, outcome, nil)
        }

        outcome.statusCode = response.statusCode
        // Ответ сохраняется и при несовпадении статуса: по нему всё равно
        // выбираются значения для следующих шагов
        outcome.response = response

        if let expected = step.expectedStatusCode, expected != response.statusCode {
            outcome.state = .failed(
                FlowRunError.unexpectedStatus(expected: expected, actual: response.statusCode).message
            )
            return (step.id, outcome, response)
        }

        outcome.state = .succeeded
        return (step.id, outcome, response)
    }
}
