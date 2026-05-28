import KitABI

// MiniJSON: a tiny recursive-descent JSON parser, just for the .sks → JSON
// loader. We avoid Foundation's JSONSerialization because the WASI Foundation
// is large and we only need the trivially-typed result (Dict / Array /
// String / Double / Bool / nil).
//
// Returns Any (one of [String: Any], [Any], String, Double, Bool, or NSNull).
// Returns nil on parse failure.
func parseJSON(_ input: String) -> Any? {
    var parser = JSONParser(chars: Array(input.unicodeScalars))
    parser.skipWhitespace()
    let value = parser.parseValue()
    parser.skipWhitespace()
    if !parser.atEnd { return nil }
    return value
}

// JSON's `null` is mapped to a sentinel since Any can't hold real `nil`.
public final class MiniJSONNull: @unchecked Sendable {
    public nonisolated(unsafe) static let null = MiniJSONNull()
    private init() {}
}

private struct JSONParser {
    let chars: [Unicode.Scalar]
    var pos: Int = 0
    var atEnd: Bool { pos >= chars.count }

    mutating func skipWhitespace() {
        while pos < chars.count {
            let c = chars[pos]
            if c == " " || c == "\n" || c == "\t" || c == "\r" { pos += 1 } else { break }
        }
    }

    mutating func parseValue() -> Any? {
        skipWhitespace()
        guard pos < chars.count else { return nil }
        let c = chars[pos]
        if c == "{" { return parseObject() }
        if c == "[" { return parseArray() }
        if c == "\"" { return parseString() }
        if c == "t" || c == "f" { return parseBool() }
        if c == "n" { return parseNull() }
        return parseNumber()
    }

    mutating func parseObject() -> [String: Any]? {
        pos += 1   // consume '{'
        var out: [String: Any] = [:]
        skipWhitespace()
        if pos < chars.count, chars[pos] == "}" { pos += 1; return out }
        while pos < chars.count {
            skipWhitespace()
            guard let key = parseString() else { return nil }
            skipWhitespace()
            guard pos < chars.count, chars[pos] == ":" else { return nil }
            pos += 1
            guard let v = parseValue() else { return nil }
            out[key] = v
            skipWhitespace()
            if pos < chars.count, chars[pos] == "," { pos += 1; continue }
            if pos < chars.count, chars[pos] == "}" { pos += 1; return out }
            return nil
        }
        return nil
    }

    mutating func parseArray() -> [Any]? {
        pos += 1
        var out: [Any] = []
        skipWhitespace()
        if pos < chars.count, chars[pos] == "]" { pos += 1; return out }
        while pos < chars.count {
            guard let v = parseValue() else { return nil }
            out.append(v)
            skipWhitespace()
            if pos < chars.count, chars[pos] == "," { pos += 1; continue }
            if pos < chars.count, chars[pos] == "]" { pos += 1; return out }
            return nil
        }
        return nil
    }

    mutating func parseString() -> String? {
        guard pos < chars.count, chars[pos] == "\"" else { return nil }
        pos += 1
        var out = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == "\"" { pos += 1; return out }
            if c == "\\" {
                pos += 1
                if pos >= chars.count { return nil }
                let esc = chars[pos]; pos += 1
                switch esc {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/":  out.append("/")
                case "b":  out.append("\u{08}")
                case "f":  out.append("\u{0C}")
                case "n":  out.append("\n")
                case "r":  out.append("\r")
                case "t":  out.append("\t")
                case "u":
                    // 4 hex digits.
                    if pos + 4 > chars.count { return nil }
                    var code: UInt32 = 0
                    for _ in 0..<4 {
                        let h = chars[pos]; pos += 1
                        let v = hexValue(h)
                        if v < 0 { return nil }
                        code = code * 16 + UInt32(v)
                    }
                    if let scalar = Unicode.Scalar(code) { out.append(Character(scalar)) }
                default: return nil
                }
                continue
            }
            out.append(Character(c)); pos += 1
        }
        return nil
    }

    mutating func parseBool() -> Bool? {
        if matches("true")  { return true }
        if matches("false") { return false }
        return nil
    }
    mutating func parseNull() -> Any? {
        if matches("null") { return MiniJSONNull.null }
        return nil
    }
    mutating func parseNumber() -> Any? {
        let start = pos
        if pos < chars.count, chars[pos] == "-" { pos += 1 }
        while pos < chars.count {
            let c = chars[pos]
            if (c >= "0" && c <= "9") || c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                pos += 1
            } else { break }
        }
        if pos == start { return nil }
        let str = String(String.UnicodeScalarView(chars[start..<pos]))
        if let d = Double(str) { return d }
        return nil
    }

    mutating func matches(_ literal: String) -> Bool {
        let lit = Array(literal.unicodeScalars)
        if pos + lit.count > chars.count { return false }
        for i in 0..<lit.count where chars[pos + i] != lit[i] { return false }
        pos += lit.count
        return true
    }
    func hexValue(_ s: Unicode.Scalar) -> Int {
        if s >= "0" && s <= "9" { return Int(s.value - 0x30) }
        if s >= "a" && s <= "f" { return Int(s.value - 0x61 + 10) }
        if s >= "A" && s <= "F" { return Int(s.value - 0x41 + 10) }
        return -1
    }
}
