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
}

extension TranscriptPersistenceClient: DependencyKey {
    public static let liveValue: TranscriptPersistenceClient = {
        return TranscriptPersistenceClient(
            save: { result, llmMetadata, audioURL, duration, sourceAppBundleID, sourceAppName in
                let fm = FileManager.default
                var recordingsFolder = try URL.kolApplicationSupport.appendingPathComponent("Recordings", isDirectory: true)
                try fm.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

                // Exclude recordings from iCloud/Time Machine backup — audio files
                // accumulate and can bloat backups significantly.
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try? recordingsFolder.setResourceValues(resourceValues)

                let filename = "\(Date().timeIntervalSince1970).wav"
                let finalURL = recordingsFolder.appendingPathComponent(filename)
                try fm.moveItem(at: audioURL, to: finalURL)

                return Transcript(
                    timestamp: Date(),
                    text: result,
                    audioPath: finalURL,
                    duration: duration,
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName,
                    llmMetadata: llmMetadata
                )
            },
            deleteAudio: { transcript in
                FileManager.default.removeItemIfExists(at: transcript.audioPath)
            }
        )
    }()
    
    public static let testValue = TranscriptPersistenceClient(
        save: { _, _, _, _, _, _ in
            Transcript(timestamp: Date(), text: "", audioPath: URL(fileURLWithPath: "/"), duration: 0)
        },
        deleteAudio: { _ in }
    )
}

public extension TranscriptPersistenceClient {
    /// Convenience: delete audio files for multiple transcripts, ignoring individual errors.
    func deleteAudioFiles(for transcripts: [Transcript]) async {
        for transcript in transcripts {
            try? await deleteAudio(transcript)
        }
    }

    /// Removes orphan .wav files in the Recordings folder that are not referenced
    /// by any transcript. Called on app launch to reclaim disk space from abandoned files.
    static func cleanupOrphanAudioFiles(referencedPaths: Set<URL>) {
        guard let recordingsFolder = try? URL.kolApplicationSupport
            .appendingPathComponent("Recordings", isDirectory: true) else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: recordingsFolder,
            includingPropertiesForKeys: nil
        ) else { return }

        var removedCount = 0
        for file in files where file.pathExtension == "wav" {
            if !referencedPaths.contains(file) {
                try? fm.removeItem(at: file)
                removedCount += 1
            }
        }
        if removedCount > 0 {
            KolLog.settings.info("Cleaned up \(removedCount) orphan audio file(s)")
        }
    }
}

public extension DependencyValues {
    var transcriptPersistence: TranscriptPersistenceClient {
        get { self[TranscriptPersistenceClient.self] }
        set { self[TranscriptPersistenceClient.self] = newValue }
    }
}
