import Foundation
import NaturalLanguage

/// Shared caption line splitting: `NLTokenizer` for languages where word boundaries are not space-delimited
/// (Chinese, Japanese, Korean, Lao, Thai, etc.); legacy whitespace / fixed character splitting otherwise.
enum CaptionTextChunker {
    private static let phraseSeparators = CharacterSet(charactersIn: ",，、")
    private static let maxLegacyWords = 12
    private static let maxLegacyCJKCharacters = 10

    private static let maxTokenizerTokensDefault = 10
    private static let maxTokenizerSpanCharactersDefault = 36
    /// Slightly tighter grouping for Chinese-like voices so lines track phrasing without feeling oversized.
    private static let maxTokenizerTokensChineseLike = 8
    private static let maxTokenizerSpanCharactersChineseLike = 30

    private static let majorSentenceEndings: Set<Character> = [
        "。", "．", ".", "!", "?", "！", "？", "…"
    ]

    private static let clauseDelimiters: Set<Character> = ["；", ";", "：", ":"]

    /// Maps `AVSpeechSynthesisVoice.language` (BCP-47) to an `NLLanguage` for tokenization.
    static func nlLanguage(forVoiceLanguageTag tag: String) -> NLLanguage? {
        let id = tag.lowercased().replacingOccurrences(of: "_", with: "-")
        guard !id.isEmpty else { return nil }

        if id.hasPrefix("zh") {
            if id.contains("hant") || id.contains("-tw") || id.contains("-hk") || id.contains("-mo") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }
        if id.hasPrefix("ja") { return .japanese }
        if id.hasPrefix("ko") { return .korean }
        if id.hasPrefix("th") { return .thai }
        if id.hasPrefix("lo") { return NLLanguage(rawValue: "lo") }
        if id.hasPrefix("yue") { return .traditionalChinese }
        if id.hasPrefix("wuu") { return .simplifiedChinese }
        if id.hasPrefix("my") { return NLLanguage(rawValue: "my") }
        if id.hasPrefix("km") { return NLLanguage(rawValue: "km") }

        return nil
    }

    static func shouldUseNLTokenizer(voiceLanguageTag: String) -> Bool {
        nlLanguage(forVoiceLanguageTag: voiceLanguageTag) != nil
    }

    /// Chinese + Japanese: split on stronger boundaries first so captions align with sentences and clauses.
    private static func usesExtendedBoundaryHierarchy(_ voiceLanguageTag: String) -> Bool {
        let id = voiceLanguageTag.lowercased()
        if id.hasPrefix("zh") || id.hasPrefix("yue") || id.hasPrefix("wuu") { return true }
        if id.hasPrefix("ja") { return true }
        return false
    }

    private static func tokenizerLimits(for voiceLanguageTag: String) -> (maxTokens: Int, maxSpanCharacters: Int) {
        let id = voiceLanguageTag.lowercased()
        if id.hasPrefix("zh") || id.hasPrefix("yue") || id.hasPrefix("wuu") || id.hasPrefix("ja") {
            return (maxTokenizerTokensChineseLike, maxTokenizerSpanCharactersChineseLike)
        }
        return (maxTokenizerTokensDefault, maxTokenizerSpanCharactersDefault)
    }

    /// Splits already caption-normalized text into short lines for timing and display.
    static func splitForCaptions(normalizedText: String, voiceLanguageTag: String) -> [String] {
        let normalized = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let pieces = preprocessorPieces(from: normalized, voiceLanguageTag: voiceLanguageTag)
        let lines = pieces.flatMap { splitPhrase($0, voiceLanguageTag: voiceLanguageTag) }
        return mergeShortTailChunks(lines, minimumGraphemes: 3)
    }

    /// Sentence / clause / light phrase boundaries, then tokenizer runs inside each piece.
    private static func preprocessorPieces(from text: String, voiceLanguageTag: String) -> [String] {
        guard usesExtendedBoundaryHierarchy(voiceLanguageTag) else {
            return splitOnCommaPhrases(text)
        }

        var output: [String] = []
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let sentences = splitOnTrailingDelimiters(line, delimiters: majorSentenceEndings)
            for sentence in sentences {
                let clauses = splitOnTrailingDelimiters(sentence, delimiters: clauseDelimiters)
                for clause in clauses {
                    output.append(contentsOf: splitOnCommaPhrases(clause))
                }
            }
        }

        return output.isEmpty ? [text] : output
    }

    /// Splits when a delimiter is seen; each segment includes its closing delimiter (e.g. `。`).
    private static func splitOnTrailingDelimiters(_ text: String, delimiters: Set<Character>) -> [String] {
        var segments: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if delimiters.contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(trimmed)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(tail)
        }
        return segments.isEmpty ? [text] : segments
    }

    private static func splitOnCommaPhrases(_ text: String) -> [String] {
        let phrases = text
            .components(separatedBy: phraseSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return phrases.isEmpty ? [text] : phrases
    }

    private static func splitPhrase(_ phrase: String, voiceLanguageTag: String) -> [String] {
        if shouldUseNLTokenizer(voiceLanguageTag: voiceLanguageTag),
           let tokenizerChunks = tokenizerChunks(for: phrase, voiceLanguageTag: voiceLanguageTag),
           !tokenizerChunks.isEmpty {
            return tokenizerChunks
        }

        if phrase.contains(where: \.isWhitespace) {
            return splitWordPhrase(phrase, maxWords: maxLegacyWords)
        }
        return splitCharacterPhrase(phrase, maxCharacters: maxLegacyCJKCharacters)
    }

    private static func tokenizerChunks(for phrase: String, voiceLanguageTag: String) -> [String]? {
        guard let language = nlLanguage(forVoiceLanguageTag: voiceLanguageTag) else { return nil }
        guard !phrase.isEmpty else { return nil }

        let (maxTokens, maxSpan) = tokenizerLimits(for: voiceLanguageTag)

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = phrase
        tokenizer.setLanguage(language)

        let fullRange = phrase.startIndex..<phrase.endIndex
        var collectedRanges: [Range<String.Index>] = []
        var chunks: [String] = []

        func spanLength(_ ranges: [Range<String.Index>]) -> Int {
            guard let first = ranges.first, let last = ranges.last else { return 0 }
            return phrase.distance(from: first.lowerBound, to: last.upperBound)
        }

        func flushCollected() {
            guard let first = collectedRanges.first, let last = collectedRanges.last else { return }
            let slice = String(phrase[first.lowerBound..<last.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty {
                chunks.append(slice)
            }
            collectedRanges.removeAll(keepingCapacity: true)
        }

        tokenizer.enumerateTokens(in: fullRange) { tokenRange, _ in
            let token = String(phrase[tokenRange])
            if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }

            let trial = collectedRanges + [tokenRange]
            let tooManyTokens = trial.count > maxTokens
            let tooLong = !collectedRanges.isEmpty && spanLength(trial) > maxSpan

            if tooManyTokens || tooLong {
                flushCollected()
                collectedRanges = [tokenRange]
            } else {
                collectedRanges.append(tokenRange)
            }
            return true
        }

        flushCollected()

        if chunks.isEmpty { return nil }

        return chunks.flatMap { chunk -> [String] in
            if chunk.count > maxSpan {
                return splitCharacterPhrase(chunk, maxCharacters: maxLegacyCJKCharacters)
            }
            return [chunk]
        }
    }

    /// Avoid a lone 1–2 character line at the end; merge into the previous caption.
    private static func mergeShortTailChunks(_ chunks: [String], minimumGraphemes: Int) -> [String] {
        guard chunks.count >= 2 else { return chunks }
        var out = chunks
        while out.count >= 2 {
            let last = out[out.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if last.count > 0, last.count < minimumGraphemes {
                out[out.count - 2] = out[out.count - 2] + last
                out.removeLast()
            } else {
                break
            }
        }
        return out
    }

    private static func splitWordPhrase(_ phrase: String, maxWords: Int) -> [String] {
        let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > maxWords else { return [phrase] }

        var chunks: [String] = []
        var index = 0
        while index < words.count {
            let end = min(index + maxWords, words.count)
            chunks.append(words[index..<end].joined(separator: " "))
            index = end
        }
        return chunks
    }

    private static func splitCharacterPhrase(_ phrase: String, maxCharacters: Int) -> [String] {
        guard phrase.count > maxCharacters else { return [phrase] }

        var chunks: [String] = []
        var current = ""
        for character in phrase {
            current.append(character)
            if current.count >= maxCharacters {
                chunks.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}
