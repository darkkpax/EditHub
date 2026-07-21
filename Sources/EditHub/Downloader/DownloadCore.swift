import Foundation

// Pure, side-effect-free download-resilience logic (retry/backoff/resume rules,
// progress formatting). Kept free of AppKit and the main actor so it stays easy
// to reason about and could be unit-tested in isolation. Ported from the
// GoogleDropboxDownloader `DownloadCore` module into the EditHub module.

/// Pure formatting helpers for the download UI.
enum DownloadFormatting {
    /// Elapsed download time as `MM:SS` under an hour, `H:MM:SS` beyond —
    /// compact enough for the narrow window.
    static func formattedElapsed(seconds total: Int) -> String {
        let total = max(0, total)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Raw seconds remaining from bytes left and current speed.
    /// `nil` when total size or speed isn't known yet; `0` once finished.
    static func rawRemainingSeconds(
        bytesWritten: Int64,
        bytesExpected: Int64?,
        bytesPerSecond: Double?
    ) -> Double? {
        guard let bytesExpected, bytesExpected > 0 else { return nil }
        let remaining = max(0, bytesExpected - max(0, bytesWritten))
        if remaining == 0 { return 0 }
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond > 0 else { return nil }
        return Double(remaining) / bytesPerSecond
    }

    /// Smooths the remaining-seconds estimate with an exponential moving average
    /// so the countdown glides instead of jumping every time the instantaneous
    /// speed wobbles — the same treatment the speed readout already gets.
    /// - alpha: weight of the new sample (smaller = smoother / slower to react).
    static func smoothRemainingSeconds(
        latest: Double,
        previous: Double?,
        alpha: Double = 0.2
    ) -> Double {
        guard let previous else { return max(0, latest) }
        return max(0, previous * (1 - alpha) + latest * alpha)
    }

    /// Formats a (smoothed) remaining-seconds value into a stable `MM:SS` /
    /// `H:MM:SS` label. Snaps to 5-second steps so the last digit doesn't
    /// flicker between adjacent values when the estimate barely moves.
    static func formatRemaining(seconds: Double) -> String {
        let snapped = (seconds / 5).rounded() * 5
        return formattedElapsed(seconds: Int(snapped))
    }

    /// Estimated time remaining as `MM:SS` / `H:MM:SS`, derived from the bytes
    /// left and the current speed. Returns `unknownPlaceholder` when the total
    /// size or speed isn't known yet (so the UI shows `--` rather than a wild
    /// guess), and `"00:00"` once everything is downloaded.
    static func estimatedRemaining(
        bytesWritten: Int64,
        bytesExpected: Int64?,
        bytesPerSecond: Double?,
        unknownPlaceholder: String = "--"
    ) -> String {
        guard let seconds = rawRemainingSeconds(
            bytesWritten: bytesWritten,
            bytesExpected: bytesExpected,
            bytesPerSecond: bytesPerSecond
        ) else { return unknownPlaceholder }
        if seconds == 0 { return "00:00" }
        return formattedElapsed(seconds: Int(seconds.rounded(.up)))
    }

    /// Aggregate downloaded/total byte counts across a whole multi-file plan.
    /// - completedBytes: real bytes from files already finished.
    /// - currentFileWritten: bytes written so far for the file in progress.
    /// - currentFileExpected: that file's total size, if the server reported it.
    /// - planKnownTotalBytes: sum of every file's size, known only when *all*
    ///   files reported a size; otherwise `nil` and we fall back to a running
    ///   estimate (completed + current file's expected) that grows file by file.
    /// Returns the absolute downloaded count and the best-known total (or `nil`).
    static func aggregateBytes(
        completedBytes: Int64,
        currentFileWritten: Int64,
        currentFileExpected: Int64?,
        planKnownTotalBytes: Int64?
    ) -> (written: Int64, expected: Int64?) {
        let written = max(0, completedBytes) + max(0, currentFileWritten)
        let expected: Int64?
        if let planKnownTotalBytes, planKnownTotalBytes > 0 {
            expected = planKnownTotalBytes
        } else if let currentFileExpected, currentFileExpected > 0 {
            expected = max(0, completedBytes) + currentFileExpected
        } else {
            expected = nil
        }
        return (written, expected)
    }

    /// A short, human-friendly label for a download link, so the queue shows
    /// something readable instead of a wall of URL characters. Falls back to the
    /// host, then to a trimmed raw string.
    static func friendlyLinkName(_ link: String, maxLength: Int = 30) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let host = components.host?.lowercased() else {
            return clip(trimmed, maxLength)
        }

        let path = components.path
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // Google Drive: .../file/d/<id>/... or .../folders/<id>
        if host.contains("drive.google.com") || host.contains("docs.google.com") {
            if let dIndex = segments.firstIndex(of: "d"), dIndex + 1 < segments.count {
                return "Drive file · " + clip(segments[dIndex + 1], maxLength)
            }
            if let fIndex = segments.firstIndex(of: "folders"), fIndex + 1 < segments.count {
                return "Drive folder · " + clip(segments[fIndex + 1], maxLength)
            }
            return "Google Drive link"
        }

        // Dropbox: last path segment is usually the file/folder name.
        if host.contains("dropbox.com") {
            if let last = segments.last, !last.isEmpty {
                return "Dropbox · " + clip(last.removingPercentEncoding ?? last, maxLength)
            }
            return "Dropbox link"
        }

        return clip(host + path, maxLength)
    }

    private static func clip(_ text: String, _ maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return "\(text.prefix(maxLength))…"
    }

    /// Combines downloaded and total size into a single `downloaded / total`
    /// label, collapsing to just the downloaded figure when the total is
    /// unknown (the server didn't report a content length).
    static func sizeProgress(downloaded: String, total: String, unknownPlaceholder: String = "--") -> String {
        guard total != unknownPlaceholder else { return downloaded }
        return "\(downloaded) / \(total)"
    }
}

/// Pure helpers for HTTP Range-based resumable downloads.
enum DownloadResume {
    /// Parses the total file size out of a `Content-Range` header value such as
    /// `"bytes 1000-9999/10000"`. Returns `nil` for `"*"` totals or malformed
    /// values.
    static func totalBytesFromContentRange(_ value: String?) -> Int64? {
        guard let value, let slash = value.lastIndex(of: "/") else { return nil }
        let totalString = value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        guard let total = Int64(totalString), total > 0 else { return nil }
        return total
    }

    /// Decides the absolute total size of a file being downloaded, preferring
    /// the server's `Content-Range`, then a size we already know, then the
    /// response's body length added to whatever we'd already saved.
    /// - existingBytes: bytes already on disk from a previous attempt.
    /// - expectedContentLength: length of THIS response's body (`-1` if unknown).
    static func resolveTotalBytes(
        contentRange: String?,
        existingBytes: Int64,
        knownTotalBytes: Int64?,
        expectedContentLength: Int64
    ) -> Int64? {
        if let fromHeader = totalBytesFromContentRange(contentRange) {
            return fromHeader
        }
        if let knownTotalBytes, knownTotalBytes > 0 {
            return knownTotalBytes
        }
        if expectedContentLength > 0 {
            // expectedContentLength counts only the bytes in THIS response; add
            // the bytes already on disk for the absolute total.
            return max(0, existingBytes) + expectedContentLength
        }
        return nil
    }

    /// Whether a download that finished its stream is actually complete.
    /// A clean connection close partway through (server hiccup) leaves the file
    /// short of its known total — that must be retried, not accepted.
    static func isComplete(writtenBytes: Int64, totalBytes: Int64?) -> Bool {
        guard let totalBytes, totalBytes > 0 else { return true }
        return writtenBytes >= totalBytes
    }
}

/// Pure, side-effect-free download resilience logic.
///
/// On a slow or unstable connection the download layer must (a) keep the
/// displayed progress monotonic so it never jumps backward, (b) retry transient
/// failures generously since resume data makes a retry cheap, and (c) cap the
/// wait between retries. These helpers encode those rules in one place.
enum DownloadRetryPolicy {
    /// Highest number of attempts for a single file. With HTTP Range resume each
    /// attempt continues from the bytes already on disk, so a high cap is cheap —
    /// it lets the download wait out a long connectivity outage. The attempt
    /// count and the backoff below are tuned so the total wait spans ~30 minutes.
    static let maxAttempts = 40

    /// Backoff before the next retry, in seconds. Grows with the attempt number
    /// (so quick blips retry fast) and caps at 60s, so the download keeps
    /// re-checking once a minute through a prolonged outage instead of giving up.
    static func backoffSeconds(for attempt: Int) -> Int {
        guard attempt > 0 else { return 0 }
        return min(60, attempt * 5)
    }

    /// Total worst-case time the retry loop will keep trying before failing —
    /// the sum of every backoff across all attempts.
    static var totalRetryWindowSeconds: Int {
        (1..<maxAttempts).reduce(0) { $0 + backoffSeconds(for: $1) }
    }

    /// Whether a `URLError` should be retried. On a flaky link almost everything
    /// transient is worth another attempt; only a genuine user cancel stops us.
    static func shouldRetry(
        urlErrorCode code: URLError.Code,
        taskIsCancelled: Bool,
        userInitiatedCancellation: Bool
    ) -> Bool {
        switch code {
        case .cancelled:
            return !taskIsCancelled && !userInitiatedCancellation
        default:
            return true
        }
    }

    /// Whether an HTTP status code represents a transient server-side failure
    /// that is worth retrying.
    static func shouldRetry(httpStatus statusCode: Int) -> Bool {
        statusCode == 408
            || statusCode == 425
            || statusCode == 429
            || (500...599).contains(statusCode)
    }

    /// Clamps a freshly reported per-file fraction against the highest fraction
    /// already shown for that file, keeping the progress bar monotonic across
    /// resumes, retries and fallback URLs. Returns the new running maximum.
    static func monotonicFraction(latest: Double, runningMax: Double) -> Double {
        max(runningMax, min(1, max(0, latest)))
    }

    /// How long a transfer may deliver zero bytes before we treat the connection
    /// as dead and force a retry.
    ///
    /// `URLSessionConfiguration.timeoutIntervalForRequest` does not cover this
    /// case once `waitsForConnectivity` is set: when the network changes under a
    /// live connection (a VPN toggling, Wi-Fi roaming) the socket can stay open
    /// while no data ever arrives, and the session waits out
    /// `timeoutIntervalForResource` — up to a day — without failing. Watching the
    /// byte counter ourselves is the only reliable way to notice.
    static let stallTimeoutSeconds: TimeInterval = 90

    /// Whether a transfer has stalled: no new bytes for `stallTimeoutSeconds`.
    /// - bytesSinceLastCheck: bytes received since the previous evaluation.
    /// - secondsSinceProgress: seconds elapsed since the byte counter last moved.
    static func hasStalled(bytesSinceLastCheck: Int64, secondsSinceProgress: TimeInterval) -> Bool {
        guard bytesSinceLastCheck <= 0 else { return false }
        return secondsSinceProgress >= stallTimeoutSeconds
    }

    /// Merges a per-file fraction into the overall multi-file progress, clamped
    /// just below 1.0 so the bar only reaches 100% on real completion.
    static func mergedProgress(fileBaseProgress: Double, fileSlice: Double, fileFraction: Double) -> Double {
        min(0.99, fileBaseProgress + (fileSlice * fileFraction))
    }
}

/// Tracks when a transfer last made progress, shared between the byte-consuming
/// loop and the stall watchdog running concurrently with it.
final class TransferActivityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity = Date()

    func touch() {
        lock.lock()
        lastActivity = Date()
        lock.unlock()
    }

    var secondsSinceLastActivity: TimeInterval {
        lock.lock()
        let timestamp = lastActivity
        lock.unlock()
        return Date().timeIntervalSince(timestamp)
    }
}
