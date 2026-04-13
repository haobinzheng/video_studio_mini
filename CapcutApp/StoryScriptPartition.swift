import Foundation

/// Script paragraphs for Edit Story and paragraph-aligned narration: split on blank lines (`\n\n` or more).
/// Chunks that are empty or whitespace-only are dropped (extra newlines do not create paragraphs).
enum StoryScriptPartition {
    /// Same TTS chunking as legacy **whole-script** export (sentence / long-form splits), applied to **one block’s** text only.
    static func narrationSegmentsWholeScriptStyle(blockText: String, voiceIdentifier: String) -> [String] {
        let trimmed = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let voiceTag = SpeechVoiceLibrary.voiceLanguageTag(forVoiceIdentifier: voiceIdentifier)
        if SpeechVoiceLibrary.usesSentenceAlignedNarration(voiceLanguageTag: voiceTag) {
            let sentences = CaptionTextChunker.sentenceSegmentsForNarration(trimmed)
            return sentences.isEmpty
                ? SpeechVoiceLibrary.narrationSegments(from: trimmed, optimizeForLongForm: true)
                : sentences
        }
        return SpeechVoiceLibrary.narrationSegments(from: trimmed, optimizeForLongForm: true)
    }

    static func nonEmptyParagraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
