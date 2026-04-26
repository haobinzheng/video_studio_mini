import Foundation

/// Splits long narration strings so each piece fits a **preview** estimated-duration budget (matches
/// **`NarrationPreviewBuilder.cappedPreviewSegments`** and **`VideoExporter.applyPreviewNarrationSynthesisBudget`**).
enum PreviewNarrationSegmentBudget {
    /// Returns consecutive substrings of `text`, each with `estimate(piece) <= maxEstimatedSeconds` when possible,
    /// preserving order. Uses **`SpeechVoiceLibrary.narrationSegments`** first, then greedy prefix cuts by binary search.
    static func splitToFitEstimatedBudget(
        _ text: String,
        maxEstimatedSeconds: Double,
        estimate: (String) -> Double
    ) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard maxEstimatedSeconds > 0 else { return [trimmed] }
        if estimate(trimmed) <= maxEstimatedSeconds {
            return [trimmed]
        }

        let refined = SpeechVoiceLibrary.narrationSegments(from: trimmed, optimizeForLongForm: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if refined.count > 1 {
            return refined.flatMap { splitToFitEstimatedBudget($0, maxEstimatedSeconds: maxEstimatedSeconds, estimate: estimate) }
        }

        return splitGreedy(trimmed, maxEstimatedSeconds: maxEstimatedSeconds, estimate: estimate)
    }

    private static func splitGreedy(
        _ text: String,
        maxEstimatedSeconds: Double,
        estimate: (String) -> Double
    ) -> [String] {
        var out: [String] = []
        var rest = text
        while !rest.isEmpty {
            if estimate(rest) <= maxEstimatedSeconds {
                out.append(rest)
                break
            }
            let (prefix, remainder) = takeLargestPrefixFitting(rest, maxEstimatedSeconds: maxEstimatedSeconds, estimate: estimate)
            if prefix.isEmpty {
                let head = String(rest.prefix(1))
                out.append(head)
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            out.append(prefix)
            rest = remainder
        }
        return out
    }

    /// Binary search on prefix length for the longest prefix with `estimate(prefix) <= maxEstimatedSeconds`.
    private static func takeLargestPrefixFitting(
        _ text: String,
        maxEstimatedSeconds: Double,
        estimate: (String) -> Double
    ) -> (prefix: String, rest: String) {
        guard !text.isEmpty else { return ("", "") }
        var lo = 1
        var hi = text.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let idx = text.index(text.startIndex, offsetBy: mid, limitedBy: text.endIndex) ?? text.endIndex
            let prefix = String(text[..<idx])
            if estimate(prefix) <= maxEstimatedSeconds {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        var cut = text.index(text.startIndex, offsetBy: lo, limitedBy: text.endIndex) ?? text.endIndex
        cut = advanceSplitIndexPastInterruptedNumberIfNeeded(text, proposedEnd: cut)
        let prefix = String(text[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(text[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (prefix, rest)
    }

    /// If the binary-search cut lands just before a `,` / `.` between two digits (`1|，100`, `1|.3`), move the cut to the end of the number token so TTS is not split mid-value.
    private static func advanceSplitIndexPastInterruptedNumberIfNeeded(_ text: String, proposedEnd: String.Index) -> String.Index {
        guard proposedEnd < text.endIndex, proposedEnd > text.startIndex else { return proposedEnd }
        var j = proposedEnd
        if j < text.endIndex, (text[j] == "," || text[j] == "." || text[j] == "，") {
            let before = text.index(before: j)
            if text[before].isNumber {
                let afterComma = text.index(after: j)
                if afterComma < text.endIndex, text[afterComma].isNumber {
                    var k = afterComma
                    while k < text.endIndex, text[k].isNumber {
                        k = text.index(after: k)
                    }
                    while k < text.endIndex, (text[k] == "," || text[k] == "." || text[k] == "，") {
                        let n = text.index(after: k)
                        if n < text.endIndex, text[n].isNumber {
                            k = n
                            while k < text.endIndex, text[k].isNumber {
                                k = text.index(after: k)
                            }
                        } else { break }
                    }
                    j = k
                }
            }
        }
        return j
    }
}
