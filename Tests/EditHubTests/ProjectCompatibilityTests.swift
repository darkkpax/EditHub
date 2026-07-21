import Foundation
import Testing
@testable import EditHub

@Test func importsFlutterProjectIdentityAndFootage() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let manifest = #"{"id":"0123456789abcdef0123456789abcdef","footageUrls":["https://example.com/a.zip"]}"#
    try Data(manifest.utf8).write(to: root.appendingPathComponent(".edithub.json"))

    let metadata = ProjectMetadataStore.load(projectURL: root)
    #expect(metadata.projectId == "0123456789abcdef0123456789abcdef")
    #expect(metadata.footageLinks == ["https://example.com/a.zip"])
}

@Test func flutterManifestReconcilesExistingNativeMetadata() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var native = ProjectMetadata()
    native.projectId = "native-id"
    native.footageLinks = ["https://example.com/mac.zip"]
    try ProjectMetadataStore.save(native, projectURL: root)
    let manifest = #"{"id":"flutter-id","footageUrls":["https://example.com/windows.zip"]}"#
    try Data(manifest.utf8).write(to: root.appendingPathComponent(".edithub.json"))

    let reconciled = ProjectMetadataStore.load(projectURL: root)
    #expect(reconciled.projectId == "flutter-id")
    #expect(reconciled.footageLinks == [
        "https://example.com/windows.zip",
        "https://example.com/mac.zip"
    ])
}

@Test func importsFlutterDirectoryArchiveFromICloudVideos() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let iCloud = base.appendingPathComponent("iCloud", isDirectory: true)
    let archive = iCloud.appendingPathComponent("edithub/Videos/2026/JULY/CLIENT FILM", isDirectory: true)
    let projects = base.appendingPathComponent("Projects", isDirectory: true)
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    let flutter = #"{"id":"icloud-project-id","footageUrls":["https://example.com/footage"]}"#
    try Data(flutter.utf8).write(to: archive.appendingPathComponent(".edithub.json"))

    let result = try ICloudArchiveImporter.import(from: iCloud, into: projects)
    let local = projects.appendingPathComponent("2026/JULY/CLIENT FILM", isDirectory: true)
    let nativeManifest = local.appendingPathComponent("CLIENT FILM.edithub")

    #expect(result.imported == 1)
    #expect(FileManager.default.fileExists(atPath: nativeManifest.path))
    #expect(ProjectMetadataStore.load(projectURL: local).projectId == "icloud-project-id")
}

@Test func restoresCompleteICloudProjectDirectory() throws {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cloudRoot = base.appendingPathComponent("Cloud", isDirectory: true)
    let cloudProject = cloudRoot.appendingPathComponent("Videos/2026/JULY/CLIENT", isDirectory: true)
    let localProject = base.appendingPathComponent("Local/2026/JULY/CLIENT", isDirectory: true)
    try FileManager.default.createDirectory(
        at: cloudProject.appendingPathComponent("FOOTAGE", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: localProject, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }

    try Data("video".utf8).write(to: cloudProject.appendingPathComponent("FOOTAGE/clip.mov"))
    let manifest = ProjectManifest(
        projectId: "directory-project",
        projectName: "CLIENT",
        year: "2026",
        month: "JULY",
        archivedAt: Date(),
        archiveRelativePath: "Videos/2026/JULY/CLIENT",
        removedHeavyFolders: [],
        archiveByteCount: nil,
        archiveChecksum: nil,
        footageLinks: nil
    )
    let manifestURL = localProject.appendingPathComponent("CLIENT.edithub")
    try manifest.write(to: manifestURL)

    let restored = try ProjectArchiver.restore(manifestURL: manifestURL, archiveRoot: cloudRoot)

    #expect(restored == localProject)
    #expect(FileManager.default.fileExists(atPath: localProject.appendingPathComponent("FOOTAGE/clip.mov").path))
    #expect(!FileManager.default.fileExists(atPath: manifestURL.path))
}

@Test func dropboxFileUsesContentHostAndKeepsFilename() throws {
    let url = try #require(URL(string: "https://www.dropbox.com/scl/fi/id/Ashley-random-questions.mov?dl=0"))
    let item = try #require(DropboxDownloader().preparePlan(url: url).first)
    let source = try #require(URL(string: item.sourceURLString))

    #expect(source.host == "dl.dropboxusercontent.com")
    #expect(URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?.contains {
        $0.name == "dl" && $0.value == "1"
    } == true)
    #expect(item.displayName == "ASHLEY-RANDOM-QUESTIONS.MOV")
}

@Test func recognizesSharedGoogleDriveFolderLink() throws {
    let link = "https://drive.google.com/drive/folders/110SsofgHIFN8BqeEie0DVGWZzd4fDL3O?usp=share_link"
    let url = try #require(URL(string: link))

    guard case .googleDrive = try LinkDetector.detect(url: url) else {
        Issue.record("Expected a Google Drive source")
        return
    }
    #expect(DownloadFormatting.friendlyLinkName(link).hasPrefix("Drive folder · 110SsofgHIFN8BqeEie0DVGW"))
}

// MARK: - Download plan safety

/// A shared Dropbox *folder* must keep the www host: rewriting it to
/// dl.dropboxusercontent.com makes Dropbox answer 404 for /scl/fo links.
@Test func dropboxFolderKeepsWwwHostAndZipName() throws {
    let url = try #require(URL(string: "https://www.dropbox.com/scl/fo/abc123/AAA?rlkey=k&dl=0"))
    let item = try #require(DropboxDownloader().preparePlan(url: url).first)
    let source = try #require(item.sourceURL)

    #expect(source.host == "www.dropbox.com")
    #expect(URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?.contains {
        $0.name == "dl" && $0.value == "1"
    } == true)
    #expect(item.displayName.hasSuffix(".ZIP"))
}

/// An empty Drive folder yields a placeholder item with no source URL. Reading
/// `sourceURL` on it must return nil rather than trapping — it used to be a
/// force-unwrap, which crashed the whole app mid-download.
@Test func folderPlaceholderItemHasNoSourceURLAndDoesNotTrap() throws {
    let placeholder = DownloadPlanItem(
        sourceURLString: "",
        relativeDestinationPath: "EMPTY FOLDER",
        displayName: "EMPTY FOLDER",
        headers: nil
    )

    #expect(placeholder.isFolderPlaceholder)
    #expect(placeholder.sourceURL == nil)
}

/// A malformed link must also degrade to nil instead of trapping. Note that
/// `URL(string:)` percent-encodes plain text rather than rejecting it, so this
/// uses a genuinely unparsable authority.
@Test func unparsableSourceStringYieldsNilURL() throws {
    let item = DownloadPlanItem(
        sourceURLString: "http://[",
        relativeDestinationPath: nil,
        displayName: "BAD",
        headers: nil
    )

    #expect(item.isFolderPlaceholder == false)
    #expect(item.sourceURL == nil)
}
