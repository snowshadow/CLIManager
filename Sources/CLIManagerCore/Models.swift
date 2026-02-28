import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var startCommand: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        startCommand: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.startCommand = startCommand
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum RuntimeStatus: String, Codable, Equatable, Sendable {
    case stopped
    case starting
    case running
    case failed
}

public struct RuntimeState: Codable, Equatable, Sendable {
    public let projectId: UUID
    public var status: RuntimeStatus
    public var pid: Int32?
    public var startedAt: Date?
    public var exitCode: Int32?
    public var lastError: String?

    public init(
        projectId: UUID,
        status: RuntimeStatus = .stopped,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        exitCode: Int32? = nil,
        lastError: String? = nil
    ) {
        self.projectId = projectId
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.exitCode = exitCode
        self.lastError = lastError
    }
}
