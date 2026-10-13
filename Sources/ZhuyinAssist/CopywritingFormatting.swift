import Foundation

// Protect literal syntax before Gemini sees it, then format only prose locally.
// Tokens are deterministic for a document, so request and response parsing can
// independently construct the same map without storing the user's text on disk.
struct CopywritingDocument {
    let lines: [CopywritingLine]

    init(_ text: String) {
        var prefix = "⟦ZHASSIST_PROTECTED_"
        while text.contains(prefix) { prefix += "_" }
        var fence: (character: Character, count: Int)?
        lines = splitLines(text).lines.enumerated().map { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let count = trimmed.prefix(while: { $0 == marker }).count
            let fenceMarker = (marker == "`" || marker == "~") && count >= 3
            var verbatim = fence != nil
            if let active = fence {
                if marker == active.character, count >= active.count,
                   trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else if fenceMarker, let marker {
                fence = (marker, count); verbatim = true
            }
            verbatim = verbatim || line.hasPrefix("    ") || line.hasPrefix("\t")
            // A complete keyboard sentence must reach the Zhuyin converter.
            let keyboard = keyboardZhuyinHint(line) != nil
            if !keyboard && line.range(of: "[\\p{Han}ㄅ-ㄩ]", options: .regularExpression) == nil { verbatim = true }
            if line.range(of: #"^\s*(?:let|var|const|func|function|class|struct|import|from|if|else|elif|while|for|guard|return|def|try|catch|switch|case|print|console\.(?:log|error)|SELECT|INSERT|UPDATE|DELETE)\b"#,
                          options: .regularExpression) != nil { verbatim = true }
            return CopywritingLine(original: line, prefix: prefix, lineIndex: index, verbatim: verbatim,
                                   ranges: keyboard || verbatim ? [] : copywritingProtectedRanges(line))
        }
    }
}

func copywritingNumbersUnchanged(original: String, corrected: String) -> Bool {
    // Width may change, but amounts, leading zeros, versions and decimal digits
    // must retain their exact sequence. Phonetic restoration is handled separately.
    let expression = try! NSRegularExpression(pattern: #"[0-9０-９]+(?:[.．][0-9０-９]+)*"#)
    let widths = Dictionary(uniqueKeysWithValues: zip(Array("０１２３４５６７８９．"), Array("0123456789.")))
    func values(_ text: String) -> [String] {
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            String(source.substring(with: $0.range).map { widths[$0] ?? $0 })
        }
    }
    return values(original) == values(corrected)
}

struct CopywritingLine {
    let original: String
    let verbatim: Bool
    let masked: String
    private let prefix: String
    private let tokens: [(marker: String, literal: String)]

    init(original: String, prefix: String, lineIndex: Int, verbatim: Bool, ranges: [NSRange]) {
        self.original = original; self.prefix = prefix; self.verbatim = verbatim
        let source = original as NSString
        var result = "", start = 0, tokens: [(String, String)] = []
        for (index, range) in ranges.enumerated() {
            result += source.substring(with: NSRange(location: start, length: range.location - start))
            let marker = prefix + "\(lineIndex)_\(index)⟧"
            tokens.append((marker, source.substring(with: range)))
            result += marker; start = NSMaxRange(range)
        }
        result += source.substring(from: start)
        masked = result; self.tokens = tokens
    }

    func restore(_ text: String) throws -> String {
        if verbatim { return original }
        let source = text as NSString
        var result = "", start = 0
        for token in tokens {
            let range = source.range(of: token.marker, options: [], range: NSRange(location: start, length: source.length - start))
            guard range.location != NSNotFound,
                  source.range(of: token.marker, options: [], range: NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))).location == NSNotFound
            else { throw fail("校正結果改動了受保護的內容，已保留原文。") }
            let preceding = source.substring(with: NSRange(location: start, length: range.location - start))
            guard !preceding.contains(prefix) else { throw fail("校正結果改動了受保護的內容，已保留原文。") }
            result += preceding + token.literal
            start = NSMaxRange(range)
        }
        let remaining = source.substring(from: start)
        guard !remaining.contains(prefix) else { throw fail("校正結果改動了受保護的內容，已保留原文。") }
        return result + remaining
    }
}

private func copywritingProtectedRanges(_ text: String) -> [NSRange] {
    let patterns = [
        // Inline code, Markdown links/images (including destinations), HTML.
        #"(`+)[^\r\n]*?\1"#,
        #"!?\[[^\]\r\n]*\]\([^\r\n]*?\)"#,
        #"!?\[[^\]\r\n]*\](?:\[[^\]\r\n]*\])?"#,
        #"<[^>\r\n]+>"#,
        // Quoted English sentences retain all their punctuation, not just words.
        #"["“「『](?=[^"”」』\r\n]*[A-Za-z])[^"”」』\p{Han}\r\n]*["”」』]"#,
        #"[a-zA-Z_][a-zA-Z0-9_]*\([^()\r\n]*\)"#,
        #"(?i)(?:https?|ftp)://[^\s<>「」『』，。！？；：、]+"#,
        #"(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}"#,
        #"(?:/|~/)[a-zA-Z0-9._/-]+"#,
        #"[a-zA-Z]:\\[^\s<>「」『』，。！？；：、]+"#,
        // Versions/decimals and ASCII identifiers, including product names.
        #"[vV]?[0-9]+(?:\.[0-9]+)+(?:[-+][a-zA-Z0-9.-]+)?"#,
        #"[a-zA-Z_][a-zA-Z0-9_]*(?:[-.][a-zA-Z0-9_]+)*"#,
        // Preserve Markdown structure and escapes. Edit only its prose.
        #"^\s*(?:#{1,6}\s+|(?:>\s*)+|[-+*]\s+|[0-9]+[.)]\s+|\[[^\]]+\]:\s+.*$)"#,
        #"\\."#,
        #"[*_~|]+"#
    ]
    let source = text as NSString
    var ranges: [NSRange] = []
    for pattern in patterns {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
        ranges += expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range)
    }
    ranges.sort { $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location }
    var merged: [NSRange] = []
    for range in ranges {
        if let previous = merged.last, range.location < NSMaxRange(previous) {
            merged[merged.count - 1] = NSUnionRange(previous, range)
        } else { merged.append(range) }
    }
    return merged
}

func formatCopywriting(_ text: String) -> String {
    func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
    func prose(_ text: String) -> String {
        let digits = Dictionary(uniqueKeysWithValues: zip(Array("０１２３４５６７８９"), Array("0123456789")))
        var result = String(text.map { digits[$0] ?? $0 })
        result = replace(result, #"(?<=\p{Han})(?=[A-Za-z0-9])|(?<=[A-Za-z0-9])(?=\p{Han})"#, " ")
        result = replace(result, #"(?<=[0-9])[ \t]+(?=[%°])"#, "")
        result = replace(result, #"(?<=[%°])(?=\p{Han})"#, " ")
        // Only remove horizontal spaces next to Chinese punctuation. Document
        // indentation and trailing Markdown hard-break spaces are added later.
        result = replace(result, #"[ \t]+(?=[，。！？；：、）】」』])|(?<=[，。！？；：、（【「『])[ \t]+"#, "")
        return result
    }
    func han(_ character: Character?) -> Bool {
        guard let character else { return false }
        return String(character).range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }
    func asciiWord(_ character: Character?) -> Bool {
        guard let character, let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return (48...57).contains(scalar.value) || (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
    let source = text as NSString
    let protected = copywritingProtectedRanges(text)
    let units = Set(["Hz", "kHz", "MHz", "GHz", "Gbps", "Mbps", "Kbps", "TB", "GB", "MB", "KB", "TiB", "GiB", "MiB", "KiB", "kg", "mg", "g", "km", "cm", "mm", "m", "ms", "s", "mL", "ml", "L", "V", "W", "kW"])
    var result = "", start = 0
    func append(_ part: String, unit: Bool = false) {
        guard !part.isEmpty else { return }
        if han(result.last) && asciiWord(part.first) || asciiWord(result.last) && han(part.first)
            || unit && result.last?.isNumber == true {
            result += " "
        }
        result += part
    }
    for range in protected {
        append(prose(source.substring(with: NSRange(location: start, length: range.location - start))))
        let literal = source.substring(with: range)
        append(literal, unit: units.contains(literal))
        start = NSMaxRange(range)
    }
    append(prose(source.substring(from: start)))
    return result
}
