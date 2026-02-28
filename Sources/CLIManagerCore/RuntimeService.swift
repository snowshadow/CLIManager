import Foundation
import Darwin

public protocol RuntimeManaging {
    func start(project: Project) async throws
    func stop(projectId: UUID) async throws
    func state(projectId: UUID) async -> RuntimeState
    func snapshotStates() async -> [UUID: RuntimeState]
    func subscribeLogs(projectId: UUID) async -> AsyncStream<String>
}

public enum RuntimeError: LocalizedError {
    case alreadyRunning
    case notRunning
    case failedToStart(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Project is already running."
        case .notRunning:
            return "Project is not running."
        case .failedToStart(let message):
            return "Failed to start process: \(message)"
        }
    }
}

private struct ManagedProcess {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
}

public actor RuntimeService: RuntimeManaging {
    private let stateStore: RuntimeStateStore
    private let logs: LogService

    private var states: [UUID: RuntimeState]
    private var processes: [UUID: ManagedProcess] = [:]
    private var logContinuations: [UUID: [UUID: AsyncStream<String>.Continuation]] = [:]
    private var expectedStops: Set<UUID> = []
    private var pollTask: Task<Void, Never>?
    private var pollingStarted = false

    public init(stateStore: RuntimeStateStore, logService: LogService) {
        self.stateStore = stateStore
        self.logs = logService
        self.states = (try? stateStore.loadStates()) ?? [:]
    }

    deinit {
        pollTask?.cancel()
    }

    public func start(project: Project) async throws {
        let current = states[project.id] ?? RuntimeState(projectId: project.id)
        if current.status == .running || current.status == .starting {
            throw RuntimeError.alreadyRunning
        }

        try await setState(RuntimeState(projectId: project.id, status: .starting, startedAt: Date()))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", project.startCommand]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path, isDirectory: true)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.appendLog(projectId: project.id, message: text) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.appendLog(projectId: project.id, message: text) }
        }

        process.terminationHandler = { [weak self] proc in
            Task {
                await self?.handleTermination(projectId: project.id, exitCode: proc.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try await setState(RuntimeState(projectId: project.id, status: .failed, pid: nil, startedAt: Date(), exitCode: nil, lastError: error.localizedDescription))
            throw RuntimeError.failedToStart(error.localizedDescription)
        }

        processes[project.id] = ManagedProcess(process: process, stdout: stdout, stderr: stderr)
        try await setState(RuntimeState(projectId: project.id, status: .running, pid: process.processIdentifier, startedAt: Date(), exitCode: nil, lastError: nil))
    }

    public func stop(projectId: UUID) async throws {
        guard let state = states[projectId], state.status == .running || state.status == .starting else {
            throw RuntimeError.notRunning
        }
        expectedStops.insert(projectId)
        guard let pid = state.pid else {
            try await setState(RuntimeState(projectId: projectId, status: .stopped))
            return
        }

        try ProcessTreeKiller.terminateTree(rootPID: pid, graceSeconds: 3)
        try await setState(RuntimeState(projectId: projectId, status: .stopped, pid: nil, startedAt: state.startedAt, exitCode: nil, lastError: nil))
        cleanupProject(projectId)
    }

    public func state(projectId: UUID) async -> RuntimeState {
        states[projectId] ?? RuntimeState(projectId: projectId)
    }

    public func snapshotStates() async -> [UUID: RuntimeState] {
        states
    }

    public func startMonitoring() {
        guard !pollingStarted else { return }
        pollingStarted = true
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func subscribeLogs(projectId: UUID) async -> AsyncStream<String> {
        let buffer = await logs.recent(projectId: projectId)

        return AsyncStream { continuation in
            let token = UUID()
            Task {
                self.addContinuation(projectId: projectId, token: token, continuation: continuation)
                buffer.forEach { continuation.yield($0) }
            }

            continuation.onTermination = { _ in
                Task { await self.removeContinuation(projectId: projectId, token: token) }
            }
        }
    }

    public func reconcilePersistedStates() async {
        for (projectId, state) in states {
            guard let pid = state.pid else { continue }
            if kill(pid, 0) != 0 {
                states[projectId] = RuntimeState(projectId: projectId, status: .stopped, pid: nil, startedAt: state.startedAt, exitCode: state.exitCode, lastError: state.lastError)
            }
        }
        try? stateStore.saveStates(states)
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await refreshRunningStates()
            } catch {
                return
            }
        }
    }

    private func refreshRunningStates() async {
        for (projectId, state) in states where state.status == .running || state.status == .starting {
            guard let pid = state.pid else { continue }
            if kill(pid, 0) != 0 {
                states[projectId] = RuntimeState(projectId: projectId, status: .stopped, pid: nil, startedAt: state.startedAt, exitCode: state.exitCode, lastError: state.lastError)
                cleanupProject(projectId)
            }
        }
        try? stateStore.saveStates(states)
    }

    private func handleTermination(projectId: UUID, exitCode: Int32) async {
        let prior = states[projectId] ?? RuntimeState(projectId: projectId)
        let isExpectedStop = expectedStops.remove(projectId) != nil
        let status: RuntimeStatus = (exitCode == 0 || isExpectedStop) ? .stopped : .failed
        let errorMessage: String? = status == .failed ? "Process exited with code \(exitCode)" : nil
        states[projectId] = RuntimeState(projectId: projectId, status: status, pid: nil, startedAt: prior.startedAt, exitCode: exitCode, lastError: errorMessage)
        try? stateStore.saveStates(states)
        cleanupProject(projectId)
    }

    private func cleanupProject(_ projectId: UUID) {
        if let managed = processes[projectId] {
            managed.stdout.fileHandleForReading.readabilityHandler = nil
            managed.stderr.fileHandleForReading.readabilityHandler = nil
            processes.removeValue(forKey: projectId)
        }
    }

    private func appendLog(projectId: UUID, message: String) async {
        await logs.append(projectId: projectId, message: message)
        let continuations = logContinuations[projectId] ?? [:]
        continuations.values.forEach { $0.yield(message) }
    }

    private func addContinuation(projectId: UUID, token: UUID, continuation: AsyncStream<String>.Continuation) {
        var items = logContinuations[projectId] ?? [:]
        items[token] = continuation
        logContinuations[projectId] = items
    }

    private func removeContinuation(projectId: UUID, token: UUID) {
        guard var items = logContinuations[projectId] else { return }
        items.removeValue(forKey: token)
        if items.isEmpty {
            logContinuations.removeValue(forKey: projectId)
        } else {
            logContinuations[projectId] = items
        }
    }

    private func setState(_ state: RuntimeState) async throws {
        states[state.projectId] = state
        try stateStore.saveStates(states)
    }
}

public actor LogService {
    private let logsDirectory: URL
    private let fileManager: FileManager
    private let maxBufferedLines: Int
    private var ring: [UUID: [String]] = [:]

    public init(logsDirectory: URL, fileManager: FileManager = .default, maxBufferedLines: Int = 500) {
        self.logsDirectory = logsDirectory
        self.fileManager = fileManager
        self.maxBufferedLines = maxBufferedLines
    }

    public func append(projectId: UUID, message: String) {
        var lines = ring[projectId] ?? []
        let chunks = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in chunks where !line.isEmpty {
            lines.append(line)
        }
        if lines.count > maxBufferedLines {
            lines.removeFirst(lines.count - maxBufferedLines)
        }
        ring[projectId] = lines

        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            let file = logsDirectory.appendingPathComponent("\(projectId.uuidString).log")
            if !fileManager.fileExists(atPath: file.path) {
                fileManager.createFile(atPath: file.path, contents: nil)
            }
            guard let data = message.data(using: .utf8) else { return }
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Ignore log write failures in MVP.
        }
    }

    public func recent(projectId: UUID) -> [String] {
        ring[projectId] ?? []
    }
}

public enum ProcessTreeKiller {
    public static func terminateTree(rootPID: Int32, graceSeconds: UInt64) throws {
        let pids = try processTree(rootPID: rootPID)
        for pid in pids {
            _ = kill(pid, SIGTERM)
        }

        usleep(useconds_t(graceSeconds * 1_000_000))

        for pid in pids where kill(pid, 0) == 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    private static func processTree(rootPID: Int32) throws -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8) else {
            return [rootPID]
        }

        var children: [Int32: [Int32]] = [:]
        for line in raw.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count == 2,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { continue }
            children[ppid, default: []].append(pid)
        }

        var collected: [Int32] = []
        var queue: [Int32] = [rootPID]
        while let next = queue.first {
            queue.removeFirst()
            collected.append(next)
            queue.append(contentsOf: children[next] ?? [])
        }
        return collected.reversed()
    }
}
