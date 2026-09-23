import Foundation
import SwiftUI
import Translation

/// The subtitle choices, the language tools they need, and the one take being
/// subtitled right now.
///
/// A take is subtitled in the background after it is finished: the next take
/// can start straight away.
@MainActor
final class SubtitleCenter: ObservableObject {
    /// Speech recognition and translation that run without a window arrived in macOS 26.
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }

    // MARK: Choices

    @Published var isEnabled: Bool {
        didSet { if persists { DevicePreferences.subtitlesEnabled = isEnabled } }
    }

    @Published var spokenLanguage: SubtitleLanguage {
        didSet {
            guard spokenLanguage != oldValue else { return }
            if persists { DevicePreferences.spokenLanguage = spokenLanguage }
            refreshReadiness()
        }
    }

    @Published var languages: Set<SubtitleLanguage> {
        didSet {
            guard languages != oldValue else { return }
            if persists { DevicePreferences.subtitleLanguages = languages }
            refreshReadiness()
        }
    }

    /// Subtitle languages in a fixed order, for tracks and lists.
    var orderedLanguages: [SubtitleLanguage] { SubtitleLanguage.allCases.filter(languages.contains) }

    private var persists: Bool { !SelfTest.isEnabled }

    // MARK: Language tools

    @Published private(set) var readiness: [SubtitleLanguage: LanguageReadiness] = [:]
    /// 0…1 while speech recognition is being downloaded.
    @Published private(set) var speechDownloadProgress: Double?
    /// The translation pack being fetched; a view hands it to `.translationTask`,
    /// which is the only way macOS offers to download one.
    @Published private(set) var translationToPrepare: TranslationSession.Configuration?
    private var pendingTranslations: [SubtitleLanguage] = []
    @Published private(set) var downloadError: String?

    var isDownloading: Bool { speechDownloadProgress != nil || translationToPrepare != nil }

    var needsDownload: Bool {
        orderedLanguages.contains { readiness[$0] == .needsDownload }
    }

    // MARK: The take being subtitled

    enum JobState: Equatable {
        case running
        case finished([SubtitleLanguage])
        /// The .srt files written before cancelling stay.
        case cancelled(kept: [SubtitleLanguage])
        case failed(String)
    }

    struct Job: Equatable {
        let video: URL
        var progress: SubtitleProgress
        let started: Date
        var state: JobState
    }

    @Published private(set) var job: Job?
    private var task: Task<Void, Never>?
    /// One per take: a cancelled muxer stays cancelled.
    private var muxer = SubtitleMuxer()

    /// Called when a take has its subtitles, so a preview can reload it.
    var onFinished: ((URL) -> Void)?

    init() {
        isEnabled = DevicePreferences.subtitlesEnabled
        spokenLanguage = DevicePreferences.spokenLanguage
        languages = DevicePreferences.subtitleLanguages
    }

    // MARK: - Readiness and downloads

    func refreshReadiness() {
        guard #available(macOS 26.0, *) else { return }
        let spoken = spokenLanguage
        for language in SubtitleLanguage.allCases where readiness[language] == nil {
            readiness[language] = .checking
        }
        Task {
            var found: [SubtitleLanguage: LanguageReadiness] = [:]
            for language in SubtitleLanguage.allCases {
                found[language] = await SubtitleAssets.readiness(spoken: spoken, target: language)
            }
            guard spoken == self.spokenLanguage else { return }
            self.readiness = found
        }
    }

    /// Fetches what the chosen languages still need: speech recognition first,
    /// then one translation pack after another.
    func downloadMissing() {
        guard #available(macOS 26.0, *), !isDownloading else { return }
        downloadError = nil
        let spoken = spokenLanguage
        let targets = orderedLanguages.filter { $0 != spoken }
        Task {
            if await SubtitleAssets.speechReadiness(spoken) == .needsDownload {
                self.speechDownloadProgress = 0
                do {
                    try await SubtitleAssets.downloadSpeech(spoken) { fraction in
                        Task { @MainActor in
                            if self.speechDownloadProgress != nil { self.speechDownloadProgress = fraction }
                        }
                    }
                } catch {
                    self.downloadError = "\(spoken.englishName) speech recognition could not be downloaded: "
                        + error.localizedDescription
                }
                self.speechDownloadProgress = nil
            }
            var missing: [SubtitleLanguage] = []
            for target in targets
            where await LanguageAvailability().status(from: spoken.language, to: target.language) == .supported {
                missing.append(target)
            }
            self.pendingTranslations = missing
            self.prepareNextTranslation()
            self.refreshReadiness()
        }
    }

    private func prepareNextTranslation() {
        guard !pendingTranslations.isEmpty else {
            translationToPrepare = nil
            refreshReadiness()
            return
        }
        let target = pendingTranslations.removeFirst()
        translationToPrepare = TranslationSession.Configuration(source: spokenLanguage.language,
                                                                target: target.language)
    }

    /// From the view's `.translationTask`, once macOS has fetched the pack — it
    /// shows its own confirmation — or failed to: on to the next.
    func translationPrepared(_ error: Error?) {
        if let error {
            downloadError = "A translation could not be downloaded: \(error.localizedDescription)"
        }
        prepareNextTranslation()
    }

    // MARK: - Subtitling a take

    /// Starts subtitles for a finished take, if they are switched on.
    func start(for video: URL) {
        guard #available(macOS 26.0, *), isEnabled, !languages.isEmpty, !SelfTest.isEnabled else { return }
        cancel()
        muxer = SubtitleMuxer()
        let spoken = spokenLanguage
        let targets = orderedLanguages
        job = Job(video: video,
                  progress: SubtitleProgress(translationCount: targets.filter { $0 != spoken }.count),
                  started: .now, state: .running)
        let muxer = muxer
        task = Task { await self.run(video: video, spoken: spoken, targets: targets, muxer: muxer) }
    }

    func cancel() {
        muxer.cancel()
        task?.cancel()
    }

    func dismiss() {
        guard job?.state != .running else { return }
        job = nil
    }

    /// The take was thrown away: stop, and take its subtitle files with it.
    func discard(_ video: URL) {
        if job?.video == video {
            cancel()
            job = nil
        }
        for language in SubtitleLanguage.allCases {
            let file = SRTWriter.url(nextTo: video, language: language)
            if FileManager.default.fileExists(atPath: file.path) {
                try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
            }
        }
    }

    @available(macOS 26.0, *)
    private func run(video: URL, spoken: SubtitleLanguage, targets: [SubtitleLanguage],
                     muxer: SubtitleMuxer) async {
        var written: [SubtitleLanguage] = []
        let translations = targets.filter { $0 != spoken }
        do {
            let words = try await SubtitleTranscriber.words(in: video, language: spoken) { fraction in
                Task { @MainActor in self.report(.listening, fraction, for: video) }
            }
            let cues = SubtitleSegmenter.cues(from: words)
            guard !cues.isEmpty else {
                finish(.failed("No speech was recognised in this take."), for: video)
                return
            }

            var tracks: [(language: SubtitleLanguage, cues: [SubtitleCue])] = []
            for target in targets {
                try Task.checkCancellation()
                var result = cues
                if let index = translations.firstIndex(of: target) {
                    let step = SubtitleProgress.Step.translating(target, index: index, count: translations.count)
                    report(step, 0, for: video)
                    result = try await SubtitleTranslator.translate(cues, from: spoken, to: target) { fraction in
                        Task { @MainActor in self.report(step, fraction, for: video) }
                    }
                }
                try SRTWriter.srt(for: result).write(to: SRTWriter.url(nextTo: video, language: target),
                                                    atomically: true, encoding: .utf8)
                written.append(target)
                tracks.append((target, result))
            }

            try Task.checkCancellation()
            report(.addingToVideo, 0, for: video)
            try await muxer.addSubtitles(tracks, to: video) { fraction in
                Task { @MainActor in self.report(.addingToVideo, fraction, for: video) }
            }
            report(.done, 1, for: video)
            finish(.finished(written), for: video)
            onFinished?(video)
        } catch {
            if Task.isCancelled || (error as? SubtitleMuxer.MuxError).map({ if case .cancelled = $0 { true } else { false } }) == true {
                finish(.cancelled(kept: written), for: video)
            } else {
                finish(.failed(error.localizedDescription), for: video)
            }
        }
    }

    /// Progress arrives from background callbacks, possibly late: only forward
    /// movement on the running job counts.
    private func report(_ step: SubtitleProgress.Step, _ fraction: Double, for video: URL) {
        guard var job, job.video == video, job.state == .running else { return }
        var next = job.progress
        next.advance(to: step, fraction: fraction)
        guard next.fraction >= job.progress.fraction else { return }
        job.progress = next
        self.job = job
    }

    private func finish(_ state: JobState, for video: URL) {
        guard var job, job.video == video else { return }
        job.state = state
        self.job = job
    }
}
