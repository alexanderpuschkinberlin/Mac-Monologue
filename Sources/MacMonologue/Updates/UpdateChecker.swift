import AppKit
import Combine
import Foundation

/// When to look for updates, and when to offer them.
///
/// Looks shortly after launch and then once a day, unless switched off. An update
/// found in the background waits until no take is running — a window appearing
/// mid-presentation would be recorded, or at least be in the way.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available([Release])
        case working(UpdateInstaller.Step)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @Published var checksAutomatically = true {
        didSet {
            guard checksAutomatically != oldValue else { return }
            if persistsPreferences { DevicePreferences.checksForUpdatesAutomatically = checksAutomatically }
            scheduleNextCheck()
        }
    }

    /// Newest first; empty when there is nothing to offer.
    var availableReleases: [Release] {
        if case .available(let releases) = state { return releases }
        return offered
    }

    let installedVersion = AppVersion.current ?? AppVersion("0")!

    /// Why this copy cannot install updates where it is, if it cannot.
    var installationProblem: UpdateInstaller.InstallError? { UpdateInstaller.installationProblem() }

    private weak var capture: CaptureController?
    private var offered: [Release] = []
    private var waitingForTakeToEnd: [Release]?
    private var timer: Timer?
    private var installation: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    /// Automatic checks are off in the self-test and in development builds, where
    /// an update would overwrite the build being worked on.
    private var automaticChecksAllowed: Bool {
        !SelfTest.isEnabled && installationProblem != .developmentBuild
    }
    private var persistsPreferences: Bool { !SelfTest.isEnabled }

    /// For bin/test-update: install whatever is found, without asking.
    private let installsWithoutAsking = UserDefaults.standard.bool(forKey: "UpdateInstallWithoutAsking")

    /// Called whenever the main window appears — which can be more than once, so
    /// only the first call does anything.
    func start(capture: CaptureController) {
        guard self.capture == nil else { return }
        self.capture = capture
        checksAutomatically = DevicePreferences.checksForUpdatesAutomatically
        lastCheck = DevicePreferences.lastUpdateCheck

        // Offer what was held back as soon as the take is over.
        capture.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, !Self.isBusy(state), let pending = self.waitingForTakeToEnd else { return }
                self.waitingForTakeToEnd = nil
                self.offer(pending)
            }
            .store(in: &subscriptions)

        scheduleNextCheck(initialDelay: UserDefaults.standard.object(forKey: "UpdateCheckDelay") as? Double ?? 8)
    }

    // MARK: - Checking

    /// `userInitiated` checks always answer, even "you're up to date", and ignore a
    /// skipped version. Automatic ones stay silent unless there is something new.
    func checkNow(userInitiated: Bool) {
        if case .working = state { return }
        if userInitiated { UpdateWindowController.shared.show(self) }
        state = .checking

        Task {
            do {
                let releases = try await ReleaseFeed.fetch()
                lastCheck = Date()
                if persistsPreferences { DevicePreferences.lastUpdateCheck = lastCheck }
                let updates = ReleaseFeed.updates(in: releases, newerThan: installedVersion)
                handle(updates, userInitiated: userInitiated)
            } catch {
                log("check failed: \(error.localizedDescription)")
                state = userInitiated ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    /// For bin/test-update, which reads what happened from standard output.
    private func log(_ message: String) {
        guard installsWithoutAsking else { return }
        print("[update] \(message)")
        fflush(stdout)
    }

    private func handle(_ updates: [Release], userInitiated: Bool) {
        guard let newest = updates.first else {
            log("up to date at \(installedVersion)")
            state = userInitiated ? .upToDate : .idle
            return
        }
        log("found \(newest.version?.description ?? newest.tagName)")
        if !userInitiated, let skipped = DevicePreferences.skippedUpdateVersion.flatMap(AppVersion.init),
           newest.version == skipped {
            state = .idle
            return
        }
        if installsWithoutAsking {
            offered = updates
            install()
            return
        }
        if !userInitiated, let capture, Self.isBusy(capture.state) {
            state = .idle
            waitingForTakeToEnd = updates
            return
        }
        offer(updates)
    }

    private func offer(_ updates: [Release]) {
        offered = updates
        state = .available(updates)
        UpdateWindowController.shared.show(self)
    }

    private func scheduleNextCheck(initialDelay: TimeInterval? = nil) {
        timer?.invalidate()
        timer = nil
        guard checksAutomatically, automaticChecksAllowed || installsWithoutAsking else { return }

        let day: TimeInterval = 24 * 60 * 60
        let sinceLast = lastCheck.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = initialDelay ?? max(60, day - sinceLast)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkNow(userInitiated: false)
                self?.scheduleNextCheck()
            }
        }
    }

    // MARK: - Choices

    func install() {
        guard let release = offered.first, installation == nil else { return }
        if let capture, Self.isBusy(capture.state) { return }

        installation = Task {
            do {
                try await UpdateInstaller.install(release) { step in
                    Task { @MainActor in self.state = .working(step) }
                }
                log("installed \(release.version?.description ?? release.tagName), relaunching")
                Relauncher.relaunch()
            } catch is CancellationError {
                state = .available(offered)
            } catch {
                log("refused: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
            installation = nil
        }
    }

    func cancelInstallation() {
        installation?.cancel()
    }

    func skipOffered() {
        if let newest = offered.first?.version, persistsPreferences {
            DevicePreferences.skippedUpdateVersion = newest.description
        }
        dismiss()
    }

    func dismiss() {
        if case .working = state { return }
        state = .idle
        UpdateWindowController.shared.close()
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(offered.first?.pageURL ?? ReleaseFeed.pageURL)
    }

    private static func isBusy(_ state: RecorderState) -> Bool {
        state == .recording || state == .paused || state == .finishing
    }
}
