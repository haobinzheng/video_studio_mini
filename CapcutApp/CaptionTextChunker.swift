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

    /// Comma / enumeration / semicolon: break long “one period” sentences into shorter narration + caption lines (Chinese / Japanese style).
    private static let lightPauseDelimiters: Set<Character> = ["，", "、", "；", ";", ","]

    /// Below this length, keep one segment even if it contains ， (avoids chopping short phrases).
    private static let minScriptLengthToSplitOnLightPauses = 24

    /// Merge short leading / middle fragments into the next chunk (e.g. avoid a lone "然而" before a longer clause).
    private static let minClauseGraphemesBeforeStandalone = 8

    /// Avoid a single TTS call spanning an extremely long string when sentence punctuation is missing.
    private static let maxSentenceAlignedUtteranceCharacters = 140

    /// Strip from caption **display** only (TTS still uses full punctuation). Applied per line for wrapped captions.
    /// Removes only *soft* clause/sentence tail marks (comma, period, colon, semicolon, ellipsis, CJK equivalents).
    /// Does not remove `)` `]` `}` `"` `?` `!` `/` or other paired / syntactic punctuation.
    private static func isSingleScalarSoftCaptionTail(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let s = scalars.first else { return false }
        switch s.value {
        case 0x002C, 0x002E, 0x003A, 0x003B: return true // , . : ;
        case 0x2026: return true // …
        case 0x00B7: return true // ·
        case 0x007E, 0xFF5E: return true // ~ ～
        case 0xFF0C, 0x3002, 0xFF1B, 0xFF1A, 0x3001, 0xFF0E, 0xFE52: return true // ，。；：、．﹒
        default: return false
        }
    }

    /// Removes trailing soft punctuation from the end of each line (for on-screen subtitles only).
    static func strippedCaptionForDisplay(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                while let last = s.last, isSingleScalarSoftCaptionTail(last) {
                    s.removeLast()
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "\n")
    }

    /// One line of on-screen caption after **`splitForCaptions`**: balances long space-delimited phrases into two
    /// lines (same rules as **`NarrationPreviewBuilder`** preview cues). Used by final export sentence-aligned
    /// captions so **Edit Story** (no preview cues) matches **whole-script** export (preview cues).
    static func displayCaptionLine(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 6 else { return trimmed }
        return balancedCaptionLine(for: trimmed)
    }

    private static func balancedCaptionLine(for text: String) -> String {
        let normalizedText = SpeechVoiceLibrary.normalizedCaptionText(text)
        let words = normalizedText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 6 else { return normalizedText }

        var bestIndex = words.count / 2
        var bestScore = Int.max
        for index in 2..<(words.count - 1) {
            let left = words[..<index].joined(separator: " ")
            let right = words[index...].joined(separator: " ")
            let score = abs(left.count - right.count)
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return words[..<bestIndex].joined(separator: " ") + "\n" + words[bestIndex...].joined(separator: " ")
    }

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

    /// TTS segment list for **sentence-aligned** narration (Chinese, Japanese, Lao family): one utterance per sentence when possible.
    static func sentenceSegmentsForNarration(_ rawText: String) -> [String] {
        let normalized = SpeechVoiceLibrary.normalizedCaptionText(rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var initial: [String] = []
        let lines = normalized.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let majorUnits = splitOnTrailingDelimiters(line, delimiters: majorSentenceEndings)
            for unit in majorUnits {
                initial.append(contentsOf: splitMajorUnitIntoClausesForNarration(unit))
            }
        }
        if initial.isEmpty {
            initial = [normalized]
        }

        // Join tiny fragments across line / unit boundaries (e.g. "然而，\n如果将…" → one utterance).
        let bridged = mergeTinyClauseFragments(initial, minGraphemes: minClauseGraphemesBeforeStandalone)
        let refined = refineSentenceSegmentsForTTSLimits(bridged)
        return refined.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// After a `。！？` unit, split further at `，` / `、` / `；` so long sentences become several shorter lines (one TTS each).
    private static func splitMajorUnitIntoClausesForNarration(_ major: String) -> [String] {
        let trimmed = major.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let hasLightPause = trimmed.contains(where: lightPauseDelimiters.contains)
        let longEnough = trimmed.count >= minScriptLengthToSplitOnLightPauses
        if !hasLightPause || !longEnough {
            return [trimmed]
        }

        let clauses = splitOnTrailingDelimiters(trimmed, delimiters: lightPauseDelimiters)
        guard clauses.count > 1 else { return [trimmed] }

        let pieces = clauses.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return mergeTinyClauseFragments(pieces, minGraphemes: minClauseGraphemesBeforeStandalone)
    }

    /// Prefers merging **forward** so a short opener (e.g. "然而，") is not left alone as the first trunk.
    private static func mergeTinyClauseFragments(_ parts: [String], minGraphemes: Int) -> [String] {
        guard !parts.isEmpty else { return [] }
        var out: [String] = []
        var buffer = ""

        func flushBuffer() {
            let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else {
                buffer = ""
                return
            }
            out.append(t)
            buffer = ""
        }

        for part in parts {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }

            if buffer.isEmpty {
                buffer = t
            } else if buffer.last.map({ majorSentenceEndings.contains($0) }) == true {
                flushBuffer()
                buffer = t
            } else {
                buffer.append(t)
            }

            if buffer.count >= minGraphemes {
                flushBuffer()
            }
        }

        if !buffer.isEmpty {
            let trimmedBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBuffer.count < minGraphemes, let lastIdx = out.indices.last {
                let prev = out[lastIdx]
                if prev.last.map({ majorSentenceEndings.contains($0) }) == true {
                    out.append(trimmedBuffer)
                } else {
                    out[lastIdx] = prev + trimmedBuffer
                }
            } else {
                out.append(trimmedBuffer)
            }
        }

        return out
    }

    private static func refineSentenceSegmentsForTTSLimits(_ pieces: [String]) -> [String] {
        var result: [String] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.count <= maxSentenceAlignedUtteranceCharacters {
                result.append(trimmed)
                continue
            }

            let clauses = splitOnTrailingDelimiters(trimmed, delimiters: clauseDelimiters)
            if clauses.count > 1 {
                result.append(contentsOf: refineSentenceSegmentsForTTSLimits(clauses))
                continue
            }

            let commas = splitOnCommaPhrases(trimmed)
            if commas.count > 1 {
                result.append(contentsOf: refineSentenceSegmentsForTTSLimits(commas))
                continue
            }

            result.append(contentsOf: SpeechVoiceLibrary.narrationSegments(from: trimmed, optimizeForLongForm: false))
        }
        return result
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
