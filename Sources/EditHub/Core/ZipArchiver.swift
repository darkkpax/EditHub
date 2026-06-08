import Foundation

enum ZipArchiverError: LocalizedError {
    case zipFailed
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .zipFailed: return "FAILED TO CREATE ARCHIVE."
        case .unzipFailed: return "FAILED TO UNZIP ARCHIVE."
        }
    }
}

enum ZipArchiver {
    /// Запаковать содержимое каталога в zip по заданному пути.
    @discardableResult
    static func archive(directory: URL, outputURL: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try zip(directory: directory, output: outputURL)
        return outputURL
    }

    static func unzip(archive: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-oq", archive.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ZipArchiverError.unzipFailed
        }
    }

    private static func zip(directory: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-qry", output.path, "."]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ZipArchiverError.zipFailed
        }
    }
}
