import Foundation

/// Downloads, verifies and installs one release. Every step can refuse; nothing
/// is replaced until all of them have passed.
enum UpdateInstaller {
    enum Step: Equatable, Sendable {
        case downloading(Double)
        case verifying
        case installing
    }

    enum InstallError: LocalizedError, Equatable {
        case translocated
        case developmentBuild
        case notWritable
        case noDownload
        case downloadFailed(String)
        case unpackFailed
        case replaceFailed(String)

        var errorDescription: String? {
            switch self {
            case .translocated:
                "Mac-Monologue is running from where it was downloaded, which macOS keeps read-only. "
                    + "Quit it, drag it into your Applications folder, and open it from there."
            case .developmentBuild:
                "Updates are switched off in development builds."
            case .notWritable:
                "Mac-Monologue cannot replace itself in this folder — it needs to be somewhere you are "
                    + "allowed to change, such as your Applications folder as an administrator."
            case .noDownload:
                "This release has no app to download."
            case .downloadFailed(let reason):
                "The download failed: \(reason)"
            case .unpackFailed:
                "The download could not be unpacked."
            case .replaceFailed(let reason):
                "The new version could not be put in place: \(reason)"
            }
        }
    }

    /// Why this copy of the app cannot update itself where it is, if it cannot —
    /// checked before offering to install rather than failing halfway.
    static func installationProblem(bundleURL: URL = Bundle.main.bundleURL) -> InstallError? {
        let path = bundleURL.path
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.contains("/build/Build/Products/") { return .developmentBuild }
        let folder = bundleURL.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: folder) || !FileManager.default.isWritableFile(atPath: path) {
            return .notWritable
        }
        return nil
    }

    /// Returns once the new version is in place at `bundleURL`; relaunching is
    /// the caller's decision.
    static func install(
        _ release: Release,
        over bundleURL: URL = Bundle.main.bundleURL,
        progress: @escaping @Sendable (Step) -> Void
    ) async throws {
        if let problem = installationProblem(bundleURL: bundleURL) { throw problem }
        guard let asset = release.appAsset, let version = release.version else { throw InstallError.noDownload }
        let identifier = Bundle.main.bundleIdentifier ?? ""
        // Taken before anything changes: the rule the new app has to satisfy.
        let requirement = try UpdateVerifier.ownDesignatedRequirement()

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-monologue-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        progress(.downloading(0))
        let archive = try await Download.fetch(asset.downloadURL, into: workspace) { fraction in
            progress(.downloading(fraction))
        }
        try Task.checkCancellation()

        progress(.verifying)
        try UpdateVerifier.verifyChecksum(of: archive, expected: release.appAssetSHA256)
        let unpacked = workspace.appendingPathComponent("unpacked")
        let app = try unpack(archive, into: unpacked)
        try UpdateVerifier.verifySignature(ofAppAt: app, matching: requirement)
        try UpdateVerifier.verifyBundle(at: app, identifier: identifier, version: version)
        try Task.checkCancellation()

        progress(.installing)
        do {
            // Atomic on the same volume. The running app keeps the files it has
            // open; it is relaunched right after.
            _ = try FileManager.default.replaceItemAt(bundleURL, withItemAt: app)
        } catch {
            throw InstallError.replaceFailed(error.localizedDescription)
        }
    }

    /// Unpacks with `ditto`, as the zip was made, and insists on exactly one
    /// Mac-Monologue app inside.
    private static func unpack(_ archive: URL, into folder: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.unpackFailed }

        let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard apps.count == 1, let app = apps.first else { throw UpdateVerifier.Failure.unreadableApp }
        return app
    }
}

/// One file download with progress, cancellable through Swift concurrency.
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var task: URLSessionDownloadTask?
    private let lock = NSLock()

    private init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func fetch(_ url: URL, into folder: URL,
                      onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let download = Download(destination: folder.appendingPathComponent("download.zip"), onProgress: onProgress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.start(url, continuation: continuation)
            }
        } onCancel: {
            download.cancel()
        }
    }

    private func start(_ url: URL, continuation: CheckedContinuation<URL, Error>) {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Mac-Monologue/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        lock.withLock {
            self.continuation = continuation
            self.task = task
        }
        task.resume()
        session.finishTasksAndInvalidate()
    }

    private func cancel() {
        lock.withLock { task }?.cancel()
    }

    private func finish(_ result: Result<URL, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(UpdateInstaller.InstallError.downloadFailed("the server answered \(http.statusCode)")))
            return
        }
        // The system deletes `location` as soon as this returns.
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            onProgress(1)
            finish(.success(destination))
        } catch {
            finish(.failure(UpdateInstaller.InstallError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as? URLError)?.code == .cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(UpdateInstaller.InstallError.downloadFailed(error.localizedDescription)))
        }
    }
}
