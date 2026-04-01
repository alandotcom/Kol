import Dependencies
import Foundation

public struct TranscriptPersistenceClient: Sendable {
    public var save: @Sendable (
        _ result: String,
        _ llmMetadata: LLMMetadata?,
        _ audioURL: URL,
        _ duration: TimeInterval,
        _ sourceAppBundleID: String?,
        _ sourceAppName: String?
    ) async throws -> Transcript

    public var deleteAudio: @Sendable (_ transcript: Transcript) async throws -> Void

    public init(
        save: @escaping @Sendable (String, LLMMetadata?, URL, TimeInterval, String?, String?) async throws -> Transcript,
        deleteAudio: @escaping @Sendable (Transcript) async throws -> Void
    ) {
        self.save = save
        self.deleteAudio = deleteAudio
    }
}

public extension TranscriptPersistenceClient {
    /// Convenience: delete audio files for multiple transcripts, ignoring individual errors.
    func deleteAudioFiles(for transcripts: [Transcript]) async {
        for transcript in transcripts {
            try? await deleteAudio(transcript)
        }
    }
}

extension TranscriptPersistenceClient: TestDependencyKey {
    public static let testValue = TranscriptPersistenceClient(
        save: { _, _, _, _, _, _ in
            Transcript(timestamp: Date(), text: "", audioPath: URL(fileURLWithPath: "/"), duration: 0)
        },
        deleteAudio: { _ in }
    )
}

public extension DependencyValues {
    var transcriptPersistence: TranscriptPersistenceClient {
        get { self[TranscriptPersistenceClient.self] }
        set { self[TranscriptPersistenceClient.self] = newValue }
    }
}
