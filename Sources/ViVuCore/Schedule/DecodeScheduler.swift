import Foundation

/// Two operation queues (docs/TECH_SPEC.md §5.3): `interactive` only for the current image,
/// `background` for neighbours, thumbnails and pyramids. Work runs off the main thread;
/// completions come back on the main actor unless the operation was cancelled.
public final class DecodeScheduler: Sendable {
    public enum Lane: Sendable { case interactive, background }

    public enum Priority: Int, Sendable {
        case veryHigh = 8, high = 4, normal = 0, low = -4, veryLow = -8

        var queuePriority: Operation.QueuePriority {
            switch self {
            case .veryHigh: .veryHigh
            case .high: .high
            case .normal: .normal
            case .low: .low
            case .veryLow: .veryLow
            }
        }
    }

    let interactive: OperationQueue
    let background: OperationQueue

    public init(backgroundConcurrency: Int? = nil) {
        interactive = OperationQueue()
        interactive.name = "ViVuView.decode.interactive"
        interactive.qualityOfService = .userInteractive
        interactive.maxConcurrentOperationCount = 2
        background = OperationQueue()
        background.name = "ViVuView.decode.background"
        background.qualityOfService = .utility
        let cores = ProcessInfo.processInfo.activeProcessorCount
        background.maxConcurrentOperationCount = backgroundConcurrency ?? max(2, cores - 3)
    }

    /// Runs `work` on a lane; `completion` runs on the main actor with the result unless the ticket was cancelled.
    @discardableResult
    public func submit<T: Sendable>(_ lane: Lane, priority: Priority = .normal,
                                    work: @escaping @Sendable (_ isCancelled: @Sendable () -> Bool) throws -> T,
                                    completion: @escaping @MainActor @Sendable (Result<T, Error>) -> Void) -> DecodeTicket {
        let ticket = DecodeTicket()
        let operation = BlockOperation { [ticket] in
            let isCancelled: @Sendable () -> Bool = { ticket.isCancelled }
            if isCancelled() { return }
            let result = Result { try work(isCancelled) }
            if isCancelled() { return }
            Task { @MainActor in
                if !ticket.isCancelled { completion(result) }
            }
        }
        operation.queuePriority = priority.queuePriority
        ticket.attach(operation)
        (lane == .interactive ? interactive : background).addOperation(operation)
        return ticket
    }

    public func cancelAll() {
        interactive.cancelAllOperations()
        background.cancelAllOperations()
    }
}

/// Handle for one submitted job. Cancelling stops it before it starts, lets a running job
/// notice through `isCancelled`, and drops its completion.
public final class DecodeTicket: @unchecked Sendable {
    // Sendable: all state is guarded by `lock`.
    private let lock = NSLock()
    private var cancelled = false
    private weak var operation: Operation?

    public init() {}

    func attach(_ operation: Operation) { lock.withLock { self.operation = operation } }

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public var isFinished: Bool { lock.withLock { operation?.isFinished ?? true } }

    public func cancel() {
        let op: Operation? = lock.withLock {
            cancelled = true
            return operation
        }
        op?.cancel()
    }
}
