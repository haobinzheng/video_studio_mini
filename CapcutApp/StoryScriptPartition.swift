import Foundation

/// Script paragraphs for Edit Story and paragraph-aligned narration: split on blank lines (`\n\n` or more).
/// Chunks that are empty or whitespace-only are dropped (extra newlines do not create paragraphs).
///
/// **Story mode product model:** narration and captions (including zh / ja / lo and related sentence-aligned
/// handling) use the **same** rules with Edit on or off. Edit only adds tools to assign **media** and **music**
/// per paragraph block. With Edit off, the entire script is treated as **one block**—the same as a single
/// block in Edit-on mode—and **`narrationSegmentsWholeScriptStyle`** is applied to that full text.
enum StoryScriptPartition {
    /// TTS utterance list for **one** story block’s script (or the whole script when Edit is off). Same rules for every block.
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
