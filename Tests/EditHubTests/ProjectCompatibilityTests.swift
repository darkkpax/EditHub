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
