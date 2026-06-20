import Foundation

/// Public-link file hosts that need no login and no API key: the share URL is
/// turned into a direct-download URL (sometimes after a tiny HTML/JSON probe)
/// and then streamed through the same `performDownload` path as Dropbox.
///
/// Folder downloads are intentionally out of scope here — those require each
/// host's authenticated API. A folder share link is asked to be re-shared as a
/// single file or a ZIP instead.
enum DirectHost: String, Codable, CaseIterable {
    case oneDrive
    case pcloud
    case mediafire

    /// Hosts of share links that map to this provider.
    func matches(host: String) -> Bool {
        switch self {
        case .oneDrive:
            return host.contains("1drv.ms")
                || host.contains("onedrive.live.com")
                || host.contains("1drv.com")
                || host.hasSuffix("sharepoint.com")
        case .pcloud:
            return host.contains("pcloud.link") || host.contains("pcloud.com")
        case .mediafire:
            return host.contains("mediafire.com")
        }
    }

    var displayName: String {
        switch self {
        case .oneDrive: return "OneDrive"
        case .pcloud: return "pCloud"
        case .mediafire: return "MediaFire"
        }
    }
}

/// Result of resolving a public share link into something downloadable.
struct DirectHostPlan: Sendable {
    let host: DirectHost
    /// Ordered candidate requests to try; later ones are fallbacks.
    let candidates: [URLRequest]
    /// Preferred filename if the host exposed one; else inferred from response.
    let suggestedFilename: String?
}

enum DirectHostResolver {
    /// Resolve a share link into a download plan. May hit the network for hosts
    /// that hide the direct URL behind an HTML page (MediaFire) or a JSON
    /// endpoint (pCloud). OneDrive is resolved by deriving the public-link
    /// download endpoints Microsoft exposes for anonymous shares.
    static func resolve(host: DirectHost, url: URL, session: URLSession = .shared) async throws -> DirectHostPlan {
        switch host {
        case .oneDrive:
            return resolveOneDrive(url: url)
        case .pcloud:
            return try await resolvePCloud(url: url, session: session)
        case .mediafire:
            return try await resolveMediaFire(url: url, session: session)
        }
    }

    // MARK: - OneDrive

    /// OneDrive public links are not consistently handled by `download=1`.
    /// Personal OneDrive links often expose `resid`/`authkey` for the legacy
    /// download endpoint, while short links work through the public shares API.
    private static func resolveOneDrive(url: URL) -> DirectHostPlan {
        let candidates = oneDriveDownloadCandidates(from: url).map { URLRequest(url: $0) }
        return DirectHostPlan(host: .oneDrive, candidates: candidates, suggestedFilename: nil)
    }

    static func oneDriveDownloadCandidates(from url: URL) -> [URL] {
        var candidates: [URL] = []

        if let liveDownloadURL = oneDriveLiveDownloadURL(from: url) {
            candidates.append(liveDownloadURL)
        }
        if let shareAPIURL = oneDriveShareAPIContentURL(from: url) {
            candidates.append(shareAPIURL)
        }
        if let downloadURL = appendingQueryItem(name: "download", value: "1", to: url) {
            candidates.append(downloadURL)
        }
        candidates.append(url)

        return candidates.uniqued()
    }

    private static func oneDriveLiveDownloadURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host.contains("onedrive.live.com") || host.contains("1drv.com"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let resid = queryItems.firstValue(named: "resid") ?? queryItems.firstValue(named: "id")
        guard let resid, !resid.isEmpty else { return nil }

        var download = URLComponents()
        download.scheme = "https"
        download.host = "onedrive.live.com"
        download.path = "/download"
        download.queryItems = [
            URLQueryItem(name: "resid", value: resid)
        ]
        if let authKey = queryItems.firstValue(named: "authkey"), !authKey.isEmpty {
            download.queryItems?.append(URLQueryItem(name: "authkey", value: authKey))
        }
        return download.url
    }

    private static func oneDriveShareAPIContentURL(from url: URL) -> URL? {
        let encoded = Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return URL(string: "https://api.onedrive.com/v1.0/shares/u!\(encoded)/root/content")
    }

    // MARK: - pCloud

    /// pCloud exposes a public, key-less endpoint: from a public link code we
    /// ask `getpublinkdownload` for the host+path of the actual file.
    private static func resolvePCloud(url: URL, session: URLSession) async throws -> DirectHostPlan {
        guard let code = pcloudPublicCode(from: url) else {
            // Fall back to trying the link as-is.
            return DirectHostPlan(host: .pcloud, candidates: [URLRequest(url: url)], suggestedFilename: nil)
        }

        var components = URLComponents(string: "https://api.pcloud.com/getpublinkdownload")!
        components.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "forcedownload", value: "1")
        ]

        let (data, response) = try await session.data(for: URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloaderError.processFailed("PCLOUD LINK COULD NOT BE RESOLVED.")
        }

        let payload = try JSONDecoder().decode(PCloudDownloadPayload.self, from: data)
        guard payload.result == 0, let hostName = payload.hosts?.first, let path = payload.path else {
            throw DownloaderError.processFailed("PCLOUD LINK IS INVALID OR EXPIRED.")
        }

        let direct = "https://\(hostName)\(path)"
        guard let directURL = URL(string: direct) else {
            throw DownloaderError.processFailed("PCLOUD RETURNED AN INVALID DOWNLOAD URL.")
        }

        let filename = URL(string: "https://x\(path)")?.lastPathComponent.removingPercentEncoding
        return DirectHostPlan(host: .pcloud, candidates: [URLRequest(url: directURL)], suggestedFilename: filename)
    }

    private static func pcloudPublicCode(from url: URL) -> String? {
        if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("code") == .orderedSame })?
            .value, !code.isEmpty {
            return code
        }
        // Short links look like https://u.pcloud.link/publink/show?code=XZ...
        // or https://pcloud.link/publink/show?code=XZ... — handled above.
        // Some links embed the code in the last path component.
        let last = url.lastPathComponent
        return last.hasPrefix("XZ") ? last : nil
    }

    // MARK: - MediaFire

    /// MediaFire serves an HTML page with the direct file URL embedded in a
    /// `href="https://download...."` link. We fetch the page and scrape it.
    private static func resolveMediaFire(url: URL, session: URLSession) async throws -> DirectHostPlan {
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw DownloaderError.processFailed("MEDIAFIRE PAGE COULD NOT BE LOADED.")
        }

        guard let directURLString = mediaFireDirectURL(inHTML: html),
              let directURL = URL(string: directURLString) else {
            throw DownloaderError.processFailed("MEDIAFIRE DIRECT LINK NOT FOUND (FILE MAY BE REMOVED OR REQUIRE A PASSWORD).")
        }

        return DirectHostPlan(host: .mediafire, candidates: [URLRequest(url: directURL)], suggestedFilename: directURL.lastPathComponent)
    }

    private static func mediaFireDirectURL(inHTML html: String) -> String? {
        // The download button: <a ... id="downloadButton" href="https://download....">
        let patterns = [
            #"href="(https://download[^"]+)""#,
            #"href='(https://download[^']+)'"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    // MARK: - Shared helpers

    private static func appendingQueryItem(name: String, value: String, to url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = (components.queryItems ?? []).filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in self {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

private extension Array where Element == URLQueryItem {
    func firstValue(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

struct SharePointAnonymousDownloader {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func buildPlanIfPossible(url: URL) async throws -> [DownloadPlanItem]? {
        guard let host = url.host?.lowercased(), host.hasSuffix("sharepoint.com") else {
            return nil
        }

        var pageRequest = URLRequest(url: url)
        pageRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: pageRequest)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        guard let driveURL = extractJSONString(named: ".driveUrl", from: html).flatMap(URL.init(string:)),
              let accessTokenValue = extractJSONString(named: ".driveAccessToken", from: html),
              let token = accessTokenValue.removingPrefix("access_token="),
              !token.isEmpty else {
            return nil
        }

        let finalURL = http.url ?? response.url ?? url
        guard let rootRelativePath = rootRelativeSharePointPath(from: finalURL, html: html), !rootRelativePath.isEmpty else {
            return nil
        }

        let rootName = sanitize(URL(fileURLWithPath: rootRelativePath).lastPathComponent)
        let rootItem = try await item(at: rootRelativePath, driveURL: driveURL, token: token)

        var usedRelativePaths = Set<String>()
        if rootItem.folder != nil {
            return try await buildFolderPlan(
                folderID: rootItem.id,
                driveURL: driveURL,
                token: token,
                localFolderRelativePath: rootName,
                usedRelativePaths: &usedRelativePaths
            )
        }

        guard let downloadURLString = rootItem.contentDownloadURL,
              let downloadURL = URL(string: downloadURLString) else {
            return nil
        }

        return [
            DownloadPlanItem(
                sourceURLString: downloadURL.absoluteString,
                relativeDestinationPath: uniqueRelativePathIfNeeded(sanitize(rootItem.name), usedRelativePaths: &usedRelativePaths),
                displayName: rootItem.name.uppercased(),
                headers: nil
            )
        ]
    }

    private func item(at path: String, driveURL: URL, token: String) async throws -> SharePointDriveItem {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: driveURL.absoluteString + "/root:/\(encodedPath):") else {
            throw DownloaderError.badServerResponse
        }
        let request = authenticatedRequest(url: url, token: token)
        let (data, response) = try await session.data(for: request)
        return try decodeSharePointResponse(data: data, response: response)
    }

    private func buildFolderPlan(
        folderID: String,
        driveURL: URL,
        token: String,
        localFolderRelativePath: String,
        usedRelativePaths: inout Set<String>
    ) async throws -> [DownloadPlanItem] {
        var result: [DownloadPlanItem] = []
        var nextURL: URL? = driveURL
            .appendingPathComponent("items")
            .appendingPathComponent(folderID)
            .appendingPathComponent("children")

        while let pageURL = nextURL {
            let request = authenticatedRequest(url: pageURL, token: token)
            let (data, response) = try await session.data(for: request)
            let page: SharePointChildrenResponse = try decodeSharePointResponse(data: data, response: response)

            for item in page.value {
                let itemName = sanitize(item.name)
                if item.folder != nil {
                    let nestedPath = appendPathComponent(localFolderRelativePath, itemName)
                    let nested = try await buildFolderPlan(
                        folderID: item.id,
                        driveURL: driveURL,
                        token: token,
                        localFolderRelativePath: nestedPath,
                        usedRelativePaths: &usedRelativePaths
                    )
                    result.append(contentsOf: nested)
                    continue
                }

                guard let downloadURLString = item.contentDownloadURL,
                      let downloadURL = URL(string: downloadURLString) else {
                    continue
                }

                let relativePath = appendPathComponent(localFolderRelativePath, itemName)
                result.append(
                    DownloadPlanItem(
                        sourceURLString: downloadURL.absoluteString,
                        relativeDestinationPath: uniqueRelativePathIfNeeded(relativePath, usedRelativePaths: &usedRelativePaths),
                        displayName: item.name.uppercased(),
                        headers: nil
                    )
                )
            }

            nextURL = page.nextLink.flatMap(URL.init(string:))
        }

        return result
    }

    private func authenticatedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func rootRelativeSharePointPath(from url: URL, html: String) -> String? {
        guard let serverPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .firstValue(named: "id")?
            .removingPercentEncoding else {
            return nil
        }

        let listURL = extractJSONString(named: "listUrl", from: html)
            ?? extractJSONString(named: "listUrlLegacy", from: html)
        if let listURL, serverPath.hasPrefix(listURL) {
            return String(serverPath.dropFirst(listURL.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        if let documentsRange = serverPath.range(of: "/Documents/") {
            return String(serverPath[documentsRange.upperBound...])
        }

        return URL(fileURLWithPath: serverPath).lastPathComponent
    }

    private func extractJSONString(named name: String, from html: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = #""# + escapedName + #"":"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return String(html[range])
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u002f"#, with: "/")
            .replacingOccurrences(of: #"\u0026"#, with: "&")
    }

    private func decodeSharePointResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw DownloaderError.badServerResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if let body = String(data: data, encoding: .utf8), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw DownloaderError.processFailed("SHAREPOINT API ERROR \(http.statusCode): \(body.prefix(180).uppercased())")
            }
            throw DownloaderError.processFailed("SHAREPOINT API ERROR \(http.statusCode).")
        }

        return try JSONDecoder().decode(T.self, from: data)
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

private struct SharePointChildrenResponse: Decodable {
    let value: [SharePointDriveItem]
    let nextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

private struct SharePointDriveItem: Decodable {
    let id: String
    let name: String
    let folder: SharePointFolderFacet?
    let contentDownloadURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case folder
        case contentDownloadURL = "@content.downloadUrl"
    }
}

private struct SharePointFolderFacet: Decodable {}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return self }
        return String(dropFirst(prefix.count))
    }
}

/// Finalizes a direct-host download: moves the temp file into the session
/// directory under a sensible name, unzipping ZIP archives just like Dropbox.
struct DirectHostDownloader {
    let host: DirectHost

    func finalizeDownload(tempFile: URL, response: URLResponse, suggestedFilename: String?, into directory: URL) throws {
        let filename = response.suggestedFilename
            ?? suggestedFilename
            ?? inferFileName(from: response.url ?? tempFile)
        let cleaned = sanitize(filename)
        let destination = directory.appendingPathComponent(cleaned)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempFile, to: destination)

        if destination.pathExtension.lowercased() == "zip" {
            try ZipArchiver.unzip(archive: destination, destination: directory)
            try? FileManager.default.removeItem(at: destination)
        }
    }

    private func inferFileName(from url: URL) -> String {
        let candidate = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if candidate.isEmpty || candidate == "/" {
            return "\(host.rawValue)_download"
        }
        return candidate
    }

    private func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "\(host.rawValue)_download" : cleaned
    }
}

private struct PCloudDownloadPayload: Decodable {
    let result: Int
    let hosts: [String]?
    let path: String?
}
