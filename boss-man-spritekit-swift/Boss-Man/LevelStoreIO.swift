import AppKit

// macOS half of the editor's level store I/O. levels.json is a real file under
// Application Support; SHOW writes it and reveals it in Finder. The wasm port
// has its own LevelStoreIO (localStorage blob + browser download). Common
// LevelStore code calls these three entry points with no #if.
enum LevelStoreIO {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Strings.App.bundleName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(LevelStore.fileName)
    }

    static func readBlob() -> String? { try? String(contentsOf: fileURL, encoding: .utf8) }

    static func writeBlob(_ json: String) {
        try? json.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func exportAndReveal(_ json: String) {
        writeBlob(json)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
