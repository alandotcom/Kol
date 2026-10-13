import CoreML
import CryptoKit
import Foundation

/// Downloads the on-device cleanup model from Hugging Face and keeps it ready to load.
///
/// The model lives at https://huggingface.co/alandotcom/kol-cleanup-360m-coreml. Each Kol release pins one revision
/// and the SHA-256 of every file, so publishing a new model never changes what an installed app runs. Files go to
/// Application Support/com.alandotcom.Kol/LocalCleanupModel-<revision>/; the Core ML package is compiled once there
/// to Cleanup.mlmodelc and then deleted, and a `.ready` file marks a complete, verified model.
enum LocalCleanupModelStore {
    static let repository = "alandotcom/kol-cleanup-360m-coreml"
    /// r022 (see the model card). Update the revision and the asset list together when publishing a new model.
    static let revision = "cfdc5540802e1a2671184d523e0766d08f075b49"

    struct Asset {
        let path: String
        let sha256: String
        let size: Int64
    }

    static let assets: [Asset] = [
        Asset(path: "Cleanup.mlpackage/Manifest.json", sha256: "2d0203fe6f0794c77ee92f510a659d11253a0f7093df37a45274111b5cfd5d06", size: 617),
        Asset(path: "Cleanup.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "3aa09ab2ecba7f54907ee1f161a514987d2cb93fcdacde44270d50a4618c98c4", size: 777_576),
        Asset(path: "Cleanup.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "8e6a97af0272e42149740ed2723ecae78eab4a0bf4b771224d895f1a0e5d16b4", size: 724_029_376),
        Asset(path: "chat_template.jinja", sha256: "872be49dbb638044ad01b60388f48d469ff2980e5f0dccdc22ec907db54d0788", size: 368),
        Asset(path: "cleanup-manifest.json", sha256: "50bbe44d9b363d9718282e5b0f184f3b853363c6ad3e529e0b72540b09daca5b", size: 1_266),
        Asset(path: "config.json", sha256: "98e9ad4431921b55be80cdb3844b75a22f8604ab2404396cd6e5de8cf42e8480", size: 857),
        Asset(path: "merges.txt", sha256: "0b54e8aa4e53d5383e2e4bc635a56b43f9647f7b13832d5d9ecd8f82dac4f510", size: 466_391),
        Asset(path: "special_tokens_map.json", sha256: "2b7379f3ae813529281a5c602bc5a11c1d4e0a99107aaa597fe936c1e813ca52", size: 655),
        Asset(path: "tokenizer_config.json", sha256: "5dbff37e2d5899f5f69d86116f80733e11a790f703fd59855e2aef5717533ac5", size: 3_398),
        Asset(path: "tokenizer.json", sha256: "7d27c493c729a66ecefc837280b05d948b1ed50d130eebdbf911b1b36cf38ed7", size: 3_522_656),
        Asset(path: "vocab.json", sha256: "82b84012e3add4d01d12ba14442026e49b8cbbaead1f79ecf3d919784f82dc79", size: 800_662),
    ]

    static var folder: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("com.alandotcom.Kol", isDirectory: true)
            .appendingPathComponent("LocalCleanupModel-\(revision)", isDirectory: true)
    }

    private static var readyMarker: URL { folder.appendingPathComponent(".ready") }

    /// True when the pinned model is downloaded, verified and compiled.
    static var isReady: Bool {
        FileManager.default.fileExists(atPath: readyMarker.path)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("Cleanup.mlmodelc").path)
    }

    /// Downloads whatever is missing, verifies every file and compiles the model. `progress` receives the fraction of
    /// bytes downloaded so far, from 0 to 1.
    static func ensure(progress: @escaping @Sendable (Double) -> Void) async throws {
        if isReady { progress(1); return }
        let progress = Throttle(progress).report
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = assets.reduce(0) { $0 + $1.size }
        var finished: Int64 = 0
        for asset in assets {
            let destination = folder.appendingPathComponent(asset.path)
            if manager.fileExists(atPath: destination.path), try sha256(of: destination) == asset.sha256 {
                finished += asset.size
                progress(Double(finished) / Double(total))
                continue
            }
            let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(asset.path)")!
            let base = finished
            let delegate = DownloadProgress { written in progress(Double(base + written) / Double(total)) }
            let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw LocalCleanupModelError.download("\(asset.path): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            guard try sha256(of: temporary) == asset.sha256 else {
                try? manager.removeItem(at: temporary)
                throw LocalCleanupModelError.download("\(asset.path) failed its checksum")
            }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: temporary, to: destination)
            finished += asset.size
            progress(Double(finished) / Double(total))
        }
        let package = folder.appendingPathComponent("Cleanup.mlpackage")
        let compiled = try await MLModel.compileModel(at: package)
        let target = folder.appendingPathComponent("Cleanup.mlmodelc")
        try? manager.removeItem(at: target)
        try manager.moveItem(at: compiled, to: target)
        try manager.removeItem(at: package)
        manager.createFile(atPath: readyMarker.path, contents: Data(revision.utf8))
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Passes on a progress fraction only when it has grown by half a percent, so the UI gets about 200 updates for
    /// the whole download instead of one per network chunk.
    private final class Throttle: @unchecked Sendable {
        private let lock = NSLock()
        private var last = -1.0
        private let forward: @Sendable (Double) -> Void

        init(_ forward: @escaping @Sendable (Double) -> Void) {
            self.forward = forward
        }

        func report(_ fraction: Double) {
            lock.lock()
            let send = fraction >= 1 || fraction - last >= 0.005
            if send { last = fraction }
            lock.unlock()
            if send { forward(fraction) }
        }
    }

    /// Reports bytes written for one download.
    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
        let report: @Sendable (Int64) -> Void

        init(report: @escaping @Sendable (Int64) -> Void) {
            self.report = report
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            report(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

enum LocalCleanupModelError: LocalizedError {
    case download(String)

    var errorDescription: String? {
        switch self {
        case let .download(detail): "The cleanup model download failed (\(detail))."
        }
    }
}
