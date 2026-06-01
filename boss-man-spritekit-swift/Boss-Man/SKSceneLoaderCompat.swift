#if os(macOS)
import Foundation

// macOS-native counterparts to the SuperBox64 SpriteKit asset helpers that the
// wasm runtime exposes (SKSceneLoader.loadAssetText + parseJSON). Providing them
// here lets level loading run through one common path: on wasm the framework
// reads from the runtime's asset store, on macOS the data ships in the app
// bundle and Foundation parses it.
enum SKSceneLoader {
    static func loadAssetText(_ path: String) -> String? {
        let name = (path as NSString).deletingPathExtension
        let ext  = (path as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name,
                                        withExtension: ext.isEmpty ? nil : ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

func parseJSON(_ input: String) -> Any? {
    guard let data = input.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}
#endif
