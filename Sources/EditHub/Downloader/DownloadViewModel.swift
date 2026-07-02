import AppKit
import Foundation
import Observation
import SwiftUI

typealias ProgressHandler = @MainActor (_ status: String, _ fraction: Double) -> Void

/// One pending download captured by the "+" button: its link plus the exact
/// destination folder (as a security-scoped bookmark) chosen at the time it was
/// added, so each queued item lands in its own folder.
struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    let link: String
    let destinationBookmark: Data?
    let destinationPath: String

    /// Human-friendly label for the link, e.g. "Drive file · 1hWh…".
    var displayName: String { DownloadFormatting.friendlyLinkName(link) }

    static func == (lhs: QueueItem, rhs: QueueItem) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class DownloadViewModel: NSObject {
    var linkText = ""
    var destinationDisplayPath = ""
    var statusText = ""
    var progressCaption = "Waiting…"
    var progressFraction: Double = 0
    var isLoading = false
    var isPaused = false
    var hasError = false
    var errorMessage: String?
    var downloadSpeedText = "--"
    var downloadedSizeText = "--"
    var totalSizeText = "--"
    var remainingTimeText = "--"
    var recoverableSessions: [PersistedDownloadState] = []
    var queue: [QueueItem] = []
    /// The project folder the active download is landing in (the parent of the
    /// destination folder, e.g. the project that owns the FOOTAGE folder). Used
    /// by the project list to show inline download progress on the right row.
    var activeDownloadProjectURL: URL?
    /// Bumped each time the link/path fields are cleared into the queue, so the
    /// UI can play a brief "cleared" pulse animation.
    var fieldsResetPulse: UInt = 0

    var canStartDownload: Bool {
        guard !isLoading else { return false }
        // Ready when the current fields hold a valid download, OR when nothing is
        // typed but the queue has items waiting to run.
        let hasCurrent = !normalizedLinkText().isEmpty && destinationStore.selectedURL != nil
        let hasQueueOnly = normalizedLinkText().isEmpty && !queue.isEmpty
        return hasCurrent || hasQueueOnly
    }

    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let destinationStore = DownloadDestinationStore()
    @ObservationIgnored private let recoveryStore = PersistedDownloadStateStore()
    @ObservationIgnored private var downloadControl = DownloadControlCoordinator()
    @ObservationIgnored private var currentDownloadTask: Task<Void, Never>?
    @ObservationIgnored private var activeRecoveryState: PersistedDownloadState?
    @ObservationIgnored private var lastAutofilledClipboardLink = ""
    @ObservationIgnored private var userInitiatedCancellation = false
    @ObservationIgnored private var antiSleepActivity: NSObjectProtocol?
    @ObservationIgnored private let diagnostics = DownloadDiagnosticsStore()
    @ObservationIgnored private var smoothedDownloadSpeedBytesPerSecond: Double?
    @ObservationIgnored private var lastSpeedTextUpdateAt: Date?
    @ObservationIgnored private var etaTimer: Timer?
    @ObservationIgnored private var latestBytesWritten: Int64 = 0
    @ObservationIgnored private var latestBytesExpected: Int64?
    @ObservationIgnored private var smoothedRemainingSeconds: Double?
    @ObservationIgnored private var lastRemainingTextUpdateAt: Date?
    @ObservationIgnored private var lastSizeTextUpdateAt: Date?
    @ObservationIgnored
    private let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    override init() {
        super.init()
        destinationDisplayPath = destinationStore.displayPath
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDownloadSessionSettingsChanged),
            name: .downloadSessionSettingsChanged,
            object: nil
        )
        refreshRecoverableSessions()
        sweepOrphanedStagingDirectories()

        if !recoverableSessions.isEmpty {
            withAnimation(SoftIOSMotion.entry) {
                statusText = "Saved sessions: \(recoverableSessions.count)"
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try destinationStore.setSelectedURL(url)
            withAnimation(SoftIOSMotion.state) {
                destinationDisplayPath = destinationStore.displayPath
                statusText = ""
            }
            sweepOrphanedStagingDirectories()
            dismissError()
        } catch {
            setError(error.localizedDescription)
        }
    }

    /// Программно задать папку назначения (например FOOTAGE выбранного проекта).
    func setDestination(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try destinationStore.setSelectedURL(url)
            destinationDisplayPath = destinationStore.displayPath
            statusText = ""
            dismissError()
        } catch {
            setError(error.localizedDescription)
        }
    }

    func autofillLinkFromClipboardIfNeeded() {
        guard !isLoading else { return }
        guard activeRecoveryState == nil else { return }
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }

        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        guard candidate != linkText else { return }
        guard candidate != lastAutofilledClipboardLink else { return }
        guard isAutofillSupportedLink(candidate) else { return }

        withAnimation(SoftIOSMotion.text) {
            linkText = candidate
            statusText = ""
        }
        lastAutofilledClipboardLink = candidate
        dismissError()
    }

    /// "+" is available whenever there's a link to capture (a folder isn't
    /// required — we fall back to the last selected one when the item runs).
    var canEnqueue: Bool {
        !normalizedLinkText().isEmpty
    }

    /// Captures the current link + chosen folder into the queue and clears the
    /// fields so the next one can be typed in. Press "+" as many times as needed.
    func enqueueCurrent() {
        let link = normalizedLinkText()
        guard !link.isEmpty else { return }

        let item = QueueItem(
            link: link,
            destinationBookmark: destinationStore.currentBookmark,
            destinationPath: destinationStore.displayPath
        )
        withAnimation(SoftIOSMotion.morph) {
            queue.append(item)
            linkText = ""
            // Blank the path field too so the next entry starts fresh; the
            // captured bookmark keeps this item's folder safe.
            destinationStore.clearSelection()
            destinationDisplayPath = ""
            statusText = "Queued: \(queue.count)"
            // Bumped so the fields can play a quick "cleared" pulse.
            fieldsResetPulse &+= 1
        }
        lastAutofilledClipboardLink = link  // don't re-autofill what we just queued
        dismissError()
    }

    /// Queue a link to download into a specific folder, captured as a
    /// security-scoped bookmark so it survives until the item runs. If nothing
    /// is currently downloading, the queue starts immediately. This is the entry
    /// point used by the create-project popover.
    func queueDownload(link: String, into folder: URL) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? destinationStore.setSelectedURL(folder)

        let item = QueueItem(
            link: trimmed,
            destinationBookmark: destinationStore.currentBookmark,
            destinationPath: folder.path
        )
        withAnimation(SoftIOSMotion.morph) {
            queue.append(item)
            statusText = "Queued: \(queue.count)"
        }
        dismissError()

        if !isLoading {
            startNextQueuedItemIfNeeded()
        }
    }

    func removeFromQueue(_ item: QueueItem) {
        withAnimation(SoftIOSMotion.state) {
            queue.removeAll { $0.id == item.id }
        }
    }

    func clearQueue() {
        withAnimation(SoftIOSMotion.state) {
            queue.removeAll()
        }
    }

    /// After a download finishes (or fails), pull the next queued item, restore
    /// its folder, and start it automatically.
    private func startNextQueuedItemIfNeeded() {
        guard currentDownloadTask == nil, !isLoading else { return }
        guard !queue.isEmpty else { return }

        let next = queue.removeFirst()

        if let bookmark = next.destinationBookmark {
            destinationStore.setFromBookmark(bookmark)
            destinationDisplayPath = destinationStore.displayPath
        }

        withAnimation(SoftIOSMotion.text) {
            linkText = next.link
        }
        startDownload()
    }

    func startDownload() {
        guard currentDownloadTask == nil else { return }
        userInitiatedCancellation = false

        // Empty fields but a non-empty queue → just begin the queue.
        if normalizedLinkText().isEmpty, !queue.isEmpty {
            startNextQueuedItemIfNeeded()
            return
        }

        if let recoveryState = activeRecoveryState,
           recoveryState.originalLink == normalizedLinkText(),
           fileManager.fileExists(atPath: recoveryState.sessionDirectoryPath) {
            currentDownloadTask = Task { [weak self] in
                await self?.download(resumeState: recoveryState)
            }
            return
        }

        guard let url = URL(string: normalizedLinkText()) else {
            setError("Add a valid Google Drive, Dropbox, OneDrive, pCloud or MediaFire link.")
            return
        }

        currentDownloadTask = Task { [weak self] in
            await self?.download(from: url)
        }
    }

    func restoreSession(_ session: PersistedDownloadState) {
        guard !isLoading else { return }
        guard fileManager.fileExists(atPath: session.sessionDirectoryPath) else {
            recoveryStore.clear(session)
            refreshRecoverableSessions()
            setError("Saved session files are missing.")
            return
        }

        activeRecoveryState = session
        withAnimation(SoftIOSMotion.text) {
            linkText = session.originalLink
            statusText = "Restoring: \(session.shortDisplayTitle)"
        }
        startDownload()
    }

    func forgetSession(_ session: PersistedDownloadState) {
        recoveryStore.clear(session)
        try? fileManager.removeItem(at: session.sessionDirectoryURL)
        refreshRecoverableSessions()
    }

    /// Menu label for a saved session: title plus how much is already on disk
    /// and how much is left, e.g. "Google Drive - VIDEO.MP4 — 1,2 GB / 10 GB · 8,8 GB LEFT".
    func recoverySessionLabel(_ session: PersistedDownloadState) -> String {
        "\(session.shortDisplayTitle) — \(session.progressSummary(formatter: byteCountFormatter))"
    }

    func clearSavedSessions() {
        recoveryStore.clearAll(removeSessionDirectories: true)
        activeRecoveryState = nil
        refreshRecoverableSessions()
    }

    func togglePause() {
        guard isLoading else { return }
        withAnimation(SoftIOSMotion.pause) {
            isPaused.toggle()
            statusText = isPaused ? "Paused" : progressCaption
        }
        downloadControl.setPaused(isPaused)
    }

    func cancelDownload() {
        guard isLoading else { return }
        userInitiatedCancellation = true
        clearRecoveryState()
        downloadControl.cancel()
        currentDownloadTask?.cancel()
        withAnimation(SoftIOSMotion.morph) {
            statusText = "Download cancelled."
            progressCaption = "Cancelled"
            progressFraction = 0
            downloadSpeedText = "--"
            downloadedSizeText = "--"
            totalSizeText = "--"
            remainingTimeText = "--"
        }
    }

    private func download(from url: URL) async {
        await downloadInternal(sourceURL: url, resumeState: nil)
    }

    private func download(resumeState: PersistedDownloadState) async {
        await downloadInternal(sourceURL: URL(string: resumeState.originalLink), resumeState: resumeState)
    }

    private func downloadInternal(sourceURL: URL?, resumeState: PersistedDownloadState?) async {
        guard !isLoading else { return }
        guard let url = sourceURL else {
            setError("Recovery state is invalid. Start a new download.")
            clearRecoveryState(removeSessionDirectory: true)
            return
        }
        guard let destinationURL = resumeState?.finalDestinationURL ?? destinationStore.selectedURL else {
            setError("Choose a download folder first.")
            return
        }

        withAnimation(SoftIOSMotion.entry) {
            isLoading = true
            isPaused = false
            progressFraction = 0
            progressCaption = "Preparing…"
            statusText = "Detecting source…"
            downloadSpeedText = "--"
            downloadedSizeText = "--"
            totalSizeText = "--"
            remainingTimeText = "--"
            // Destinations are `<project>/FOOTAGE`; the project is the parent.
            activeDownloadProjectURL = destinationURL.deletingLastPathComponent()
        }
        smoothedDownloadSpeedBytesPerSecond = nil
        lastSpeedTextUpdateAt = nil
        startETATimer()
        dismissError()
        downloadControl = DownloadControlCoordinator()
        antiSleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Downloading files"
        )
        diagnostics.log("DOWNLOAD STARTED FOR LINK: \(url.absoluteString)")

        defer {
            currentDownloadTask = nil
            downloadControl.reset()
            stopETATimer()
            withAnimation(SoftIOSMotion.controlSwap) {
                isPaused = false
                isLoading = false
                activeDownloadProjectURL = nil
            }
            if let antiSleepActivity {
                ProcessInfo.processInfo.endActivity(antiSleepActivity)
                self.antiSleepActivity = nil
            }
            // Chain into the queue: when this download ends on its own (done or
            // failed), kick off the next queued item. A user cancel stops the
            // whole queue — it shouldn't silently roll on to the next link.
            if !userInitiatedCancellation, !queue.isEmpty {
                let nextDelay: Duration = .milliseconds(800)
                Task { [weak self] in
                    try? await Task.sleep(for: nextDelay)
                    self?.startNextQueuedItemIfNeeded()
                }
            }
        }

        do {
            let source = try LinkDetector.detect(url: url)
            let state = try await preparedRecoveryState(for: source, originalURL: url, existing: resumeState)
            activeRecoveryState = state

            let reporter: ProgressHandler = { status, fraction in
                withAnimation(SoftIOSMotion.progress) {
                    self.progressCaption = status
                    self.progressFraction = min(1, max(0, fraction))
                    self.statusText = self.isPaused ? "Paused" : status
                }
            }

            let materializedURLs = try await runPersistedDownload(state: state, progress: reporter, finalDestination: destinationURL)
            reporter("Completed", 1.0)
            let resultPath = materializedURLs.count == 1 ? materializedURLs[0].path : destinationURL.path
            withAnimation(SoftIOSMotion.morph) {
                progressFraction = 1
                progressCaption = "Completed"
                statusText = "Done: \(resultPath)"
                downloadSpeedText = "--"
            }
            smoothedDownloadSpeedBytesPerSecond = nil
            lastSpeedTextUpdateAt = nil
            diagnostics.log("DOWNLOAD COMPLETED: \(resultPath)")
            clearRecoveryState(removeSessionDirectory: true)
            try? await Task.sleep(for: .milliseconds(650))
        } catch is CancellationError {
            if userInitiatedCancellation {
                withAnimation(SoftIOSMotion.morph) {
                    progressFraction = 0
                    downloadSpeedText = "--"
                }
                smoothedDownloadSpeedBytesPerSecond = nil
                lastSpeedTextUpdateAt = nil
                diagnostics.log("DOWNLOAD CANCELLED BY USER")
            } else {
                setError("Download was cancelled before completion.")
            }
        } catch let error as URLError where error.code == .cancelled {
            if userInitiatedCancellation {
                withAnimation(SoftIOSMotion.morph) {
                    progressFraction = 0
                    downloadSpeedText = "--"
                }
                smoothedDownloadSpeedBytesPerSecond = nil
                lastSpeedTextUpdateAt = nil
                diagnostics.log("NETWORK REQUEST CANCELLED BY USER")
            } else {
                setError("Network request was cancelled.")
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func preparedRecoveryState(for source: LinkSource, originalURL: URL, existing: PersistedDownloadState?) async throws -> PersistedDownloadState {
        if let existing,
           existing.originalLink == originalURL.absoluteString,
           fileManager.fileExists(atPath: existing.sessionDirectoryPath),
           isReusableRecoveryState(existing, for: source) {
            return existing
        }

        let persistedSource: PersistedDownloadSource = {
            switch source {
            case .dropbox: return .dropbox
            case .googleDrive: return .googleDrive
            case .directHost(let host): return PersistedDownloadSource(directHost: host)
            }
        }()

        let sessionDirectory = try makePersistentSessionDirectory()
        var state = PersistedDownloadState(
            id: UUID().uuidString,
            source: persistedSource,
            originalLink: originalURL.absoluteString,
            sessionDirectoryPath: sessionDirectory.path,
            finalDestinationPath: destinationStore.selectedURL?.path,
            items: [],
            currentIndex: 0,
            resumeDataBase64: nil,
            topLevelDestinationPaths: nil,
            updatedAt: Date()
        )

        switch source {
        case .dropbox:
            state.items = DropboxDownloader().preparePlan(url: originalURL)
        case .googleDrive:
            let key = GoogleDriveAPIKeyStorage.current()
            let accessToken = try await GoogleDriveAuthController.shared.currentAccessToken()
            guard !key.isEmpty || accessToken != nil else {
                throw DownloaderError.googleDriveAuthorizationRequired
            }
            state.items = try await GoogleDriveDownloader(apiKey: key, accessToken: accessToken).buildDownloadPlan(url: originalURL)
        case .directHost(let host):
            if host == .oneDrive,
               let sharePointItems = try await SharePointAnonymousDownloader().buildPlanIfPossible(url: originalURL),
               !sharePointItems.isEmpty {
                state.items = sharePointItems
                break
            }

            let plan = try await DirectHostResolver.resolve(host: host, url: originalURL)
            guard let primary = (host == .oneDrive ? originalURL : plan.candidates.first?.url) else {
                throw DownloaderError.processFailed("\(host.displayName.uppercased()) LINK COULD NOT BE RESOLVED.")
            }
            state.items = [
                DownloadPlanItem(
                    sourceURLString: primary.absoluteString,
                    relativeDestinationPath: plan.suggestedFilename,
                    displayName: (plan.suggestedFilename ?? host.displayName).uppercased(),
                    headers: nil
                )
            ]
        }

        recoveryStore.save(state)
        return state
    }

    private func isReusableRecoveryState(_ state: PersistedDownloadState, for source: LinkSource) -> Bool {
        switch source {
        case .dropbox:
            return state.source == .dropbox
        case .googleDrive:
            return state.source == .googleDrive && state.items.allSatisfy { !$0.sourceURLString.isEmpty }
        case .directHost:
            // Direct download URLs (pCloud/MediaFire/OneDrive) are short-lived
            // and may have expired by the time we recover, so always re-resolve.
            return false
        }
    }

    private func runPersistedDownload(
        state: PersistedDownloadState,
        progress: @escaping ProgressHandler,
        finalDestination: URL
    ) async throws -> [URL] {
        var state = state
        var materializedURLs: [URL] = []
        var topLevelDestinationPaths = state.topLevelDestinationPaths ?? [:]

        guard !state.items.isEmpty else {
            try fileManager.createDirectory(at: state.sessionDirectoryURL, withIntermediateDirectories: true)
            return []
        }

        try fileManager.createDirectory(at: state.sessionDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: finalDestination, withIntermediateDirectories: true)

        // Plan-wide total in bytes, known only if every file reported a size.
        // (Dropbox files and exported Google-Apps docs don't, so it can be nil.)
        let planKnownTotalBytes: Int64? = state.items.allSatisfy { ($0.byteSize ?? 0) > 0 }
            ? state.items.reduce(0) { $0 + ($1.byteSize ?? 0) }
            : nil
        // Real bytes from files already finished in this run.
        var completedBytes: Int64 = 0
        // Resumed sessions start partway through; count earlier files as done.
        for earlier in 0..<min(state.currentIndex, state.items.count) {
            completedBytes += state.items[earlier].byteSize ?? 0
        }

        let resumeStartIndex = state.currentIndex
        for index in state.currentIndex..<state.items.count {
            try Task.checkCancellation()

            let item = state.items[index]
            let itemRequest = try await makeRequest(for: item, source: state.source)
            let fileBaseProgress = Double(index) / Double(max(state.items.count, 1))
            let fileSlice = 1.0 / Double(max(state.items.count, 1))
            let plannedDestination: URL?
            if state.source == .googleDrive {
                guard let relativePath = item.relativeDestinationPath else {
                    throw DownloaderError.badServerResponse
                }
                plannedDestination = finalItemDestination(
                    for: relativePath,
                    into: finalDestination,
                    topLevelDestinationPaths: &topLevelDestinationPaths
                )
                state.topLevelDestinationPaths = topLevelDestinationPaths
            } else {
                plannedDestination = nil
            }

            state.currentIndex = index
            state.updatedAt = Date()
            recoveryStore.save(state)
            activeRecoveryState = state

            let displayName = item.displayName
            // Resume data only applies to the exact item it was captured for —
            // the first item of a resumed session. Every later item starts fresh.
            let activeResumeData = (index == resumeStartIndex) ? state.resumeData : nil

            // Google Drive streams to a persistent partial file in the session
            // directory, keyed by index, so a dropped connection (or even an app
            // restart) resumes from disk instead of restarting from zero.
            let partialFileURL: URL? = state.source == .googleDrive
                ? state.sessionDirectoryURL.appendingPathComponent("part-\(index).download")
                : nil

            let (tempFile, response) = try await downloadValidatedItem(
                source: state.source,
                sourceRequest: itemRequest,
                resumeData: activeResumeData,
                displayName: displayName,
                index: index,
                totalCount: state.items.count,
                fileBaseProgress: fileBaseProgress,
                fileSlice: fileSlice,
                priorCompletedBytes: completedBytes,
                planKnownTotalBytes: planKnownTotalBytes,
                partialFileURL: partialFileURL,
                knownFileBytes: item.byteSize,
                progress: progress
            )

            // Fold this file's real size into the running completed total so the
            // aggregate "downloaded / total" stays accurate across files.
            completedBytes += item.byteSize ?? fileSizeOnDisk(tempFile)

            switch state.source {
            case .dropbox:
                try DropboxDownloader().finalizeDownload(tempFile: tempFile, response: response, into: state.sessionDirectoryURL)
                materializedURLs.append(contentsOf: try materializeDownloadedItems(from: state.sessionDirectoryURL, into: finalDestination))
                progress("Dropbox download completed", min(0.99, fileBaseProgress + fileSlice))
            case .googleDrive:
                guard let destination = plannedDestination else {
                    throw DownloaderError.badServerResponse
                }
                try GoogleDriveDownloader(apiKey: GoogleDriveAPIKeyStorage.current()).finalizeDownload(tempFile: tempFile, to: destination)
                materializedURLs.append(destination)
            case .oneDrive:
                if let relativePath = item.relativeDestinationPath, !relativePath.isEmpty {
                    let destination = state.sessionDirectoryURL.appendingPathComponent(relativePath)
                    try GoogleDriveDownloader(apiKey: GoogleDriveAPIKeyStorage.current()).finalizeDownload(tempFile: tempFile, to: destination)
                } else {
                    try DirectHostDownloader(host: .oneDrive).finalizeDownload(
                        tempFile: tempFile,
                        response: response,
                        suggestedFilename: item.relativeDestinationPath,
                        into: state.sessionDirectoryURL
                    )
                }
                materializedURLs.append(contentsOf: try materializeDownloadedItems(from: state.sessionDirectoryURL, into: finalDestination))
                progress("OneDrive download completed", min(0.99, fileBaseProgress + fileSlice))
            case .pcloud, .mediafire:
                guard let host = state.source.directHost else { throw DownloaderError.badServerResponse }
                try DirectHostDownloader(host: host).finalizeDownload(
                    tempFile: tempFile,
                    response: response,
                    suggestedFilename: item.relativeDestinationPath,
                    into: state.sessionDirectoryURL
                )
                materializedURLs.append(contentsOf: try materializeDownloadedItems(from: state.sessionDirectoryURL, into: finalDestination))
                progress("\(host.displayName) download completed", min(0.99, fileBaseProgress + fileSlice))
            }

            state.resumeDataBase64 = nil
            state.currentIndex = index + 1
            state.updatedAt = Date()
            recoveryStore.save(state)
            activeRecoveryState = state
        }

        return materializedURLs
    }

    private func makeRequest(for item: DownloadPlanItem, source: PersistedDownloadSource) async throws -> URLRequest {
        switch source {
        case .dropbox, .oneDrive, .pcloud, .mediafire:
            return item.request
        case .googleDrive:
            var request = URLRequest(url: try makeGoogleDriveSourceURL(from: item.sourceURL))
            let key = GoogleDriveAPIKeyStorage.current()
            let accessToken = try await GoogleDriveAuthController.shared.currentAccessToken()
            guard !key.isEmpty || accessToken != nil else {
                throw DownloaderError.googleDriveAuthorizationRequired
            }

            item.headers?
                .filter { $0.key.caseInsensitiveCompare("Authorization") != .orderedSame }
                .forEach { key, value in
                    request.setValue(value, forHTTPHeaderField: key)
                }

            if let accessToken, !accessToken.isEmpty {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            return request
        }
    }

    private func makeGoogleDriveSourceURL(from url: URL) throws -> URL {
        let apiKey = GoogleDriveAPIKeyStorage.current()
        guard !apiKey.isEmpty else { return url }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DownloaderError.badServerResponse
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name.caseInsensitiveCompare("key") == .orderedSame }
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw DownloaderError.badServerResponse
        }
        return resolvedURL
    }

    private func prepareRecoveryCheckpointForTermination() async {
        guard isLoading, var state = activeRecoveryState else { return }
        if let checkpoint = await downloadControl.checkpoint() {
            if state.currentIndex < state.items.count {
                let currentItem = state.items[state.currentIndex]
                state.items[state.currentIndex] = DownloadPlanItem(
                    sourceURLString: checkpoint.sourceURL.absoluteString,
                    relativeDestinationPath: currentItem.relativeDestinationPath,
                    displayName: currentItem.displayName,
                    headers: currentItem.headers,
                    byteSize: currentItem.byteSize
                )
            }
            state.resumeDataBase64 = checkpoint.resumeData?.base64EncodedString()
            state.updatedAt = Date()
            recoveryStore.save(state)
            refreshRecoverableSessions()
        } else {
            recoveryStore.save(state)
            refreshRecoverableSessions()
        }
    }

    private func clearRecoveryState(removeSessionDirectory: Bool = false) {
        if let activeRecoveryState {
            if removeSessionDirectory {
                try? fileManager.removeItem(at: activeRecoveryState.sessionDirectoryURL)
            }
            recoveryStore.clear(activeRecoveryState)
        }
        activeRecoveryState = nil
        refreshRecoverableSessions()
    }

    /// Removes leftover staging directories under `.raw-downloader-sessions`
    /// that no live recovery session points at. These are orphans from a
    /// download that was interrupted (crash, force-quit, expired session) and
    /// would otherwise leave files sitting in the hidden folder inside the
    /// user's destination.
    private func sweepOrphanedStagingDirectories() {
        let liveSessionPaths = Set(recoverableSessions.map { $0.sessionDirectoryURL.standardizedFileURL.path })

        var roots: [URL] = []
        if let destination = destinationStore.selectedURL {
            roots.append(destination.appendingPathComponent(".raw-downloader-sessions", isDirectory: true))
        }
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(appSupport.appendingPathComponent(".raw-downloader-sessions", isDirectory: true))
        }

        for root in roots {
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }

            for child in children where !liveSessionPaths.contains(child.standardizedFileURL.path) {
                try? fileManager.removeItem(at: child)
            }

            // Drop the hidden root entirely if it ended up empty.
            if let remaining = try? fileManager.contentsOfDirectory(atPath: root.path), remaining.isEmpty {
                try? fileManager.removeItem(at: root)
            }
        }
    }

    private func makePersistentSessionDirectory() throws -> URL {
        let baseDirectory = destinationStore.selectedURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseDirectory
            .appendingPathComponent(".raw-downloader-sessions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @objc
    private func handleAppWillTerminate() {
        Task { await prepareRecoveryCheckpointForTermination() }
    }

    @objc
    private func handleDownloadSessionSettingsChanged() {
        refreshRecoverableSessions()
    }

    private func materializeDownloadedItems(from stagingDirectory: URL, into destinationDirectory: URL) throws -> [URL] {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var result: [URL] = []
        for item in items {
            // Skip in-progress partial files left by the Range downloader.
            if item.lastPathComponent.hasPrefix("part-"), item.pathExtension == "download" { continue }
            let destination = uniqueDestinationURL(for: destinationDirectory.appendingPathComponent(item.lastPathComponent))
            try fileManager.moveItem(at: item, to: destination)
            result.append(destination)
        }
        return result
    }

    private func finalItemDestination(
        for relativePath: String,
        into destinationDirectory: URL,
        topLevelDestinationPaths: inout [String: String]
    ) -> URL {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let firstComponent = components.first else {
            return uniqueDestinationURL(for: destinationDirectory.appendingPathComponent("download"))
        }

        if components.count == 1 {
            if let destinationPath = topLevelDestinationPaths[firstComponent] {
                return URL(fileURLWithPath: destinationPath)
            }

            let destination = uniqueDestinationURL(for: destinationDirectory.appendingPathComponent(firstComponent))
            topLevelDestinationPaths[firstComponent] = destination.path
            return destination
        }

        let rootDestination = if let destinationPath = topLevelDestinationPaths[firstComponent] {
            URL(fileURLWithPath: destinationPath, isDirectory: true)
        } else {
            {
                let destination = uniqueDestinationURL(for: destinationDirectory.appendingPathComponent(firstComponent, isDirectory: true))
                topLevelDestinationPaths[firstComponent] = destination.path
                return destination
            }()
        }

        return components.dropFirst().reduce(rootDestination) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private func uniqueDestinationURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(baseName)_\(index)" : "\(baseName)_\(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    private func fileSizeOnDisk(_ url: URL) -> Int64 {
        let size = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64
        return size.flatMap { $0 } ?? 0
    }

    private func setError(_ text: String) {
        withAnimation(SoftIOSMotion.modal) {
            hasError = true
            statusText = text
            progressCaption = "Error"
            progressFraction = 0
            errorMessage = text
        }
        diagnostics.log("ERROR: \(text)")
    }

    func dismissError() {
        withAnimation(SoftIOSMotion.modal) {
            hasError = false
            errorMessage = nil
        }
    }

    private func downloadValidatedItem(
        source: PersistedDownloadSource,
        sourceRequest: URLRequest,
        resumeData: Data?,
        displayName: String,
        index: Int,
        totalCount: Int,
        fileBaseProgress: Double,
        fileSlice: Double,
        priorCompletedBytes: Int64,
        planKnownTotalBytes: Int64?,
        partialFileURL: URL? = nil,
        knownFileBytes: Int64? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> (URL, URLResponse) {
        // Keep per-item progress monotonic: a resume reports the *remaining* file
        // size as the expected total, and a fresh retry/fallback restarts the
        // fraction near 0. Without clamping, the bar visibly jumps backward.
        // We never report less than the highest fraction already shown.
        var highestFractionForItem = 0.0
        var highestBytesWrittenForItem: Int64 = 0
        // No verbose status word — the bar already shows what's happening.
        // For multi-file plans show just the file counter; otherwise nothing.
        let caption = totalCount > 1 ? "\(index + 1)/\(totalCount)" : ""
        let progressHandler: DownloadProgressCallback = { fileFraction, speedBytesPerSecond, bytesWritten, bytesExpected in
            highestFractionForItem = DownloadRetryPolicy.monotonicFraction(latest: fileFraction, runningMax: highestFractionForItem)
            // Keep the byte counter monotonic for the same reason as the bar.
            highestBytesWrittenForItem = max(highestBytesWrittenForItem, bytesWritten)
            let merged = DownloadRetryPolicy.mergedProgress(
                fileBaseProgress: fileBaseProgress,
                fileSlice: fileSlice,
                fileFraction: highestFractionForItem
            )
            if let speedBytesPerSecond {
                self.updateDisplayedSpeed(using: speedBytesPerSecond)
            }
            // Aggregate over the whole plan: bytes from finished files plus what
            // this file has written, against the plan total (or a running
            // estimate when not every file's size is known up front).
            let aggregate = DownloadFormatting.aggregateBytes(
                completedBytes: priorCompletedBytes,
                currentFileWritten: highestBytesWrittenForItem,
                currentFileExpected: bytesExpected,
                planKnownTotalBytes: planKnownTotalBytes
            )
            self.updateByteProgress(written: aggregate.written, expected: aggregate.expected)
            progress(caption, merged)
        }

        let requestsToTry: [URLRequest] = {
            if source == .dropbox {
                let fallbackRequests = DropboxDownloader()
                    .fallbackDownloadURLs(from: sourceRequest.url!)
                    .map { URLRequest(url: $0) }
                return [sourceRequest] + fallbackRequests
            }
            if source == .oneDrive, let url = sourceRequest.url {
                return DirectHostResolver.oneDriveDownloadCandidates(from: url).map { URLRequest(url: $0) }
            }
            return [sourceRequest]
        }()

        var lastError: Error?

        for (attemptIndex, requestToTry) in requestsToTry.enumerated() {
            do {
                return try await downloadWithRetries(
                    source: source,
                    request: requestToTry,
                    resumeData: source == .googleDrive ? nil : (attemptIndex == 0 ? resumeData : nil),
                    progressHandler: progressHandler,
                    displayName: displayName,
                    partialFileURL: source == .googleDrive ? partialFileURL : nil,
                    knownFileBytes: knownFileBytes
                )
            } catch let error as DownloaderError {
                diagnostics.log("ATTEMPT FAILED FOR \(displayName): \(error.localizedDescription)")
                if source == .dropbox,
                   case .httpStatus(let statusCode, let bodySnippet) = error,
                   shouldRetryDropboxDownload(statusCode: statusCode, bodySnippet: bodySnippet),
                   attemptIndex < requestsToTry.count - 1 {
                    progress("Retrying Dropbox direct link...", min(0.97, fileBaseProgress + fileSlice * 0.2))
                    lastError = error
                    continue
                }

                if attemptIndex < requestsToTry.count - 1 {
                    // Another candidate URL remains (e.g. OneDrive alternate).
                    lastError = error
                    continue
                }

                if source == .dropbox, shouldPresentAsUnavailable(error) {
                    throw DownloaderError.fileCannotBeDownloaded(displayName)
                }
                if shouldPresentAsUnavailable(error) {
                    throw DownloaderError.fileCannotBeDownloaded(displayName)
                }
                throw error
            } catch {
                diagnostics.log("ATTEMPT FAILED FOR \(displayName): \(error.localizedDescription)")
                lastError = error
            }
        }

        if let lastError = lastError as? DownloaderError,
           shouldPresentAsUnavailable(lastError) {
            throw DownloaderError.fileCannotBeDownloaded(displayName)
        }
        if let lastError {
            throw lastError
        }
        throw DownloaderError.fileCannotBeDownloaded(displayName)
    }

    private func shouldRetryDropboxDownload(statusCode: Int, bodySnippet: String?) -> Bool {
        guard statusCode == 200 || statusCode == 403 || statusCode == 302 || statusCode == 301 else { return false }
        guard let bodySnippet else { return true }
        let normalized = bodySnippet.lowercased()
        return normalized.contains("<html")
            || normalized.contains("<!doctype html")
            || normalized.contains("dropbox")
            || normalized.contains("sign in")
            || normalized.contains("login")
    }

    private func downloadWithRetries(
        source: PersistedDownloadSource,
        request: URLRequest,
        resumeData: Data?,
        progressHandler: @escaping DownloadProgressCallback,
        displayName: String,
        partialFileURL: URL? = nil,
        knownFileBytes: Int64? = nil
    ) async throws -> (URL, URLResponse) {
        // On a very slow / unstable link a handful of retries isn't enough; a
        // single file can drop the connection many times. Resume data means each
        // retry continues rather than restarts, so a high cap is cheap.
        let maxAttempts = DownloadRetryPolicy.maxAttempts
        var nextResumeData = resumeData
        // Remember the most recent transient failure so that if every attempt is
        // exhausted we can report *why* (e.g. "could not connect"), not a vague
        // "file cannot be downloaded".
        var lastTransientError: Error?

        for attempt in 1...maxAttempts {
            if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
            do {
                let requestForAttempt: URLRequest
                if source == .googleDrive, attempt > 1 {
                    requestForAttempt = await refreshedGoogleDriveRequest(from: request)
                } else {
                    requestForAttempt = request
                }

                let result: (URL, URLResponse)
                if let partialFileURL {
                    // Google Drive: stream to a persistent partial file and
                    // resume via HTTP Range so a drop continues from disk.
                    result = try await performResumableRangeDownload(
                        request: requestForAttempt,
                        partialFileURL: partialFileURL,
                        knownTotalBytes: knownFileBytes,
                        control: downloadControl,
                        progress: progressHandler
                    )
                } else {
                    result = try await performDownload(
                        request: requestForAttempt,
                        resumeData: nextResumeData,
                        control: downloadControl,
                        progress: progressHandler
                    )
                }
                try validateDownloadedPayload(tempFile: result.0, response: result.1, source: source)
                return result
            } catch let wrapped as ResumableRangeError {
                // Mid-stream drop of a Range download; the partial file holds
                // bytesSaved, so the next attempt continues from there.
                if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
                let underlying = wrapped.underlying
                lastTransientError = underlying
                let retryable = (underlying as? URLError).map(shouldRetry) ?? true
                guard attempt < maxAttempts, retryable else { throw underlying }
                diagnostics.log("RESUME \(attempt + 1)/\(maxAttempts) FOR \(displayName) @ \(wrapped.bytesSaved) BYTES (\(underlying.localizedDescription))")
                try? await Task.sleep(for: .seconds(backoffSeconds(for: attempt)))
                continue
            } catch let wrapped as ResumableDownloadError {
                // A user-initiated cancel also surfaces resumeData; never retry it.
                if userInitiatedCancellation || Task.isCancelled {
                    throw CancellationError()
                }
                // A slow-link stall / connection drop that left partial data.
                // Keep the resumeData so the next attempt continues from there
                // instead of re-downloading the whole file.
                let underlying = wrapped.underlying
                lastTransientError = underlying
                let retryable = (underlying as? URLError).map(shouldRetry) ?? true
                guard attempt < maxAttempts, retryable else { throw underlying }
                nextResumeData = wrapped.resumeData
                diagnostics.log("RESUME \(attempt + 1)/\(maxAttempts) FOR \(displayName) (\(underlying.localizedDescription))")
                try? await Task.sleep(for: .seconds(backoffSeconds(for: attempt)))
                continue
            } catch let error as DownloaderError {
                if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
                lastTransientError = error
                let retryable = shouldRetry(error) || (source == .googleDrive && isGoogleAuthorizationFailure(error))
                guard attempt < maxAttempts, retryable else { throw error }
                diagnostics.log("RETRY \(attempt + 1)/\(maxAttempts) FOR \(displayName) (\(error.localizedDescription))")
            } catch let error as URLError {
                if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
                lastTransientError = error
                guard attempt < maxAttempts, shouldRetry(error) else { throw error }
                diagnostics.log("RETRY \(attempt + 1)/\(maxAttempts) FOR \(displayName) (\(error.localizedDescription))")
            }

            nextResumeData = nil
            try? await Task.sleep(for: .seconds(backoffSeconds(for: attempt)))
        }

        // Every attempt exhausted — surface the real reason, not a vague message.
        let minutes = DownloadRetryPolicy.totalRetryWindowSeconds / 60
        if let lastTransientError {
            let reason = lastTransientError.localizedDescription
            throw DownloaderError.processFailed(
                "Couldn’t finish “\(displayName)” after \(maxAttempts) attempts over ~\(minutes) min. Last error: \(reason)"
            )
        }
        throw DownloaderError.fileCannotBeDownloaded(displayName)
    }

    /// Exponential-ish backoff capped so a high retry count doesn't make the
    /// user wait minutes between attempts on a slow link.
    private func backoffSeconds(for attempt: Int) -> Int {
        DownloadRetryPolicy.backoffSeconds(for: attempt)
    }

    private func refreshedGoogleDriveRequest(from request: URLRequest) async -> URLRequest {
        var refreshed = request
        guard let accessToken = try? await GoogleDriveAuthController.shared.currentAccessToken(),
              !accessToken.isEmpty else {
            return refreshed
        }
        refreshed.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return refreshed
    }

    private func shouldRetry(_ error: DownloaderError) -> Bool {
        switch error {
        case .httpStatus(let statusCode, _):
            return DownloadRetryPolicy.shouldRetry(httpStatus: statusCode)
        default:
            return false
        }
    }

    private func isGoogleAuthorizationFailure(_ error: DownloaderError) -> Bool {
        guard case .httpStatus(let statusCode, _) = error else { return false }
        return statusCode == 401 || statusCode == 403
    }

    private func shouldRetry(_ error: URLError) -> Bool {
        DownloadRetryPolicy.shouldRetry(
            urlErrorCode: error.code,
            taskIsCancelled: Task.isCancelled,
            userInitiatedCancellation: userInitiatedCancellation
        )
    }

    private func shouldPresentAsUnavailable(_ error: DownloaderError) -> Bool {
        switch error {
        case .httpStatus(let statusCode, _):
            return statusCode == 401 || statusCode == 403 || statusCode == 404 || statusCode == 410
        case .fileCannotBeDownloaded:
            return true
        default:
            return false
        }
    }

    private func isAutofillSupportedLink(_ text: String) -> Bool {
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return false }

        if host.contains("dropbox.com") { return true }
        if host.contains("drive.google.com") || host.contains("docs.google.com") { return true }
        if host.contains("youtube.com") || host.contains("youtu.be") { return true }
        if DirectHost.allCases.contains(where: { $0.matches(host: host) }) { return true }
        return false
    }

    private func normalizedLinkText() -> String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshRecoverableSessions() {
        recoveryStore.pruneExpiredSessions(removeSessionDirectories: true)
        var result: [PersistedDownloadState] = []

        for storedState in recoveryStore.loadAll() {
            var state = migrateRecoverySessionIfNeeded(storedState)
            if state.id == nil {
                state.id = UUID().uuidString
                recoveryStore.save(state)
            }

            guard fileManager.fileExists(atPath: state.sessionDirectoryPath) else {
                recoveryStore.clear(state)
                continue
            }

            result.append(state)
        }

        // Collapse duplicate sessions for the same link: keep only the one with
        // the most already downloaded, delete the rest (and their partial files)
        // so the user isn't offered three half-finished copies of one download.
        result = dedupedKeepingMostProgress(result)

        recoverableSessions = result.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// For each distinct source link, keeps the session that has the most bytes
    /// on disk and discards the others (removing their session directories).
    private func dedupedKeepingMostProgress(_ sessions: [PersistedDownloadState]) -> [PersistedDownloadState] {
        var bestByLink: [String: PersistedDownloadState] = [:]
        var losers: [PersistedDownloadState] = []

        for session in sessions {
            if let existing = bestByLink[session.originalLink] {
                let existingBytes = existing.downloadedBytesOnDisk
                let candidateBytes = session.downloadedBytesOnDisk
                if candidateBytes > existingBytes {
                    losers.append(existing)
                    bestByLink[session.originalLink] = session
                } else {
                    losers.append(session)
                }
            } else {
                bestByLink[session.originalLink] = session
            }
        }

        for loser in losers {
            try? fileManager.removeItem(at: loser.sessionDirectoryURL)
            recoveryStore.clear(loser)
        }

        return Array(bestByLink.values)
    }

    private func migrateRecoverySessionIfNeeded(_ state: PersistedDownloadState) -> PersistedDownloadState {
        guard let destinationRoot = destinationStore.selectedURL else { return state }

        let currentSessionURL = state.sessionDirectoryURL
        let currentPath = currentSessionURL.path
        let appSupportPathPrefix = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path ?? ""
        guard !appSupportPathPrefix.isEmpty, currentPath.hasPrefix(appSupportPathPrefix) else {
            return state
        }
        guard fileManager.fileExists(atPath: currentPath) else { return state }

        let sessionsRoot = destinationRoot.appendingPathComponent(".raw-downloader-sessions", isDirectory: true)
        let migratedSessionURL = sessionsRoot.appendingPathComponent(currentSessionURL.lastPathComponent, isDirectory: true)

        if fileManager.fileExists(atPath: migratedSessionURL.path) {
            var updated = state
            updated.sessionDirectoryPath = migratedSessionURL.path
            updated.updatedAt = Date()
            recoveryStore.save(updated)
            return updated
        }

        do {
            try fileManager.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
            try fileManager.moveItem(at: currentSessionURL, to: migratedSessionURL)
            var updated = state
            updated.sessionDirectoryPath = migratedSessionURL.path
            updated.updatedAt = Date()
            recoveryStore.save(updated)
            diagnostics.log("RECOVERY SESSION MIGRATED TO DESTINATION: \(migratedSessionURL.path)")
            return updated
        } catch {
            diagnostics.log("RECOVERY SESSION MIGRATION FAILED: \(error.localizedDescription)")
            return state
        }
    }

    private func formattedSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "--" }
        let mbPerSecond = bytesPerSecond / (1024 * 1024)
        return String(format: "%.2f MB/s", mbPerSecond)
    }

    private func updateDisplayedSpeed(using latestSampleBytesPerSecond: Double) {
        guard latestSampleBytesPerSecond.isFinite, latestSampleBytesPerSecond > 0 else { return }
        let alpha = 0.22
        if let previous = smoothedDownloadSpeedBytesPerSecond {
            smoothedDownloadSpeedBytesPerSecond = (previous * (1 - alpha)) + (latestSampleBytesPerSecond * alpha)
        } else {
            smoothedDownloadSpeedBytesPerSecond = latestSampleBytesPerSecond
        }

        let now = Date()
        let minUpdateInterval: TimeInterval = 0.45
        if let lastSpeedTextUpdateAt, now.timeIntervalSince(lastSpeedTextUpdateAt) < minUpdateInterval {
            return
        }

        guard let smoothed = smoothedDownloadSpeedBytesPerSecond else { return }
        downloadSpeedText = formattedSpeed(smoothed)
        lastSpeedTextUpdateAt = now
    }

    private func updateByteProgress(written: Int64, expected: Int64?) {
        // Always keep the raw figures fresh — the ETA calc depends on them.
        latestBytesWritten = written
        latestBytesExpected = expected
        refreshRemainingTime()

        // But throttle the *visible* "downloaded" text so it doesn't churn many
        // times a second and make the row jitter. Update at most ~once a second.
        let now = Date()
        let minUpdateInterval: TimeInterval = 0.8
        let isComplete = expected.map { written >= $0 } ?? false
        if let lastSizeTextUpdateAt,
           now.timeIntervalSince(lastSizeTextUpdateAt) < minUpdateInterval,
           !isComplete {
            return
        }
        lastSizeTextUpdateAt = now

        let writtenText = byteCountFormatter.string(fromByteCount: max(0, written))
        let totalText = (expected.map { $0 > 0 } == true) ? byteCountFormatter.string(fromByteCount: expected!) : "--"
        if downloadedSizeText != writtenText { downloadedSizeText = writtenText }
        if totalSizeText != totalText { totalSizeText = totalText }
    }

    private func startETATimer() {
        remainingTimeText = "--"
        latestBytesWritten = 0
        latestBytesExpected = nil
        smoothedRemainingSeconds = nil
        lastRemainingTextUpdateAt = nil
        lastSizeTextUpdateAt = nil
        etaTimer?.invalidate()
        // Refresh the countdown once a second so it ticks down smoothly even
        // when byte callbacks are sparse on a slow link.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRemainingTime() }
        }
        RunLoop.main.add(timer, forMode: .common)
        etaTimer = timer
    }

    private func stopETATimer() {
        etaTimer?.invalidate()
        etaTimer = nil
    }

    private func refreshRemainingTime() {
        guard !isPaused else { return }

        guard let rawSeconds = DownloadFormatting.rawRemainingSeconds(
            bytesWritten: latestBytesWritten,
            bytesExpected: latestBytesExpected,
            bytesPerSecond: smoothedDownloadSpeedBytesPerSecond
        ) else {
            remainingTimeText = "--"
            return
        }

        if rawSeconds == 0 {
            smoothedRemainingSeconds = 0
            remainingTimeText = "00:00"
            return
        }

        // Smooth the estimate so it glides rather than jumping each second.
        smoothedRemainingSeconds = DownloadFormatting.smoothRemainingSeconds(
            latest: rawSeconds,
            previous: smoothedRemainingSeconds
        )

        // Throttle the visible text the same way the speed readout is throttled,
        // so the digits don't churn faster than the eye can read.
        let now = Date()
        let minUpdateInterval: TimeInterval = 0.9
        if let lastRemainingTextUpdateAt, now.timeIntervalSince(lastRemainingTextUpdateAt) < minUpdateInterval {
            return
        }

        guard let smoothed = smoothedRemainingSeconds else { return }
        remainingTimeText = DownloadFormatting.formatRemaining(seconds: smoothed)
        lastRemainingTextUpdateAt = now
    }
}

enum DownloaderError: LocalizedError {
    case unsupportedLink
    case googleAPIKeyRequired
    case googleDriveAuthorizationRequired
    case invalidGoogleDriveID
    case badServerResponse
    case httpStatus(Int, String?)
    case fileCannotBeDownloaded(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLink:
            return "Supported links: Google Drive, Dropbox, OneDrive, pCloud, MediaFire."
        case .googleAPIKeyRequired:
            return "Set a Google API key from the top menu: Google Drive → Set API Key…"
        case .googleDriveAuthorizationRequired:
            return "Sign in to Google Drive or set an API key from the Google Drive menu."
        case .invalidGoogleDriveID:
            return "Couldn’t extract the Google Drive file or folder ID from the link."
        case .badServerResponse:
            return "The server returned an unexpected response."
        case .httpStatus(let statusCode, let bodySnippet):
            if let bodySnippet, !bodySnippet.isEmpty {
                return "Download error \(statusCode): \(bodySnippet)"
            }
            return "Download error \(statusCode)."
        case .fileCannotBeDownloaded(let filename):
            return "“\(filename)” can’t be downloaded."
        case .processFailed(let message):
            return message
        }
    }
}

enum LinkSource {
    case googleDrive
    case dropbox
    case directHost(DirectHost)
}

enum LinkDetector {
    static func detect(url: URL) throws -> LinkSource {
        let host = (url.host ?? "").lowercased()
        if host.contains("dropbox.com") {
            return .dropbox
        }
        if host.contains("drive.google.com") || host.contains("docs.google.com") {
            return .googleDrive
        }
        if let directHost = DirectHost.allCases.first(where: { $0.matches(host: host) }) {
            return .directHost(directHost)
        }
        throw DownloaderError.unsupportedLink
    }
}

enum GoogleDriveAPIKeyStorage {
    static let storageKey = "google_drive_api_key"
    static let keychainAccount = "google_drive_api_key"

    /// No key is baked into source (repo is public). Set it once via the app's
    /// settings (stored in Keychain) or the `EDITHUB_GDRIVE_API_KEY` env var.
    /// The real value is kept locally in the gitignored SECRETS.local.md.
    static let bundledDefault =
        ProcessInfo.processInfo.environment["EDITHUB_GDRIVE_API_KEY"] ?? ""

    static func current() -> String {
        if let keychainValue = (try? KeychainCredentialStore.readString(account: keychainAccount))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !keychainValue.isEmpty {
            return keychainValue
        }

        let defaultsValue = UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !defaultsValue.isEmpty {
            try? KeychainCredentialStore.writeString(defaultsValue, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: storageKey)
            return defaultsValue
        }
        return bundledDefault
    }

    static func clear() {
        try? KeychainCredentialStore.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    @MainActor
    static func promptForAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Google Drive API Key"
        alert.informativeText = "Insert API key for Google Drive links."
        alert.alertStyle = .informational

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "AIza..."
        field.stringValue = current()
        alert.accessoryView = field

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                clear()
            } else {
                try? KeychainCredentialStore.writeString(value, account: keychainAccount)
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
    }

    static func currentMaskedValue() -> String {
        let value = current()
        guard !value.isEmpty else { return "API key: not set" }
        if value.count <= 8 {
            return "API key: \(value)"
        }
        return "API key: \(value.prefix(4))…\(value.suffix(4))"
    }
}

final class DownloadDestinationStore {
    private(set) var selectedURL: URL?
    private(set) var displayPath: String = ""

    private let defaultsKey = "selectedDownloadFolderBookmark"
    private let pathDefaultsKey = "selectedDownloadFolderPath"
    private let footageFolderName = "FOOTAGE"
    private var hasScopedAccess = false

    init() {
        loadBookmark()
    }

    deinit {
        stopAccessingIfNeeded()
    }

    func setSelectedURL(_ url: URL) throws {
        stopAccessingIfNeeded()
        let resolvedURL = resolveDestinationURL(from: url)

        let bookmark = try resolvedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
        UserDefaults.standard.set(resolvedURL.path, forKey: pathDefaultsKey)

        selectedURL = resolvedURL
        displayPath = resolvedURL.path
        startAccessingIfPossible(resolvedURL)
    }

    /// Security-scoped bookmark for the current folder, so a queued download can
    /// reopen the exact same destination later even after the selection changes.
    var currentBookmark: Data? {
        UserDefaults.standard.data(forKey: defaultsKey)
    }

    /// Re-selects a destination from a previously captured bookmark (used when a
    /// queued item starts and needs its own saved folder, not the current one).
    @discardableResult
    func setFromBookmark(_ bookmark: Data) -> Bool {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return false }

        stopAccessingIfNeeded()
        UserDefaults.standard.set(bookmark, forKey: defaultsKey)
        UserDefaults.standard.set(url.path, forKey: pathDefaultsKey)
        selectedURL = url
        displayPath = url.path
        startAccessingIfPossible(url)
        return true
    }

    /// Clears the current selection (used to blank the path field for the next
    /// queue entry without losing already-captured per-item bookmarks).
    func clearSelection() {
        stopAccessingIfNeeded()
        selectedURL = nil
        displayPath = ""
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: pathDefaultsKey)
    }

    private func loadBookmark() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            displayPath = UserDefaults.standard.string(forKey: pathDefaultsKey) ?? ""
            return
        }

        do {
            var stale = false
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            selectedURL = resolvedURL
            displayPath = resolvedURL.path
            startAccessingIfPossible(resolvedURL)

            if stale {
                try setSelectedURL(resolvedURL)
            }
        } catch {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            selectedURL = nil
            displayPath = UserDefaults.standard.string(forKey: pathDefaultsKey) ?? ""
        }
    }

    private func startAccessingIfPossible(_ url: URL) {
        hasScopedAccess = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingIfNeeded() {
        guard hasScopedAccess, let url = selectedURL else { return }
        url.stopAccessingSecurityScopedResource()
        hasScopedAccess = false
    }

    private func resolveDestinationURL(from selectedURL: URL) -> URL {
        guard let footageURL = findFootageSubfolder(in: selectedURL) else {
            return selectedURL
        }
        return footageURL
    }

    private func findFootageSubfolder(in directoryURL: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let directPath = directoryURL.appendingPathComponent(footageFolderName, isDirectory: true)
        if FileManager.default.fileExists(atPath: directPath.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return directPath
        }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return children.first { child in
            guard child.lastPathComponent.caseInsensitiveCompare(footageFolderName) == .orderedSame else { return false }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
    }
}

enum PersistedDownloadSource: String, Codable {
    case dropbox
    case googleDrive
    case oneDrive
    case pcloud
    case mediafire

    init(directHost: DirectHost) {
        switch directHost {
        case .oneDrive: self = .oneDrive
        case .pcloud: self = .pcloud
        case .mediafire: self = .mediafire
        }
    }

    /// The matching direct host, or nil for the native Dropbox/Drive sources.
    var directHost: DirectHost? {
        switch self {
        case .oneDrive: return .oneDrive
        case .pcloud: return .pcloud
        case .mediafire: return .mediafire
        case .dropbox, .googleDrive: return nil
        }
    }
}

struct PersistedDownloadState: Codable {
    var id: String?
    var source: PersistedDownloadSource
    var originalLink: String
    var sessionDirectoryPath: String
    var finalDestinationPath: String?
    var items: [DownloadPlanItem]
    var currentIndex: Int
    var resumeDataBase64: String?
    var topLevelDestinationPaths: [String: String]?
    var updatedAt: Date

    var stableID: String {
        id ?? sessionDirectoryPath
    }

    var sessionDirectoryURL: URL {
        URL(fileURLWithPath: sessionDirectoryPath, isDirectory: true)
    }

    var finalDestinationURL: URL? {
        guard let finalDestinationPath, !finalDestinationPath.isEmpty else { return nil }
        return URL(fileURLWithPath: finalDestinationPath, isDirectory: true)
    }

    var resumeData: Data? {
        guard let resumeDataBase64 else { return nil }
        return Data(base64Encoded: resumeDataBase64)
    }

    var shortDisplayTitle: String {
        let sourceLabel = switch source {
        case .dropbox: "Dropbox"
        case .googleDrive: "Google Drive"
        case .oneDrive: "OneDrive"
        case .pcloud: "pCloud"
        case .mediafire: "MediaFire"
        }

        let candidate = items.dropFirst(currentIndex).first?.displayName
            ?? items.last?.displayName
            ?? URL(string: originalLink)?.lastPathComponent
            ?? originalLink
        let clipped = candidate.count > 34 ? "\(candidate.prefix(34))..." : candidate
        return "\(sourceLabel) - \(clipped)"
    }

    var contextMenuTitle: String {
        let completed = min(currentIndex, max(items.count, 1))
        return "\(shortDisplayTitle) (\(completed)/\(max(items.count, 1)))"
    }

    /// Sum of every file's known size — the total this session must download.
    /// `nil` if any file's size is unknown (then we can't show "remaining").
    var totalBytes: Int64? {
        guard items.allSatisfy({ ($0.byteSize ?? 0) > 0 }) else { return nil }
        return items.reduce(0) { $0 + ($1.byteSize ?? 0) }
    }

    /// Bytes actually saved so far: full size of every completed file plus the
    /// size of the in-progress partial file(s) still sitting in the session dir.
    var downloadedBytesOnDisk: Int64 {
        let fileManager = FileManager.default
        var bytes: Int64 = 0
        for index in 0..<min(currentIndex, items.count) {
            bytes += items[index].byteSize ?? 0
        }
        if let partials = try? fileManager.contentsOfDirectory(
            at: sessionDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) {
            for url in partials where url.lastPathComponent.hasPrefix("part-") {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                bytes += Int64(size)
            }
        }
        return bytes
    }

    /// "12 MB / 5 GB" style progress for the recovery menu, or just downloaded
    /// when the total isn't known.
    func progressSummary(formatter: ByteCountFormatter) -> String {
        let downloaded = formatter.string(fromByteCount: downloadedBytesOnDisk)
        guard let totalBytes, totalBytes > 0 else { return downloaded }
        let remaining = max(0, totalBytes - downloadedBytesOnDisk)
        return "\(downloaded) / \(formatter.string(fromByteCount: totalBytes)) · \(formatter.string(fromByteCount: remaining)) LEFT"
    }
}

final class PersistedDownloadStateStore {
    static let retentionDaysDefaultsKey = "downloadSessionRetentionDays"
    static let defaultRetentionDays = 7
    static let retentionOptions = [1, 3, 7, 14, 30]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("EditHub", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("download-recovery.json")

        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PersistedDownloadState? {
        loadAll().sorted { $0.updatedAt > $1.updatedAt }.first
    }

    func loadAll() -> [PersistedDownloadState] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        if let envelope = try? decoder.decode(PersistedDownloadStateEnvelope.self, from: data) {
            return envelope.sessions
        }
        if let legacy = try? decoder.decode(PersistedDownloadState.self, from: data) {
            return [legacy]
        }
        return []
    }

    func save(_ state: PersistedDownloadState) {
        var state = state
        if state.id == nil {
            state.id = UUID().uuidString
        }

        var sessions = loadAll()
        sessions.removeAll { existing in
            existing.stableID == state.stableID
                || existing.sessionDirectoryPath == state.sessionDirectoryPath
        }
        sessions.append(state)
        sessions = unexpiredSessions(from: sessions, removeSessionDirectories: true)

        guard let data = try? encoder.encode(PersistedDownloadStateEnvelope(sessions: sessions)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear(_ state: PersistedDownloadState) {
        let sessions = loadAll().filter { existing in
            existing.stableID != state.stableID
                && existing.sessionDirectoryPath != state.sessionDirectoryPath
        }
        write(sessions)
    }

    func clearAll(removeSessionDirectories: Bool) {
        if removeSessionDirectories {
            loadAll().forEach { try? FileManager.default.removeItem(at: $0.sessionDirectoryURL) }
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func pruneExpiredSessions(removeSessionDirectories: Bool) {
        write(unexpiredSessions(from: loadAll(), removeSessionDirectories: removeSessionDirectories))
    }

    static func retentionDays() -> Int {
        let stored = UserDefaults.standard.integer(forKey: retentionDaysDefaultsKey)
        return stored > 0 ? stored : defaultRetentionDays
    }

    static func setRetentionDays(_ days: Int) {
        UserDefaults.standard.set(days, forKey: retentionDaysDefaultsKey)
        NotificationCenter.default.post(name: .downloadSessionSettingsChanged, object: nil)
    }

    private func unexpiredSessions(from sessions: [PersistedDownloadState], removeSessionDirectories: Bool) -> [PersistedDownloadState] {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays()) * 24 * 60 * 60)
        return sessions.filter { state in
            let keep = state.updatedAt >= cutoff
            if !keep, removeSessionDirectories {
                try? FileManager.default.removeItem(at: state.sessionDirectoryURL)
            }
            return keep
        }
    }

    private func write(_ sessions: [PersistedDownloadState]) {
        if sessions.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? encoder.encode(PersistedDownloadStateEnvelope(sessions: sessions)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct PersistedDownloadStateEnvelope: Codable {
    var sessions: [PersistedDownloadState]
}

extension Notification.Name {
    static let downloadSessionSettingsChanged = Notification.Name("downloadSessionSettingsChanged")
}

final class DownloadDiagnosticsStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let formatter = ISO8601DateFormatter()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("EditHub", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("download.log")
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)

        if !fileManager.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
