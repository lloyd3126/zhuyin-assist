import Foundation

// Recognize keyboard-like prose without requiring every syllable to be valid.
// This is only routing evidence. Gemini receives every original key unchanged.
func keyboardZhuyinHint(_ text: String) -> String? {
    let keys = Array("1qaz2wsxedcrfv5tgbyhnujm8ik,9ol.0p;/-")
    let symbols = Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄧㄨㄩㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ")
    let mapping = Dictionary(uniqueKeysWithValues: zip(keys, symbols))
    let tones: [Character: Character] = ["3": "ˇ", "4": "ˋ", "6": "ˊ", "7": "˙"]
    let punctuation: [Character: Character] = ["<": "，", ">": "。", "!": "！", "?": "？", "，": "，", "。": "。", "！": "！", "？": "？"]
    let initials = Set(Array("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ"))
    let medials = Set(Array("ㄧㄨㄩ"))
    let finals = Set(Array("ㄚㄛㄜㄝㄞㄟㄠㄡㄢㄣㄤㄥㄦ"))
    func valid(_ syllable: [Character]) -> Bool {
        guard !syllable.isEmpty, syllable.count <= 3 else { return false }
        var position = 0
        let initial = initials.contains(syllable[0]) ? syllable[0] : nil
        if initial != nil { position += 1 }
        var medial: Character?
        if position < syllable.count, medials.contains(syllable[position]) { medial = syllable[position]; position += 1 }
        var final: Character?
        if position < syllable.count, finals.contains(syllable[position]) { final = syllable[position]; position += 1 }
        guard position == syllable.count else { return false }
        if let initial, medial == nil && final == nil { return "ㄓㄔㄕㄖㄗㄘㄙ".contains(initial) }
        if final == "ㄦ" { return initial == nil && medial == nil }
        if let initial, "ㄐㄑㄒ".contains(initial) { return medial == "ㄧ" || medial == "ㄩ" }
        return true
    }
    // English, literal identifiers, URLs, paths, and source code stay protected.
    let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard source.range(of: "[a-z]", options: .regularExpression) != nil,
          source.range(of: #"(?:https?://|www\.|@|^/|^~/|`|[=:\\{}\[\]()])"#, options: .regularExpression) == nil,
          source.range(of: #"(?i)\b[a-z0-9_-]+\.[a-z]{1,63}\b"#, options: .regularExpression) == nil,
          source.range(of: #"^[a-z][a-z0-9_.-]*;$"#, options: .regularExpression) == nil,
          source.range(of: #"^(?:let|var|const|func|function|class|struct|import|from|if|else|while|for|guard|return|def|try|catch|switch|case)\b"#, options: .regularExpression) == nil
    else { return nil }
    var syllable: [Character] = [], result = "", count = 0, validCount = 0, toneCount = 0
    func finish() {
        guard !syllable.isEmpty else { return }
        count += 1
        if valid(syllable) { validCount += 1 }
        syllable.removeAll(keepingCapacity: true)
    }
    for key in text {
        if let symbol = mapping[key] {
            syllable.append(symbol); result.append(symbol)
        } else if let tone = tones[key] {
            finish(); toneCount += 1; result.append(tone)
        } else if key == " " || key == "\t" {
            finish(); result.append(key)
        } else if let mark = punctuation[key] {
            finish(); result.append(mark)
        } else { return nil }
    }
    finish()
    // A few malformed syllables no longer reject the whole sentence. Still
    // require substantial keyboard evidence so English is not blindly mapped.
    guard count >= 3, toneCount >= 2, validCount >= 2, validCount * 2 >= count else { return nil }
    return result
}

func hasKeyboardRecoveryInput(_ text: String) -> Bool {
    CopywritingDocument(text).lines.contains { !$0.verbatim && keyboardZhuyinHint($0.original) != nil }
}
