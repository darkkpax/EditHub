import AppKit
import Foundation
import SwiftUI

typealias ProgressHandler = @MainActor (_ status: String, _ fraction: Double) -> Void

@MainActor
final class DownloadViewModel: NSObject, ObservableObject {
    @Published var linkText = ""
    @Published var destinationDisplayPath = ""
    @Published var statusText = ""
    @Published var progressCaption = "WAITING..."
    @Published var progressFraction: Double = 0
    @Published var isLoading = false
    @Published var isPaused = false
    @Published var hasError = false
    @Published var errorMessage: String?
    @Published var downloadSpeedText = "--"

    var canStartDownload: Bool {
        !isLoading
            && !normalizedLinkText().isEmpty
            && destinationStore.selectedURL != nil
    }

    private let fileManager = FileManager.default
    private let destinationStore = DownloadDestinationStore()
    private let recoveryStore = PersistedDownloadStateStore()
    private var downloadControl = DownloadControlCoordinator()
    private var currentDownloadTask: Task<Void, Never>?
    private var activeRecoveryState: PersistedDownloadState?
    private var lastAutofilledClipboardLink = ""
    private var userInitiatedCancellation = false
    private var antiSleepActivity: NSObjectProtocol?
    private let diagnostics = DownloadDiagnosticsStore()
    private var smoothedDownloadSpeedBytesPerSecond: Double?
    private var lastSpeedTextUpdateAt: Date?

    override init() {
        super.init()
        destinationDisplayPath = destinationStore.displayPath
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )

        if let state = recoverableStateFromDisk() {
            withAnimation(SoftIOSMotion.entry) {
                linkText = state.originalLink
                statusText = "RESTORING PREVIOUS DOWNLOAD..."
            }
            activeRecoveryState = state
            startDownload(resumeRecoveryIfPossible: true)
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
        panel.prompt = "CHOOSE"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try destinationStore.setSelectedURL(url)
            withAnimation(SoftIOSMotion.state) {
                destinationDisplayPath = destinationStore.displayPath
                statusText = ""
            }
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

    func startDownload() {
        startDownload(resumeRecoveryIfPossible: true)
    }

    private func startDownload(resumeRecoveryIfPossible: Bool) {
        guard currentDownloadTask == nil else { return }
        userInitiatedCancellation = false

        if resumeRecoveryIfPossible, let recoveryState = activeRecoveryState ?? recoverableStateFromDisk() {
            activeRecoveryState = recoveryState
            currentDownloadTask = Task { [weak self] in
                await self?.download(resumeState: recoveryState)
            }
            return
        }

        guard let url = URL(string: normalizedLinkText()) else {
            setError("ADD A VALID GOOGLE DRIVE OR DROPBOX LINK.")
            return
        }

        currentDownloadTask = Task { [weak self] in
            await self?.download(from: url)
        }
    }

    func togglePause() {
        guard isLoading else { return }
        withAnimation(SoftIOSMotion.pause) {
            isPaused.toggle()
            statusText = isPaused ? "PAUSED" : progressCaption
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
            statusText = "DOWNLOAD CANCELLED."
            progressCaption = "CANCELLED"
            progressFraction = 0
            downloadSpeedText = "--"
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
            setError("RECOVERY STATE IS INVALID. START A NEW DOWNLOAD.")
            clearRecoveryState(removeSessionDirectory: true)
            return
        }
        guard let destinationURL = destinationStore.selectedURL else {
            setError("CHOOSE DOWNLOAD PATH FIRST.")
            return
        }

        withAnimation(SoftIOSMotion.entry) {
            isLoading = true
            isPaused = false
            progressFraction = 0
            progressCaption = "PREPARING..."
            statusText = "DETECTING SOURCE..."
            downloadSpeedText = "--"
        }
        smoothedDownloadSpeedBytesPerSecond = nil
        lastSpeedTextUpdateAt = nil
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
            withAnimation(SoftIOSMotion.controlSwap) {
                isPaused = false
                isLoading = false
            }
            if let antiSleepActivity {
                ProcessInfo.processInfo.endActivity(antiSleepActivity)
                self.antiSleepActivity = nil
            }
        }

        do {
            let source = try LinkDetector.detect(url: url)
            let state = try await preparedRecoveryState(for: source, originalURL: url, existing: resumeState)
            activeRecoveryState = state

            let reporter: ProgressHandler = { status, fraction in
                let caption = status.uppercased()
                withAnimation(SoftIOSMotion.progress) {
                    self.progressCaption = caption
                    self.progressFraction = min(1, max(0, fraction))
                    self.statusText = self.isPaused ? "PAUSED" : caption
                }
            }

            try await runPersistedDownload(state: state, progress: reporter, finalDestination: destinationURL)
            reporter("Moving files to destination...", 0.98)
            let materializedURLs = try materializeDownloadedItems(from: state.sessionDirectoryURL, into: destinationURL)
            reporter("Completed", 1.0)
            let resultPath = materializedURLs.count == 1 ? materializedURLs[0].path : destinationURL.path
            withAnimation(SoftIOSMotion.morph) {
                progressFraction = 1
                progressCaption = "COMPLETED"
                statusText = "DONE: \(resultPath)"
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
                setError("DOWNLOAD WAS CANCELLED BEFORE COMPLETION.")
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
                setError("NETWORK REQUEST WAS CANCELLED.")
            }
        } catch {
            setError(error.localizedDescription.uppercased())
        }
    }

    private func preparedRecoveryState(for source: LinkSource, originalURL: URL, existing: PersistedDownloadState?) async throws -> PersistedDownloadState {
        if let existing,
           existing.originalLink == originalURL.absoluteString,
           fileManager.fileExists(atPath: existing.sessionDirectoryPath),
           isReusableRecoveryState(existing, for: source) {
            return existing
        }

        let sessionDirectory = try makePersistentSessionDirectory()
        var state = PersistedDownloadState(
            source: source == .dropbox ? .dropbox : .googleDrive,
            originalLink: originalURL.absoluteString,
            sessionDirectoryPath: sessionDirectory.path,
            items: [],
            currentIndex: 0,
            resumeDataBase64: nil,
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
        }

        recoveryStore.save(state)
        return state
    }

    private func isReusableRecoveryState(_ state: PersistedDownloadState, for source: LinkSource) -> Bool {
        guard state.source == (source == .dropbox ? .dropbox : .googleDrive) else { return false }

        switch source {
        case .dropbox:
            return true
        case .googleDrive:
            return state.items.allSatisfy { !$0.sourceURLString.isEmpty }
        }
    }

    private func runPersistedDownload(
        state: PersistedDownloadState,
        progress: @escaping ProgressHandler,
        finalDestination: URL
    ) async throws {
        var state = state

        guard !state.items.isEmpty else {
            try fileManager.createDirectory(at: state.sessionDirectoryURL, withIntermediateDirectories: true)
            return
        }

        try fileManager.createDirectory(at: state.sessionDirectoryURL, withIntermediateDirectories: true)

        for index in state.currentIndex..<state.items.count {
            try Task.checkCancellation()

            let item = state.items[index]
            let itemRequest = try await makeRequest(for: item, source: state.source)
            let fileBaseProgress = Double(index) / Double(max(state.items.count, 1))
            let fileSlice = 1.0 / Double(max(state.items.count, 1))

            state.currentIndex = index
            state.updatedAt = Date()
            recoveryStore.save(state)
            activeRecoveryState = state

            let displayName = item.displayName
            let activeResumeData = (index == state.currentIndex) ? state.resumeData : nil

            let (tempFile, response) = try await downloadValidatedItem(
                source: state.source,
                sourceRequest: itemRequest,
                resumeData: activeResumeData,
                displayName: displayName,
                index: index,
                totalCount: state.items.count,
                fileBaseProgress: fileBaseProgress,
                fileSlice: fileSlice,
                progress: progress
            )

            switch state.source {
            case .dropbox:
                try DropboxDownloader().finalizeDownload(tempFile: tempFile, response: response, into: state.sessionDirectoryURL)
                progress("Dropbox download completed", min(0.99, fileBaseProgress + fileSlice))
            case .googleDrive:
                guard let relativePath = item.relativeDestinationPath else {
                    throw DownloaderError.badServerResponse
                }
                let destination = state.sessionDirectoryURL.appendingPathComponent(relativePath)
                try GoogleDriveDownloader(apiKey: GoogleDriveAPIKeyStorage.current()).finalizeDownload(tempFile: tempFile, to: destination)
            }

            state.resumeDataBase64 = nil
            state.currentIndex = index + 1
            state.updatedAt = Date()
            recoveryStore.save(state)
            activeRecoveryState = state
        }
    }

    private func makeRequest(for item: DownloadPlanItem, source: PersistedDownloadSource) async throws -> URLRequest {
        switch source {
        case .dropbox:
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
                    headers: currentItem.headers
                )
            }
            state.resumeDataBase64 = checkpoint.resumeData?.base64EncodedString()
            state.updatedAt = Date()
            recoveryStore.save(state)
        } else {
            recoveryStore.save(state)
        }
    }

    private func clearRecoveryState(removeSessionDirectory: Bool = false) {
        if removeSessionDirectory, let activeRecoveryState {
            try? fileManager.removeItem(at: activeRecoveryState.sessionDirectoryURL)
        }
        activeRecoveryState = nil
        recoveryStore.clear()
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

    private func materializeDownloadedItems(from stagingDirectory: URL, into destinationDirectory: URL) throws -> [URL] {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var result: [URL] = []
        for item in items {
            let destination = uniqueDestinationURL(for: destinationDirectory.appendingPathComponent(item.lastPathComponent))
            try fileManager.moveItem(at: item, to: destination)
            result.append(destination)
        }
        return result
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

    private func setError(_ text: String) {
        withAnimation(SoftIOSMotion.modal) {
            hasError = true
            statusText = text
            progressCaption = "ERROR"
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
        progress: @escaping ProgressHandler
    ) async throws -> (URL, URLResponse) {
        let progressHandler: @Sendable @MainActor (Double, Double?) -> Void = { fileFraction, speedBytesPerSecond in
            let merged = min(0.99, fileBaseProgress + (fileSlice * fileFraction))
            if let speedBytesPerSecond {
                self.updateDisplayedSpeed(using: speedBytesPerSecond)
            }
            progress("Downloading \(index + 1)/\(totalCount): \(displayName)", merged)
        }

        let requestsToTry: [URLRequest] = {
            if source == .dropbox {
                let fallbackRequests = DropboxDownloader()
                    .fallbackDownloadURLs(from: sourceRequest.url!)
                    .map { URLRequest(url: $0) }
                return [sourceRequest] + fallbackRequests
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
                    displayName: displayName
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

                if source == .dropbox, shouldPresentAsUnavailable(error) {
                    throw DownloaderError.fileCannotBeDownloaded(displayName)
                }
                throw error
            } catch {
                diagnostics.log("ATTEMPT FAILED FOR \(displayName): \(error.localizedDescription)")
                lastError = error
            }
        }

        if source == .dropbox,
           let lastError = lastError as? DownloaderError,
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
        progressHandler: @escaping @Sendable @MainActor (Double, Double?) -> Void,
        displayName: String
    ) async throws -> (URL, URLResponse) {
        let maxAttempts = 5
        var nextResumeData = resumeData

        for attempt in 1...maxAttempts {
            if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
            do {
                let requestForAttempt: URLRequest
                if source == .googleDrive, attempt > 1 {
                    requestForAttempt = await refreshedGoogleDriveRequest(from: request)
                } else {
                    requestForAttempt = request
                }

                let result = try await performDownload(
                    request: requestForAttempt,
                    resumeData: nextResumeData,
                    control: downloadControl,
                    progress: progressHandler
                )
                try validateDownloadedPayload(tempFile: result.0, response: result.1, source: source)
                return result
            } catch let wrapped as ResumableDownloadError {
                // A user-initiated cancel also surfaces resumeData; never retry it.
                if userInitiatedCancellation || Task.isCancelled {
                    throw CancellationError()
                }
                // A slow-link stall / connection drop that left partial data.
                // Keep the resumeData so the next attempt continues from there
                // instead of re-downloading the whole file.
                let underlying = wrapped.underlying
                let retryable = (underlying as? URLError).map(shouldRetry) ?? true
                guard attempt < maxAttempts, retryable else { throw underlying }
                nextResumeData = wrapped.resumeData
                diagnostics.log("RESUME \(attempt + 1)/\(maxAttempts) FOR \(displayName)")
                try? await Task.sleep(for: .seconds(attempt))
                continue
            } catch let error as DownloaderError {
                if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
                let retryable = shouldRetry(error) || (source == .googleDrive && isGoogleAuthorizationFailure(error))
                guard attempt < maxAttempts, retryable else { throw error }
                diagnostics.log("RETRY \(attempt + 1)/\(maxAttempts) FOR \(displayName)")
            } catch let error as URLError {
                if userInitiatedCancellation || Task.isCancelled { throw CancellationError() }
                guard attempt < maxAttempts, shouldRetry(error) else { throw error }
                diagnostics.log("RETRY \(attempt + 1)/\(maxAttempts) FOR \(displayName)")
            }

            nextResumeData = nil
            try? await Task.sleep(for: .seconds(attempt))
        }

        throw DownloaderError.fileCannotBeDownloaded(displayName)
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
            return statusCode == 408 || statusCode == 425 || statusCode == 429 || (500...599).contains(statusCode)
        default:
            return false
        }
    }

    private func isGoogleAuthorizationFailure(_ error: DownloaderError) -> Bool {
        guard case .httpStatus(let statusCode, _) = error else { return false }
        return statusCode == 401 || statusCode == 403
    }

    private func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .cancelled:
            return !Task.isCancelled
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
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
        return false
    }

    private func normalizedLinkText() -> String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recoverableStateFromDisk() -> PersistedDownloadState? {
        guard var state = recoveryStore.load() else { return nil }
        state = migrateRecoverySessionIfNeeded(state)
        guard fileManager.fileExists(atPath: state.sessionDirectoryPath) else {
            recoveryStore.clear()
            return nil
        }
        return state
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
            return "ONLY GOOGLE DRIVE AND DROPBOX LINKS ARE SUPPORTED."
        case .googleAPIKeyRequired:
            return "SET GOOGLE API KEY FROM TOP MENU: GOOGLE DRIVE -> SET API KEY..."
        case .googleDriveAuthorizationRequired:
            return "SIGN IN TO GOOGLE DRIVE OR SET API KEY FROM THE GOOGLE DRIVE MENU."
        case .invalidGoogleDriveID:
            return "FAILED TO EXTRACT GOOGLE DRIVE FILE/FOLDER ID FROM THE LINK."
        case .badServerResponse:
            return "SERVER RETURNED AN UNEXPECTED RESPONSE."
        case .httpStatus(let statusCode, let bodySnippet):
            if let bodySnippet, !bodySnippet.isEmpty {
                return "DOWNLOAD ERROR \(statusCode): \(bodySnippet)"
            }
            return "DOWNLOAD ERROR \(statusCode)."
        case .fileCannotBeDownloaded(let filename):
            return "FILE '\(filename)' CANNOT BE DOWNLOADED."
        case .processFailed(let message):
            return message
        }
    }
}

enum LinkSource {
    case googleDrive
    case dropbox
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
        throw DownloaderError.unsupportedLink
    }
}

enum GoogleDriveAPIKeyStorage {
    static let storageKey = "google_drive_api_key"
    static let keychainAccount = "google_drive_api_key"

    /// Baked-in default so the app works on a fresh machine without manual setup.
    /// A user-entered value (Keychain/UserDefaults) always takes precedence.
    static let bundledDefault = "***REMOVED***"

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
        guard !value.isEmpty else { return "API KEY: NOT SET" }
        if value.count <= 8 {
            return "API KEY: \(value)"
        }
        return "API KEY: \(value.prefix(4))...\(value.suffix(4))"
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
}

struct PersistedDownloadState: Codable {
    var source: PersistedDownloadSource
    var originalLink: String
    var sessionDirectoryPath: String
    var items: [DownloadPlanItem]
    var currentIndex: Int
    var resumeDataBase64: String?
    var updatedAt: Date

    var sessionDirectoryURL: URL {
        URL(fileURLWithPath: sessionDirectoryPath, isDirectory: true)
    }

    var resumeData: Data? {
        guard let resumeDataBase64 else { return nil }
        return Data(base64Encoded: resumeDataBase64)
    }
}

final class PersistedDownloadStateStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("GoogleDropboxDownloader", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("download-recovery.json")

        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PersistedDownloadState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(PersistedDownloadState.self, from: data)
    }

    func save(_ state: PersistedDownloadState) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

final class DownloadDiagnosticsStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let formatter = ISO8601DateFormatter()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("GoogleDropboxDownloader", isDirectory: true)
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
