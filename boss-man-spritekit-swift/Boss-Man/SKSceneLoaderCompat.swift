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

// Mirrors the SuperBox64 SpriteKit MiniJSON API so game code that consumes
// parseJSON compiles identically against Apple SpriteKit and the wasm kit.
enum JSONValue {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    var intValue: Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }
    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
    subscript(_ key: String) -> JSONValue? { objectValue?[key] }
}

func parseJSON(_ input: String) -> JSONValue? {
    guard let data = input.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
    return JSONValue(bridging: obj)
}

private extension JSONValue {
    init?(bridging value: Any) {
        switch value {
        case let dict as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, element) in dict {
                guard let converted = JSONValue(bridging: element) else { return nil }
                object[key] = converted
            }
            self = .object(object)
        case let items as [Any]:
            var array: [JSONValue] = []
            for element in items {
                guard let converted = JSONValue(bridging: element) else { return nil }
                array.append(converted)
            }
            self = .array(array)
        case let text as String:
            self = .string(text)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                self = .bool(num.boolValue)
            } else {
                self = .number(num.doubleValue)
            }
        case is NSNull:
            self = .null
        default:
            return nil
        }
    }
}
#endif
