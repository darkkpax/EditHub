import Foundation

struct DownloadPlanItem: Codable, Sendable {
    let sourceURLString: String
    let relativeDestinationPath: String?
    let displayName: String
    let headers: [String: String]?

    var sourceURL: URL {
        URL(string: sourceURLString)!
    }

    var request: URLRequest {
        var request = URLRequest(url: sourceURL)
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

struct DropboxDownloader {
    func preparePlan(url: URL) -> [DownloadPlanItem] {
        let directURL = makeDirectDropboxURL(from: url)
        return [
            DownloadPlanItem(
                sourceURLString: directURL.absoluteString,
                relativeDestinationPath: nil,
                displayName: inferFileName(from: directURL).uppercased(),
                headers: nil
            )
        ]
    }

    func finalizeDownload(tempFile: URL, response: URLResponse, into directory: URL) throws {
        let filename = response.suggestedFilename ?? inferFileName(from: response.url ?? tempFile)
        let destination = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)

        if destination.pathExtension.lowercased() == "zip" {
            try ZipArchiver.unzip(archive: destination, destination: directory)
            try? FileManager.default.removeItem(at: destination)
        }
    }

    func fallbackDownloadURL(from current: URL) -> URL? {
        fallbackDownloadURLs(from: current).first
    }

    func fallbackDownloadURLs(from current: URL) -> [URL] {
        var candidates: [URL] = []

        var components = URLComponents(url: current, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        let hadRaw = items.contains { $0.name.lowercased() == "raw" }
        items.removeAll { ["dl", "raw"].contains($0.name.lowercased()) }
        items.append(URLQueryItem(name: "raw", value: "1"))
        components?.queryItems = items
        if let rawURL = components?.url, rawURL != current || !hadRaw {
            candidates.append(rawURL)
        }

        if let contentURL = makeDropboxContentHostURL(from: current), !candidates.contains(contentURL) {
            candidates.append(contentURL)
        }

        return candidates
    }

    private func makeDirectDropboxURL(from original: URL) -> URL {
        var components = URLComponents(url: original, resolvingAgainstBaseURL: false)
        var items = (components?.queryItems ?? []).filter { $0.name.lowercased() != "dl" }
        items.append(URLQueryItem(name: "dl", value: "1"))
        components?.queryItems = items
        return components?.url ?? original
    }

    private func makeDropboxContentHostURL(from original: URL) -> URL? {
        guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        components.host = "dl.dropboxusercontent.com"
        components.queryItems = (components.queryItems ?? []).filter { !["dl", "raw"].contains($0.name.lowercased()) }
        return components.url
    }

    private func inferFileName(from url: URL) -> String {
        let candidate = url.lastPathComponent
        if candidate.isEmpty || candidate == "/" {
            return "dropbox_download"
        }
        return candidate
    }
}

struct GoogleDriveDownloader {
    private let apiKey: String
    private let accessToken: String?
    private let session: URLSession

    init(apiKey: String, accessToken: String? = nil, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.session = session
    }

    func buildDownloadPlan(url: URL, rootDirectoryName: String? = nil) async throws -> [DownloadPlanItem] {
        let linkContext = try extractLinkContext(from: url)
        let rootItem = try await getMetadata(fileID: linkContext.itemID, resourceKey: linkContext.resourceKey)

        let rawPlan: [DrivePlanEntry]
        let rootFolderName: String?

        if rootItem.mimeType == "application/vnd.google-apps.folder" {
            rootFolderName = sanitize(rootItem.name)
            rawPlan = try await buildPlan(
                folderID: rootItem.id,
                folderResourceKey: rootItem.resourceKey ?? linkContext.resourceKey,
                localFolderRelativePath: rootFolderName!
            )
        } else {
            rootFolderName = rootDirectoryName
            rawPlan = [DrivePlanEntry(item: rootItem, relativeFolderPath: rootDirectoryName ?? "")]
        }

        return try materializePlan(entries: rawPlan, rootFolderName: rootFolderName)
    }

    func finalizeDownload(tempFile: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)
    }

    private func extractLinkContext(from url: URL) throws -> DriveLinkContext {
        let string = url.absoluteString

        let patterns = [
            #"/folders/([a-zA-Z0-9_-]+)"#,
            #"/file/d/([a-zA-Z0-9_-]+)"#,
            #"id=([a-zA-Z0-9_-]+)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..<string.endIndex, in: string)),
               let range = Range(match.range(at: 1), in: string) {
                let itemID = String(string[range])
                let resourceKey = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name.caseInsensitiveCompare("resourcekey") == .orderedSame })?
                    .value
                return DriveLinkContext(itemID: itemID, resourceKey: resourceKey)
            }
        }

        throw DownloaderError.invalidGoogleDriveID
    }

    private func getMetadata(fileID: String, resourceKey: String? = nil) async throws -> DriveItem {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        var queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,resourceKey,capabilities/canDownload,shortcutDetails"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
        ]
        appendAPIKeyIfNeeded(to: &queryItems)
        if let resourceKey, !resourceKey.isEmpty {
            queryItems.append(URLQueryItem(name: "resourceKey", value: resourceKey))
        }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, resourceKeys: [(fileID, resourceKey)].compactMapResourceKeys())
        let (data, response) = try await session.data(for: request)
        return try decodeResponse(data: data, response: response)
    }

    private func listChildren(folderID: String, folderResourceKey: String?, pageToken: String?) async throws -> DriveListResponse {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,resourceKey,capabilities/canDownload,shortcutDetails)"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "pageSize", value: "1000")
        ]
        appendAPIKeyIfNeeded(to: &query)
        if let folderResourceKey, !folderResourceKey.isEmpty {
            query.append(URLQueryItem(name: "resourceKey", value: folderResourceKey))
        }

        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = query

        let request = makeRequest(url: components.url!, resourceKeys: [(folderID, folderResourceKey)].compactMapResourceKeys())
        let (data, response) = try await session.data(for: request)
        return try decodeResponse(data: data, response: response)
    }

    private func buildPlan(folderID: String, folderResourceKey: String?, localFolderRelativePath: String) async throws -> [DrivePlanEntry] {
        var token: String? = nil
        var result: [DrivePlanEntry] = []

        repeat {
            let page = try await listChildren(folderID: folderID, folderResourceKey: folderResourceKey, pageToken: token)
            for item in page.files {
                if item.mimeType == "application/vnd.google-apps.folder" {
                    let nestedRelativePath = appendPathComponent(localFolderRelativePath, sanitize(item.name))
                    let nestedPlan = try await buildPlan(
                        folderID: item.id,
                        folderResourceKey: item.resourceKey,
                        localFolderRelativePath: nestedRelativePath
                    )
                    result.append(contentsOf: nestedPlan)
                    continue
                }

                if item.mimeType == "application/vnd.google-apps.shortcut", let targetID = item.shortcutDetails?.targetID {
                    let target = try await getMetadata(fileID: targetID, resourceKey: item.shortcutDetails?.targetResourceKey)
                    if target.mimeType == "application/vnd.google-apps.folder" {
                        continue
                    }
                    result.append(DrivePlanEntry(item: target, relativeFolderPath: localFolderRelativePath))
                    continue
                }

                guard item.capabilities?.canDownload != false else {
                    throw DownloaderError.processFailed("GOOGLE DRIVE FILE '\(item.name.uppercased())' DISABLES DOWNLOADS.")
                }
                result.append(DrivePlanEntry(item: item, relativeFolderPath: localFolderRelativePath))
            }
            token = page.nextPageToken
        } while token != nil

        return result
    }

    private func materializePlan(entries: [DrivePlanEntry], rootFolderName: String?) throws -> [DownloadPlanItem] {
        var usedRelativePaths = Set<String>()
        var result: [DownloadPlanItem] = []

        for entry in entries {
            let source = makeDownloadSource(for: entry.item)
            let folder = entry.relativeFolderPath
            let baseRelativePath = folder.isEmpty ? source.filename : appendPathComponent(folder, source.filename)
            let uniqueRelativePath = uniqueRelativePathIfNeeded(baseRelativePath, usedRelativePaths: &usedRelativePaths)

            result.append(
                DownloadPlanItem(
                    sourceURLString: source.sourceURL.absoluteString,
                    relativeDestinationPath: uniqueRelativePath,
                    displayName: source.filename.uppercased(),
                    headers: source.headers
                )
            )
        }

        if result.isEmpty, let rootFolderName {
            return [
                DownloadPlanItem(
                    sourceURLString: "",
                    relativeDestinationPath: rootFolderName,
                    displayName: rootFolderName.uppercased(),
                    headers: nil
                )
            ]
        }

        return result
    }

    private func makeDownloadSource(for item: DriveItem) -> (sourceURL: URL, filename: String, headers: [String: String]?) {
        if let export = exportConfig(for: item.mimeType) {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(item.id)/export")!
            var queryItems = [
                URLQueryItem(name: "mimeType", value: export.mimeType)
            ]
            appendAPIKeyIfNeeded(to: &queryItems)
            if let resourceKey = item.resourceKey, !resourceKey.isEmpty {
                queryItems.append(URLQueryItem(name: "resourceKey", value: resourceKey))
            }
            components.queryItems = queryItems
            return (components.url!, sanitize(item.name) + ".\(export.extension)", makeDownloadHeaders(resourceKeys: [(item.id, item.resourceKey)].compactMapResourceKeys()))
        }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(item.id)")!
        var queryItems = [
            URLQueryItem(name: "alt", value: "media")
        ]
        appendAPIKeyIfNeeded(to: &queryItems)
        if let resourceKey = item.resourceKey, !resourceKey.isEmpty {
            queryItems.append(URLQueryItem(name: "resourceKey", value: resourceKey))
        }
        components.queryItems = queryItems
        return (components.url!, sanitize(item.name), makeDownloadHeaders(resourceKeys: [(item.id, item.resourceKey)].compactMapResourceKeys()))
    }

    private func makeRequest(url: URL, resourceKeys: [String]) -> URLRequest {
        var request = URLRequest(url: url)
        makeDownloadHeaders(resourceKeys: resourceKeys)?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func makeDownloadHeaders(resourceKeys: [String]) -> [String: String]? {
        var headers: [String: String] = [:]
        if let accessToken, !accessToken.isEmpty {
            headers["Authorization"] = "Bearer \(accessToken)"
        }
        if !resourceKeys.isEmpty {
            headers["X-Goog-Drive-Resource-Keys"] = resourceKeys.joined(separator: ",")
        }
        return headers.isEmpty ? nil : headers
    }

    private func appendAPIKeyIfNeeded(to queryItems: inout [URLQueryItem]) {
        guard accessToken == nil, !apiKey.isEmpty else { return }
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
    }

    private func decodeResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw DownloaderError.badServerResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(GoogleDriveAPIErrorEnvelope.self, from: data) {
                throw DownloaderError.processFailed("GOOGLE DRIVE API ERROR \(http.statusCode): \(apiError.error.message.uppercased())")
            }

            if let body = String(data: data, encoding: .utf8), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DownloaderError.processFailed("GOOGLE DRIVE API ERROR \(http.statusCode): \(body.prefix(180).uppercased())")
            }
            throw DownloaderError.processFailed("GOOGLE DRIVE API ERROR \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func exportConfig(for mimeType: String) -> (mimeType: String, `extension`: String)? {
        switch mimeType {
        case "application/vnd.google-apps.document":
            return ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx")
        case "application/vnd.google-apps.spreadsheet":
            return ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx")
        case "application/vnd.google-apps.presentation":
            return ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx")
        case "application/vnd.google-apps.drawing":
            return ("application/pdf", "pdf")
        case "application/vnd.google-apps.script":
            return ("application/vnd.google-apps.script+json", "json")
        default:
            return nil
        }
    }

    private func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    private func uniqueRelativePathIfNeeded(_ relativePath: String, usedRelativePaths: inout Set<String>) -> String {
        guard !usedRelativePaths.contains(relativePath) else {
            let fileURL = URL(fileURLWithPath: relativePath)
            let dir = fileURL.deletingLastPathComponent()
            let base = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension

            var index = 1
            while true {
                let candidateName = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
                let candidatePath = dir.path == "/" ? candidateName : appendPathComponent(dir.path, candidateName)
                if !usedRelativePaths.contains(candidatePath) {
                    usedRelativePaths.insert(candidatePath)
                    return candidatePath
                }
                index += 1
            }
        }

        usedRelativePaths.insert(relativePath)
        return relativePath
    }

    private func appendPathComponent(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else { return right }
        return (left as NSString).appendingPathComponent(right)
    }
}

private struct DrivePlanEntry {
    let item: DriveItem
    let relativeFolderPath: String
}

private struct DriveLinkContext {
    let itemID: String
    let resourceKey: String?
}

private struct DriveListResponse: Decodable {
    let nextPageToken: String?
    let files: [DriveItem]
}

private struct GoogleDriveAPIErrorEnvelope: Decodable {
    let error: GoogleDriveAPIError
}

private struct GoogleDriveAPIError: Decodable {
    let message: String
}

private struct DriveShortcutDetails: Decodable {
    let targetID: String
    let targetResourceKey: String?

    enum CodingKeys: String, CodingKey {
        case targetID = "targetId"
        case targetResourceKey = "targetResourceKey"
    }
}

private struct DriveCapabilities: Decodable {
    let canDownload: Bool?
}

private struct DriveItem: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let resourceKey: String?
    let capabilities: DriveCapabilities?
    let shortcutDetails: DriveShortcutDetails?
}

private extension Array where Element == (String, String?) {
    func compactMapResourceKeys() -> [String] {
        compactMap { fileID, resourceKey in
            guard let resourceKey, !resourceKey.isEmpty else { return nil }
            return "\(fileID)/\(resourceKey)"
        }
    }
}

/// Error thrown when a download fails partway but the system handed back
/// `resumeData`, allowing the next attempt to continue instead of restarting.
struct ResumableDownloadError: Error {
    let underlying: Error
    let resumeData: Data?
}

func performDownload(
    request: URLRequest,
    resumeData: Data? = nil,
    control: DownloadControlCoordinator? = nil,
    progress: @escaping @Sendable @MainActor (Double, Double?) -> Void
) async throws -> (URL, URLResponse) {
    let bridge = DownloadBridge(progress: progress)
    let configuration = URLSessionConfiguration.default
    // Idle timeout: max gap between two data chunks. On a slow link (~0.6 MB/s)
    // remote servers (Drive/Dropbox) often stall for a while, so keep this high
    // to avoid dropping a connection that is simply slow rather than dead.
    configuration.timeoutIntervalForRequest = 600
    configuration.timeoutIntervalForResource = 60 * 60 * 24
    configuration.waitsForConnectivity = true
    configuration.httpAdditionalHeaders = [
        "Accept": "*/*",
        "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ", "),
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    ]
    let session = URLSession(configuration: configuration, delegate: bridge, delegateQueue: nil)
    bridge.session = session

    do {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                bridge.continuation = continuation
                let task = if let resumeData {
                    session.downloadTask(withResumeData: resumeData)
                } else {
                    session.downloadTask(with: request)
                }
                bridge.task = task

                if let control {
                    let sourceURL = request.url ?? URL(string: "about:blank")!
                    let state = control.bind(task: task, session: session, sourceURL: sourceURL)
                    if state.isCancelled {
                        task.cancel()
                        return
                    }
                    if !state.isPaused {
                        task.resume()
                    }
                    return
                }

                task.resume()
            }
        } onCancel: {
            bridge.cancel()
            control?.cancel()
        }
    } catch {
        // Surface partial-download data (if any) so callers can resume.
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        if resumeData != nil {
            throw ResumableDownloadError(underlying: error, resumeData: resumeData)
        }
        throw error
    }
}

func validateDownloadedPayload(tempFile: URL, response: URLResponse) throws {
    try validateDownloadedPayload(tempFile: tempFile, response: response, source: nil)
}

func validateDownloadedPayload(tempFile: URL, response: URLResponse, source: PersistedDownloadSource?) throws {
    guard let http = response as? HTTPURLResponse else { return }
    if (200...299).contains(http.statusCode) {
        if source == .dropbox, let snippet = htmlPayloadSnippet(from: tempFile, response: http) {
            throw DownloaderError.httpStatus(http.statusCode, snippet)
        }
        return
    }

    if let body = try? Data(contentsOf: tempFile) {
        if let apiError = try? JSONDecoder().decode(GoogleDriveAPIErrorEnvelope.self, from: body) {
            throw DownloaderError.httpStatus(http.statusCode, apiError.error.message.uppercased())
        }

        if let text = String(data: body, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DownloaderError.httpStatus(http.statusCode, String(text.prefix(180)).uppercased())
        }
    }

    throw DownloaderError.httpStatus(http.statusCode, nil)
}

private func htmlPayloadSnippet(from tempFile: URL, response: HTTPURLResponse) -> String? {
    let contentType = ((response.allHeaderFields["Content-Type"] as? String) ?? "").lowercased()
    let responseLooksHTML = contentType.contains("text/html") || response.mimeType?.lowercased() == "text/html"

    guard let handle = try? FileHandle(forReadingFrom: tempFile) else { return nil }
    defer { try? handle.close() }

    let data = handle.readData(ofLength: 4096)
    guard let text = String(data: data, encoding: .utf8) else { return nil }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()
    let bodyLooksHTML = normalized.hasPrefix("<!doctype html")
        || normalized.hasPrefix("<html")
        || normalized.contains("<title>dropbox")
        || normalized.contains("sign in")
        || normalized.contains("login")

    guard responseLooksHTML || bodyLooksHTML else { return nil }
    return String(trimmed.prefix(180)).uppercased()
}

final class DownloadControlCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTask: URLSessionDownloadTask?
    private var currentSession: URLSession?
    private var currentSourceURL: URL?
    private var isPaused = false
    private var isCancelled = false

    func bind(task: URLSessionDownloadTask, session: URLSession, sourceURL: URL) -> (isPaused: Bool, isCancelled: Bool) {
        lock.lock()
        currentTask = task
        currentSession = session
        currentSourceURL = sourceURL
        let state = (isPaused, isCancelled)
        lock.unlock()
        return state
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        let task = currentTask
        lock.unlock()

        if paused {
            task?.suspend()
        } else {
            task?.resume()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = currentTask
        let session = currentSession
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
    }

    func checkpoint() async -> DownloadTaskCheckpoint? {
        let snapshot = currentSnapshot()
        let task = snapshot.task
        let sourceURL = snapshot.sourceURL
        guard let task, let sourceURL else { return nil }

        return await withCheckedContinuation { continuation in
            task.cancel { resumeData in
                continuation.resume(returning: DownloadTaskCheckpoint(sourceURL: sourceURL, resumeData: resumeData))
            }
        }
    }

    func reset() {
        lock.lock()
        currentTask = nil
        currentSession = nil
        currentSourceURL = nil
        isPaused = false
        isCancelled = false
        lock.unlock()
    }

    private func currentSnapshot() -> (task: URLSessionDownloadTask?, sourceURL: URL?) {
        lock.lock()
        let snapshot = (currentTask, currentSourceURL)
        lock.unlock()
        return snapshot
    }
}

struct DownloadTaskCheckpoint: Sendable {
    let sourceURL: URL
    let resumeData: Data?
}

private final class DownloadBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    var task: URLSessionDownloadTask?
    var session: URLSession?

    private let progress: @Sendable @MainActor (Double, Double?) -> Void
    private var temporaryURL: URL?
    private var response: URLResponse?
    private var lastProgressTimestamp: Date?
    private var lastProgressBytesWritten: Int64 = 0

    init(progress: @escaping @Sendable @MainActor (Double, Double?) -> Void) {
        self.progress = progress
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let now = Date()
        var speedBytesPerSecond: Double?
        if let lastProgressTimestamp {
            let elapsed = now.timeIntervalSince(lastProgressTimestamp)
            if elapsed > 0.16 {
                let deltaBytes = totalBytesWritten - lastProgressBytesWritten
                if deltaBytes > 0 {
                    speedBytesPerSecond = Double(deltaBytes) / elapsed
                }
                self.lastProgressTimestamp = now
                self.lastProgressBytesWritten = totalBytesWritten
            }
        } else {
            lastProgressTimestamp = now
            lastProgressBytesWritten = totalBytesWritten
        }
        Task { @MainActor in
            progress(fraction, speedBytesPerSecond)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let ownedLocation = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(location.pathExtension.isEmpty ? "tmp" : location.pathExtension)
            let parentDirectory = ownedLocation.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: ownedLocation.path) {
                try FileManager.default.removeItem(at: ownedLocation)
            }
            try FileManager.default.moveItem(at: location, to: ownedLocation)
            temporaryURL = ownedLocation
        } catch {
            temporaryURL = nil
        }
        response = downloadTask.response
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            self.session?.finishTasksAndInvalidate()
            self.session = nil
            self.task = nil
            self.continuation = nil
        }

        if let error {
            continuation?.resume(throwing: error)
            return
        }

        if temporaryURL == nil, let response {
            continuation?.resume(
                throwing: DownloaderError.processFailed(
                    "DOWNLOADED FILE '\((response.suggestedFilename ?? response.url?.lastPathComponent ?? "UNKNOWN").uppercased())' COULDN'T BE MOVED FROM TEMP STORAGE."
                )
            )
            return
        }

        guard let temporaryURL, let response else {
            continuation?.resume(throwing: DownloaderError.badServerResponse)
            return
        }

        continuation?.resume(returning: (temporaryURL, response))
    }
}
