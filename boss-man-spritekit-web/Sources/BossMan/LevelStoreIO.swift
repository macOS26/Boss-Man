import SpriteKit

// wasm half of the editor's level store I/O. levels.json lives as a localStorage
// blob keyed by the file name; SHOW writes it and triggers a browser download so
// the user keeps a real file. The macOS port has its own LevelStoreIO (real file
// + Finder reveal). Common LevelStore code calls these three entry points.
enum LevelStoreIO {
    static func readBlob() -> String? {
        let v = LocalStore.string(forKey: LevelStore.fileName)
        return (v?.isEmpty ?? true) ? nil : v
    }

    static func writeBlob(_ json: String) {
        LocalStore.setString(json, forKey: LevelStore.fileName)
    }

    static func exportAndReveal(_ json: String) {
        writeBlob(json)
        WebDownload.file(named: LevelStore.fileName, contents: json)
    }
}
