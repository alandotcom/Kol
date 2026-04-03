import Foundation

public struct LLMMetadata: Codable, Equatable, Sendable {
    public var originalText: String
    public var model: String?
    public var latencyMs: Int?
    public var promptTokens: Int?
    public var completionTokens: Int?

    public init(
        originalText: String,
        model: String? = nil,
        latencyMs: Int? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.originalText = originalText
        self.model = model
        self.latencyMs = latencyMs
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public struct Transcript: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var text: String
    public var audioPath: URL
    public var duration: TimeInterval
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var llmMetadata: LLMMetadata?

    public var wordCount: Int { text.split(separator: " ").count }

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        audioPath: URL,
        duration: TimeInterval,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        llmMetadata: LLMMetadata? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.audioPath = audioPath
        self.duration = duration
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.llmMetadata = llmMetadata
    }
}

public struct TranscriptionHistory: Codable, Equatable, Sendable {
    public var history: [Transcript] = []
    
    public init(history: [Transcript] = []) {
        self.history = history
    }
}
